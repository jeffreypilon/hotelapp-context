# Context Map

Index of this repository. Start here to find which document decides what.

`hotelapp-context` holds specifications only — no application code. It is read by human
developers and by coding agents working in the four implementation repos:
`hotelapp-client-react`, `hotelapp-client-angular`, `hotelapp-server-nodejs`,
`hotelapp-server-springboot`.

**Every decision lives in exactly one document.** Others cross-reference it. If two documents
appear to decide the same thing, one is stale — treat that as a bug.

---

## Read these first

In this order, regardless of what you are working on:

1. **[shared/project-overview.md](./shared/project-overview.md)** — what the product does, in
   plain language. Authoritative on scope: if a feature is not here, it is not in the project.
2. **[shared/data-model.md](./shared/data-model.md)** — the database schema. Authoritative on
   PostgreSQL 18.6, entities, constraints, and the no-overbooking guarantee.
3. **[shared/api-contracts.md](./shared/api-contracts.md)** — every REST endpoint.
   **Normative**: where an implementation disagrees with it, the implementation is wrong.

Those three are the project. Everything else elaborates them.

---

## `shared/` — decisions that bind all four repos

| Document | Read it when you need | Authoritative for |
|----------|----------------------|-------------------|
| [project-overview.md](./shared/project-overview.md) | To know whether something is in scope | Features, roles, workflows, business rules, out-of-scope list |
| [data-model.md](./shared/data-model.md) | To write a query, an entity, or a migration | Schema, constraints, enums, indexes, pricing formula, cancellation-deadline computation, ORM notes |
| [api-contracts.md](./shared/api-contracts.md) | To add or consume any endpoint | Paths, methods, auth tiers, request/response shapes, status codes, error catalogue, pagination, session protocol |
| [domain-glossary.md](./shared/domain-glossary.md) | A term is unfamiliar | Definitions. Decides nothing; points everywhere |
| [glossary-of-conventions.md](./shared/glossary-of-conventions.md) | Naming anything | Casing per layer, JSON↔SQL mapping, UI/prose terminology, commit and branch conventions |
| [architecture-overview.md](./shared/architecture-overview.md) | Orienting, or deciding where logic belongs | Component shape, request flow, layering, how the two backends are kept identical, what's excluded |
| [security-principles.md](./shared/security-principles.md) | Touching auth, validation, secrets, or headers | Threat model, password and lockout policy, CORS, injection posture, secrets, logging rules, out-of-scope line |
| [non-functional-requirements.md](./shared/non-functional-requirements.md) | Sizing, seeding, or judging "fast enough" | Data volumes, response targets, the explicit absence of high availability, browser matrix, a11y target |
| [acceptance-criteria.md](./shared/acceptance-criteria.md) | Writing tests | 40+ Given/When/Then criteria: no-overbooking, cancellation boundary, authorization, sessions. **Required in both backend repos** |
| [versioning-strategy.md](./shared/versioning-strategy.md) | Changing the API or the schema | Breaking-change definition, why no `/v2` exists, **migration ownership: Flyway executes, Prisma introspects** |
| [devops-pipeline-overview.md](./shared/devops-pipeline-overview.md) | Setting up CI | Per-repo jobs, the OpenAPI diff, the Compose smoke test |
| [local-integration-guide.md](./shared/local-integration-guide.md) | Running a frontend against a backend by hand, or switching which backend it talks to | The frontend×backend matrix, verified startup commands, and the switch procedure. A runbook, not a decision — cross-references each stack's own `environment-setup-guide.md` rather than repeating it |
| [phased-implementation-plan.md](./shared/phased-implementation-plan.md) | Asking "what's next" | Build order, per-phase definition of done, open items |
| [decision-log.md](./shared/decision-log.md) | Asking "why is this not X" | *Reversed* decisions only — five entries: dropped free-tier hosting, JWT→sessions, migration ownership, and two backend package-layout corrections (`domain/`'s exception hierarchy, Spring Boot's `web/` split) |
| [defect-log.md](./shared/defect-log.md) | Asking "what's still broken" or logging a real bug found in one of the four code repos | Open and fixed defects in application code — distinct from decision-log.md, which tracks specification reversals, not code bugs |

---

## `stacks/` — per-technology specifications

| Stack | Status |
|-------|--------|
| `stacks/react/` | ✅ **Written** (Phase 3) — 12 documents |
| `stacks/angular/` | ✅ **Written** (Phase 3) — 12 documents |
| `stacks/nodejs/` | ✅ **Written** (Phase 4) — 10 documents |
| `stacks/springboot/` | ✅ **Written** (Phase 4) — 10 documents |

