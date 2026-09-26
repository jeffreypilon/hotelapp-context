# DevOps Pipeline — React

CI for `hotelapp-client-react`. The cross-repo shape — platform, triggers, the absence of any deployment
step, and the two cross-repo checks — is settled in
[devops-pipeline-overview.md](../../shared/devops-pipeline-overview.md) and is **not** re-litigated here.
This document fills in this repo's job.

**No deployment step. No release. No published artifact.** This job answers one question per push: does
this still build, lint clean, type-check, and pass its tests?

---

## The job

One workflow, `.github/workflows/ci.yml`, on push to `main` and on pull requests targeting `main`.

| Step | Command | Fails the build? |
|------|---------|------------------|
| Checkout | `actions/checkout@<pinned>` | — |
| Node setup + npm cache | `actions/setup-node@<pinned>` with `cache: npm` and `node-version-file: .nvmrc` | — |
| Install | `npm ci` | Yes |
| Lint | `npm run lint` | **Yes** |
| Format check | `npm run format:check` | **Yes** |
| Type check | `npm run typecheck` | **Yes** |
| Unit + component tests | `npm run test:run` | **Yes** |
| Production build | `npm run build` | **Yes** |
| Bundle size check | see below | **No — warning** |

`node-version-file: .nvmrc` rather than a literal version, so CI and a developer's machine cannot drift.

Actions are pinned to a specific version, never a floating tag, for the same reproducibility reason Docker
images are pinned in
[versioning-strategy.md](../../shared/versioning-strategy.md#versions-of-the-platform-itself).

Target runtime: **under 3 minutes.** The cross-repo budget is five; a frontend job with no database should
beat it comfortably, and a pipeline slower than that stops being run before pushing.

### Why lint and format fail the build

A warning nobody acts on is noise, and a formatter that runs in CI without failing is a formatter that
never gets run locally. `format:check` **verifies and never writes** — a CI job that reformats and commits
turns every build into a source of diffs nobody reviewed.

### Why the production build is a separate step from tests

`npm run build` catches what dev mode and tests never do: a type error only the production compile surfaces,
a dynamic import that cannot be resolved, a broken asset path. Tests can pass on a bundle that cannot be
built.

### Bundle size

Checked against the **< 300 KB gzipped** initial-chunk budget from
[non-functional-requirements.md](../../shared/non-functional-requirements.md#response-time-targets), and
reported as a **warning, not a failure**.

A hard gate would fail a legitimate feature at an arbitrary threshold; a silent check is one nobody reads.
So: print the gzipped size of the initial chunk in the job summary, and warn when it exceeds the budget.
**Parity with the Angular client's bundle size is explicitly not a goal** — the frameworks have different
baselines and forcing convergence would be the wrong kind of symmetry.

---

## What this job does NOT do

| Absent | Why |
|--------|-----|
| Deploy anything | There is no environment. This is the root reason for most of the rest of this table |
| Build or publish a Docker image | Images are built locally and thrown away |
| End-to-end browser tests | **The acknowledged gap** — [devops-pipeline-overview.md](../../shared/devops-pipeline-overview.md#deliberately-absent). Nothing here exercises this client against a live backend |
| Run against a real backend | Component tests mock HTTP at the network boundary; the real-integration answer is the Compose smoke test |
| Coverage threshold gate | Coverage is reported, not enforced — [testing-standards.md](./testing-standards.md#coverage) |
| Dependency scanning | A declined cost, explained in [security-principles.md](../../shared/security-principles.md#out-of-scope-and-why-that-line-is-acceptable) |
| Lighthouse / performance audits | No deployed URL to audit |
| Visual regression tests | Would need a baseline store and produce noise on every intentional design change |
| Release tagging | Nothing consumes this as a versioned artifact |

---

## Secrets

**None.** This job authenticates nowhere and needs no repository secret. If one ever becomes necessary it
goes in GitHub Actions encrypted secrets — never in a workflow file, never in a committed config, per
[security-principles.md](../../shared/security-principles.md#secrets-and-configuration).

This client holds no credential at runtime either, so there is nothing to inject at build time. A build-time
secret in a frontend bundle is public by definition, which is worth stating once so nobody tries.

---

## This repo's part in the cross-repo checks

Two checks in
[devops-pipeline-overview.md](../../shared/devops-pipeline-overview.md) involve more than one repo. Neither
runs here, but one has a frontend analogue this repo should carry:

**The OpenAPI diff** is a backend concern — it compares the two backends' generated documents. This client
participates only indirectly: its hand-written types in `api/types.ts` are the thing the contract is supposed
to match, and a mismatch shows up as a failing component test against a contract-shaped fixture rather than
as a diff.

**The `ui-specifications.md` section diff** is the frontend analogue, proposed in
[ui-specifications.md](./ui-specifications.md) section 3. Sections 1–2 of the two clients'
`ui-specifications.md` files are byte-identical by construction; a job should extract them from both and fail
on any difference:

```bash
# in hotelapp-context, or either client repo with both files available
extract() { sed -n '/^## 1\. Conventions/,/^## 3\. /p' "$1" | sed '$d'; }
diff <(extract react/ui-specifications.md) <(extract angular/ui-specifications.md) \
  || { echo "Screen specifications have diverged"; exit 1; }
```

It belongs in `hotelapp-context`, since that is where both files live, and it is the only automated defense
against the two clients' screen specifications drifting. Noted here because this repo is a consumer of that
guarantee.

---

## Local equivalence

A developer should be able to run exactly what CI runs, in one command:

```bash
npm run ci        # lint && format:check && typecheck && test:run && build
```

CI running something a developer cannot reproduce locally is how a red build becomes someone else's problem.
The script exists so the answer to "why did CI fail" is always "run `npm run ci`".
