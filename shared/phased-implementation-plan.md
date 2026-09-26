# Phased Implementation Plan

The build order for HotelApp, from specification to running application, with a concrete
definition of "done" for each phase.

The sequencing principle: **specify what is shared before what is stack-specific, and specify
everything before implementing anything.** Two frontends and two backends that must behave
identically cannot be written first and reconciled afterward — the reconciliation is the hard
part, and doing it on paper is enormously cheaper than doing it in four codebases.

---

## Phase status at a glance

| Phase | Scope | Status |
|-------|-------|--------|
| 1 | `shared/project-overview.md` | ✅ Done |
| 1a | `shared/data-model.md`, `shared/api-contracts.md` | ✅ Done |
| 1b | Auth redesign: JWT → server-side sessions | ✅ Done |
| 2 | The remaining nine `shared/` documents | ✅ Done (this document is part of it) |
| 3 | `stacks/react/` + `stacks/angular/` | ⬜ Next |
| 4 | `stacks/nodejs/` + `stacks/springboot/` | ⬜ |
| 5 | `copilot-instructions.md` / `CLAUDE.md` per implementation repo | ⬜ |
| 6 | Backend implementation | ⬜ |
| 7 | Frontend implementation | ⬜ |
| 8 | Integration, smoke test, polish | ⬜ |

---

## Completed phases

### Phase 1 — Product definition ✅

[project-overview.md](./project-overview.md): users, roles, workflows, business rules, and
scope boundaries in plain language. The single source of truth for *what the application
does*, and the document every later one defers to on questions of product scope.

### Phase 1a — Data model and API contract ✅

[data-model.md](./data-model.md) and [api-contracts.md](./api-contracts.md), written together
because neither is decidable without the other.

Established: PostgreSQL 18.6; real room units as the bookable inventory; the no-overbooking
exclusion constraint; per-property rate plans; snapshot pricing on reservations; the stored
cancellation deadline; RFC 9457 error format; offset pagination; money as decimal strings;
and the rule that search returns room types while the server allocates the specific room.

Four open questions were resolved by decision rather than left ambiguous: room units vs.
per-type counts, discount granularity, admin property scoping, and flat vs. seasonal rates.

### Phase 1b — Authentication redesign ✅

Replaced JWT access tokens plus rotating refresh tokens with **server-side sessions** in the
shared database, after the free-tier hosting stretch goal was dropped and removed the
cross-origin topology the token design was solving for.

