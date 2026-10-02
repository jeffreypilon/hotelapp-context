# DevOps Pipeline — AI Service

This repository's CI job.

The shape common to all repos, the two cross-repo checks, and the deliberate absence of any
deployment step are in
[devops-pipeline-overview.md](../../shared/devops-pipeline-overview.md) and are not restated.
This document covers what is specific to a Python service with a probabilistic dependency.

**Target: under five minutes** for the per-commit job, same as every other repo. The evaluation
suite is deliberately *not* in that budget — see §3.

---

## 1. The per-commit job

| Step | Command | Notes |
|------|---------|-------|
| Checkout | | Plus a **second checkout of `hotelapp-context`**, pinned to `main`, for the migrations |
| Toolchain | `uv` + Python 3.13 | With cache |
| Install | `uv sync --frozen` | Fails on a stale lockfile — this stack's `npm ci` |
| Lint | `ruff check .` | Fails the build |
| Format | `ruff format --check .` | Verify, never rewrite, in CI |
| Type-check | `mypy src` | Strict. Fails the build |
| Layering | `lint-imports` | See §2 |
| Boundary grep | see §2 | See §2 |
| Unit tests | `pytest tests/unit` | No infrastructure |
| Integration tests | `pytest tests/integration` | Postgres + Flyway + a backend, below |
| Image build | `docker build` | Catches what a local run never does |

### Services the integration job needs

```yaml
services:
  db:
    image: pgvector/pgvector:pg18      # NOT postgres:18.6 -- no third-party extensions
    env:
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: hotelapp_test
    options: >-
      --health-cmd pg_isready --health-interval 10s
      --health-timeout 5s --health-retries 5
```

Then, in order:

1. **Flyway CLI against the second checkout's `shared/migrations/`** — including
   `V002__ai_tables.sql`. Identical to how the Node repo's CI migrates a database it cannot
   migrate itself, and for the same reason: Flyway is the sole DDL executor.
2. **A backend container**, because this service reads business data over REST and no database
   fixture can substitute for one. Spring Boot by default.
3. **The LLM provider is stubbed.** No provider key is present in the per-commit job, and none is
   needed — provider output is non-deterministic and asserting on it belongs to the evaluation
   suite.

> **The per-commit job needs no secrets at all.** The database password is a throwaway defined in
> the workflow, the provider is stubbed, and nothing else authenticates anywhere — matching the
> project-wide position in
> [devops-pipeline-overview.md](../../shared/devops-pipeline-overview.md#secrets-in-ci).

---

## 2. Two checks that exist only here

### The layering rule is enforced, not documented

`lint-imports` (import-linter) encodes the contract in
[module-registry.md](./module-registry.md#import-rules-stated-once) as a CI-checkable
configuration: `transport/` may not import `langchain`, `openai` or `psycopg`; `services/` may not
import `fastapi` or `fastmcp`; `gateways/` and `repositories/` may not import each other;
`domain/` may import nothing from this project.

A layering rule that lives only in prose is a layering rule that decays. This project has already
had two package-layout mistakes reach code and require refactors
([decision-log.md](../../shared/decision-log.md) entries 4 and 5); both were the kind a linter
catches for free.

### The REST-only rule is greppable

```bash
! grep -rE '\b(reservations|properties|room_types|rooms|users|sessions|payments)\b' src/hotelapp_ai/repositories/
```

A hit means SQL is reaching a business table, which is the one constraint this component is
built around
([architecture-specification.md](./architecture-specification.md#the-rest-only-rule-and-what-it-means-for-this-repo)).
Crude, and it works — the same instinct as the banned-token grep both frontends already run.

The database role's grants enforce the same thing at runtime, so this check is the fast feedback,
not the only defence.

---

## 3. The evaluation job runs on a different trigger

RAGAS uses an LLM judge, so every run **costs money and takes minutes**. Putting it in the
per-commit job would blow the five-minute target and bill for commits that cannot have affected
quality.

| Trigger | Why |
|---------|-----|
| **Pull requests touching** `prompts/`, `services/assistant.py`, `services/ingestion.py`, `domain/chunking.py`, `domain/fusion.py`, `corpus/`, or `pyproject.toml` | These are the only paths that can move answer quality. Path-filtered, so unrelated PRs are not charged |
| **Nightly, scheduled** | Catches provider-side model drift, which changes nothing in this repository and would otherwise go unnoticed |
| **Manual dispatch** | For deliberate tuning runs |

**It needs a real provider key**, which is the one secret this repository's CI uses. It lives in
GitHub Actions encrypted secrets, never in a workflow file
([security-principles.md](../../shared/security-principles.md#secrets-and-configuration)).

**A floor breach fails the job.** Faithfulness and context recall have committed minimum values,
and a drop below either is a failure in exactly the way a failing test is — see
[testing-standards.md](./testing-standards.md#5-the-evaluation-suite). Results are written to
`ai_eval_runs` so quality over time is queryable rather than remembered.

> **This is the gate the other four repos do not have, and it exists because their assumption does
> not hold here.** Everywhere else in this project, a green test suite means a change is safe. A
> model, embedding or prompt change can leave every test passing while the assistant gets worse,
> and nothing in pytest can see it.

---

## 4. Not in this pipeline

| Absent | Why |
|--------|-----|
| **Deployment** | No environment, unchanged project-wide |
| **Image publishing** | Images are built in CI to prove they build, then discarded. No registry |
| **The OpenAPI diff** | That check exists to prove the *two backends* agree. This service is not one of them and has no counterpart to diff against |
| **Coverage gates** | Same position as everywhere else: the acceptance criteria and the evaluation floors are the meaningful bars, and both are behavioural |
| **Load or cost testing** | No throughput target exists to regress against. Per-request cost is recorded at runtime instead |
| **A provider key in the per-commit job** | §1 |

---

## 5. Where this service appears in the Compose smoke test

The two-backend smoke test in
[devops-pipeline-overview.md](../../shared/devops-pipeline-overview.md#2-the-docker-compose-smoke-test)
is **not** extended to cover this service.

That test exists to prove the two backends are interchangeable, which is a property of them, not
of their consumers. Adding an AI service to it would slow the strongest demonstration in the
project to prove something unrelated — and the AI service's own interchangeability (it runs
unmodified against either backend) is asserted by its own integration suite, parameterized over
both.

The additive-ness guarantee runs the other way and *is* tested: every existing acceptance criterion
must still pass with this service stopped
([testing-standards.md](./testing-standards.md#additive-ness)).
