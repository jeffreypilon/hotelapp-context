# DevOps Pipeline — Node / Express

CI for `hotelapp-server-nodejs`. The cross-repo shape — platform, triggers, the absence of any
deployment step, and the two cross-repo checks — is settled in
[devops-pipeline-overview.md](../../shared/devops-pipeline-overview.md) and is **not** re-litigated
here.

**No deployment step. No release. No published artifact.** This job answers one question per push:
does this still build, lint clean, type-check, and pass its tests against a real PostgreSQL?

---

## The job, and the thing that makes it unusual

One workflow, `.github/workflows/ci.yml`, on push to `main` and on pull requests targeting `main`.

> ## This repo's CI needs a second checkout, and that is the migration asymmetry
>
> **This backend cannot build its own test schema.** Prisma does not apply DDL, so CI must obtain the
> canonical migrations from `hotelapp-context` and run **Flyway** against them before any integration
> test can execute — [versioning-strategy.md](../../shared/versioning-strategy.md#database-schema-migrations).
>
> ```yaml
> - uses: actions/checkout@<pinned>
> - uses: actions/checkout@<pinned>          # the second checkout
>   with:
>     repository: jeffreypilon/hotelapp-context
>     path: hotelapp-context
>     ref: main
> ```
>
> Then the **standalone Flyway CLI** applies them — no JVM application build required, just the CLI or
> its container image. The Spring Boot repo needs none of this: Flyway is already part of its startup,
> so its test schema is built by the same mechanism as production.
>
> **Two consequences worth accepting deliberately:**
>
> 1. **This repo's build can go red because of a commit in a different repo.** Pinning the context
>    checkout to `main` means a merged schema change immediately affects this pipeline. That is the
>    intended behavior — it is how a schema change this backend has not caught up with becomes
>    visible — but it is a real coupling, and pinning to a tag instead would trade that signal for
>    stability.
> 2. **`prisma migrate deploy` must never appear in this workflow.** It would work, and it would mean
>    the CI schema is built by a different mechanism than production, which is exactly the
>    two-writers problem the ownership rule prevents.

| Step | Command | Fails the build? |
|------|---------|------------------|
| Checkout this repo | `actions/checkout@<pinned>` | — |
| **Checkout `hotelapp-context`** | `actions/checkout@<pinned>` | Yes |
| Node setup + npm cache | `actions/setup-node@<pinned>`, `node-version-file: .nvmrc` | — |
| Install | `npm ci` | Yes |
| Lint | `npm run lint` | **Yes** |
| Format check | `npm run format:check` | **Yes** |
| Type check | `npm run typecheck` | **Yes** |
| **Flyway migrate** | CLI against the second checkout's SQL | **Yes** |
| `prisma generate` | From the committed `schema.prisma` | **Yes** |
| Unit + integration tests | `npm run test:run` | **Yes** |
| Build | `npm run build` | **Yes** |
| Publish the OpenAPI document | Upload `openapi.json` as an artifact | No |

`node-version-file: .nvmrc` rather than a literal version, so CI and a developer's machine cannot
drift. Actions pinned to a specific version, never a floating tag, for the same reproducibility reason
Docker images are pinned in
[versioning-strategy.md](../../shared/versioning-strategy.md#versions-of-the-platform-itself).

Target runtime: **under 5 minutes**, the cross-repo budget.

---

## The database in CI

```yaml
services:
  postgres:
    image: postgres:18.6
    env: { POSTGRES_PASSWORD: postgres, POSTGRES_DB: hotelapp_test }
    options: >-
      --health-cmd pg_isready --health-interval 10s
      --health-timeout 5s --health-retries 5
```

**`postgres:18.6`, pinned.** Not `postgres:latest` and not `postgres:17` — the schema uses
`uuidv7()`, a PostgreSQL 18 core function, so an earlier image fails at migration time rather than
mysteriously later.

**A service container rather than Testcontainers, in CI only.** The test suite uses Testcontainers
locally, which needs Docker-in-Docker on a runner. Pointing the suite at a service container through
`DATABASE_URL` is simpler and faster. The suite must therefore accept an externally provided database
instead of always starting its own — a small design requirement on the test setup, noted here because
it is easy to hard-code the container.

**No substitute is acceptable.** H2 has no exclusion constraints, so an H2-backed run would pass while
the project's central guarantee was entirely absent — reasoning in
[testing-standards.md](./testing-standards.md).

---

## `schema.prisma` drift — a check this repo needs and the other does not

Spring Boot gets `ddl-auto=validate` for free: if entities disagree with the migrated schema, startup
fails. **This repo has no equivalent**, because `schema.prisma` is generated rather than validated.

So CI should add one:

```bash
npx prisma db pull --print > /tmp/pulled.prisma
diff <(normalize prisma/schema.prisma) <(normalize /tmp/pulled.prisma) \
  || { echo "schema.prisma is stale — run npm run prisma:pull"; exit 1; }
```

A difference means the canonical migrations have moved ahead of the committed client, and the fix is
`npm run prisma:pull`. **This is the Node counterpart of the other backend's startup validation**, it
exists only because of the migration asymmetry, and without it a stale client is discovered as a
runtime error on one endpoint rather than as a failed build.

Treat it as a **warning first**: introspection output can differ cosmetically between Prisma versions,
so normalize before comparing and tighten to a hard failure once it is proven stable.

---

## Timezone pass

```yaml
- run: npm run test:integration
  env: { TZ: Asia/Tokyo }
```

A second run under a non-UTC process timezone. Cheap, and the only thing that catches a
process-timezone dependency in the cancellation-deadline arithmetic —
[AC-CX-04](../../shared/acceptance-criteria.md#ac-cx-04--deadline-respects-the-propertys-timezone-not-the-servers).
Invisible under a single setting, and exactly the divergence the stored-deadline design exists to
prevent.

---

## This repo's part in the cross-repo checks

**The OpenAPI diff** is the primary defense against the two backends drifting —
[devops-pipeline-overview.md](../../shared/devops-pipeline-overview.md#1-the-openapi-diff). This repo's
obligation is to **publish `openapi.json` as a build artifact** so the comparison job in
`hotelapp-context` can fetch it.

This backend's document is **hand-maintained**, not generated —
[architecture-specification.md](./architecture-specification.md#openapi) — which is the asymmetry that
makes normalization necessary on the comparison side. A useful local check: assert the document is
valid OpenAPI 3.1 and that its set of paths matches the routes actually registered on the Express app.
That catches a route added without a contract entry, which a hand-maintained document makes easy to
forget.

**The Docker Compose smoke test** lives in `hotelapp-context` and is where
[AC-SE-05](../../shared/acceptance-criteria.md#ac-se-05--a-session-works-interchangeably-against-both-backends)
runs for real, with both backends live. This repo's obligation is a **Dockerfile that builds and runs
without a migration step** — because the Compose topology runs Flyway as its own service before either
backend starts. A Dockerfile whose entrypoint tried to migrate would fight that.

---

## What this job does NOT do

| Absent | Why |
|--------|-----|
| Deploy anything | There is no environment |
| Publish a Docker image | Images are built locally and thrown away |
| `prisma migrate` of any kind | Prisma does not apply DDL |
| Run the other backend | Cross-backend behavior is the Compose smoke test's job |
| End-to-end browser tests | The acknowledged gap — [devops-pipeline-overview.md](../../shared/devops-pipeline-overview.md#deliberately-absent) |
| Coverage threshold gate | Reported, not enforced — [testing-standards.md](./testing-standards.md#5-what-is-not-tested-here) |
| Dependency scanning | A declined cost, explained in [security-principles.md](../../shared/security-principles.md#out-of-scope-and-why-that-line-is-acceptable) |
| Load testing | No throughput target exists to regress against |
| Release tagging | Nothing consumes this as a versioned artifact |

---

## Secrets

**None.** The test database password is a throwaway defined in the workflow file. The
`hotelapp-context` checkout uses the default token, which suffices for a repo on the same account.

**No build-time secret is needed or possible**: this backend reads all configuration at runtime from
the environment, so there is nothing to bake in.

---

## Local equivalence

```bash
npm run ci        # lint && format:check && typecheck && test:run && build
```

CI running something a developer cannot reproduce locally is how a red build becomes someone else's
problem. The one thing `npm run ci` cannot reproduce is the second checkout — locally the context repo
is a sibling directory, in CI it is checked out. That difference is the asymmetry showing up one last
time, and it is why `HOTELAPP_MIGRATIONS_DIR` is configurable rather than hard-coded.
