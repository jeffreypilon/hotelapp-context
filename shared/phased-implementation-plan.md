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
| 3 | `stacks/react/` + `stacks/angular/` | ✅ Done — 24 documents |
| 4 | `stacks/nodejs/` + `stacks/springboot/` | ✅ Done — 20 documents, including `V001__initial_schema.sql` |
| 5 | `copilot-instructions.md` / `CLAUDE.md` per implementation repo | ✅ Done — 2026-09-27 |
| 6 | Backend implementation | ⬜ **In progress** — Steps 0-6 done; Spring Boot's guest-facing slice (items 1-8) complete. Node Steps 0-1 (walking skeleton, sessions) done as of 2026-09-29; Node Steps 2-6 remain, with detailed step-by-step build instructions for Copilot below, mirroring Spring Boot's 7 steps. Admin/reporting/cross-cutting (items 9-12) deferred — see the design decision before Phase 7 |
| 7 | Frontend implementation | ⬜ **In progress** — React's entire guest-facing slice (Steps 1-7, items 1-6) is done and verified against live Spring Boot. **Paused here at Jeff's explicit instruction (2026-09-27)** rather than proceeding straight to Node per the original sequencing — see the design decision below for what "next" meant before the pause |
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
| [acceptance-criteria.md](./acceptance-criteria.md) | 44 Given/When/Then criteria across no-overbooking, the cancellation boundary, authorization, and sessions |
| [versioning-strategy.md](./versioning-strategy.md) | Breaking-change policy, why no `/v2` is built, and the one-executor migration rule |
| [devops-pipeline-overview.md](./devops-pipeline-overview.md) | Per-repo CI, the OpenAPI diff, the Compose smoke test |
| [phased-implementation-plan.md](./phased-implementation-plan.md) | This document |

`shared/decision-log.md` was outside Phase 2's scope and was populated immediately afterwards,
with three reversals: the dropped free-tier hosting goal, the Phase 1b session redesign, and the
migration-ownership change below.