**All 44 stack documents are written.** See
[phased-implementation-plan.md](./shared/phased-implementation-plan.md) for what each phase
delivered and what remains (Phase 5 onward: agent instructions, then implementation).

Ten documents common to all four stacks:

| Document | Holds |
|----------|-------|
| `architecture-specification.md` | Folder layout, routing, the API client layer, build tooling |
| `coding-standards.md` | Language and framework conventions, naming, what is forbidden |
| `testing-standards.md` | Test approach per layer, and **what these suites do not cover** |
| `error-handling.md` | Problem-code → user-facing message mapping |
| `security-implementation.md` | Where each policy control sits, and what must never reappear |
| `logging-observability.md` | Console logging and redaction. Deliberately thin |
| `environment-setup-guide.md` | Clone to running, literally |
| `devops-pipeline.md` | This stack's CI job |
| `dependency-policy.md` | The approved set, the prohibited set, and how to decide |
| `module-registry.md` | Inventory of modules and who owns what |

Two more in the frontend stacks only:

| Document | Holds |
|----------|-------|
| `ui-specifications.md` | **Screen by screen, S0–S15.** Sections 1–2 are byte-identical between the React and Angular files — any diff is a defect. Section 3 holds per-stack notes |
| `state-management.md` | Server-state, form, and session state. **The one place the two frontends differ in substance**: TanStack Query v5 for React, NgRx SignalStore for Angular |

### Documents held to cross-stack identity

Four pairs are byte-identical over their shared sections, not merely consistent. Each is built
from one shared body, and a CI diff of those sections is the analogue of the OpenAPI diff that
guards the two backends' wire behavior.

| Pair | Identical span | Why |
|------|---------------|-----|
| `react` / `angular` `ui-specifications.md` | §1–2 | Both clients must deliver the same screens, states, and copy |
| `react` / `angular` `error-handling.md` | §1–4 | A guest must see the same message text in either client |
| `nodejs` / `springboot` `error-handling.md` | §1–5 | The two backends must emit the same status, `code`, `title`, and `detail` for the same condition |
| `nodejs` / `springboot` `testing-standards.md` | §1–5 | Both must satisfy the same 44 acceptance criteria at the same layers |

### The one asymmetry

The two frontends are peers. **The two backends are not.** Flyway is the sole DDL executor and
runs in `springboot`; `nodejs` introspects with `prisma db pull` and cannot migrate a database
unaided — [versioning-strategy.md](./shared/versioning-strategy.md#database-schema-migrations),
logged as a reversal in [decision-log.md](./shared/decision-log.md). That shapes both backends'
`architecture-specification.md`, `environment-setup-guide.md`, `devops-pipeline.md`,
`security-implementation.md`, and `testing-standards.md`. A backend document that reads as
symmetric on schema, migrations, or database privilege is probably wrong.

Rule for all stack documents: one may say **how** its technology satisfies a shared
requirement. It may not restate or contradict the requirement.

---

## Finding things by task

| Task | Documents |
|------|-----------|
| Add an endpoint | api-contracts (first), then data-model, glossary-of-conventions, acceptance-criteria |
| Change the schema | data-model, versioning-strategy (migration rules), then both backends' mappings |
| Implement auth | api-contracts § Authentication, data-model § sessions, security-principles |
| Understand no-overbooking | data-model § No overbooking, acceptance-criteria § 1 |
| Understand the 48-hour rule | project-overview § Business Rules, data-model § Cancellation policy, acceptance-criteria § 2 |
| Write tests | acceptance-criteria, then the stack's `testing-standards.md` |
| Set up a repo | The stack's `environment-setup-guide.md`, devops-pipeline-overview |
| Name something | glossary-of-conventions; domain-glossary for the concept itself |
| Judge scope | project-overview, plus the "deliberately absent" sections of architecture-overview, security-principles, and devops-pipeline-overview |

---

## Conventions in this repo

- One topic per file, `kebab-case.md`, H1 matching the subject.
- Cross-reference with a link and a one-line summary; never copy reasoning.
- Judgment calls are marked `> **Design Decision — ...**`; gaps in the source material are
  marked `> **Assumption ...**`. Both are searchable, so every place the project chose
  something can be found and reviewed.
- Prose wraps at 90 columns; tables and code may exceed it.