Net effect: one `sessions` table, one `HttpOnly; SameSite=Lax` cookie, immediate revocation, and
roughly a hundred lines of token-handling machinery per frontend that will now never be
written. The reasoning is preserved in
[api-contracts.md](./api-contracts.md#authentication) — including what it gives up — so the
trade is visible to a reviewer rather than implied.

### Phase 2 — Shared specifications ✅

The remaining nine `shared/` documents:

| Document | Establishes |
|----------|-------------|
| [glossary-of-conventions.md](./glossary-of-conventions.md) | Casing across layers, nested-object mapping, prose/UI terminology, Conventional Commits |
| [domain-glossary.md](./domain-glossary.md) | Every domain term, with pointers to where each is specified |
| [architecture-overview.md](./architecture-overview.md) | System shape, request flow, where logic lives, the four drift-prevention layers |
| [security-principles.md](./security-principles.md) | Threat model, password and lockout policy, CORS, validation, injection, secrets, headers, and the out-of-scope line |
| [non-functional-requirements.md](./non-functional-requirements.md) | Demo-scale volumes, response targets, the plainly-stated absence of high availability, browser matrix |
| [acceptance-criteria.md](./acceptance-criteria.md) | 40+ Given/When/Then criteria across no-overbooking, the cancellation boundary, authorization, and sessions |
| [versioning-strategy.md](./versioning-strategy.md) | Breaking-change policy, why no `/v2` is built, and the one-executor migration rule |
| [devops-pipeline-overview.md](./devops-pipeline-overview.md) | Per-repo CI, the OpenAPI diff, the Compose smoke test |
| [phased-implementation-plan.md](./phased-implementation-plan.md) | This document |

`shared/decision-log.md` remains a stub — see
[Open items](#open-items-carried-into-phase-3).

**Phase 2's most consequential new decision** is the migration ownership rule in
[versioning-strategy.md](./versioning-strategy.md#database-schema-migrations): canonical
numbered SQL lives in this repo, Flyway is the only executor, and Prisma consumes the schema by
introspection rather than authoring it. That constrains Phase 4 on both backends and should be
reviewed before Phase 4 begins.

---

## Phase 3 — Frontend stack specifications ⬜

**Scope:** `stacks/react/` and `stacks/angular/`, twelve documents each.

**Written together, not sequentially.** The two frontends must deliver the same features,
screens, and UI copy with different frameworks. Writing React's specification first and
Angular's later guarantees the second drifts toward its framework's idioms — the divergence
would be in what the apps *do*, not just how they are built, which is the one kind of
difference this project cannot afford.

The documents per stack:

| Document | Purpose |
|----------|---------|
| `architecture-specification.md` | App structure, routing, module or folder organization, API client layer |
| `coding-standards.md` | Language and framework conventions, component patterns, naming |
| `ui-specifications.md` | **Screen by screen**, shared across both stacks — the anti-drift document |
| `state-management.md` | Server-state caching, form state, auth state. Framework-specific answers to one shared question |
| `error-handling.md` | Mapping RFC 9457 problems to user-facing messages |
| `testing-standards.md` | Unit, component, and integration test approach and coverage expectations |
| `security-implementation.md` | `credentials: "include"`, route guards, XSS discipline, no token storage |
| `logging-observability.md` | Client-side error surfacing. Deliberately thin |
| `environment-setup-guide.md` | Clone to running, including `.env.example` and backend URL config |
| `devops-pipeline.md` | This stack's CI job specifics |
| `dependency-policy.md` | What may be added and what must not |
| `module-registry.md` | Inventory of modules/components and their responsibilities |

**`ui-specifications.md` is the important one**, and the work of Phase 3 is mostly in it:
every screen, its layout, its states (loading, empty, error, success), its validation
messages, and its exact UI copy. Two clients built from one screen specification can be
compared like for like; two clients built from a feature list cannot. UI copy in particular
must come from
[glossary-of-conventions.md](./glossary-of-conventions.md#terminology-in-prose-and-ui-copy) —
"Front Desk" and "Manager" verbatim, not each frontend's own wording.

**Done means:**

1. All 24 documents written, no stubs.
2. `ui-specifications.md` covers every screen implied by
   [project-overview.md](./project-overview.md)'s workflows: property list, property detail,
   search and results, booking summary, login and registration, payment form, confirmation,
   guest account and booking history, admin booking list, check-in/check-out, the room/rate
   calendar, property and room-type management, rate-plan management, and the two reports.
3. Every endpoint in [api-contracts.md](./api-contracts.md) is consumed by at least one
   specified screen — and any endpoint no screen needs is identified, since it may be surplus
   contract surface.
4. The two stacks' specifications differ **only** where the frameworks genuinely differ
   (state management, routing syntax, component idiom) and are identical on features, screens,
   copy, validation rules, and error handling.
5. Responsive behavior matches the guest-mobile-first / admin-desktop-first split in
   [non-functional-requirements.md](./non-functional-requirements.md#browser-and-device-support).
6. Accessibility expectations per screen are stated, not just the WCAG 2.1 AA target.
7. No contract changes were needed — or, if any were, they were made in
   [api-contracts.md](./api-contracts.md) first and are listed in the phase summary.

**Risk to watch.** Phase 3 is the most likely place to discover the API contract is missing
something, because it is the first time anyone walks the actual screens. That is the point of
doing it before implementation. The rule: **change the contract, do not work around it in a
frontend specification.** A shim in one client is drift with extra steps.

---

## Phase 4 — Backend stack specifications ⬜

**Scope:** `stacks/nodejs/` and `stacks/springboot/`, ten documents each — the same list as
Phase 3 minus `ui-specifications.md` and `state-management.md`.

Also written together, for the same reason: two implementations of one contract, where the
interesting content is how each stack satisfies a shared requirement.

Inputs already fixed, not to be reopened: Express and Prisma; Spring Boot and JPA/Hibernate;
the three-layer separation in
[architecture-overview.md](./architecture-overview.md#backend-architecture-in-outline);
bcrypt cost 12; the migration ownership rule; and the specific ORM constraints in
[data-model.md](./data-model.md#orm-generation-notes).

**The specifically hard parts**, each of which needs a concrete answer per stack rather than a
gesture:

| Problem | Why it needs care |
|---------|-------------------|
| Prisma cannot express the exclusion constraint, the `daterange` generated column, or the composite foreign keys | Hand-written migration SQL plus `Unsupported(...)` mappings. Already diagnosed in [data-model.md](./data-model.md#no-overbooking) |
| Catching SQLSTATE `23P01` and mapping it to `409 ROOM_UNAVAILABLE` | Different exception types, identical outcome required |
| Room allocation with retry on conflict | 3 attempts, lowest room number, identical order in both — [AC-OB-07](./acceptance-criteria.md#ac-ob-07--allocation-order-is-deterministic) |
| Decimal arithmetic and rounding order | `Prisma.Decimal` vs `BigDecimal`, same result to the cent — [AC-CX-10](./acceptance-criteria.md#ac-cx-10--pricing-arithmetic-and-rounding-order) |
| Timezone arithmetic for the cancellation deadline | Must not depend on the process timezone — [AC-CX-04](./acceptance-criteria.md#ac-cx-04--deadline-respects-the-propertys-timezone-not-the-servers) |
| Session middleware, including the 5-minute write-throttle | Express middleware vs. a Spring Security filter; same numbers |
| Injectable clock | Required by the cancellation criteria, painful to retrofit — decide it here |
| RFC 9457 generation | Spring Boot 3 has `ProblemDetail` natively; Node needs it built |
| OpenAPI 3.1 generation that survives the diff | `springdoc-openapi` vs. a Node generator, normalized comparison per [devops-pipeline-overview.md](./devops-pipeline-overview.md#1-the-openapi-diff) |
| DTOs distinct from ORM entities | No entity is ever serialized directly |

**Done means:**

1. All 20 documents written, no stubs.
2. Every endpoint in [api-contracts.md](./api-contracts.md) maps to a named controller,
   service, and repository in both stacks.
3. Every entity in [data-model.md](./data-model.md) maps to a Prisma model and a JPA entity,
   with the `Unsupported`/`@Generated` cases explicitly handled.
4. Every criterion in [acceptance-criteria.md](./acceptance-criteria.md) maps to a named test
   in both stacks' `testing-standards.md`.
5. The migration workflow from
   [versioning-strategy.md](./versioning-strategy.md#database-schema-migrations) is written as
   concrete commands per stack, including how the Node repo obtains and applies the canonical
   SQL.
6. The canonical `V001__initial_schema.sql` exists in this repo — Phase 4's one code-shaped
   deliverable, and the point at which the schema stops being prose.
7. Both stacks' `environment-setup-guide.md` takes a reader from clone to a running API with a
   seeded database.

---

## Phase 5 — Per-repo agent instructions ⬜

**Scope:** `copilot-instructions.md` and/or `CLAUDE.md` in each of the four implementation
repos, plus this one.

Each file is short and points into this repo rather than duplicating it. The established
pattern: a root `CLAUDE.md` whose body imports `.github/copilot-instructions.md` so Copilot and
Claude share one source of truth, plus a required-reading table naming which `shared/` and
`stacks/` documents to read for which kind of task.

**The known constraint, learned the hard way:** an `@`-import pointing *outside* a repo does
not reliably load — a sibling-repo `@../hotelapp-context/...` import will silently not resolve.
So cross-repo references must be **instructions to read a path**, not `@` imports. Only
in-repo files may be `@`-imported.

**Done means:** a fresh coding-agent session in any implementation repo, given only "implement
X", finds its way to the right specification documents without being told they exist — and
verifiably so, tested in a clean session per repo rather than assumed.

---

## Phase 6 — Backend implementation ⬜

Build both backends. **One at a time, and the harder one first.**

> **Recommendation — Spring Boot first.** It is the stack that must apply the canonical
> migrations (Flyway is the executor), so building it first makes the schema real and gives the
> Node backend a migrated database to introspect from day one. Building Node first would mean
> either hand-running Flyway before Prisma can introspect anything, or discovering the
> ownership asymmetry at the least convenient moment. This is a recommendation, not a fixed
> decision — worth confirming before Phase 6 starts.

Suggested order within each backend, each step ending somewhere demonstrable:

1. Project skeleton, configuration, database connection, `GET /health`.
2. Migrations applied; entities or Prisma models generated; schema validation passing.
3. Sessions: register, login, logout, `/auth/me`. **The first real milestone** — and the point
   at which [AC-SE-05](./acceptance-criteria.md#ac-se-05--a-session-works-interchangeably-against-both-backends)
   becomes testable once the second backend reaches the same step.
4. Public catalogue: properties, room types, amenities, rate categories.
5. Availability search — the most complex query, and worth an `EXPLAIN` check as specified in
   [non-functional-requirements.md](./non-functional-requirements.md#response-time-targets).
6. Booking: `POST /reservations` with allocation, dummy payment, and the exclusion constraint
   caught and mapped. **The central feature.**
7. Guest reservation management: list, detail, modify, cancel, with the 48-hour boundary.
8. Guest profile and password change.
9. Admin reservations: list, detail, check-in, check-out, staff cancel.
10. Admin inventory: properties, room types, rooms, photos, rate plans.
11. Admin calendar and reports.
12. Cross-cutting: security headers, CORS, rate limiting, log masking, OpenAPI document.

**Done means:** both backends pass every criterion in
[acceptance-criteria.md](./acceptance-criteria.md); the OpenAPI diff is clean; CI is green in
both repos; both serve identical responses to the same requests against the same database.

---

## Phase 7 — Frontend implementation ⬜

Build both clients from Phase 3's specifications. Again one at a time, and **React first** —
the smaller framework surface gets the shared decisions settled faster, and Angular then
implements a specification already proven to be implementable.

Suggested order, mirroring the backend's so each layer has something to talk to:

1. Skeleton, routing, Tailwind setup, API client with `credentials: "include"`.
2. Public browsing: property list and detail, room types.
3. Search: filters, sorting, results, pricing display.
4. Auth: login, registration, session bootstrap via `/auth/me`, route guards.
5. Booking flow: summary, payment form, confirmation.
6. Guest account: profile, booking history, modify, cancel.
7. Admin: booking list and filters, check-in/check-out.
8. Admin: calendar, inventory management, rate plans, reports.
9. Accessibility and responsive passes against the Phase 3 specification.

**Done means:** both clients implement every specified screen; either can be pointed at either
backend by changing one configuration value and behaves identically; the accessibility and
responsive targets are met; builds are within the bundle budget.

---

## Phase 8 — Integration and polish ⬜

1. **The Compose smoke test** from
   [devops-pipeline-overview.md](./devops-pipeline-overview.md#2-the-docker-compose-smoke-test),
   including the two-backend concurrency race in step 10 — the strongest demonstration in the
   project.
2. **Compose files for running the whole thing**, so a reviewer needs one command rather than a
   PostgreSQL install.
3. **Seed data at the volumes in
   [non-functional-requirements.md](./non-functional-requirements.md#scale)** — three
   properties, ~300 rooms, ~3,000 reservations. Realistic data is what makes search results,
   the calendar, and the reports look like a real system rather than a form demo.
4. **The four-way interchangeability walkthrough**: each frontend against each backend.
5. **Per-repo `README.md`** — currently one line each. Screenshots, what it is, how to run it,
   and a pointer to `hotelapp-context`. For a portfolio piece these are the most-read files in
   the project and currently the least written.
6. **Optional, if wanted:** one end-to-end browser test for the booking flow, the gap named in
   [devops-pipeline-overview.md](./devops-pipeline-overview.md#deliberately-absent).

**Done means:** a reviewer with Docker and nothing else can run HotelApp, book a room, check
the guest in, and see the calendar update — against either backend, from either frontend.

---

## Open items carried into Phase 3

Not blockers, but they should be resolved or consciously deferred:

1. **`shared/decision-log.md` is still a stub**, and was not in Phase 2's scope. It is the
   natural home for decisions that were *reversed* — Phase 1b's session redesign, the dropped
   hosting stretch goal, the rejected per-type-count inventory model. Git history records these;
   a log surfaces them. Worth a short pass before Phase 3, while the reasoning is fresh.
2. **`context-map.md`** was populated during Phase 2 as an index of all thirteen `shared/`
   documents plus the `stacks/` layout. It needs updating as Phase 3 and 4 fill in `stacks/`.
3. **Spring Boot before Node in Phase 6** — recommended above, not yet confirmed.
4. **Migration ownership** (Flyway executes, Prisma introspects) is the Phase 2 decision most
   worth an explicit review, since it makes the two backends asymmetric in a way nothing else
   in the project does.
5. **No end-to-end browser testing** is the one acknowledged gap in the test strategy. Fine to
   carry; worth deciding deliberately rather than by default.

---

## Why this order

Stated once, since the plan's shape is itself a design decision a reviewer may ask about:

**Contract before implementation** is the whole premise. Four components must agree; agreement
is cheap in a document and expensive in four codebases.

**Shared before stack-specific** because a decision made in a stack document is a decision made
twice, and the second copy is where drift begins.

**Both frontends together, both backends together** because parallel implementations written
sequentially diverge — the second one reads the first's code instead of the specification, and
inherits its accidents along with its decisions.

**Backends before frontends** because a frontend can be built against a real API but an API
cannot be built against a hypothetical frontend, and because the backends are where the
interesting correctness lives.

**Integration last, but the pieces that prove integration designed first.** The session table,
the shared schema, and the OpenAPI diff were all specified in Phases 1–2 precisely so that
Phase 8 is a demonstration rather than a discovery.