**Phase 2's most consequential new decision** is the migration ownership rule in
[versioning-strategy.md](./versioning-strategy.md#database-schema-migrations): canonical
numbered SQL lives in this repo, Flyway is the only executor, and Prisma consumes the schema by
introspection rather than authoring it. It went on to shape every Phase 4 document, and is
recorded as a reversal in [decision-log.md](./decision-log.md) because it overturned the Phase 1a
assumption that each backend would carry its own migrations.

---

## Phase 3 — Frontend stack specifications ✅

**Scope:** `stacks/react/` and `stacks/angular/`, twelve documents each. **All 24 written.**

> **Delivered in two passes**, deliberately split because 24 documents in one pass risked the
> cross-stack drift the phase exists to prevent. Pass 1 took the three decision-bearing documents
> per stack (`ui-specifications`, `state-management`, `architecture-specification`); pass 2 took
> the remaining nine, which are per-stack conventions downstream of those.
>
> **Two pairs are byte-identical over their shared sections**, built from one shared body rather
> than written twice and hoped to match: `ui-specifications.md` §1–2, and `error-handling.md`
> §1–4 so a guest sees the same message text in either client.
>
> **State management was the open question and is now decided with reasoning.** React: TanStack
> Query v5, no Redux-style store, and deliberately **no optimistic updates** — every mutation here
> can be refused for a reason the client cannot predict. Angular: NgRx **SignalStore**, with
> classic NgRx declined because ~42 endpoints of action/reducer/effect/selector ceremony buys
> time-travel and global traceability this project has no use for.
>
> **The one asymmetry that emerged:** TanStack Query gives the React client caching for free, so
> Angular's cache semantics had to be written as explicit policy to keep observable behavior
> matched. That is an ecosystem consequence, not a requirements divergence.

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

**Outcome against those criteria.** All seven met, with two findings worth carrying forward:

- **Item 3, the endpoint cross-check:** 41 of 42 endpoints are consumed by a specified screen.
  The exception is `GET /health`, which is correct — it is an operational endpoint whose purpose
  is letting a tester confirm which backend answered. `GET /room-types/{id}` is the closest thing
  to surplus surface, since its data is nearly all present in the property's room-types list; it
  is retained for a direct-load, shareable route.
- **Item 7:** no contract change was needed. The screens fit the contract as written.
- Sixteen screens were specified, S0–S15 — two more than the phase scope listed, because the app
  shell (session bootstrap and the global `401` rule) and the not-found/error routes both needed
  specifying and belonged to no other screen.

**The risk this phase was watching for did not materialize.** It was the most likely place to
discover the API contract was missing something, since it is the first time anyone walks the
actual screens. The rule stood and was not needed: **change the contract, do not work around it
in a frontend specification.** A shim in one client is drift with extra steps.

---

## Phase 4 — Backend stack specifications ✅ (one deliverable outstanding)

**Scope:** `stacks/nodejs/` and `stacks/springboot/`, ten documents each — the same list as
Phase 3 minus `ui-specifications.md` and `state-management.md`. **All 20 written.**

> **Delivered in two passes**, same reasoning as Phase 3. Pass 1: `architecture-specification`,
> `coding-standards`, `error-handling`, `testing-standards`. Pass 2: the remaining six.
>
> **Two more byte-identical pairs**, built from one shared body: `error-handling.md` §1–5, so both
> backends emit the same status, `code`, `title`, and `detail` for the same condition; and
> `testing-standards.md` §1–5, so both satisfy the same 44 criteria at the same layers.
>
> **The migration asymmetry is carried through rather than smoothed over**, which was the phase's
> main discipline. The Node setup guide opens by stating it cannot create its own schema; its CI
> needs a second checkout of this repo plus the Flyway CLI; and it needs a `schema.prisma` drift
> check that the Spring repo gets free from `ddl-auto=validate`. The Spring documents state the
> converse — it is the **more privileged** backend, because it alone needs DDL rights, with a
> two-role database setup recommended to bound that privilege to startup.
>
> **The finding this phase produced:** Prisma has **no mapped error code for SQLSTATE `23P01`**, so
> the Node backend detects an exclusion-constraint violation via a raw-query error code or by
> matching message text, where Spring reads `SQLException.getSQLState()` as structured data. The
> integrity guarantee is unaffected — the constraint is enforced by PostgreSQL and a failure to
> classify yields `500` instead of `409`, fail-closed either way — but it makes
> [AC-OB-01](./acceptance-criteria.md#ac-ob-01--two-concurrent-bookings-for-the-last-room-exactly-one-wins)
> against real PostgreSQL the only guard on the project's central guarantee in that stack, and it is
> why mocking the Prisma client is prohibited there. Cross-referenced from nine stack documents.

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
| RFC 9457 generation | Spring Boot has `ProblemDetail` natively; Node needs it built |
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

**Outcome against those criteria.** All seven are met, including item 6 — resolved after this
section was originally written, and confirmed here.

> ### Resolved: `shared/migrations/V001__initial_schema.sql` — done 2026-09-27
>
> Delivered as recommended, before Phase 5: 515 lines, 11 tables, 5 enums, 36 indexes,
> `btree_gist`, the generated `stay_period` column, the `reservations_no_overlap_excl` partial
> exclusion constraint, both composite FKs, and the seven `amenities` rows. Commit `281365f`.
>
> **Verified by execution, not review**, before being counted as done: applied to a throwaway
> PostgreSQL 18.6 database with `ON_ERROR_STOP=1`, then 16 behavioural tests — adjacent stays
> succeed, four overlap shapes give `23P01`, cancel-then-rebook succeeds, the
> role/status/date/rate-category CHECKs and composite FKs each reject, and `EXPLAIN` confirmed an
> Index Only Scan using `reservations_no_overlap_excl` for the availability query. Database
> dropped afterwards.
>
> Four deviations from a literal transcription, each commented in the file: `confirmation_number`
> UNIQUE declared once rather than duplicated as a separate index (the two would have collided);
> `properties_id_key` omitted as redundant with the PK; `users.email` functional index only; and
> the table-level date CHECK named explicitly (`reservations_dates_chk`) rather than left to
> PostgreSQL's opaque auto-naming.

---

## Phase 5 — Per-repo agent instructions ✅

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

**Outcome — done 2026-09-27.** All five repos have both `.github/copilot-instructions.md` and a
`CLAUDE.md` that `@import`s it: react `ecbcd7a`, angular `002097d`, nodejs `af20489`, springboot
`f8e130b`, this repo `bfdb279`. Shared blocks across the four implementation repos are
byte-identical by md5. The `@`-import constraint above was discovered during this phase, not
before it.

---

## Phase 6 — Backend implementation ⬜ **in progress**

Build both backends. **One at a time, and the harder one first.**

> **Recommendation — Spring Boot first.** It is the stack that must apply the canonical
> migrations (Flyway is the executor), so building it first makes the schema real and gives the
> Node backend a migrated database to introspect from day one. Building Node first would mean
> either hand-running Flyway before Prisma can introspect anything, or discovering the
> ownership asymmetry at the least convenient moment. This is a recommendation, not a fixed
> decision — worth confirming before Phase 6 starts.

### Step 0 — A walking skeleton that reaches a browser, before anything else

> **Do this first, and do not let it slide.** Before continuing down the backend, get **one thin
> vertical slice running end to end**: `V001` applied to a real database, `GET /properties`
> answering, and **one React screen rendering the result in a browser**. Nothing else — no auth, no
> second backend, no second frontend, no styling, no CI.
>
> **Why it earns its place ahead of eleven steps of backend work.** This project specified 59
> documents before any code existed, so **the API contract has never been validated against a
> client**. That is the single largest unvalidated assumption in the project, and this is the
> cheapest point at which to test it. A response shape that is awkward to consume, a money string
> that does not round-trip, or a date that shifts by a day is far cheaper to find now than after
> eleven more endpoints have copied the pattern.
>
> It is also the moment the Prisma-side risks become real rather than theoretical: whether
> introspection produces a usable client, and whether the `Unsupported("daterange")` mapping behaves
> as [data-model.md](./data-model.md#no-overbooking) predicts.
>
> **Done when:** one command starts a database and a backend, and a browser shows seeded properties
> fetched over HTTP. **Then write down what it taught you**, and fold any contract correction into
> [api-contracts.md](./api-contracts.md) before resuming — a correction deferred past this point
> gets made in four repositories instead of one.
>
> This is the walking-skeleton step the project skipped earlier; the reasoning and the general
> practice are recorded in `claude-memory/AI Assisted Software Architecture Approach.md`. Arriving
> at Phase 6 is the last cheap opportunity to take it.

### What Step 0 actually taught us — done 2026-09-27

Step 0 ran: Spring Boot 4.1.1 on `:8080`, Vite on `:5173`, a browser rendering two seeded properties
fetched live. Commits `e34f686` (springboot) and `d0a20fe` (client-react).

**It found one real contract defect**, which is the whole reason the step exists:

> **Nullable fields were being omitted rather than sent as `null`.**
> `environment-setup-guide.md` specified `spring.jackson.default-property-inclusion=non_null`, which
> drops `photoUrl` from the JSON entirely — while this document's own response examples show explicit
> nulls. The two documents contradicted each other.
>
> Worse than a client-convenience issue: **Node's `JSON.stringify` emits `"photoUrl": null` by
> default**, so the two backends would have produced different bytes for identical data, and the
> OpenAPI diff would not have caught it. Fixed by stating the rule in
> [api-contracts.md](./api-contracts.md#conventions) and correcting the Jackson configuration and
> both backends' DTO guidance. **Had this shipped, it would have propagated through 42 endpoints.**

**It also revealed that Step 0 validated less than this document assumed.** `GET /properties` carries
**no money field and no date field**, so the two riskiest serialization rules in the project — money
as a decimal string, and dates not shifting — remain **unvalidated**. That is not a failure of the
step, but it is a correction to what it proves.

> **Carry-forward requirement:** the first endpoint returning `baseRate` — `GET
> /properties/{id}/room-types`, Step 4 — must explicitly verify that money round-trips as a decimal
> **string** through both backends and both clients, and that no date shifts. Do not inherit
> confidence from Step 0; it did not test either.

**Two smaller outcomes.** Spring Boot's current stable is **4.1.1** (21 Aug 2026), not the 3.x these
documents assumed — references were corrected, and `TestRestTemplate` is gone in favour of
`RestTestClient`. And `mvn verify` could not run at Step 0 time: **Docker was not installed**, so
Testcontainers could not start.

> **Resolved in Step 1.** Docker Desktop was installed; `mvn verify` then failed a second time
> because `pom.xml` pinned `testcontainers-bom` to `1.21.3`, overriding Spring Boot's own parent
> BOM and defaulting docker-java to Docker API 1.32 against a Docker 29 daemon that requires
> ≥1.40. Removing the pin resolved Testcontainers 2.x (`testcontainers-junit-jupiter` /
> `testcontainers-postgresql`). `PropertyControllerIT` — written in Step 0 but never executed
> then — ran clean as part of Step 1's `mvn verify` (`Tests run: 2, Failures: 0, Errors: 0`,
> read directly from the failsafe report), so the walking skeleton's own integration test is now
> confirmed, not just the manual browser check.

Suggested order within each backend after that, each step ending somewhere demonstrable:

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

### Step 1 (sessions) — done 2026-09-27, Spring Boot only

`hotelapp-server-springboot@744df5a`. `POST /auth/register`, `POST /auth/login`, `POST
/auth/logout`, `GET /auth/me`. `mvn verify`: 13 run, 0 failures, 0 errors —
`AuthControllerIT` (11) plus `PropertyControllerIT` (2), run twice for stability.

AC-SE-01/02/03/04/06/08/09/10 and AC-AZ-11 verified over real HTTP. AC-SE-05 (the
cross-backend interchangeability guarantee) has its single-process half done via raw JDBC
against this backend only — per this document's own step 3 note, it cannot be verified
cross-backend until the Node backend reaches this same step. AC-SE-07 (revoke-all-except) is
exercised at the service level only, since `PUT /me/password` is out of this step's scope;
re-test through HTTP once that endpoint exists.

Unlike Step 0, Step 1 found no contract defect — nothing was folded back into
[api-contracts.md](./api-contracts.md).

### Step 2 (public catalogue) — done 2026-09-27, Spring Boot only

`hotelapp-server-springboot@c430f67`. Completed `GET /properties` (`sort`, `city`, `q`, and a
`400` instead of a clamp on out-of-range paging — [AC-CC-03](./acceptance-criteria.md#ac-cc-03--pagination-is-consistent-everywhere))
and newly built `GET /properties/{propertyId}`, `GET /properties/{propertyId}/room-types`,
`GET /room-types/{roomTypeId}`, `GET /amenities`, `GET /rate-categories`. `mvn verify`: 26 run,
0 failures, 0 errors — `AuthControllerIT` (11) + `PropertyControllerIT` (2) +
`PublicCatalogueIT` (13), run twice for stability.

**Closes the money half of Step 0's carry-forward requirement.** `baseRate` is now asserted
directly against the raw JSON body as the string `"249.00"`, never a bare number — the check
Step 0 flagged as still owed. **The date half remains open**: no endpoint in this step returns a
persisted date (`timezone` is a string, not a date), so it still carries forward to whichever
step first returns one — earliest candidate is `POST /reservations` (item 6 above).

Two implementation bugs surfaced and were fixed, not workaround-hidden: Spring Data JPA's
`Specification.and(null)` throws here rather than no-op'ing, so optional `city`/`q` criteria are
now folded in conditionally; and sharing one Testcontainers Postgres across three `*IT` classes
via `@Testcontainers`/`@Container` was stopping and restarting the container between classes,
producing a genuine mid-teardown `500` — fixed with a singleton-container pattern (a plain
`static { POSTGRES.start(); }` block) instead.

**One judgment call, flagged rather than silently decided:** `api-contracts.md` names a "summary
form" for the `roomTypes` array embedded in `GET /properties/{propertyId}` without an example.
Interpreted as the flat room-type fields without the `amenities`/`photos` collections
(`RoomTypeSummaryResponse`) — worth confirming against the frontends' actual needs before that
shape is relied on in Phase 7.

### Step 3 (availability search) — done 2026-09-27, Spring Boot only

`hotelapp-server-springboot@7f86d37`. `GET /availability` — the parameterized native query
implementing [data-model.md](./data-model.md#no-overbooking)'s literal anti-join shape
(`NamedParameterJdbcTemplate`, no string-built SQL), extended with `roomTypeCode`,
`accessibleOnly`, `amenityCode` (all-match), `minNightlyRate`/`maxNightlyRate` (applied to the
discounted rate, in application code), and sorting/pagination in memory given the small
per-property room-type cardinality. `mvn verify`: 34 IT tests run (0 failures, 0 errors) —
`AuthControllerIT` (11) + `AvailabilityIT` (8) + `PropertyControllerIT` (2) +
`PublicCatalogueIT` (13) — plus 2 unit tests (`PricingTest`), run twice for stability.

**Pricing built as reusable pure domain logic** (`domain/Pricing.java`, no Spring/JPA), for reuse
unchanged by `POST /reservations` in Step 6. [AC-CX-10](./acceptance-criteria.md#ac-cx-10--pricing-arithmetic-and-rounding-order)'s
rounding-order requirement is unit-tested with **both** required cases — the 249.00/10%/3-nights
case, and the 100.01/33.33%/3-nights case that actually distinguishes rounding-then-multiplying
from multiplying-then-rounding, since the first case alone doesn't prove the order matters.

**The query-plan requirement from [non-functional-requirements.md](./non-functional-requirements.md#response-time-targets)
was met as an automated assertion, not a manual check**: `AvailabilityIT` seeds 2,000 synthetic
reservations, runs `ANALYZE`, then runs `EXPLAIN (ANALYZE, BUFFERS)` against the *exact same*
query method the production path calls, and asserts the plan uses the
`reservations_no_overlap_excl` GiST index rather than a sequential scan on `reservations`.

**Judgment call, flagged rather than silently decided:** the contract doesn't specify what happens
when a requested `rateCategory` has no active `rate_plans` row for that property. Decided as a 0%
discount (same as `NONE`); the room type stays in results rather than being excluded. Documented in
`Pricing.java`'s javadoc and covered by a dedicated integration test (requesting `AARP` where no
plan exists).

No contract or migration mismatch was found this step — `rooms` and `rate_plans` matched what
Step 2's already-applied `V001` implied.

### Step 4 (booking: POST /reservations) — done 2026-09-27, Spring Boot only

`hotelapp-server-springboot@7dc2e1b`. "The central feature": allocation, dummy payment, and the
no-overbooking exclusion constraint under real concurrency. `mvn verify`: 52 IT tests + 2 unit
tests, 0 failures, 0 errors — added `ReservationIT` (18) on top of Step 3's suite.

Three judgment calls, all documented in code: confirmation-number scheme (`HA` + 8-char Crockford
base32 via CSPRNG, in `ConfirmationNumberGenerator` — correctly kept out of `domain/` since it's
non-deterministic, not a pure function, despite being small); payment-decline check runs before
allocation (a card known to decline should never hold a room); idempotency implemented as an
**in-process cache only**, explicitly not durable across restarts or across backends — an accepted
demo-scope limitation, stated rather than silently presented as complete.

Did not close the date half of Step 0/2's carry-forward requirement despite `checkInDate`/
`checkOutDate` now being persisted and returned — closed instead by Step 5, below.

### Architectural corrections found during Phase 6 (2026-09-27)

Two package-layout mistakes were caught by inspecting the generated code, not by re-reading a
spec in isolation — see [decision-log.md](./decision-log.md) entries 4 and 5 for full reasoning.
Both refactors verified by execution (test count unchanged before/after, 0 failures both times)
before being counted as done, the same discipline as every step above.

- **The `AppException` hierarchy was inside `domain/`**, alongside the four pure rule functions,
  since Phase 4 wrote the layout that way in both backend stacks. `domain/`'s own stated rule
  (pure computation, no framework/HTTP dependency) doesn't hold for exception types, whose whole
  job is HTTP-error translation. Split into `exception/` (commit `795fa99`, 52/52 tests before
  and after). The Node spec had the identical mistake, fixed there too (`4aa14f4`) before any
  Node code existed.
- **`web/` mixed four responsibilities** — controllers, servlet filters, Spring Security hooks,
  and exception-to-response translation. Unlike the above, this one was **not** shared with
  Node — Node's spec already separated `middleware/` from `routes/`, since Express's request
  model forces the distinction; Spring Boot's spec never had that forcing function. Split into
  top-level `controller/` + `security/`, no `web/` umbrella, matching Node's shape (commit
  `c300fa8`, 52/52 before and after).

An architectural audit pass across both frontend stacks and the full `acceptance-criteria.md`
found no further issues of this kind, and found and fixed one unrelated naming collision in
`api-contracts.md` itself: the admin calendar endpoint reused `nightlyRate` — normatively the
*discounted* per-night price everywhere else — for the plain, undiscounted `base_rate`. Renamed
to `baseRate` (commit `f0c4cfe`), caught before any code touched that endpoint (item 11, not yet
built).

### Step 5 (guest reservation management: list, detail, modify, cancel) — done 2026-09-27, Spring Boot only

`hotelapp-server-springboot@db7d225`. `GET /reservations`, `GET /reservations/{id}`,
`PATCH /reservations/{id}`, `POST /reservations/{id}/cancel`. `mvn verify`: 65 IT tests, 0
failures, 0 errors — added `ReservationManagementIT` (13) on top of Step 4's suite.

Built `ReservationStatusRules.java`, the fourth and last of the pure functions
`architecture-specification.md` had planned since Phase 4 (legal status transitions, AC-CX-09).
Entity mutation done via two scoped methods (`Reservation.applyModification(...)`,
`Reservation.cancel(...)`) rather than generic setters, each written so it cannot violate
`reservations_status_timestamps_chk` by construction — an improvement worth carrying into later
steps rather than a one-off.

**Found and fixed a genuinely subtle bug during testing, not by inspection**: the shared `Clock`
bean (required by `ClockConfig` for the cancellation-boundary criteria) also drives session
expiry, so jumping the test clock to a cancellation-deadline instant was silently expiring the
guest's own login session, producing a `401` instead of the expected business-logic response.
Fixed by seeding the clock to a baseline close to the target instant *before* login and booking,
not at real wall-clock time.

**Closes the date half of Step 0/2's carry-forward requirement.** `checkInDate`/`checkOutDate`
are returned from a *mutated* (`PATCH`) reservation for the first time, not just a freshly
created one — a stronger round-trip test than Step 4's create-only path — and passed with no
additional Jackson configuration needed.

AC-OB-04 (cancel frees the room for another booking) is tested through real HTTP for the first
time, now that both create and cancel exist. AC-CX-09's `CHECKED_IN`/`CHECKED_OUT` states still
have no real endpoint (item 9) and are set via JDBC in the test fixture, same treatment Step 4
gave AC-OB-05 — flagged for re-verification once that step lands.

### Step 6 (guest profile and password change) — done 2026-09-27, Spring Boot only

`hotelapp-server-springboot@081881a`. `GET /me`, `PATCH /me`, `PUT /me/password` — the last
guest-facing item; **Spring Boot's guest-facing slice (Phase 6 items 1-8) is now complete.**
`mvn verify`: 74 IT tests, 0 failures, 0 errors — added `ProfileIT` (9) on top of Step 5's suite.

`PATCH /me`'s "omitted is unchanged, explicit `null` clears it" semantics — inexpressible with a
typed request record — solved by binding the body as a raw `JsonNode` (this project is on
Jackson 3, `tools.jackson.*`; the implementer confirmed the actual API via `javap` rather than
assuming Jackson 2 method names). Binding as `JsonNode` bypasses the global
`fail-on-unknown-properties` config, so `ProfileService` manually rejects any key outside
`firstName`/`lastName`/`phone`/`address` (and, as a nice extra, unknown keys *inside* `address`
too) with `400 VALIDATION_FAILED` — this is what actually satisfies
[AC-AZ-09](./acceptance-criteria.md#ac-az-09--registration-cannot-escalate)'s second half
(`role`/`isActive` rejected via `PATCH /me`, not silently ignored).

**Judgment call, flagged rather than silently decided:** `address`, when present in a `PATCH`
body at all, replaces the whole sub-object rather than merging field-by-field — consistent with
how this contract treats other sub-objects elsewhere (`PUT /admin/.../rate-plans`). Documented
in code and covered by a dedicated test.

The common-password deny-list was extracted from `AuthService` into `domain/PasswordPolicy.java`
(pure, no I/O) so registration and password-change share one list. `SessionService.revokeAllExcept`
— built in Step 1, unit-tested but never called over HTTP — is exercised through real HTTP for
the first time here, closing that gap.

**Done means:** Step 0's slice ran and its findings were folded back into
[api-contracts.md](./api-contracts.md); both backends pass every criterion in
[acceptance-criteria.md](./acceptance-criteria.md); the OpenAPI diff is clean; CI is green in
both repos; both serve identical responses to the same requests against the same database.

---

### Node implementation steps — detailed instructions for Copilot

Prospective, sequenced build instructions for `hotelapp-server-nodejs`, mirroring Spring Boot's
already-completed Steps 0–6 above one for one: walking skeleton, sessions, public catalogue,
availability search, booking, reservation management, profile/password — Spring Boot's
guest-facing slice, items 1-8 minus the admin items.

**Unlike every Step section above, which is a retrospective outcome report written after the work
landed, the steps below are written prospectively.** They are instructions for a Copilot agent to
read and act on directly, one step at a time, with Jeff saying only "do Node Step N" — not a
chat-relayed prompt written fresh each time. A cold Copilot session given nothing but that
instruction should be able to find everything it needs from this section plus the documents it
points into. This is a deliberate trial of that approach for the Node build specifically
(2026-09-29); whether it becomes the standing way of working with Copilot on this project,
including for Angular later, is a separate decision not made here.

> **Standing rules for every step below**, stated once rather than seven times:
>
> 1. **Commit and push at the end of the step, regardless of what the step's own text says.**
>    Both `hotelapp-client-react`'s and `hotelapp-server-springboot`'s Copilot instructions had
>    this added mid-project, after two steps each landed fully verified but uncommitted (see the
>    Phase 7 Step 1/2 outcomes above). `hotelapp-server-nodejs`'s own Copilot instructions do
>    **not** yet carry an equivalent rule as of this writing — do not assume it is implied.
> 2. **Any new pure function in `domain/` with non-obvious logic ships with its own test in the
>    same commit.** React's Copilot instructions picked up this rule after the gap recurred three
>    steps running (Phase 7 Steps 3 and 5 above). Do not defer a `pricing.ts` / `cancellation.ts`
>    / `allocation.ts` / `status.ts` test to "later."
> 3. **Verify completion by actually running `npm run test:run` and reading the raw output** —
>    never report a step done from a self-summary. Check `git status` and `git log` before
>    claiming anything is committed; an agent-reported "done" that was still uncommitted has
>    happened often enough in this project to be a named, recurring lesson (see the Phase 6 and
>    Phase 7 step outcomes above).
> 4. **Before starting the next step, add a short outcome note back into this document** — a new
>    subsection under this one, in the same style as Spring Boot's and React's Step outcomes
>    above: what shipped, the real test count read from raw output, any judgment call made, any
>    contract defect found. This document has gone stale against real progress before because an
>    outcome update was skipped in the moment and never caught up (see "Doc-drift found and
>    fixed" below) — do not let that happen here too.
> 5. **Every endpoint's happy path gets at least one integration test**, per
>    [testing-standards.md](../stacks/nodejs/testing-standards.md#4-beyond-the-criteria) — the
>    acceptance criteria named per step below are the criteria that must be *provably* correct,
>    not the whole of what needs a test.
> 6. **A judgment call, an ambiguity, or a contract gap found while building is disclosed, not
>    silently worked around** — the same discipline Spring Boot's and React's steps followed
>    throughout. If Node's build finds that `api-contracts.md` itself needs a correction, fix it
>    there first, the same as every prior contract defect this project has found.

#### Node Step 0 — walking skeleton — instructions for Copilot

**Scope.** No new product endpoints. Project skeleton, database connection, `GET /health`,
`GET /properties` — proving the Prisma half of Phase 6 Step 0's original goal, which Spring
Boot already proved for the wire format itself.

**Read first.**
[architecture-specification.md](../stacks/nodejs/architecture-specification.md#the-migration-asymmetry-and-what-it-means-for-this-repo)
and its [Layering](../stacks/nodejs/architecture-specification.md#layering) and
[Folder layout](../stacks/nodejs/architecture-specification.md#folder-layout) sections;
[environment-setup-guide.md](../stacks/nodejs/environment-setup-guide.md) in full — it is written
to be followed literally and its "read this first: you cannot start here" box is not optional
context; [coding-standards.md](../stacks/nodejs/coding-standards.md); the "Conventions" table at
the top of [api-contracts.md](./api-contracts.md#conventions).

**Match Spring Boot — do not re-derive.** The nullable-fields-must-be-`null`-never-omitted rule
that Step 0's Spring Boot run found the hard way is already fixed in
[api-contracts.md](./api-contracts.md#conventions) and stated as a Node-specific hazard in
[architecture-specification.md](../stacks/nodejs/architecture-specification.md#dtos): map every
DTO field to `?? null`, never `?? undefined`, and type nullable fields as `string | null` rather
than optional so the compiler catches the difference. This is not a fresh risk to investigate —
it is a known trap with a known fix, already written down.

**Node/Prisma-specific concerns.**

- **A migrated database must already exist before this step can do anything.** This backend
  cannot create its own schema. Either the Spring Boot backend has been started once against the
  local `hotelapp` database, or run the Flyway CLI directly per
  [environment-setup-guide.md](../stacks/nodejs/environment-setup-guide.md#quick-start). Confirm
  which before writing any code — if neither is true yet, that is this step's actual first
  blocker, not a coding problem.
- `npx prisma db pull` against that database, then `npx prisma generate`. Expect `stay_period` to
  introspect as `Unsupported("daterange")` — that is correct, not a bug to fix, per
  [architecture-specification.md](../stacks/nodejs/architecture-specification.md#prisma-usage).
- `GET /properties` must map every field through an explicit DTO, never a raw Prisma result — see
  [DTOs](../stacks/nodejs/architecture-specification.md#dtos). This is the one endpoint where the
  nullable-field trap above is real: `photoUrl` and `address.line2` are both nullable.
- No money or date field is exercised by `GET /properties` (it carries `roomTypeCount`, not
  pricing, and no date field) — same carve-out Spring Boot's own Step 0 had. Do not claim money or
  date serialization is validated from this step; that is Step 2's and Step 3's job respectively.

**Tests required.** A `PropertyControllerIT`-equivalent integration test (real PostgreSQL, per
[testing-standards.md](../stacks/nodejs/testing-standards.md#1-the-layers-and-what-each-one-is-for)
— no substitute database) asserting `GET /health` and `GET /properties` both respond correctly
against the live schema. This step predates the acceptance-criteria matrix; no AC-ID is owed yet.

**Done when.** `npm run dev` starts against the already-migrated database, `curl
localhost:3000/api/v1/health` returns `{"status":"UP","database":"UP",...,"backend":"nodejs"}` per
[environment-setup-guide.md](../stacks/nodejs/environment-setup-guide.md#quick-start), and
`GET /properties` returns the same seeded properties Spring Boot already serves, byte-comparable
field by field (same nullable-vs-omitted behavior, same field names). Point
`hotelapp-client-react`'s configured backend URL at Node's `:3000` and confirm the existing
property list screen (Phase 7 Step 1's `S1`) renders correctly with no frontend code change —
the concrete proof of "either frontend against either backend" for the first time in this project.

#### Node Step 1 (sessions) — instructions for Copilot

**Scope.** `POST /auth/register`, `POST /auth/login`, `POST /auth/logout`, `GET /auth/me`, per
[api-contracts.md](./api-contracts.md#authentication-endpoints).

**Read first.**
[api-contracts.md](./api-contracts.md#authentication) (the session design in full) and
[api-contracts.md](./api-contracts.md#authentication-endpoints) (the four endpoints' exact
shapes); [architecture-specification.md](../stacks/nodejs/architecture-specification.md#session-handling)
(the six-step middleware sequence, normative); every mention of sessions in
[security-implementation.md](../stacks/nodejs/security-implementation.md); the `decision-log.md`
entry on the JWT-to-sessions reversal (entry 2) so no part of the removed design is reintroduced.

**Match Spring Boot — do not re-derive.** Nothing to match from a judgment call — Spring Boot's
Step 1 found no contract defect and made no flagged judgment call. Match its *behavior* exactly:
the same 8-hour sliding idle window with a 5-minute write-throttle and a 30-day absolute cap (the
values themselves are fixed in
[data-model.md](./data-model.md#sessions), and Node's `.env.example` already carries them per
[environment-setup-guide.md](../stacks/nodejs/environment-setup-guide.md) — do not change them);
the same `INVALID_CREDENTIALS` response for both an unknown email and a wrong password, with
comparable timing on both paths.

**Node/Prisma-specific concerns.**

- Token generation is `crypto.randomBytes(32)`, never `Math.random()`; hash comparison is a
  database lookup on `token_hash`, so `crypto.timingSafeEqual` is not needed there — full detail
  in [security-implementation.md](../stacks/nodejs/security-implementation.md#sessions).
- `middleware/session.ts` must read `role` and `is_active` from the **joined** user row on every
  request, not a cached value — this is what makes deactivation take effect immediately, per
  [architecture-specification.md](../stacks/nodejs/architecture-specification.md#session-handling).
- Timing equality on login: verify against a dummy bcrypt hash of the same cost when no user is
  found, or the unknown-email path returns fast enough to be a usable account oracle — see
  [error-handling.md](../stacks/nodejs/error-handling.md#timing-equality-on-login) and
  [security-implementation.md](../stacks/nodejs/security-implementation.md#passwords).
- `bcrypt` cost from `BCRYPT_COST`, defaulting to 12 — must cross-verify with Spring Security's
  `BCryptPasswordEncoder`-produced hashes; this is directly testable once both backends exist.
- Rate limiting on `/auth/login` and `/auth/register`: 10 attempts / 15 minutes, keyed on IP *and*
  email, whichever trips first, per
  [security-implementation.md](../stacks/nodejs/security-implementation.md#rate-limiting).
- Grep the finished code: `grep -rniE "bearer|jwt|refreshToken|auth/refresh" src/` must return
  nothing, per
  [security-implementation.md](../stacks/nodejs/security-implementation.md#what-must-never-appear-in-this-codebase).

**Tests required.** AC-SE-01, 02, 03, 04, 06, 08, 09, 10, and AC-AZ-11 — the same set Spring
Boot's Step 1 covered. **This is the step where
[AC-SE-05](./acceptance-criteria.md#ac-se-05--a-session-works-interchangeably-against-both-backends)
first becomes real rather than theoretical**: once this step lands, run the manual cross-backend
walkthrough in
[environment-setup-guide.md](../stacks/nodejs/environment-setup-guide.md#working-against-the-other-frontend-or-alongside-the-other-backend)
by hand — log in against Node, call `/auth/me` against Spring Boot with the same cookie, log out
from Spring Boot, confirm Node now returns `401` too — and record the result in this step's
outcome note. The formal automated version still belongs to the Phase 8 Compose smoke test, but
the single-process approximation (seed a `sessions` row directly via SQL, then assert this backend
honors it) is this repo's own required test, per
[testing-standards.md](../stacks/nodejs/testing-standards.md#sessions).

**Done when.** `npm run test:run` passes with 0 failures covering the criteria above, the manual
cross-backend walkthrough succeeds by hand at least once, and `hotelapp-server-nodejs`'s own
Copilot instructions are updated with the endpoint status and current test count (its "Build,
test, and lint — NOT YET ESTABLISHED" section is stale the moment real commands exist to put
there).

#### What Node Step 0 actually taught us — done 2026-09-29

Shipped: project skeleton (`config/`, `middleware/`, `errors/`, `dto/`, `repositories/`,
`services/`, `routes/`), `GET /health`, `GET /properties` (with `sort`/`city`/`q`/pagination,
ahead of Step 2's minimum), the RFC 9457 error middleware and `AppError` hierarchy for the full
16-code catalogue (only `NOT_FOUND` and `VALIDATION_FAILED` are actually raised yet), `npm run
dev` on `:3000`. **5 integration tests, read from raw `vitest run` output, all passing** against a
real Testcontainers `postgres:18.6` migrated by the **Flyway CLI** (never `prisma migrate`) —
`GET /health`, `GET /properties` filtering to active-only with every nullable field explicit,
pageSize validation (`400`, never clamped), city filtering, and the Problem Details `404` shape.

**Verified byte-comparable against the live Spring Boot backend**, not just visually: `(nodeJson
| ConvertTo-Json) -eq (springJson | ConvertTo-Json)` on `GET /properties` returned `True` —
identical field names, identical explicit `null`s, identical `roomTypeCount`. Then
`hotelapp-client-react`'s `VITE_API_BASE_URL` was pointed at `:3000` and S1 (the property list)
rendered the same two seeded properties with **no frontend code change** — the concrete
"either frontend against either backend" proof this step exists to produce — then reverted back
to `:8080` afterward, since this was a one-time verification, not a change of the React repo's
default backend.

**One deliberate deviation, disclosed rather than worked around**: `architecture-specification.md`
and `dependency-policy.md`'s `prisma`/`@prisma/client` guidance predates Prisma 7's breaking
config-model change (`datasource.url` in `schema.prisma` no longer works at all under Prisma 7 —
`db pull` fails outright with `P1012`). Pinned both to **`6.12.0`** instead of the newest 6.x —
the specific patch that predates `@prisma/config` being pulled in as a transitive dependency,
which is what a newer 6.x carries a HIGH-severity `deepmerge-ts` advisory through
(`GHSA-ggr8-5vv4-36mx`, in the CLI tool only, never reachable from the running server).
`npm audit --omit=dev` is 0 vulnerabilities at this pin; `express` was also bumped from the
spec's `4.21.2` to `4.22.3` (still Express 4) to clear an unrelated `path-to-regexp`/`qs` chain.
Full detail in `claude-memory` (this machine's local-environment notes) since it is a toolchain
fact, not a contract fact — no `api-contracts.md` change was needed, and none of Step 0's actual
wire-format findings (there were none — Step 0 found no contract defect this time, unlike Spring
Boot's) are affected by it.

**Judgment call, disclosed**: no OpenAPI document was started this step. `architecture-
specification.md#openapi` describes a hand-maintained `openapi/spec.ts`, but nothing in Step 0's
own "Done when" section requires it, and writing one now for two endpoints (one of them
operational) would be speculative. Deferred to whichever step first needs the cross-backend
OpenAPI diff to mean something.

#### What Node Step 1 actually taught us — done 2026-09-29

Shipped: `POST /auth/register`, `POST /auth/login`, `POST /auth/logout`, `GET /auth/me`. Session
rows via `crypto.randomBytes(32)` + SHA-256 hash, the six-step validate-and-slide sequence split
between `middleware/session.ts` (cookie I/O) and the Express-free `services/sessionService.ts`
(steps 2-6, unit-testable on its own), `middleware/rateLimit.ts` (dual IP+email `express-rate-limit`
factories, one instance per `createApp()` call so tests don't trip each other's counters), bcrypt
cost 12 with a lazily-computed dummy hash for timing equality on the unknown-email login path, and
a curated common-password deny-list applied at the Zod validation boundary. **18 integration tests
total (13 new), read from raw `vitest run` output, all passing**: AC-SE-01 through AC-SE-04,
AC-SE-06, AC-SE-08 (all three parts — slide, throttle, absolute cap — driven by an injectable
`TimeSource`/`ManualClock`), AC-SE-09 (rate limit trips at 11, a correct password inside the window
still `429`), AC-SE-10 (unknown email vs. wrong password, identical body), and both halves of
AC-AZ-11 (login against a deactivated account; a live session deactivated mid-session). AC-SE-05's
single-process approximation (seed a `sessions` row directly, assert this backend honors it) is
also a required test and passes.

**AC-SE-05 verified by hand against a live Spring Boot on `:8080`**, per the step's own
requirement: registered against Node, called `GET /auth/me` against Spring Boot with Node's cookie
and got the same user back, logged out from Spring Boot, then called Node's `/auth/me` with the
same cookie and got `401` immediately. **First attempt gave a false negative** using PowerShell's
`Invoke-RestMethod -SessionVariable` — its underlying `WebRequestSession`/`CookieContainer` appears
to scope cookies per-port rather than per-host, so a cookie obtained from `:3000` was not attached
to a request to `:8080` even though both are `localhost` and RFC 6265 cookies are host-scoped, not
port-scoped. Switching to `curl`'s cookie jar (`-c`/`-b`, the same tool
`environment-setup-guide.md`'s own example uses) reproduced real browser behavior and confirmed the
session interoperability holds. **Worth flagging for anyone reaching for PowerShell's session
cmdlets for this kind of cross-port manual check again** — `curl` is the reliable tool for it, not
a `WebSession` object.

**No contract defect found.** `api-contracts.md`'s authentication section and
`architecture-specification.md#session-handling`'s six-step sequence matched what was needed
without correction.

**One judgment call, disclosed**: the common-password deny-list (`src/lib/commonPasswords.ts`) is
a curated ~60-entry list, not an exhaustive breach-corpus check (no such corpus is bundled per
`dependency-policy.md`'s no-new-dependency-for-this stance). Stated as a limitation in the file
itself, matching `security-principles.md#passwords`'s own phrasing that length beats composition
rules and a full deny-list is aspirational, not required.

#### Node Step 2 (public catalogue) — instructions for Copilot

**Scope.** `GET /properties` (with `sort`, `city`, `q` — Step 0 built a minimal version; this step
completes it), `GET /properties/{propertyId}`, `GET /properties/{propertyId}/room-types`,
`GET /room-types/{roomTypeId}`, `GET /amenities`, `GET /rate-categories`, per
[api-contracts.md](./api-contracts.md#public-catalogue-endpoints).

**Read first.** The full "Public catalogue endpoints" section of
[api-contracts.md](./api-contracts.md#public-catalogue-endpoints), including every response
example; [Pagination, sorting, filtering](./api-contracts.md#pagination-sorting-filtering);
[Query rules](../stacks/nodejs/architecture-specification.md#query-rules) (the `select`-only,
`include`-not-N+1 rules).

**Match Spring Boot — do not re-derive.** `api-contracts.md` names a "summary form" for the
`roomTypes` array embedded in `GET /properties/{propertyId}` without an example. Spring Boot's
Step 2 interpreted this as the flat room-type fields with no `amenities`/`photos` collections, and
React's Phase 7 Step 2 later confirmed this by curling the live Spring Boot backend directly (see
that outcome above) — so this is no longer an open judgment call for Node to re-derive, it is a
confirmed shape to match exactly. Type it narrowly (e.g. a `PropertyRoomTypeSummary` DTO distinct
from the full room-type DTO used elsewhere), not richer.

**Node/Prisma-specific concerns.**

- **This is where the money half of Step 0's carry-forward requirement gets closed.** Assert
  `baseRate` directly against the raw JSON response body as the string `"249.00"`, with an
  explicit assertion that it is never the bare number `249` — the same check Spring Boot's Step 2
  ran. Do not trust a parsed-object comparison; parse the raw response text.
- `select` explicitly on every query — no bare `findMany` — per
  [Query rules](../stacks/nodejs/architecture-specification.md#query-rules) and
  [security-implementation.md](../stacks/nodejs/security-implementation.md#injection): a bare
  query on `properties` or `room_types` would pull no sensitive columns here, but the habit is
  what protects the `users` and `sessions` queries elsewhere, and inconsistency invites a mistake
  later.
- Out-of-range pagination (`pageSize=101`, `page=0`) must be `400 VALIDATION_FAILED`, never
  silently clamped — [AC-CC-03](./acceptance-criteria.md#ac-cc-03--pagination-is-consistent-everywhere).
  Zod's `.strict()` numeric bounds on the query schema are the mechanism.
- `GET /properties/{propertyId}` and `GET /room-types/{roomTypeId}` accept either a UUID or a
  slug in the path segment per the contract — do not assume UUID-only.
- Public room-type responses must never include `roomCount` or room numbers — confirm the DTO for
  this endpoint is genuinely distinct from the admin-facing one, not the same type with fields
  conditionally omitted (conditional omission is exactly the "field present sometimes" hazard this
  project's nullable-field rule exists to prevent).

**Tests required.** Every endpoint's happy path; the money-as-string assertion above;
AC-CC-03 (pagination, out-of-range, and the `id`-tiebreak stable sort across two identical
requests); the public-catalogue half of
[AC-AZ-10](./acceptance-criteria.md#ac-az-10--public-endpoints-require-nothing-and-leak-nothing)
(no room numbers or ids anywhere in these responses, no session required).

**Done when.** `npm run test:run` passes; the money-as-string check is a real assertion in the
test file, not a comment claiming it was checked; `hotelapp-context`'s own note about the
`RoomTypeSummaryResponse` shape (still phrased as an open judgment call in Spring Boot's Step 2
outcome above) can be considered doubly confirmed and this step's outcome note should say so.

#### Node Step 3 (availability search) — instructions for Copilot

**Scope.** `GET /availability`, per [Availability search](./api-contracts.md#availability-search).

**Read first.** [Availability search](./api-contracts.md#availability-search) in full, including
the allocation-rule design decision at its end;
[data-model.md](./data-model.md#no-overbooking) (the literal anti-join SQL shape this query must
implement); [Query rules](../stacks/nodejs/architecture-specification.md#query-rules) (the
`$queryRaw` requirement — Prisma's query builder cannot express the `&&` range operator or the
`NOT EXISTS` anti-join this query needs);
[non-functional-requirements.md](./non-functional-requirements.md#response-time-targets) (the
`EXPLAIN` requirement); [AC-CX-10](./acceptance-criteria.md#ac-cx-10--pricing-arithmetic-and-rounding-order).

**Match Spring Boot — do not re-derive.** Two judgment calls Spring Boot's Step 3 made and
documented, both to be matched rather than re-decided: a `rateCategory` with no active
`rate_plans` row for the property is treated as a **0% discount** (same as `NONE`), and the room
type stays in results rather than being excluded; and pricing rounds the nightly rate to the cent
**first**, then multiplies by nights — not the reverse. Implement `domain/pricing.ts` to match
Spring Boot's `Pricing.java` behavior exactly, including the 0%-fallback case, since a reviewer
comparing the two should find the same rule stated the same way.

**Node/Prisma-specific concerns.**

- The availability query is hand-written SQL via `$queryRaw` with every date, id, and count as a
  **bound tagged-template parameter** — never string-interpolated — per
  [Query rules](../stacks/nodejs/architecture-specification.md#query-rules) and
  [security-implementation.md](../stacks/nodejs/security-implementation.md#injection). This is
  the single most parameter-dense query in the application and the one place SQL injection could
  plausibly be introduced.
- `Prisma.Decimal` throughout the pricing path, never `number` — `Number(decimal)` or
  `decimal.toNumber()` on a value headed for a response is a review finding per
  [coding-standards.md](../stacks/nodejs/coding-standards.md).
- `minNightlyRate`/`maxNightlyRate` filter on the **discounted** rate, applied in application code
  after pricing is resolved, matching Spring Boot's approach — not pushed into the SQL, since the
  discount calculation is a domain-layer concern.
- Sorting (`nightlyRate`, `maxOccupancy`, `name`) and pagination happen in application code given
  small per-property room-type cardinality, the same choice Spring Boot made — this is a
  reasonable default to match, not a hard requirement independently re-derived; flag it in the
  outcome note either way.
- `domain/pricing.ts` must be pure — no Prisma, no Express — per
  [architecture-specification.md](../stacks/nodejs/architecture-specification.md#layering), so it
  is unit-testable exhaustively and directly comparable to `Pricing.java`.

**Tests required.** [AC-CX-10](./acceptance-criteria.md#ac-cx-10--pricing-arithmetic-and-rounding-order)
as a **unit** test on `domain/pricing.ts` with both the 249.00/10%/3-nights case and a case where
round-then-multiply and multiply-then-round actually diverge (e.g. base 100.01 at 33.33% over 3
nights — the contract's own example does not distinguish the orders), plus an integration
assertion that `nightlyRate`/`totalAmount` are JSON strings, never numbers; AC-OB-06 and AC-OB-08
(the search-side half of out-of-service exclusion and accurate `availableRoomCount`); a dedicated
test for the 0%-discount-fallback judgment call (requesting a `rateCategory` with no configured
plan); an `EXPLAIN` assertion — per
[non-functional-requirements.md](./non-functional-requirements.md#response-time-targets) — that
seeds enough synthetic reservations to make a sequential scan measurably worse, then asserts the
plan uses the GiST index backing `reservations_no_overlap_excl` rather than a sequential scan on
`reservations`, run against the *exact* query the production path executes.

**Done when.** `npm run test:run` passes including the `EXPLAIN` assertion; `domain/pricing.ts` is
unit-tested exhaustively per the standing rule above; no contract or migration mismatch is found
(if one is, it is corrected in `api-contracts.md`/`data-model.md` first, per the standing rules).

#### Node Step 4 (booking: POST /reservations) — instructions for Copilot

**Scope.** `POST /reservations`, per
[the full endpoint section](./api-contracts.md#post-reservations--guest) — "the central feature,"
the same phrase Spring Boot's own Step 4 used.

**Read first.** The full `POST /reservations` section of
[api-contracts.md](./api-contracts.md#post-reservations--guest), including the "no hold, cart, or
pending state" design decision and the payment-payload note; the SQLSTATE-to-problem mapping table
and ["The no-overbooking path, precisely"](../stacks/nodejs/error-handling.md#the-no-overbooking-path-precisely)
in `error-handling.md`, **including its `> The exclusion constraint is the hard case in this
stack` callout in full** — this is the single most important passage in the Node specification for
this step;
[security-implementation.md](../stacks/nodejs/security-implementation.md#payment-data);
[Transactions](../stacks/nodejs/architecture-specification.md#transactions).

**Match Spring Boot — do not re-derive.** Three judgment calls Spring Boot's Step 4 made and
documented, all to be matched: the confirmation-number scheme is `HA` plus 8 Crockford base32
characters from a CSPRNG (kept out of `domain/` deliberately, since it is non-deterministic, not a
pure function — put it in a small dedicated module, not inline in the service); the
payment-decline check (a card ending `0000`) runs **before** room allocation, since a card known
to decline should never hold a room; idempotency is implemented as an **in-process cache only**,
explicitly not durable across restarts or across backends, and this must be stated as an accepted
demo-scope limitation in code, not silently presented as complete.

**Node/Prisma-specific concerns — this step carries the project's hardest Node-specific problem.**

- **Prisma has no mapped error code for SQLSTATE `23P01`.** Detection must go through
  `isExclusionViolation()` matching a raw error code or message text, per
  [error-handling.md](../stacks/nodejs/error-handling.md#the-no-overbooking-path-precisely)'s
  worked example — prefer issuing the reservation insert through `$queryRaw` inside the
  transaction so the driver's error carries a structured code (`code === '23P01'`) rather than a
  string match against `PrismaClientUnknownRequestError`'s message.
- **The allocation retry wraps the transaction; it does not live inside it.** A rolled-back
  transaction cannot be continued — three attempts, lowest `room_number` by natural sort each
  time, then `409 ROOM_UNAVAILABLE`. The exact retry-loop shape is in
  [error-handling.md](../stacks/nodejs/error-handling.md#the-no-overbooking-path-precisely)'s code
  example — follow it structurally.
- **A mocked Prisma client is prohibited for this test.**
  [AC-OB-01](./acceptance-criteria.md#ac-ob-01--two-concurrent-bookings-for-the-last-room-exactly-one-wins)
  must run against real PostgreSQL via Testcontainers or it proves nothing — a unit test with a
  mocked client would pass while the guarantee was entirely gone, per
  [testing-standards.md](../stacks/nodejs/testing-standards.md#1-the-layers-and-what-each-one-is-for).
- The reservation insert and the payment insert happen in **one transaction**, per
  [Transactions](../stacks/nodejs/architecture-specification.md#transactions) — a payment row
  must never exist without its reservation.
- Payment data: only `cardBrand` (derived from leading digits) and `cardLastFour` are ever
  written, logged, or returned — the PAN, CVV, and expiry are read once to derive those two
  fields and then discarded, never passed further down the call stack, per
  [security-implementation.md](../stacks/nodejs/security-implementation.md#payment-data). Request
  body logging must be disabled on this route specifically, at the logger, not per handler.
- `Idempotency-Key` header handling: a repeat of the same key within 24 hours returns the original
  `201` body rather than creating a second reservation.

**Tests required.** The concurrency test for
[AC-OB-01](./acceptance-criteria.md#ac-ob-01--two-concurrent-bookings-for-the-last-room-exactly-one-wins)
using `Promise.allSettled`, asserting on the **sorted pair** of outcomes, per
[testing-standards.md](../stacks/nodejs/testing-standards.md#the-concurrency-test) — never two
sequential `await`s, which would pass against an implementation with the race still present;
AC-OB-02 through AC-OB-05 and AC-OB-07 (adjacent stays, every overlap shape, cancel-frees-dates,
checked-out-does-not-free-dates, deterministic allocation order); the integration half of
[AC-CX-10](./acceptance-criteria.md#ac-cx-10--pricing-arithmetic-and-rounding-order) (`totalAmount`
as a JSON string on the created reservation); a `PAYMENT_DECLINED` test using a card ending
`0000`; an `Idempotency-Key` replay test.

**Done when.** `npm run test:run` passes, including the concurrency test run enough times locally
to be confident it is not a lucky interleaving (the stronger form described in
[testing-standards.md](../stacks/nodejs/testing-standards.md#1-the-layers-and-what-each-one-is-for) —
holding a transaction open with a conflicting insert uncommitted, then asserting the booking
request blocks and then fails — is worth writing at least once here too); the three judgment
calls above are documented in code comments, matching Spring Boot's; no mocked Prisma client
appears anywhere in the exclusion-constraint test path.

#### Node Step 5 (guest reservation management) — instructions for Copilot

**Scope.** `GET /reservations`, `GET /reservations/{reservationId}`,
`PATCH /reservations/{reservationId}`, `POST /reservations/{reservationId}/cancel`, per
[Guest reservation endpoints](./api-contracts.md#guest-reservation-endpoints) (the three below
`POST /reservations`, which Step 4 already built).

**Read first.** The `GET /reservations`, `GET /reservations/{reservationId}`,
`PATCH /reservations/{reservationId}`, and `POST .../cancel` sections of
[api-contracts.md](./api-contracts.md#guest-reservation-endpoints) in full;
[AC-CX-01](./acceptance-criteria.md#ac-cx-01--just-before-the-deadline-refundable) through
[AC-CX-09](./acceptance-criteria.md#ac-cx-09--illegal-cancellations-are-rejected) — the whole
cancellation-boundary block — and especially
[AC-CX-05](./acceptance-criteria.md#ac-cx-05--dst-transition-does-not-shift-the-deadline-arithmetic),
worked through step by step in the criteria document rather than re-derived by hand;
[Ownership: 404 versus 403](../stacks/nodejs/error-handling.md#ownership-404-versus-403).

**Match Spring Boot — do not re-derive.** Legal status-transition rules (what `PATCH` and cancel
may and may not do from each `status`) match Spring Boot's `ReservationStatusRules.java` /
[AC-CX-09](./acceptance-criteria.md#ac-cx-09--illegal-cancellations-are-rejected) exactly — put
this in `domain/status.ts`, pure, the fourth of the four planned pure modules. **A specific bug
Spring Boot's Step 5 found and fixed is worth guarding against here too, even though Node's clock
design differs in shape**: jumping a test clock to a cancellation-boundary instant silently
expired the guest's own login session in Spring Boot, because one shared `Clock` bean drove both
the cancellation arithmetic and session expiry, producing a confusing `401` instead of the
expected business-logic response. Node's session middleware and `domain/cancellation.ts` both need
a time source — check explicitly whether a test's injected `TimeSource` reaches both paths
consistently, and if a test seeds a session *before* moving the clock to a deadline instant (not
after), the same class of bug cannot recur silently.

**Node/Prisma-specific concerns.**

- **This step closes the date half of Step 0/2's carry-forward requirement.** `checkInDate`/
  `checkOutDate` must round-trip correctly from a *mutated* (`PATCH`) reservation, not just a
  freshly created one (Step 4 covers create-only) — assert both as `YYYY-MM-DD` strings that do
  not shift by a day under either process timezone tested (see below).
- `domain/cancellation.ts` computes the deadline as `check_in_date AT TIME ZONE tz - 48h` — an
  exact 48-hour duration, not "midnight two calendar days earlier." Verify
  [AC-CX-05](./acceptance-criteria.md#ac-cx-05--dst-transition-does-not-shift-the-deadline-arithmetic)'s
  worked DST example against the IANA zone database, not against hand arithmetic, and run the
  suite under at least two process timezones (`TZ=UTC` and something non-UTC), per
  [testing-standards.md](../stacks/nodejs/testing-standards.md#2-test-data-and-isolation).
- `PATCH` re-runs allocation and re-prices at **current** rates (not the original booking's
  rates), and may move the reservation to a different room — the response must carry the current
  `room`.
- Ownership: a guest reading, patching, or cancelling another guest's reservation gets `404`, not
  `403` — [AC-AZ-01](./acceptance-criteria.md#ac-az-01--a-guest-cannot-read-another-guests-reservation)
  and [AC-AZ-03](./acceptance-criteria.md#ac-az-03--a-guest-cannot-cancel-another-guests-reservation).
  The ownership check must precede any mutation — a handler that cancels first and checks
  ownership after returns `404` having still cancelled the booking, which
  [AC-AZ-03](./acceptance-criteria.md#ac-az-03--a-guest-cannot-cancel-another-guests-reservation)
  specifically asserts against (reservation state unchanged, not just the status code).
- `GET /reservations` never widens scope via a request parameter — filter on
  `req.context.user.id` server-side always, per
  [AC-AZ-02](./acceptance-criteria.md#ac-az-02--a-guests-list-contains-only-their-own-reservations).

**Tests required.** AC-CX-01 through AC-CX-09, all clock-controlled using an injected
`TimeSource`, exercised through real HTTP; AC-OB-04 (cancel frees the room, now testable through
real HTTP for the first time since both create and cancel exist); AC-AZ-01, AC-AZ-02, AC-AZ-03.

**Done when.** `npm run test:run` passes including the DST case and the two-process-timezone
run (`npm run test:tz`); the shared-clock/session-expiry interaction above has been checked, not
assumed safe; the outcome note explicitly states whether the date-serialization carry-forward
requirement is now closed for Node (mirroring how Spring Boot's Step 5 outcome above states it).

#### Node Step 6 (guest profile and password change) — instructions for Copilot

**Scope.** `GET /me`, `PATCH /me`, `PUT /me/password`, per
[Guest account endpoints](./api-contracts.md#guest-account-endpoints) — the last guest-facing
item. Completing this step closes Node's guest-facing slice (Phase 6 items 1-8), the same
milestone Spring Boot's Step 6 reached.

**Read first.** The `GET /me`, `PATCH /me`, and `PUT /me/password` sections of
[api-contracts.md](./api-contracts.md#guest-account-endpoints) in full;
[AC-AZ-09](./acceptance-criteria.md#ac-az-09--registration-cannot-escalate)'s second half (`PATCH
/me` specifically); [AC-SE-07](./acceptance-criteria.md#ac-se-07--password-change-revokes-other-sessions-but-not-the-callers).

**Match Spring Boot — do not re-derive.** Two judgment calls to match, not re-decide: `address`,
when present in a `PATCH /me` body at all, **replaces the whole sub-object** rather than merging
field-by-field, matching how the contract treats other sub-objects elsewhere (e.g.
`PUT /admin/.../rate-plans`); and `PATCH /me`'s "omitted is unchanged, explicit `null` clears it"
semantics is the whole point of this step.

**Node/Prisma-specific concerns.**

- **The omitted-vs-null distinction is easier to express in Node than it was in Spring Boot, not
  harder — do not import Spring's `JsonNode`-binding workaround.** A plain parsed JSON object in
  JavaScript already distinguishes "key absent" from "key present with value `null`" (`'phone' in
  req.body` is `false` in the first case, `true` with `req.body.phone === null` in the second) —
  Java's Jackson needed a raw-`JsonNode` escape hatch specifically because a typed request record
  cannot express that distinction, and Node has no equivalent problem. A Zod `.partial()` schema
  combined with checking key presence on the parsed body (not on the Zod-validated output alone,
  which may normalize absence and `undefined` together) is the natural fit here — verify this
  assumption against a real request before committing to the approach, since it is a design
  choice this document is making on Node's behalf rather than one already tested against this
  codebase.
- `.strict()` on the `PATCH /me` Zod schema so `role`/`isActive`/any other server-owned field is
  rejected with `400 VALIDATION_FAILED`, not silently dropped — this is what actually satisfies
  [AC-AZ-09](./acceptance-criteria.md#ac-az-09--registration-cannot-escalate)'s second half, per
  [Validation](../stacks/nodejs/coding-standards.md#validation) and
  [coding-standards.md](../stacks/nodejs/coding-standards.md)'s "never accept a server-owned
  field" rule.
- `PUT /me/password` must revoke every **other** session for the user while keeping the caller's
  current session valid — [SessionService](../stacks/nodejs/architecture-specification.md)'s
  equivalent `revokeAllExcept`-shaped method, unit-tested since Step 1 if it was built ahead of
  need, but only exercised through real HTTP here for the first time.
- The common-password deny-list used by registration (Step 1) should be reused here rather than
  duplicated — one deny-list, one place, consistent with
  [coding-standards.md](../stacks/nodejs/coding-standards.md)'s "a second money or date formatter"
  rule generalized to "a second copy of any shared rule."

**Tests required.** [AC-AZ-09](./acceptance-criteria.md#ac-az-09--registration-cannot-escalate)'s
second half (`role`/`isActive` rejected via `PATCH /me`, `400`, profile unchanged);
[AC-SE-07](./acceptance-criteria.md#ac-se-07--password-change-revokes-other-sessions-but-not-the-callers)
through real HTTP; `PUT /me/password`'s `INVALID_CREDENTIALS` case (wrong `currentPassword`); a
dedicated test for the omitted-vs-null-vs-present distinction on at least `phone` and `address`,
since this is the one endpoint in the whole contract where that distinction is load-bearing.

**Done when.** `npm run test:run` passes; **Node's guest-facing slice (Phase 6 items 1-8) is
complete**, the same milestone Spring Boot reached at its own Step 6; the outcome note for this
step says so explicitly and updates the Phase 6 status table above accordingly, the same update
this document needed (and initially missed) after Spring Boot's own Step 6.

---

> **Design Decision — interleaving Phase 6 and Phase 7 rather than finishing each fully in
> order, driven by an interview deadline (2026-09-27).** The order below, and Phase 6's own
> suggested order, both assume finishing one phase before starting the next. That reasoning
> (contract before implementation, backends before frontends, since "the interesting
> correctness lives in the backends") **still holds** — this is not a reversal of it, and
> nothing built so far was built against an assumption this now breaks. It is a re-prioritization
> for a specific goal a strict phase order doesn't optimize for: having a complete, demoable
> vertical as early as possible, so an unfinished project still has one fully working thing to
> show rather than four partially-done ones.
>
> **The revised order:** finish Spring Boot's guest-facing slice only (Phase 6 items 1-8 — **done,
> as of Step 6**) — Phase 6 items 9-12 (admin, reporting, cross-cutting) wait. Then build React's
> guest-facing screens (Phase 7 items 1-6)
> against that slice — **this is the first "one full stack working" milestone**, worth protecting
> if time runs short. Then Node's guest-facing slice, to the same point Spring Boot reached,
> unlocking [AC-SE-05](./acceptance-criteria.md#ac-se-05--a-session-works-interchangeably-against-both-backends)
> — "the clearest thirty-second proof that the two backends implement one API" — and the Phase 8
> two-backend concurrency race, live rather than merely specified. Then Angular's guest-facing
> screens, benefiting from React's now-validated UX and any contract fixes React's build
> surfaced. **Only then** circle back for both backends' admin endpoints, both frontends' admin
> screens, and Phase 8 integration — the most legitimately cuttable layer if the calendar runs
> out before the interview does.
>
> **The one discipline to keep across this re-sequencing**: a UX or contract gap React's build
> discovers gets fixed in `ui-specifications.md`/`api-contracts.md` themselves, not worked around
> silently and then copied into Angular's build unexamined — a shim in one client is drift with
> extra steps, per Phase 3's own outcome notes above.

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

### Step 1 (foundation) — done 2026-09-27, React only

`hotelapp-client-react@fbcd8df`. Item 1 (skeleton, routing, Tailwind, API client) plus session
bootstrap pulled forward from item 4 — see the judgment call below. `npm run lint` / `typecheck`
/ `test:run` (4 files, 24 tests) / `build` (104 modules, ~118 KB gzip) all pass, verified by
running them, not by trusting the report.

Built: full ESLint 9 + Prettier + Vitest + React Testing Library + MSW toolchain (none of it
existed after Step 0); `QueryClient` defaults per
[state-management.md](../stacks/react/state-management.md#defaults) (30s `staleTime`, no retry on
a 4xx); the `qk` query-key factory; a complete fetch wrapper (all HTTP methods,
`Idempotency-Key` passthrough, the global `401`/`ACCOUNT_INACTIVE` rule with bootstrap
suppression for `GET /auth/me`); `AuthProvider`/`useSession`; the full error-code message table;
`lib/format.ts`; a real S0 shell (Header, Footer, ToastProvider, ErrorBoundary); S1 brought up to
its full spec (search, city filter, sort, pagination, both empty states, all URL-driven via
`useSearchParams`).

**Judgment call, flagged rather than silently decided:** this step's own suggested order lists
session bootstrap under item 4 (Auth), but it was built here in item 1 instead, because
[ui-specifications.md](../stacks/react/ui-specifications.md#s0--app-shell) calls bootstrap "the
app's first action" and [architecture-specification.md](../stacks/react/architecture-specification.md#provider-composition)
wires `AuthProvider` unconditionally from `main.tsx` before any auth screen exists. The `401`
redirect target (`/login`) 404s harmlessly (S15) until Step 4 (still Auth, per the item list)
fills it in.

Two real bugs found during manual browser verification, not present in the original scope,
caught by testing rather than assumed correct: the filter-debounce effect unconditionally
deleted the `page` URL param on mount, breaking a deep link to a specific page — fixed by
diffing against the current URL params instead of the stale closure values. And `page=0` was
being silently clamped to `1` (`|| 1`) instead of reaching the server to be validated, violating
[api-contracts.md](./api-contracts.md#pagination-sorting-filtering)'s "never silently clamped"
rule — fixed with an explicit `Number.isFinite` check.

**Found, not fixed here** (a different repo, out of scope for this one): Spring Security's
`401`/`403` responses in `hotelapp-server-springboot` are missing CORS headers, because they're
emitted before `WebConfig`'s MVC-scoped CORS mapping runs — confirmed with `curl`, `GET
/properties` (200, MVC-handled) carries `Access-Control-Allow-*`, `GET /auth/me` (401,
security-handled) does not. This client tolerates it by design (falls back to its network-failure
banner), so S1 still renders correctly, but the "logged out" vs. "can't reach the server"
distinction is currently lost in a real browser. Needs a fix in the Spring Boot repo — a CORS
configuration source wired to Spring Security directly, not only `WebMvcConfigurer` — before Step
4's login/logout flows depend on that distinction being visible.

### Step 2 (public browsing: property detail, room types) — done 2026-09-27, React only

`hotelapp-client-react@353ec32`. Item 2: property detail (S2) — hero, address, description, the
date/guest search-entry form — the Rooms section as room-type cards (amenity chips, an accessible
badge, money via the shared formatter), and room-type detail, route-addressable either way at
`/room-types/:roomTypeId` (a desktop modal, or a standalone page on a direct URL load). `npm run
lint` / `typecheck` / `test:run` (7 files, 33 tests) / `build` (118 modules, ~102 KB gzip) all
verified by running them.

**A routing-shape change, not just a new screen.** The room-type modal needs React Router's
background-location pattern — rendering the property-detail page behind the modal from
`useLocation().state`, so a direct URL load with no such state falls through to the standalone
page instead. Step 1's `createBrowserRouter`/`RouterProvider` (data router) matches purely on
pathname and can't be overridden this way, so routing moved to declarative `<BrowserRouter>` +
`<Routes>`. The `401` redirect wiring moved from `main.tsx` to `App.tsx` (`useNavigate` in a
`useEffect`) as a direct consequence — a case where a screen's own UI requirement forced a
structural change nobody had planned for at Step 1.

**The one genuinely uncertain part from Step 1 is now resolved, by evidence rather than
inference**: `GET /properties/{propertyId}`'s embedded `roomTypes` field, which
[api-contracts.md](./api-contracts.md) names only as "summary form" with no example, was curled
against the live backend and confirmed flat — no `description`, `amenities`, or `photos` — matching
what the Spring Boot implementer had assumed when building it (see this document's Step 2 outcome
under Phase 6) but never previously confirmed against a client. Typed narrowly in `api/types.ts` as
`PropertyRoomTypeSummary` rather than inventing a richer shape; this screen doesn't read the field
at all, since the Rooms section calls the separate `GET /properties/{propertyId}/room-types`
endpoint instead. **Worth settling with a real example in `api-contracts.md`** before Angular or the
Node backend has to guess the same thing independently.

**A process gap found and closed**: two steps in a row (this one and Step 1) landed fully verified
but uncommitted, discovered only by checking `git log` rather than trusting the completion summary.
Both `hotelapp-client-react`'s and `hotelapp-server-springboot`'s Copilot instructions now carry a
standing rule to commit at the end of every step regardless of whether the prompt says so.

### Step 3 (search and results) — done 2026-09-27, React only

`hotelapp-client-react@83cb778`. Item 3: `GET /availability`/`/amenities`/`/rate-categories`
wired through TanStack Query (`availability` at `staleTime: 0` per state-management.md — the one
query that must never serve a cached answer; the reference lists at `Infinity`). `SearchScreen`
renders the search form, sidebar filters, sort, result cards with discount pricing and scarcity
text, and client-side date pre-validation reusing `error-handling.md`'s exact field-code wording.
The standing commit rule worked as intended this time — committed and pushed without having to be
caught and asked for again.

Four judgment calls, all verified present in the actual code, not just claimed: the rate-category
label on a result card comes from `GET /rate-categories`'s data, never the raw enum value; all
four sort options use the same `field:asc`/`field:desc` convention `GET /properties` already
established, inferred rather than given an explicit grammar in the contract; the room-type filter
list is sourced from the static 5-value `room_type_code` enum (factored into
`lib/roomTypeCategories.ts`, shared with S2's room-type card) rather than a per-property endpoint,
since none exists scoped that way; a server-side `VALIDATION_FAILED` this screen's own
pre-validation didn't already catch renders as one generic form-level alert rather than a
field-mapped one — a fallback path expected to be unreachable in practice, not a full experience.

**A real gap, not disclosed in the original summary and found by checking, not trusting**: this
step shipped zero new test files — `SearchScreen.tsx` (412 lines), `ResultCard.tsx`, and
`validation.ts` all untested, despite every prior step adding tests for its new logic and this
being ui-specifications.md's own "most complex guest screen." Carried forward rather than closed
immediately here, for cost reasons — see the Step 4 entry below for how it's being closed.

**Not a code defect, but worth recording so it isn't mistaken for one**: a stray leftover Vite dev
server was squatting on port 5173 during verification, silently bumping new dev servers to 5174 —
which makes every backend call fail as an opaque CORS error, since the backend only allow-lists
5173. Distinct from the separately-documented `/auth/me` CORS defect; check for a stray process on
5173 before suspecting either CORS issue again.

### Step 4 (auth: login, registration, route guards) — done 2026-09-27, React only

`hotelapp-client-react@69f6924`. Item 4: `login()`/`register()`, `LoginScreen`/`RegisterScreen`
(shared `AuthLayout`, React Hook Form + Zod, a `PasswordField` with show/hide), and
`RequireAuth`/`RequireStaff`/`RequireManager` route guards with a rank map. `react-hook-form` and
`zod` installed — the first screen that actually needed them. Opened with a preamble closing part
of Step 3's test-coverage gap: `validateDateRange` unit tests (33 → 40 tests), not the fuller
`SearchScreen` component-test debt, which is still carried forward.

Five judgment calls, all verified present in the actual code: `Retry-After` parsing assumes
delta-seconds, never an HTTP-date (`api-contracts.md` doesn't specify the format either way — the
code comment states this more confidently than the disclosed judgment call itself does, worth
softening); the mutation `onError` handlers reuse `resolveError` generically rather than branching
per-code, matching `error-handling.md` §5's canonical pattern, with `EMAIL_ALREADY_REGISTERED`'s
login link layered on via a separate flag since the shared resolver only returns text and field;
an authenticated-but-under-ranked visitor is redirected (`RequireStaff` → `/`, `RequireManager` →
`/admin`) rather than shown a page-level permission screen, since none exists in this phase and
`INSUFFICIENT_ROLE` is meant to be unreachable when guards work; `RequireStaff`/`RequireManager`
are built but not wired into `routes.tsx` (per this step's own scope — `/admin` doesn't exist
until Phase 6 items 9-12), proven instead against a test-only protected route; the three new
dependencies followed this `package.json`'s existing `^`-range convention rather than
`dependency-policy.md`'s literal "pinned exactly" wording, since no existing dependency in the
file is actually pinned that way.

**One real bug caught and fixed during the preamble, not by inspection but by a failing test**:
a first-draft `PAST_DATE` test used UTC calendar-day arithmetic, but `validation.ts`'s own
`todayUtcDate()` defines "today" as the *local* calendar day expressed as a UTC-anchored `Date` —
the two can disagree by a day depending on the machine's timezone. Fixed the test helper to match
the function under test, not the other way around.

**The banned-token-handling grep from security-implementation.md was run, not just assumed
clean**: `bearer|jwt|accessToken|refreshToken|auth/refresh` returns nothing in `src/`.

### Step 5 (booking flow: summary, payment, confirmation) — done 2026-09-27, React only

`hotelapp-client-react@9acb688`. Item 5, "the central feature" of the guest journey: S4/S6/S7
built end to end and verified live against Spring Boot, not just automated checks — register →
S4 (re-validation against live availability) → S6 success (`4242…`) → S7 → a fresh reload (real
fetch, not cache) → back to S6, decline (`…0000`) → field-level error with the form retained →
an unknown reservation id → 404. `RequireAuth` (built in Step 4, unwired until now) gets its
first real consumer here.

Four judgment calls, all verified in the actual code: `formatTimestamp` spells out every
`Intl.DateTimeFormat` component explicitly, since `dateStyle`/`timeStyle` can't combine with
`timeZoneName`; a new `lib/cancellationDeadline.ts` mirrors the backend's
`check_in_date AT TIME ZONE tz - 48h` formula client-side (S4 needs a deadline before a
reservation exists to have one), using `timeZoneName: "longOffset"` for a DST-aware UTC offset
with no date library, per dependency-policy.md; `useBlocker` was correctly avoided in favor of
`beforeunload` plus a disabling overlay, since it needs a data router and Step 2 deliberately
moved this app onto declarative routing for the room-type modal; a `ReservationPricing` type was
typed narrower than the availability response's `Pricing` after a live click-through caught
`pricing.nights` rendering blank on S7 — the reservation object's embedded pricing has no
`nights`/`rateCategory` fields, unlike `GET /availability`'s.

**The recurring test-coverage gap escalated, not just re-flagged a third time.** This step shipped
856 lines including the trickiest new pure logic yet (`cancellationDeadline.ts`, explicitly
hand-verified against `acceptance-criteria.md`'s own worked examples) with exactly one test
touched, none new. Second occurrence after Step 3 — this time closed two ways: `cancellationDeadline.test.ts`
was added directly (pinned to AC-CX-04's two-timezone example and AC-CX-05's DST-transition case
— the same values that were checked by hand and would otherwise have been thrown away), and
`hotelapp-client-react`'s Copilot instructions now carry a standing rule that any new pure
function with non-obvious logic ships with tests in the same commit, regardless of what that
step's own prompt says — the same escalation already applied to the commit-and-push gap after it
recurred once.

### Step 6 (guest reservation history, modify, cancel: S8b/S8c) — done 2026-09-27, React only

`hotelapp-client-react@18a0f52`. Split from item 6's own scope the same way the backend split it
(reservation management vs. profile/password): S8b (the four-tab reservation list) and S8c
(detail, with status-gated modify/cancel) only — S8a/S8d are a separate, lighter step still ahead.
Verified end to end against live Spring Boot using Step 5's reservation: Upcoming shows it,
Past/Cancelled show distinct empty copy, a date change to a different rate category produces the
correct new-total comparison, and cancelling shows the refund wording before confirming and the
outcome note after.

**The standing test-coverage rule (added after Step 5) worked immediately, not just eventually.**
Both new pure-logic files this step introduced — `lib/reservationTabs.ts` (the tab-to-query-param
mapping) and `lib/reservationChangeSummary.ts` (the new-vs-old-total comparison) — got their own
test files in the same commit, unprompted by a reminder. Test count: 44 → 50.

Three judgment calls, all verified in the actual code: the `all` tab's empty copy
("You have no reservations.") isn't literally specified in ui-specifications.md (only Upcoming/
Past/Cancelled are); a cancelled reservation's outcome note uses the cancel mutation's own
response (exact `cancelledAt` and refund amount) when cancelled in the current session, falling
back to `cancellation.isRefundableNow` on a plain page load of an already-cancelled reservation,
since `GET /reservations/{id}`'s documented shape carries no `cancelledAt`/refund detail for that
case — worth adding to the contract if a precise post-hoc outcome matters later; both dialogs are
conditionally mounted rather than controlled by an `open` prop (`{open && <Dialog .../>}`), since
`react-hooks/set-state-in-effect` correctly rejected a reset-on-open effect and a fresh mount per
open is the idiomatic fix — this also gets native `<dialog>`'s automatic return-focus-on-close for
free, satisfying the focus-trapping requirement without extra code.

**Worth watching, not yet a problem**: the production bundle crossed Rollup's generic 500 KB
pre-gzip chunk-size warning threshold for the first time (510 KB raw, 152.58 KB gzip) — still
comfortably inside non-functional-requirements.md's 300 KB **gzipped** budget, which is the actual
spec'd number, so no action needed yet. Worth a glance again once Node/Angular or the admin phase
add more screens to this same bundle.

### Step 7 (guest profile, password: S8a/S8d) — done 2026-09-27, React only

`hotelapp-client-react@06d375b`. The other half of item 6, closing it out — and with it, **all of
Phase 7's guest-facing scope (items 1-6) is now built and manually verified against the live
Spring Boot backend**: public browsing, search, auth, booking, reservation management, and
profile/password. Nothing in that scope was simplified or skipped; the only deliberately deferred
work is admin (items 7-8, S9-S14), same as Spring Boot's own guest-facing/admin split, plus the
still-open Spring Boot Security-CORS defect (documented, not fixed here, out of this repo).

The standing test-coverage rule held for a third step running: `lib/buildProfilePatch.ts` (the
dirty-fields-to-PATCH-body builder — the frontend's mirror of the backend's own hardest problem on
this endpoint, omitted-vs-null-vs-empty-string) shipped with its own test in the same commit,
unprompted. 50 → 56 tests.

Three judgment calls, all verified in the actual code: `PUT /me/password`'s `INVALID_CREDENTIALS`
is field-level here (`ui-specifications.md`'s explicit S8d text), a deliberate departure from the
shared error map's form-level wording for the same code on the login screen — confirmed in the
browser that the client's global dead-session redirect (which keys on error *code*, not HTTP
status) correctly does not fire for it, since this code isn't in that rule's list; `Profile.address`
is typed non-nullable per the contract's own `GET /me` example even though `data-model.md` allows
null address columns for a guest, rendered defensively (`?? ""`) regardless; `Header`'s `UserArea`
became a real dropdown menu (`role="menu"`/`"menuitem"`, click-outside + Escape) rather than
extending the previous flat inline layout, since ui-specifications.md's S0 table literally says
"menu" for the Guest state — a larger diff than a single link addition, but scoped to Guest-only
items as the prompt asked.

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

## Open items carried into Phase 6

1. **Spring Boot before Node in Phase 6** — followed in practice, not just recommended. Steps 0
   through 5 were all built against Spring Boot first, per the migration asymmetry: the
   Flyway-owning backend had to make the schema real before Prisma has anything to introspect.
   The Node backend has not been started.
2. **No end-to-end browser testing.** The one acknowledged gap in the test strategy, named in
   [devops-pipeline-overview.md](./devops-pipeline-overview.md#deliberately-absent) and in all four
   stacks' `testing-standards.md`. Fine to carry; worth deciding deliberately rather than by
   default.
3. **The per-repo `README.md` files are one line each**, and are the most-read files in a portfolio
   project. Phase 8 item 5 covers them; worth noting that they are currently the weakest artifact
   in the four implementation repos.
4. **A CI job that diffs the byte-identical document pairs** is specified in four stack documents
   but not yet written. Four pairs now depend on it —
   [context-map.md](../context-map.md) lists them. Six broken cross-document anchors were found by
   hand during Phases 3 and 4, which is the argument for automating the link check alongside it.

### Resolved since Phase 2

- **`shared/decision-log.md`** was a stub; it now holds three reversals.
- **`context-map.md`** is current: all four stacks marked written, the four byte-identical pairs
  listed, and the migration asymmetry called out as the thing a symmetric-reading backend document
  probably got wrong.
- **Migration ownership** was reviewed and carried into all 20 Phase 4 documents, with its
  consequences made explicit in both directions rather than mentioned once.

### Resolved since Phase 4

- **`shared/migrations/V001__initial_schema.sql`** now exists (`281365f`), verified by execution
  against a throwaway database — see the Phase 4 outcome above.
- **Phase 5** is done: all five repos carry agent instructions, verified by file presence and
  md5-identical shared blocks.
- **Docker / Testcontainers** was blocked at Step 0 (Docker not installed) and again at Step 1
  (a stale `testcontainers-bom` pin); both are resolved — see the Phase 6 outcome above.

### Resolved since Phase 6 began

- **Date serialization** is now validated: `checkInDate`/`checkOutDate` round-trip correctly from
  both a created (Step 4) and a modified (Step 5) reservation. Money was closed in Step 2 — both
  halves of Step 0's original carry-forward requirement are now closed.
- **Two package-layout mistakes** (the exception hierarchy in `domain/`; `web/` mixing four
  responsibilities) found and refactored — see "Architectural corrections" under Step 4 above and
  decision-log.md entries 4-5.

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
