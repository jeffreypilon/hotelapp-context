# DevOps Pipeline Overview

CI and local orchestration for HotelApp's five repos.

**This is a portfolio project's pipeline, and the document is written to that scale on
purpose.** There is no hosted environment, no staging, no Kubernetes, no deployment step at
all. What CI does here is answer one question per push — *does this still build, pass its
tests, and honor the contract?* — and stop. Inventing a delivery pipeline with nothing to
deliver to would be the most obvious possible padding, and a reviewer would read it as
exactly that.

Stack-specific pipeline detail belongs in `stacks/<tech>/devops-pipeline.md` (Phases 3 and
4). This document holds the shape common to all five repos and the two checks that are
genuinely cross-repo.

---

## What exists

| Concern | Decision |
|---------|----------|
| CI platform | GitHub Actions — all five repos are on GitHub, so it needs no extra account or runner |
| Triggers | Push to `main`, and pull requests targeting `main` |
| Deployment | **None.** No environment to deploy to |
| Local development | Native processes: PostgreSQL 18.6, one backend, one frontend dev server |
| Containerization | Docker Compose, later. Not a prerequisite for development |
| Container orchestration | **None.** No Kubernetes, no Swarm, no Helm |
| Environments | Local only. No dev/staging/prod ladder |
| Artifact registry | **None.** Images are built locally and not published |
| Release process | **None.** No tags, no versioned releases, no changelog |
| Monitoring, alerting, tracing, log aggregation | **None.** See the end of this document |

---

## Per-repo CI

Every repo runs a small, fast job. The target is **under five minutes**, because a pipeline
slower than that stops getting run before pushing, and an ignored pipeline is worse than a
short one.

### All repos

| Step | What it does |
|------|--------------|
| Checkout | |
| Toolchain setup | With dependency caching — npm cache, Maven/Gradle cache |
| Install | From the committed lockfile. `npm ci`, not `npm install` — a lockfile that isn't respected isn't a lockfile |
| Lint | Fails the build. A warning nobody acts on is noise |
| Format check | `prettier --check` / `spotless:check`. Verify, never rewrite, in CI |
| Build | Type-check and compile |
| Test | Unit, then integration |

### `hotelapp-context` (this repo)

Documentation only, so CI verifies the documents rather than compiling anything:

- **Markdown link check** — every relative link between `shared/` and `stacks/` documents
  resolves, and no anchor points at a heading that no longer exists. These thirteen documents
  cross-reference each other heavily by design, per
  [glossary-of-conventions.md](./glossary-of-conventions.md#documentation-conventions-in-this-repo),
  and a broken link is the first visible symptom of drift.
- **Markdown lint** — consistent heading hierarchy, fenced code blocks tagged with a language.
- **No trailing whitespace, files end with a newline.**

That is the whole job, and it is worth having: a link check is the only automated test a
specification repo can meaningfully run, and it catches the thing that actually breaks.

### Backend repos (`hotelapp-server-nodejs`, `hotelapp-server-springboot`)

Both need a real PostgreSQL for integration tests — **not H2, not an in-memory substitute,
not a mock**, for the reason given in
[acceptance-criteria.md](./acceptance-criteria.md): several criteria test PostgreSQL behavior
specifically (an exclusion constraint, `daterange` overlap semantics, timezone arithmetic), and
a substituted database would let those tests pass while proving nothing.

```
services:
  postgres:
    image: postgres:18.6
    env:
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: hotelapp_test
    options: >-
      --health-cmd pg_isready --health-interval 10s
      --health-timeout 5s --health-retries 5
```

Steps beyond the common set:

| Step | Notes |
|------|-------|
| Apply migrations | Flyway against the canonical SQL in `hotelapp-context`, per [versioning-strategy.md](./versioning-strategy.md#database-schema-migrations). **The Node repo needs those SQL files too** — see the note below |
| Schema validation (Spring only) | `ddl-auto=validate` means startup itself is the check: entity mappings that disagree with the schema fail the build |
| Integration tests | Against the live database, including the concurrency test in [AC-OB-01](./acceptance-criteria.md#ac-ob-01--two-concurrent-bookings-for-the-last-room-exactly-one-wins) |
| Clock-controlled tests | The cancellation-boundary criteria require an injectable clock in both backends |
| Publish the OpenAPI document | Generate `openapi.json` and upload it as a build artifact, for the diff job below |

> **The Node repo's migration problem, and how CI handles it.** Flyway is the only executor and
> the canonical SQL lives in `hotelapp-context`, so the Node backend cannot build its own test
> database unaided — the asymmetry is acknowledged in
> [versioning-strategy.md](./versioning-strategy.md#database-schema-migrations). In CI, the
> Node job checks out `hotelapp-context` as a second checkout and runs the **standalone Flyway
> CLI** against those SQL files. No Java application is needed, just the Flyway container or
> CLI, which keeps the Node repo's pipeline free of a JVM build.
>
> Pinning the context checkout to `main` means a merged contract change immediately affects the
> Node repo's CI. That is the intended behavior — it is how a schema change that the Node
> backend has not caught up with becomes visible — but it does mean the Node repo's build can
> go red because of a commit in a different repo. In a polyrepo with a shared schema that is
> unavoidable, and it is better to learn it from CI than from a runtime error.

### Frontend repos (`hotelapp-client-react`, `hotelapp-client-angular`)

| Step | Notes |
|------|-------|
| Lint, format, type-check | |
| Unit and component tests | |
| Production build | Catches what dev-mode never does |
| Bundle size check | Against the budget in [non-functional-requirements.md](./non-functional-requirements.md#response-time-targets). A warning, not a failure |

No end-to-end browser tests in per-repo CI. They need a running backend and database, which is
what the Compose smoke test is for.

---

## The two cross-repo checks

These are the checks that exist *because* this project is four implementations of one contract.
Everything above is ordinary; these are the ones worth the reviewer's attention.

### 1. The OpenAPI diff

**The primary automated defense against the two backends drifting apart**, required by
[api-contracts.md](./api-contracts.md#cross-cutting-requirements) and named as an enforcement
layer in
[architecture-overview.md](./architecture-overview.md#how-the-two-backends-stay-identical).

How it runs: each backend's CI publishes its generated `openapi.json` as an artifact. A job in
`hotelapp-context` — scheduled daily and manually dispatchable — fetches the latest artifact
from both repos and compares them.

What it compares, and what it tolerates:

| Compared | Tolerated |
|----------|-----------|
| The set of paths | Ordering of paths, properties, or enum members |
| The set of methods per path | `summary`, `description`, and example values |
| Required vs. optional per field | `operationId` naming differences between generators |
| Field names and types per schema | Generator-specific extensions (`x-*`) |
| Response status codes per operation | Formatting and whitespace |
| Enum members per field | |

**A meaningful diff fails the job**, and the failure means one backend violates the contract —
the job does not say which, and deciding that requires reading
[api-contracts.md](./api-contracts.md), which is the point.

> **Design Decision — a normalizing comparison, not a raw `diff`.**
> `springdoc-openapi` and a Node generator will never produce byte-identical JSON: they order
> keys differently, generate different `operationId`s, and emit different vendor extensions. A
> raw text diff would fail on every run and be switched off within a week. The check must
> normalize both documents — sort keys, drop descriptions and examples, drop `x-*` — then
> compare structurally. An off-the-shelf tool such as `oasdiff` does this; a small script that
> canonicalizes both documents and diffs the result is also sufficient and easier to tune.
>
> The check is **scheduled rather than blocking**, because it depends on artifacts from two
> other repos and cannot be a required status check on either backend's pull requests without
> making each repo's CI depend on the other's last successful build. Daily is frequent enough
> to catch drift while it is still one commit old.

### 2. The Docker Compose smoke test

The only test that exercises the system as a system, and the only place
[AC-SE-05](./acceptance-criteria.md#ac-se-05--a-session-works-interchangeably-against-both-backends)
— the cross-backend session proof — can actually run, since it needs both backends live at
once.

Compose topology for the smoke test: **one database, both backends, no frontend.**

```
services:
  db:              postgres:18.6, healthcheck, tmpfs volume
  flyway:          applies canonical migrations, exits 0
  seed:            loads demo data, exits 0
  api-node:        hotelapp-server-nodejs      → :3000
  api-spring:      hotelapp-server-springboot  → :8080
```

Both backends against one database is not the normal runtime shape — normally one runs at a
time — but it is exactly the shape that makes interchangeability testable. The smoke test then
runs as a shell or HTTP script:

| # | Step | Asserts |
|---|------|---------|
| 1 | `GET /health` on both | Both up, database up, `backend` field distinguishes them |
| 2 | `GET /api/v1/properties` on both | Identical response bodies from both backends |
| 3 | `POST /api/v1/auth/login` against **Node** | `200`, session cookie set |
| 4 | `GET /api/v1/auth/me` against **Spring**, same cookie | `200`, same user — **AC-SE-05** |
| 5 | `GET /availability` on both | Identical results |
| 6 | `POST /reservations` against **Spring** | `201`, confirmation number returned |
| 7 | `GET /reservations` against **Node** | The new reservation is visible |
| 8 | `POST /auth/logout` against **Spring** | `204` |
| 9 | `GET /auth/me` against **Node**, same cookie | `401` — logout crossed backends |
| 10 | Two concurrent `POST /reservations` for the last room, one against each backend | Exactly one `201`, one `409` — **AC-OB-01 across two processes** |

Step 10 is the strongest version of the no-overbooking test available anywhere in the project:
two *different implementations in different languages* racing for the same room, arbitrated by
the database constraint. No application-level locking scheme could pass it, which is the
clearest possible demonstration of why the guarantee belongs in the database. Steps 4 and 9 are
the session proof.

The whole script should run in **under two minutes** and be runnable locally with one command,
because a smoke test that only runs in CI is one nobody uses while debugging.

> Compose is also, separately, the intended way for someone else to run this project: one
> command for a database, a backend, and a frontend, with no native PostgreSQL install. That
> matters for a portfolio piece — a reviewer who has to install PostgreSQL 18 and configure a
> JDK before seeing anything will not see anything. The smoke-test topology above is the
> two-backend variant; per-stack "just run it" Compose files belong in the implementation repos.

---

## Local development

Native, not containerized, for the inner loop. Compose is for verification and for other
people, not for day-to-day work — rebuilding a container to see a code change is a worse
experience than either framework's hot reload.

```
PostgreSQL 18.6   native, localhost:5432, database `hotelapp`
Migrations        Flyway against hotelapp-context/shared/migrations/
Backend           one of the two — :3000 (Node) or :8080 (Spring)
Frontend          one of the two — Vite or ng serve, proxying /api to the backend
```

Both backends can run simultaneously when testing interchangeability, and both share the
`localhost` cookie jar regardless of port — the property
[AC-SE-05](./acceptance-criteria.md#ac-se-05--a-session-works-interchangeably-against-both-backends)
depends on, noted in
[architecture-overview.md](./architecture-overview.md#deployment-shape).

Per-stack setup steps — exact commands, `.env.example` contents, seeding — belong in
`stacks/<tech>/environment-setup-guide.md`.

---

## Secrets in CI

- CI needs **no real secrets.** The test database is ephemeral with a throwaway password
  defined in the workflow file; nothing else in the pipeline authenticates anywhere.
- If a future step ever needs one, it goes in GitHub Actions encrypted secrets — never in a
  workflow file, never in a committed `.env`, per
  [security-principles.md](./security-principles.md#secrets-and-configuration).
- Workflows use pinned action versions rather than floating tags, for the same
  reproducibility reason Docker images are pinned in
  [versioning-strategy.md](./versioning-strategy.md#versions-of-the-platform-itself).

---

## Deliberately absent

Each of these is standard in a production pipeline and would be padding here. Listed so the
scope is a visible choice.

| Absent | Why |
|--------|-----|
| **Deployment of any kind** | There is no environment. This is the root reason for most of the rest of this table |
| **Staging / preview environments** | Nothing to stage toward |
| **Kubernetes, Helm, Terraform, any IaC** | No infrastructure to describe |
| **Container registry, image publishing** | Images are built locally and thrown away |
| **Blue-green, canary, rolling deploys** | No deployment to strategize about |
| **Release tagging, semantic versioning of the apps** | Nothing is consumed as a versioned artifact. The API's versioning is separate and covered in [versioning-strategy.md](./versioning-strategy.md) |
| **Dependency scanning, SAST, secret scanning** | Considered and declined in [security-principles.md](./security-principles.md#out-of-scope-and-why-that-line-is-acceptable), which also notes this is the easiest item here to add later |
| **Code coverage gates** | Coverage thresholds reward writing tests that execute lines. The acceptance criteria are the meaningful bar, and they are behavioral |
| **Performance / load testing in CI** | No throughput target exists to regress against — [non-functional-requirements.md](./non-functional-requirements.md#throughput-and-concurrency). The one performance check worth having is asserting the availability query's plan uses the GiST index, which belongs in the backend integration suites |
| **Monitoring, APM, log aggregation, tracing, alerting** | Nothing is running to observe. Requests carry a `traceId` so the correlation story exists if an environment ever does |
| **Automated database backups** | Recovery is reseeding, per [non-functional-requirements.md](./non-functional-requirements.md#availability) |
| **End-to-end browser tests (Playwright/Cypress) in CI** | The genuine gap in this pipeline. The Compose smoke test covers API-level integration; nothing exercises either frontend automatically. Worth adding for one flow — search, book, confirm — against one frontend and one backend, once both exist. Named here rather than quietly omitted |

**The honest summary.** This pipeline does three things: it keeps each repo building and
tested, it proves the two backends implement the same contract (OpenAPI diff), and it proves
the four components work together (Compose smoke test). Those are the claims the project makes.
Everything else on the list above belongs to operating a service, which this project does not
do.
