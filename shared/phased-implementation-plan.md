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
| 6 | Backend implementation | ⬜ **In progress** — Steps 0-6 done for both backends; **Node's guest-facing slice (Phase 6 items 1-8) is now complete, the same milestone Spring Boot reached at its own Step 6.** Admin/reporting/cross-cutting (items 9-12) deferred for both backends — see the design decision before Phase 7 |
| 7 | Frontend implementation | ⬜ **In progress** — React's entire guest-facing slice (Steps 1-7, items 1-6) is done and verified against live Spring Boot. Angular Steps 1-4 (foundation, property detail/room types, search/results, and auth/route guards, S1-S3 + S5) are now done too, against live Node (Step 4 also cross-verified against live Spring Boot for AC-SE-05). **Paused here at Jeff's explicit instruction (2026-09-27)** rather than proceeding straight to Node per the original sequencing — see the design decision below for what "next" meant before the pause |
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

#### What Node Step 2 actually taught us — done 2026-09-29

Shipped: `GET /properties/{propertyId}` (UUID or slug, plus its embedded `roomTypes` in the
confirmed-flat summary form), `GET /properties/{propertyId}/room-types` (full shape with
`amenities`/`photos`), `GET /room-types/{roomTypeId}`, `GET /amenities`, `GET /rate-categories`.
9 new integration tests, all passing, on top of Step 0/1's 18 (27 total). `npm run lint`,
`typecheck`, `build`, and `format:check` all clean; `npm audit --omit=dev` still 0
vulnerabilities.

**The money-as-string check Step 0 flagged as still open is now closed**, on both the summary and
full room-type shapes: asserted against raw response text (`res.text`), not a parsed body, that
`baseRate` serializes as `"249.00"` and never the bare number `249`. `Prisma.Decimal.toFixed(2)`
(`src/lib/money.ts`) is exact for this column's `numeric(10,2)` domain — no floating-point
rounding step is involved, unlike a `Number()` conversion would be.

**Confirmed, not re-derived**: `GET /properties/{propertyId}`'s embedded `roomTypes` is the flat
summary shape (`id, code, name, baseRate, currency, maxOccupancy, bedConfiguration,
isAccessible` — no `amenities`/`photos`), matching Spring Boot's `RoomTypeSummaryResponse` and
confirmed independently by curling the live Spring Boot backend in the React client's Phase 7
Step 2. Typed as a distinct `RoomTypeSummaryDto`, not the full `RoomTypeDto` with fields
conditionally omitted.

**One divergence from the plan's own instructions, disclosed**: `room_types` has no `slug` column
in `data-model.md` — only `properties` does. The plan's blanket statement that "`GET
/properties/{propertyId}` and `GET /room-types/{roomTypeId}` accept either a UUID or a slug"
does not hold for the room-type endpoint; Spring Boot's own `RoomTypeController` also only ever
takes a UUID path variable, confirming this is a plan wording slip rather than a Node-specific
choice. Node matches Spring Boot: a non-UUID-shaped `roomTypeId` is a `404 NOT_FOUND` (checked
before querying, so a malformed value never reaches a `uuid`-typed column and produces a
database-level `500`), not a slug lookup.

**`select` used throughout, including nested relations** (`room_type_amenities` → `amenities`,
`room_type_photos`) fetched in one query via nested `select`, never per-row in a loop — no
`include` with a bare object was used anywhere in this step.

No contract defect found. `api-contracts.md`'s public catalogue section matched what was needed
without correction.

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

#### What Node Step 3 actually taught us — done 2026-09-29

Shipped `GET /availability` end to end: the physical-room anti-join as one hand-written
`$queryRaw` (`Prisma.sql` fragments nested inside a parent template, `Prisma.empty` for absent
optional filters, `Prisma.join` for `IN (...)` lists — no string concatenation anywhere), pure
`domain/pricing.ts` ported line-for-line from `Pricing.java`, and filtering/sorting/pagination in
application code on the discounted rate, matching Spring Boot's Step 3 approach exactly. 15 new
tests (6 unit on `domain/pricing.ts`, 9 integration), on top of Step 0–2's 27 (42 total), all
passing; `npm run ci` (lint, format:check, typecheck, test:run, build) green.

**Matched, not re-derived, both Spring Boot judgment calls**: a `rateCategory` with no active
`rate_plans` row resolves to a 0% discount, same as `NONE`, room type stays in results; nightly
rate rounds to the cent first, then multiplies by nights. The 100.01/33.33%/3-nights case that
actually distinguishes rounding order from the 249.00/10%/3-nights case is unit-tested directly
against the same two fixture numbers Spring Boot's `PricingTest`/`AvailabilityIT` use, so the two
implementations are directly comparable line for line.

**The required `EXPLAIN` assertion is a real automated test, not a manual check**: seeds 2000
synthetic reservations (one each on 2000 distinct decoy rooms, generated with client-side
`randomUUID()` ids so both bulk inserts run in two round trips with no query needed to learn
generated ids afterward), `ANALYZE`s the affected tables, then calls the exact production query
function in `EXPLAIN (ANALYZE, BUFFERS)` mode and asserts the plan uses
`reservations_no_overlap_excl` rather than a sequential scan on `reservations`.

**One schema detail not called out explicitly anywhere it was needed**: `reservations_status_
timestamps_chk` requires `cancelled_at IS NOT NULL` whenever `status = 'CANCELLED'` (matching the
same requirement for `checked_in_at`/`checked_out_at`) — a test fixture builder inserting a
CANCELLED reservation without setting `cancelled_at` fails at the database with a `23514` check
violation, not a Prisma-level validation error. Worth a one-line mention in `data-model.md`'s own
constraint section for whichever backend hits this fixture-building requirement next.

No contract or migration mismatch was found this step — `api-contracts.md`'s availability-search
section and `data-model.md`'s no-overbooking section matched what was needed without correction.

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

#### What Node Step 4 actually taught us — done 2026-09-29

Shipped `POST /reservations` end to end: `domain/cancellation.ts`, `domain/allocation.ts`, and
`domain/paymentValidation.ts` (three new pure modules, ported line-for-line from Spring Boot's
`Cancellation`/`Allocation`/`PaymentValidation`), `lib/confirmationNumber.ts` and
`lib/idempotencyCache.ts` (matching `ConfirmationNumberGenerator`/`IdempotencyCache` exactly), and
`db/prismaErrors.ts` for the `23P01`/`23505` raw-SQLSTATE detection error-handling.md calls out as
this stack's hardest problem. `bookingService.ts` runs the allocation retry (3 room candidates ×
5 confirmation-number attempts each) entirely outside any `$transaction`, opening one fresh
transaction per attempt via `repositories/reservationRepo.ts`'s `$queryRaw` insert (never
`prisma.reservations.create`, specifically so a constraint violation surfaces `meta.code` rather
than only a message string). 19 new tests (3 unit files, 16 integration — AC-OB-01 through
AC-OB-07 including the stronger held-open-transaction form, AC-CX-10's serialized pricing,
`PAYMENT_DECLINED`, Idempotency-Key replay), 71 total, all passing; `npm run ci` green.

**The one real Node-specific discovery, confirmed rather than assumed from the spec's prose**:
Prisma's raw-query errors (`$queryRaw`/`$executeRaw`) surface as a
`PrismaClientKnownRequestError` with code `'P2010'` ("raw query failed"), whose `meta.code` holds
the actual Postgres SQLSTATE — `'23P01'` for the exclusion-constraint violation the no-overbooking
guarantee depends on, `'23505'` for the confirmation-number collision. This is what makes
`isExclusionViolation`/`isConfirmationNumberCollision` a structured-field check rather than a
message-text match, exactly as `error-handling.md`'s callout said would be possible if the insert
went through `$queryRaw`.

**Matched, not re-derived, all three named Spring Boot judgment calls**: `HA` + 8 Crockford-base32
CSPRNG characters (`node:crypto`'s `randomInt`, not `Math.random`) for the confirmation number; the
payment-decline check (a card ending `0000`) runs before allocation; the Idempotency-Key cache is
an in-process `Map` with a stated 24-hour TTL, documented in its own module as a demo-scope
limitation rather than presented as durable.

**A test-fixture trap, not a production bug**: a reservations integration test file that logs
guests in through the real, rate-limited `POST /auth/register` endpoint eventually 429s itself,
since the rate limiter is shared per `createApp()` instance (one instance per test file, matching
`availability.test.ts`'s existing pattern), not per test — registering more than 10 guests in one
file makes later bookings fail with a confusing `401 AUTHENTICATION_REQUIRED` instead of exercising
booking behavior at all. Fixed by creating the guest user and its session directly
(`insertGuestUser` + `services/sessionService.createSession`), bypassing the endpoint and its rate
limiter entirely for fixture setup — worth remembering for Step 5's reservation-management tests
too, which will need just as many authenticated fixture guests.

No contract or migration mismatch was found this step.

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

#### What Node Step 5 actually taught us — done 2026-09-29

Shipped all four guest reservation-management endpoints: `GET /reservations` (list, scoped
server-side to the caller, never widened by a request parameter), `GET /reservations/{id}`,
`PATCH /reservations/{id}` (re-prices at the room type's current `base_rate`, re-allocates only
when dates changed, recomputes `cancellation.deadline`), and `POST /reservations/{id}/cancel`
(the refund boundary, `wasRefundable`/`refund` shape). `domain/status.ts` is the fourth and final
planned pure module, ported line-for-line from Spring Boot's `ReservationStatusRules` (`canCancel`/
`canModify`, both `status === 'CONFIRMED'`). 13 new integration tests plus 2 new unit tests, 86
total, all passing; `npm run ci` green.

**Matched, not re-derived:** ownership resolves to `404`, checked before any mutation (AC-AZ-01/
AC-AZ-03); `PATCH`'s re-allocation reuses the same `findAllocationCandidateRooms` query from Step
4, extended with an optional `excludingReservationId` parameter (mirroring Spring Boot's
`RoomRepository.findAllocationCandidates(..., excludingReservationId)`) — without it, a
reservation being modified would wrongly disqualify its own currently-held room as a candidate
whenever the new dates still overlap the old ones on the same room.

**The date-serialization carry-forward requirement is now closed for the mutate path too.**
`GET`/`PATCH`/cancel's reservation reads and writes all go through `$queryRaw` with `::text`
casts on every date and money column, exactly like Step 4's `insertReservation` — never a Prisma
model method for these columns — so `checkInDate`/`checkOutDate` round-trip as exact `YYYY-MM-DD`
strings regardless of the Node process's own timezone, on create, read, and update alike.

**The shared-clock/session-expiry interaction Spring Boot's Step 5 flagged does recur here in a
different shape, and was designed around rather than patched.** Both `middleware/session.ts` and
`domain/cancellation.ts` read the one injected `TimeSource`, so a test that reuses one login
session across a multi-day `clock` jump to reach a cancellation-boundary instant hits the
session's own 8-hour idle window first and gets a confusing `401` instead of exercising the
boundary. Fix: mint a **fresh** session (`sessionService.createSession`) at the clock's
already-jumped-to value immediately before the request under test, rather than trying to keep one
session's sliding-expiry window synchronized with an arbitrarily large jump. `ManualClock` also
gained a `set(iso)` absolute-jump method alongside its existing relative `advanceMs(ms)`, matching
Spring Boot's own `MutableClock.set(Instant)`, for landing exactly on a computed boundary instant
without accumulating rounding error across several `advanceMs` deltas.

A second, unrelated test-fixture bug was found and fixed in `test/builders/reservation.builder.ts`
(not a production bug): `insertTestReservation` only set `cancelled_at` for a `CANCELLED` fixture,
so directly inserting a `CHECKED_IN`/`CHECKED_OUT` fixture (needed for AC-CX-09's illegal-transition
tests) violated `reservations_status_timestamps_chk` (23514), which requires each status's own
timestamp column non-null. Fixed once in the shared builder.

No contract or migration mismatch was found this step.

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

#### What Node Step 6 actually taught us — done 2026-09-29

Shipped `GET /me`, `PATCH /me`, `PUT /me/password`. **This closes Node's guest-facing slice
(Phase 6 items 1-8)**, the same milestone Spring Boot reached at its own Step 6 — see the Phase 6
status table above, updated accordingly. `GET /me`/`PATCH /me` are distinct from the existing
`GET /auth/me` (the lighter `{ user }` bootstrap shape from Step 1): the new router returns the
full, flat profile object, including `phone`, `address`, and `createdAt`. 9 new integration tests,
95 total, all passing (**corrected 2026-09-29**: originally recorded as "104 total" here, which
was never actually run — Node Step 7's own count only reconciled at 104 after adding a confirmed 9
more tests on top of this step's real total, checked by running `npm run test:run` against this
step's own commit, `hotelapp-server-nodejs@5275012`, directly).

**The omitted-vs-null design this document proposed on Node's behalf (see the instructions above)
was verified against zod 3.24.4's actual parse output before being relied on, not assumed:** for
an optional key absent from the request body, the parsed result object genuinely omits the key
(`'phone' in result` is `false`); for an explicit `null`, the key is present with that value. A
throwaway script (`node` + a two-line `.parse({})` vs `.parse({ b: null })` check) confirmed this
before any route code was written. Since a parsed JSON body can never contain a literal
`undefined` (JSON has no such value), `body.phone !== undefined` in the route handler is exactly
"the key was present in the request" — no raw-body/`req.body` presence-checking workaround
(let alone Spring's `JsonNode` escape hatch) was needed at all, confirming the document's
prediction.

**`address` replaces the whole sub-object, matching Spring Boot's judgment call**: sending a new
`address` with no `line2` clears a previously-set `line2` rather than preserving it — tested
directly (set an address with `line2`, then replace it with one omitting `line2`, assert the
response's `line2` is `null`). `address: null` clears all six columns in one call.

`.strict()` on `patchMeSchema` is what makes `role`/`isActive` a `400 VALIDATION_FAILED`
(AC-AZ-09's second half) with the profile provably unchanged afterward (asserted with a direct
`prisma.users.findUniqueOrThrow`, not just the response status) — neither field is declared in
the schema at all, so `.strict()` rejects them as unrecognized keys before any handler code runs.

`PUT /me/password` reuses `sessionService`'s existing `createSession`/session-repo pattern: a new
`revokeAllSessionsExcept(db, clock, userId, exceptSessionId)` (service) /
`revokeAllSessionsForUserExcept` (repository) pair, excluding the caller's own `req.context.session.id`
via `id: { not: exceptSessionId }`. AC-SE-07 is tested exactly as specified: three real sessions,
change from the first, assert the first still works and the other two now 401.

The common-password deny-list (`lib/commonPasswords.ts`, built for registration in Step 1) is
reused unmodified for `newPassword` via the shared `password` Zod schema, now exported from
`auth.schema.ts` instead of being module-private — one rule, one place, per
coding-standards.md's "a second copy of any shared rule" prohibition.

No contract or migration mismatch was found this step.

#### Node Step 7 (DEBUG-level redacted request/response body logging) — instructions for Copilot

**Scope.** Not a new endpoint — a cross-cutting logging addition, matching the Spring Boot stack's
`BodyLoggingFilter` (`hotelapp-server-springboot@2803232`, 2026-09-28): a `debug`-level-only
companion to the existing per-request log line that logs each request's and response's body,
redacted, so a developer running with `LOG_LEVEL=DEBUG` can see full request/response content
during local development or a live demo. Off by default (`LOG_LEVEL=info`); costs nothing in that
mode.

**Read first.**
[Redaction — the hard rule](../stacks/nodejs/logging-observability.md#redaction--the-hard-rule) in
full, **including its `bodyLoggingMiddleware` paragraph naming this exact step** — this section
already specifies the design, this is not a fresh design problem;
[Logging and data handling](./security-principles.md#logging-and-data-handling) (the
project-wide "redacted body logging, not a blanket ban" design decision this step implements);
[Payment data](../stacks/nodejs/security-implementation.md#payment-data);
[Middleware order](../stacks/nodejs/architecture-specification.md#middleware-order).

**Match Spring Boot — do not re-derive the policy, but expect the mechanism to differ.** The
*policy* is identical and already proven: redact the same field set, gate the whole thing behind
`debug`, never let body content reach a log line through any other path. What Spring Boot needed
that Node likely does not: `ContentCachingRequestWrapper`/`ContentCachingResponseWrapper` exist in
Spring Boot because a Java `HttpServletRequest`'s input stream can only be read once, so the body
had to be cached to be read a second time for logging. **Express does not have this problem for the
request side** — `express.json()` (already first in the middleware chain, per
[Middleware order](../stacks/nodejs/architecture-specification.md#middleware-order)) parses the
body into `req.body` as a plain object before any later middleware runs, so `bodyLoggingMiddleware`
registered after it can read `req.body` directly, no wrapper class and no content-cache-limit
configuration needed. **The response side does still need an interception mechanism** — Express
has no response-body-caching wrapper built in, so capture what a handler sends by wrapping
`res.json` (reassign it to a function that captures the argument, then calls the original) before
calling `next()`, not by trying to read `res` after the fact.

**Node/Express-specific concerns.**

- **A real, confirmed gap in the existing redaction list, found by checking the actual field
  names, not assumed**: `src/lib/logger.ts`'s current `redact.paths` array has `'*.password'`,
  `'*.cardNumber'`, `'*.cvv'`, `'*.expiry'`, `'*.expiryMonth'`, `'*.expiryYear'` — but **not**
  `'*.currentPassword'` or `'*.newPassword'`, even though
  [Redaction — the hard rule](../stacks/nodejs/logging-observability.md#redaction--the-hard-rule)'s
  own code sample explicitly lists both, and `PUT /me/password`'s real request body (confirmed in
  `src/routes/account.schema.ts`) uses exactly those two field names. Fix `logger.ts`'s paths list
  to match the spec's sample exactly as part of this step — this is not solely a
  `bodyLoggingMiddleware`-only concern, since any accidental structured log of that endpoint's body
  today would leak both fields in the clear.
- Build `bodyLoggingMiddleware` as its own module (e.g. `middleware/bodyLogging.ts`), guarded by a
  `logger.isLevelEnabled('debug')` check so it does no redaction work at all at the `info` default
  — matching `BodyLoggingFilter`'s `log.isDebugEnabled()` guard and its "costs nothing when off"
  property.
- Reuse the base logger's existing `redact` configuration rather than hand-writing a second
  field list — call `logger`'s redaction over the captured request/response objects the same way
  a normal structured `logger.debug({ requestBody, responseBody }, ...)` call would, so the two
  redaction lists (the general one and this one) cannot independently drift out of sync the way
  Spring's two `REDACT` sets were deliberately kept as one shared constant.
- A non-JSON or empty body must be reported as a literal placeholder (e.g. `'<empty>'` /
  `'<non-JSON body>'`), **never as raw bytes** — falling back to raw content on a parse failure
  defeats the entire point, the same rule `BodyLoggingFilter` followed.
- **`POST /reservations` is the one route this step cannot get wrong** — its request body is the
  payment payload. Write the dedicated test for this route specifically, not just a generic case
  (see Tests required below).
- Register `bodyLoggingMiddleware` after `requestContext` (needs `req.context.traceId`) and after
  `express.json()` (needs `req.body` already parsed) — before or after `requestLogger` in
  [Middleware order](../stacks/nodejs/architecture-specification.md#middleware-order) does not
  matter functionally, since the two log independently, but keep them adjacent for readability.
- `err` objects still go through pino's standard serializer per
  [Redaction — the hard rule](../stacks/nodejs/logging-observability.md#redaction--the-hard-rule)'s
  last paragraph — this step does not change that rule, only adds the body-logging path alongside
  it.

**Tests required.** A unit test suite for the redaction/formatting logic itself, independent of a
running server, mirroring `BodyLoggingFilterTest`'s six cases: a top-level sensitive field, a
nested sensitive field (`payment.cardNumber`), an array containing a sensitive field, a
non-sensitive field left untouched, an empty body, and a non-JSON body. An integration test that
starts the app with `LOG_LEVEL=debug`, makes a real `POST /reservations` request with valid
payment data, captures the actual log output, and asserts `cardNumber`/`cvv`/`expiryMonth`/
`expiryYear` each appear only as the censor value, never as the real submitted values — the same
grep-the-real-log-output discipline Spring Boot's verification used, not an assertion against a
mocked logger. A `PUT /me/password` equivalent covering `currentPassword`/`newPassword`. Confirm
the existing 104 tests still pass unmodified at the `info` default, proving the disabled fast path
changes nothing about current behavior.

**Done when.** `npm run test:run` passes at the `info` default with no change to the existing 104
tests; a manual run with `LOG_LEVEL=debug` against a real `POST /reservations` and a real
`PUT /me/password` shows full request/response bodies in the terminal with every sensitive field
replaced by the censor value, verified by reading the actual terminal output, not assumed from the
code; `logger.ts`'s redact-paths gap above is fixed; the stale `// Never log request/response
bodies...` comment at the top of `logger.ts` is corrected to describe the actual policy (redacted,
not banned), since it currently contradicts this step's own feature.

#### What Node Step 7 actually taught us

**Shipped**: `middleware/bodyLogging.ts`'s `bodyLoggingMiddleware`, registered in `app.ts` right
after `requestContext` (there is no separate `requestLogger` middleware in this codebase yet — that
gap against `architecture-specification.md`'s middleware order predates this step and is unrelated
to it). Gated by `logger.isLevelEnabled('debug')`, so at the `info` default it does no wrapping, no
cloning, and no redaction work at all — confirmed the existing 95 tests all still pass unmodified
(104 total after this step's own 9 new tests: 7 unit + 2 integration). The real redaction fields
fixed in `logger.ts`'s `REDACT_PATHS` per this step's own callout: `currentPassword`/`newPassword`
were missing entirely (both as top-level and `*.`-prefixed paths); also switched from `remove: true`
to `censor: '[REDACTED]'`, since the spec's own sample code censors rather than removes, and this
step's "developer sees the field name plus a censor marker" goal needs the key to still be present.

**Two real, non-obvious mechanics found by testing directly rather than assumed from the spec's
prose, both load-bearing for correctness:**

1. **`fast-redact` mutates its argument in place** (confirmed with a throwaway script before
   relying on it) — applying it directly to `req.body` would have silently destroyed the real
   card number/password the route handler still needed to process the request, a much worse bug
   than a missing log line. Fixed by `structuredClone`-ing the body before redacting, never
   redacting the live object.
2. **`fast-redact`'s wildcard paths (`'*.cardNumber'`) match exactly one level of nesting, not
   recursively** (also confirmed directly: `payment.cardNumber` matches, `requestBody.payment.
   cardNumber` does not). This is why `bodyLoggingMiddleware` redacts each body object *directly*,
   never nested under a wrapper key like `{ requestBody: ... }` first — doing so would have pushed
   every field one level deeper and silently stopped matching, for exactly the payloads
   (`POST /reservations`'s `payment.cardNumber`) this step exists to protect.

**A third mechanic, needed only for this step's own integration tests**: pino's default
destination (`SonicBoom` around file descriptor 1) writes directly to the fd and bypasses
`process.stdout.write` entirely — spying on that method to capture real log output (the same
grep-the-real-output discipline Spring Boot's `BodyLoggingFilterTest` used) silently captured
nothing. Fixed by constructing `logger.ts`'s `pino(...)` call with `process.stdout` passed
explicitly as its destination stream, which makes pino call `.write()` on it directly and makes
the logger's real output observable in a test. Confirmed via a two-line reproduction before
changing the production file. No behavior change for a real running process — it still writes to
stdout either way.

Both `POST /reservations` and `PUT /me/password` integration tests read the actual captured debug
line's `requestBody`/`responseBody` fields and assert the raw submitted card number/passwords never
appear anywhere in the captured output text, not only that the parsed fields equal the censor
value.

No contract or migration mismatch was found this step.

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

### Angular implementation steps — detailed instructions for Copilot

Prospective, sequenced build instructions for `hotelapp-client-angular`, mirroring React's own
completed Steps 1–7 above one for one, in the same order and the same guest-facing scope (items
1-6): foundation, public browsing, search, auth, booking, reservation management, profile/password.
Admin (items 7-8) is out of scope here, same as it was for React and Node — see "Sequencing for
interview readiness" earlier in this document.

**Unlike a Step outcome above, which is a retrospective report written after the work landed, the
steps below are written prospectively**, the same trial format used for the Node steps earlier in
this document (see "Node implementation steps" above). A cold Copilot session given nothing but "do
Angular Step N" should be able to find everything it needs from this section plus the documents and
files it points into.

**This project's stated goal for Angular is closer parity than a typical "same contract, different
framework" rebuild**: Jeff intends to demo both frontends side by side to interviewers, so
`hotelapp-client-angular` must look and behave like the same product as `hotelapp-client-react`, not
merely satisfy the same shared `ui-specifications.md`. Sections 1-2 of that document are normative
and byte-identical between the two stacks, but they under-specify exact Tailwind spacing, color
choices, and component boundaries — React's already-built, already-verified-against-Spring-Boot
implementation is the tie-breaker for anything the shared spec leaves open. Each step below names
the specific React source file(s) to open and match, not just the shared spec section.

**A gap worth flagging before Step 1 starts**: `hotelapp-client-angular/.github/copilot-instructions.md`
does not yet carry the "commit and push regardless of step wording" / "a new non-obvious pure
function ships with its own test" standing rules that had to be retrofitted into React's and Spring
Boot's instructions mid-project after each repo hit the same gap (see the Phase 7 Step 1/2 outcomes
above), and that Node's own instructions were flagged as still missing when its steps were written.
Fold the rules below into that file directly, rather than relying on Copilot to re-read this section
before every step.

> **Standing rules for every step below**, stated once rather than seven times:
>
> 1. **Commit and push at the end of the step, regardless of what the step's own text says.** Both
>    `hotelapp-client-react`'s and `hotelapp-server-springboot`'s Copilot instructions had this
>    added mid-project, after two steps each landed fully verified but uncommitted.
> 2. **Any new pure function or store method with non-obvious logic ships with its own test in the
>    same commit.** React's Copilot instructions picked up this rule after the gap recurred three
>    steps running (Phase 7 Steps 3 and 5 above); do not defer a `format.ts` / `cancellationDeadline.ts`
>    / `buildProfilePatch`-equivalent test to "later." This applies equally to a `signalStore`'s
>    `rxMethod` logic, which has no React analogue and is therefore new risk, not ported risk.
> 3. **Verify completion by actually running `npm run test:run`, `npm run lint`, `npm run typecheck`,
>    and `npm run build` and reading the raw output** — never report a step done from a self-summary.
>    Check `git status` and `git log` before claiming anything is committed; an agent-reported "done"
>    that was still uncommitted has happened repeatedly enough in this project (Spring Boot Step 1,
>    React Steps 1 and 2) to be a named, recurring lesson.
> 4. **Before starting the next step, add a short outcome note back into this document** — a new
>    subsection under this one, in the same style as React's and Node's own Step outcomes: what
>    shipped, the real test count read from raw output, any judgment call made, any contract or spec
>    defect found. This document has gone stale against real progress before because an outcome
>    update was skipped in the moment and never caught up (see "Doc-drift found and fixed" earlier in
>    this document) — do not let that happen here too.
> 5. **A judgment call, an ambiguity, or a contract/spec gap found while building is disclosed, not
>    silently worked around** — the same discipline Spring Boot's, React's, and Node's steps followed
>    throughout. If Angular's build finds that `ui-specifications.md`'s shared §1–2 span needs a
>    correction, fix it in **both** `stacks/react/ui-specifications.md` and
>    `stacks/angular/ui-specifications.md` and verify the shared span is still byte-identical
>    afterward — the same discipline already used for the Conference Room wording fix, the phone-mask
>    fix, and the card-mask fix (all recorded earlier in this file's project history).
> 6. **Before marking a step done, run both dev servers side by side — Angular's `npm start` on
>    `:4200` and React's `npm run dev` on `:5173`, against the same backend — and visually compare
>    the equivalent screen.** The written spec and even a matching component test are necessary but
>    not sufficient proof of parity for a pair of screens meant to look like the same product in a
>    live interview demo. Note any visual divergence found this way in the step's outcome note, even
>    a minor one — a spacing or color drift missed here is exactly the kind of thing an interviewer
>    would notice looking at both screens side by side.

#### Angular Step 1 (foundation) — instructions for Copilot

**Scope.** Project skeleton, routing, Tailwind setup, the HTTP interceptor, session bootstrap, and
S1 (property list) — the same scope React's Step 1 covered, including pulling session bootstrap
forward from item 4 for the same reason React did.

**Read first.**
[architecture-specification.md](../stacks/angular/architecture-specification.md) in full — folder
layout, routing, the API client layer, and application configuration are all foundational here;
[state-management.md](../stacks/angular/state-management.md#the-library-decision) and its
[Session state](../stacks/angular/state-management.md#session-state) section;
[security-implementation.md](../stacks/angular/security-implementation.md#sessions-what-this-client-does-and-does-not-do);
[environment-setup-guide.md](../stacks/angular/environment-setup-guide.md) in full, the same
"written to be followed literally" discipline Node's Step 0 called out; the "Conventions" table at
the top of [api-contracts.md](./api-contracts.md#conventions).

**Match React — do not re-derive.**

- **Session bootstrap belongs in this step, not item 4.** React's own Step 1 flagged this as a
  judgment call (bootstrap is "the app's first action" per
  [ui-specifications.md](../stacks/angular/ui-specifications.md#s0--app-shell), and the architecture
  spec wires it unconditionally before any route). Angular's own architecture spec already settles
  this the same way via `provideAppInitializer` — there is nothing to re-derive here, only to build.
- **Match `hotelapp-client-react/src/App.tsx`'s S0 shell structure**: a root layout component
  rendering a header, a dismissible-but-not-required network-error banner
  (`bg-amber-50 px-4 py-2 text-sm text-amber-900`, "Unable to reach the server." plus a "Dismiss"
  link), a flex-1 routed-content region, and a footer — `flex min-h-screen flex-col` on the outer
  element so the footer sticks to the bottom on short pages. Angular's `SessionStore` exposes the
  network-failure state the same way React's `useSession().networkError` does.
- **Match `hotelapp-client-react/src/components/layout/Header.tsx` and `Footer.tsx` file-for-file**
  for the visual structure: `border-b border-slate-200 bg-white` header, `mx-auto flex max-w-5xl
  items-center justify-between px-4 py-3` inner row, the "HotelApp" wordmark linking home, a
  `hidden md:flex` primary nav collapsing to a hamburger below `md`, and the user-area states table
  from `ui-specifications.md#s0--app-shell` (skeleton chip while resolving; "Log in"/"Create
  account" for anonymous; first name + role badge + a `role="menu"` dropdown for an authenticated
  session). React's `UserArea` badge styling (`rounded-full bg-slate-100 px-2 py-0.5 text-xs
  font-medium text-slate-700` for the Front Desk/Manager badge) and menu styling (`absolute right-0
  z-10 mt-2 w-48 rounded-md border border-slate-200 bg-white py-1 shadow-lg`, items `block px-4 py-2
  text-slate-700 hover:bg-slate-50`) are the tie-breaker for anything `ui-specifications.md` leaves
  unstated about exact appearance — build the Angular ARIA menu primitive to produce the same visual
  result, not a differently-styled equivalent. `Footer.tsx` is three lines of copy
  (`border-t border-slate-200 bg-white`, `mx-auto max-w-5xl px-4 py-6 text-sm text-slate-500`) — copy
  it exactly.
- **Match `hotelapp-client-react/src/features/properties/PropertyListScreen.tsx`** for S1's layout:
  `mx-auto max-w-5xl px-4 py-8`, an `<h1>` "Our hotels", search/city/sort controls in a
  `flex flex-col gap-4 sm:flex-row` row, a responsive card grid
  (`grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3`), and skeleton cards
  (`h-56 animate-pulse rounded-lg bg-slate-200`) during loading. The property card itself
  (`overflow-hidden rounded-lg border border-slate-200 shadow-sm transition hover:shadow-md`, a
  16:9 photo region with an initials placeholder when `photoUrl` is null, `p-4` content) is the
  visual template for every card-shaped list item in this application (room types, results,
  reservations) — get it right once here and reuse the pattern.
- **`page=0`/negative page must reach the server as-is and come back a 400, never be silently
  clamped to 1** — React's Step 1 found and fixed exactly this bug
  (`Number.isFinite` check, not `|| 1`), per
  [api-contracts.md](./api-contracts.md#pagination-sorting-filtering)'s explicit rule. Free-text
  filters (`q`, `city`) debounce ~300ms before writing to the URL, diffed against the *current* URL
  parameters rather than a stale value, so the debounce effect's initial run does not strip an
  existing `page` param from a deep link — the same bug class React's Step 1 fixed.
- **The debug-visibility lines are part of this step, not a later polish pass**: React's `App.tsx`
  logs a `"navigated"` debug line on every route change and `api/client.ts` logs an `"api request"`
  debug line per call (method/path/status/duration, never the body). Angular's own
  [logging-observability.md](../stacks/angular/logging-observability.md#the-console-logger) already
  specifies the equivalent pair for this stack (a `Router` `NavigationEnd` subscriber; the HTTP
  interceptor) — build both now rather than treating them as a Node/Spring-Boot-only feature.

**Angular-specific concerns.**

- **`provideAppInitializer` must resolve on `401`, never reject** — an anonymous visitor is not a
  startup failure. A rejecting initializer hangs the app on a blank page for every anonymous visitor,
  per [environment-setup-guide.md](../stacks/angular/environment-setup-guide.md#troubleshooting)'s
  own named failure mode. This is the one place Angular's arrangement is structurally *better* than
  React's: because bootstrap completes before the first route activates, no guard can ever observe
  an unresolved session — see
  [architecture-specification.md](../stacks/angular/architecture-specification.md#routing) and
  [state-management.md](../stacks/angular/state-management.md#session-state). Do not port React's
  `isResolved`-checking-guard pattern defensively as though the race still existed; it structurally
  cannot here, though guards may still read `isResolved` per
  [security-implementation.md](../stacks/angular/security-implementation.md#route-guards-and-their-real-status).
- **`withCredentials: true` lives in the functional interceptor, set on every request, never per
  call** — `HttpClient` defaults it to `false`, unlike `fetch`'s `credentials: "include"` which
  React's wrapper sets once. Getting this wrong produces a `401` on exactly one screen, per
  [architecture-specification.md](../stacks/angular/architecture-specification.md#the-api-client-layer)
  and [security-implementation.md](../stacks/angular/security-implementation.md#sessions-what-this-client-does-and-does-not-do).
- **`PropertiesStore` is a `signalStore`, route-provided**, following the exact shape in
  [state-management.md](../stacks/angular/state-management.md#feature-stores)'s `AvailabilityStore`
  example (`withState`/`withComputed`/`withMethods`, `tapResponse` required in the `rxMethod`, never
  a bare `error` callback — an unhandled error inside `rxMethod`'s inner observable silently kills
  the stream, per [coding-standards.md](../stacks/angular/coding-standards.md#async-and-data)).
  `isEmpty` must be `computed()` from `status` and `results`, not a separate flag, so the empty state
  never flashes during load.
- **No component library, no Angular Material** — Angular ARIA (stable in Angular 22) plus Tailwind
  tokens shared with the React client, per
  [architecture-specification.md](../stacks/angular/architecture-specification.md#styling) and
  [dependency-policy.md](../stacks/angular/dependency-policy.md#explicitly-not-allowed). Standalone
  components throughout, `ChangeDetectionStrategy.OnPush` on every component, native control flow
  (`@if`/`@for`/`@switch`), no `NgModule` for new code — per
  [coding-standards.md](../stacks/angular/coding-standards.md#components).
- **Runtime config, not compile-time**: `core/config/env.ts` prefers
  `window.__HOTELAPP_CONFIG__` and falls back to the compiled value, with the **same global name** as
  the React client, per
  [architecture-specification.md](../stacks/angular/architecture-specification.md#configuration) and
  [environment-setup-guide.md](../stacks/angular/environment-setup-guide.md#pointing-at-either-backend).
  This is what makes "point either frontend at either backend" true of a *built* Angular bundle, not
  only its dev server.
- **Do not use the Angular CLI's `proxyConfig`.** It would make the API same-origin in dev and hide
  the cross-origin credentialed-cookie path a real build exercises — an explicit trap named in
  [environment-setup-guide.md](../stacks/angular/environment-setup-guide.md#cors-and-the-thing-that-will-bite-first).
  Keep the API cross-origin in development, same as it is in a build, same as React already does.

**Tests required.** This step predates any acceptance criterion the way Spring Boot's, Node's, and
React's own Step 0/1 did — no `AC-XX-NN` is owed yet. Per
[testing-standards.md](../stacks/angular/testing-standards.md#store-tests), `PropertiesStore` gets
the five standard store assertions (loading → success/error transitions, `isEmpty` false while
loading, a second in-flight call discarding the first response, an error not killing the stream).
Per [testing-standards.md](../stacks/angular/testing-standards.md#interceptor-tests), the HTTP
interceptor gets its own suite: `withCredentials: true` present on every request, the base URL
applied, a `problem+json` body mapped to `ApiError`, a non-JSON error body still producing an
`ApiError` rather than throwing, and — the one interceptor test with no React analogue worth
calling out — `SessionInitializer` resolving (not rejecting) on a bootstrap `401`.

**Done when.** `npm run ci` (lint, format:check, typecheck, test:run, build — per
[devops-pipeline.md](../stacks/angular/devops-pipeline.md#local-equivalence)) passes clean. `npm
start` on `:4200` renders the seeded property list against a running backend, matching React's
`:5173` rendering of the same data side by side per standing rule 6 above. Reload the page while
logged in (once Step 4 exists this becomes testable; for now, confirm reload preserves the
anonymous-vs-resolving distinction correctly) and confirm `localStorage`/`sessionStorage` remain
empty, per
[environment-setup-guide.md](../stacks/angular/environment-setup-guide.md#verifying-the-setup-works)'s
own step 6, "the one people skip and the one that catches a real policy breach."

### Angular Step 1 (foundation) — done 2026-09-29

`hotelapp-client-angular@1d64fe2`. Scaffolded the repo from nothing (it held only a README and
`.github/copilot-instructions.md` before this step): Angular 22.2 standalone app via
`@angular/cli@22`, Tailwind v4 (`@tailwindcss/postcss`, no custom theme -- same default palette
React already uses), `@ngrx/signals`/`@ngrx/operators`, `@angular/aria` installed (not yet used --
Step 1's one dropdown menu was hand-rolled with plain ARIA attributes instead; see judgment calls
below), `angular-eslint` + Prettier, and the Angular CLI's own built-in Vitest unit-test builder
(`@angular/build:unit-test`) rather than a separate Analog/Vitest integration.

**Verified by execution, not self-summary, per standing rule 3**: `npm run ci` (lint,
format:check, typecheck, test:run, build) read directly from raw terminal output, all green.
15 tests, 0 failures. Initial bundle **79.93 KB gzip** -- comfortably under the 300 KB budget
(architecture-specification.md), with the admin area not yet built to inflate it. `git log`/
`git status` confirmed clean and pushed before reporting done here, per the same standing rule.

**Manually verified against a live `hotelapp-server-nodejs` on `:3000`** (started fresh for this
step, not assumed running): property list renders both seeded properties with photos, matches
`hotelapp-client-react`'s `:5173` rendering of the same data byte-for-byte visually at 1280x800
(standing rule 6 -- screenshots compared side by side, indistinguishable), reload preserves the
anonymous state correctly (no hang, no flash of a stale state), and `localStorage`/
`sessionStorage` both confirmed empty via a direct `page.evaluate` length check, per
environment-setup-guide.md's step 6.

**Judgment calls, disclosed per standing rule 5:**

- **The user-account dropdown menu (Header's `UserArea`) was hand-rolled with plain `role="menu"`/
  `role="menuitem"` attributes and manual outside-click/Escape handling**, matching React's own
  implementation almost line-for-line, rather than built on `@angular/aria`'s menu primitive. The
  package is installed and dependency-policy.md approves it, but with Step 1 already covering a
  large surface (toolchain + session + S1), spending time confirming this specific Angular 22.2
  release's exact `@angular/aria` menu API surface felt like the wrong place to gamble under time
  pressure. **Worth revisiting in a later step**: swap in the real Angular ARIA menu directive once
  its API is confirmed, since that's the actual reason the package was approved over a hand-rolled
  pattern.
- **`switchMap`'s test came out stronger than the state-management.md wording implies.** The spec
  says a late response should be "discarded"; what Angular's `HttpClient` + `rxMethod` actually do
  is **cancel the underlying HTTP request outright** on unsubscribe (confirmed via
  `HttpTestingController`: flushing an unsubscribed request throws "Cannot flush a cancelled
  request" rather than silently succeeding). Rewrote that test to assert `request.cancelled` rather
  than trying to flush both requests and check which one won -- a strictly stronger guarantee than
  the React client's fetch-based equivalent can make, and worth calling out since it wasn't
  obvious going in.
- **`core/api/http.interceptor.ts` decides "is this an API request" via `req.url.startsWith('/')`**
  rather than always prefixing unconditionally. Every request this app makes today is relative
  (`/properties`, `/auth/me`), so the branch is currently dead code, but it's cheap insurance
  against a future absolute-URL request (e.g. a third-party asset) being silently rewritten to
  point at the API host. Flagging in case a later step finds this unnecessary and wants to simplify.
- **`preview` (the runtime `config.js` mechanism check from environment-setup-guide.md) is a
  50-line hand-written `node:http` static file server (`scripts/preview-server.mjs`)** instead of
  pulling in `http-server` or similar, per dependency-policy.md's "could fifty lines replace it?"
  question -- not run as part of `npm run ci`, only documented as available.
- **`strict: true` and `strictTemplates: true` were added explicitly to `tsconfig.json`** -- the
  Angular 22 CLI's 2025-style-guide schematic no longer sets a blanket `"strict": true`, instead
  enabling a named subset (`noImplicitOverride`, `noImplicitReturns`, etc.) that is close to but not
  exactly `strict` mode. architecture-specification.md's "not negotiable" framing reads as the
  full flag, so it was added rather than assumed already covered.

No contract or shared-spec defect was found this step -- `GET /properties` behaved exactly as
`hotelapp-client-react`'s own Step 0/1 already characterized it.

#### Angular Step 2 (public browsing: property detail, room types) — instructions for Copilot

**Scope.** S2 (property detail: hero, address, description, date/guest search-entry form; the
Rooms section as room-type cards) and room-type detail (S2's modal-or-route view), matching React's
item 2 exactly.

**Read first.** [ui-specifications.md](../stacks/angular/ui-specifications.md#s2--property-detail);
[architecture-specification.md](../stacks/angular/architecture-specification.md#routing) for the
`room-types/:roomTypeId` route entry;
[security-implementation.md](../stacks/angular/security-implementation.md#xss) for the `safeImageUrl`
equivalent, since every photo URL on this screen is admin-entered data rendered into a `src`
attribute.

**Match React — do not re-derive.**

- **`PropertyRoomTypeSummary` is flat by design, not an oversight**: React's Step 2 curled the live
  Spring Boot backend and confirmed `GET /properties/{propertyId}`'s embedded `roomTypes` field
  carries no `description`, `amenities`, or `photos` — only
  `{id, code, name, baseRate, currency, maxOccupancy, bedConfiguration, isAccessible}`. Type it this
  narrowly in `core/api/types.ts` rather than guessing a richer shape; this screen's Rooms section
  calls the separate `GET /properties/{propertyId}/room-types` endpoint for the full shape anyway,
  the same as React does.
- **Match `hotelapp-client-react/src/features/properties/PropertyDetailScreen.tsx`** for layout:
  `mx-auto max-w-5xl px-4 py-8`, a `flex aspect-[21/9]` hero region with an initials fallback, then
  name/address/phone/description, then the date/guest search-entry `<form>`
  (`mt-6 flex flex-wrap items-end gap-4 rounded-lg border border-slate-200 p-4`) whose submit
  navigates to the (not-yet-built) search route — this 404s to S15 until Step 3 exists, the same
  deferred-target pattern React used and the same one to use here.
- **Match `hotelapp-client-react/src/features/properties/components/RoomTypeCard.tsx`** for the
  Rooms section: a horizontal card stacking to vertical on mobile
  (`flex flex-col gap-4 rounded-lg border border-slate-200 p-4 sm:flex-row`), a 16:9 photo region
  fixed at `sm:w-56`, an "Accessible" badge (`rounded-full bg-slate-100 px-2 py-0.5 text-xs
  font-medium text-slate-700`) when applicable, amenity chips in the same pill style, and a "Check
  availability" button (`rounded-md bg-slate-900 px-4 py-2 text-sm font-medium text-white
  hover:bg-slate-700`) that is the primary-action button style for this entire application — reuse
  it verbatim everywhere a primary action button appears in later steps.
- **Port `roomTypeCategoryLabel`/`occupancyLabel`/`rateUnit` as one shared utility**, mirroring
  `hotelapp-client-react/src/lib/roomTypeCategories.ts` exactly: a `CONFERENCE_ROOM` renders
  "Capacity N" instead of "Sleeps N" and "/ day" instead of "/ night" — per
  [ui-specifications.md](../stacks/angular/ui-specifications.md#s2--property-detail)'s explicit
  callout and [domain-glossary.md](./domain-glossary.md#room-type)'s note that a
  Conference Room follows the same full-day booking rules as a guest room without being one. This is
  a judgment call React already made and fixed once as a real UX defect after shipping — do not
  re-introduce "Sleeps 20" for a meeting room here.
- **Port `safeImageUrl`** from `hotelapp-client-react/src/lib/safeImageUrl.ts` conceptually (Angular's
  own version is specified in
  [security-implementation.md](../stacks/angular/security-implementation.md#xss) — reuse that exact
  validation logic, not a fresh reimplementation): reject anything that is not `http:`/`https:`
  before it reaches a `[src]` binding, returning the initials placeholder on rejection.

**Angular-specific concerns.**

- **The room-type modal needs a background-location-equivalent pattern or an Angular ARIA dialog
  driven by a secondary/auxiliary route, not React Router's `useLocation().state` trick**, which is
  React-Router-specific and has no direct Angular Router equivalent. Angular Router's own answer is
  either (a) a named/auxiliary outlet holding the modal while the primary route stays on the property
  detail page underneath, or (b) opening the Angular ARIA dialog imperatively from the property
  detail component when `room-types/:roomTypeId` is reached via an in-app link (`Router.navigate`
  with `skipLocationChange: false` so the URL still updates and is shareable), falling through to a
  standalone full-page render when the route is entered directly (no `NavigationStart` from within
  the property detail page). Confirm which approach this Angular Router version actually supports
  cleanly before building — this is exactly the kind of framework-shaped difference
  [ui-specifications.md](../stacks/angular/ui-specifications.md#3-angular-implementation-notes)
  section 3 exists to hold, and it is fine for the mechanism to differ as long as the resulting
  behavior (modal on desktop, full page on a direct load, both at the same shareable URL) matches.
- **`withComponentInputBinding()`** delivers `propertyId`/`roomTypeId` as component `input()`s rather
  than through `ActivatedRoute` injection — use it, per
  [architecture-specification.md](../stacks/angular/architecture-specification.md#application-configuration).
- **`OnPush` plus signals**: the date/guest form's local state is `signal()`s, not a reactive form —
  it is a search-entry form that hands off to Step 3's URL state rather than validating and
  submitting itself.

**Tests required.** No `AC-XX-NN` criterion covers public catalogue browsing directly (the
acceptance-criteria matrix starts at overbooking/cancellation/authorization/session behavior, none
of which this step exercises) — same honest gap Spring Boot's and Node's own catalogue steps had.
Per [testing-standards.md](../stacks/angular/testing-standards.md#component-tests), `PropertyDetail`
and the room-type card/detail components get all five states (loading, success, empty — "This hotel
has no rooms listed yet.", error `NOT_FOUND` — full-page "We couldn't find that hotel.", and any
other error mapped generically), asserting the specified copy verbatim, queried by role and
accessible name, not CSS selector or test id.

**Done when.** `npm run ci` passes. Side by side with React's `:5173` (standing rule 6): the hero,
address block, Rooms section cards, and room-type detail view read as the same product — same card
proportions, same badge/chip styling, same button treatment. Confirm the Conference Room's
"Capacity"/"day" wording renders correctly if seeded test data includes one (see this file's
"Database seed data update" entry earlier for the seeded `CONFERENCE_ROOM` row) — this is the one
easy regression a fresh reimplementation could reintroduce.

### Angular Step 2 (property detail, room types) — done 2026-09-29

`hotelapp-client-angular@061f60f`. Built S2 in full: `PropertyDetailScreen` (hero with initials
fallback, address/phone/description, the date/guest search-entry form navigating to the
not-yet-built `/properties/:id/search` — 404s to a new wildcard-routed `NotFoundScreen`, same
deferred-target pattern React used), the Rooms section as `RoomTypeCard`s (category label,
"Sleeps N"/"Capacity N", accessible badge, amenity chips, "From $X / night" or "/ day"), and
room-type detail route-addressable at `/room-types/:roomTypeId` either way. `PropertiesStore`
extended with `detail`/`roomTypes`/`roomType` state rather than a second store, per
state-management.md's table mapping `PropertiesStore` to both S1 and S2. `formatMoney` (and a
`MoneyPipe` wrapper), `roomTypeCategoryLabel`/`occupancyLabel`/`rateUnit`, and phone display
formatting ported as their own `shared/util/` modules, matching React's equivalents.

**Verified by execution**: `npm run ci` green (lint/format/typecheck/test/build), 28 tests across
7 files (store tests for the three new load methods plus `clearRoomType`'s reset, `formatMoney`
against known values, and five-state component tests for both new screens using a stub store per
testing-standards.md rather than real HTTP). Initial bundle still **80.21 KB gzip**, comfortably
under the 300 KB budget. **Manually verified against a live `hotelapp-server-nodejs`** with the
database's actual seeded room types (no manual seed insert was needed — later Node/Spring Boot
steps had already seeded Harborview Grand with `KING`/`SUITE`/`DOUBLE`/`CONFERENCE_ROOM` room
types and Lakeside Inn with two): all four room types render with correct badges, category
labels, and pricing, including the Conference Room's "Capacity 20"/"From $349.00 / day" wording;
clicking a room-type card opens its detail without leaving `/properties/harborview-grand`, and
pasting the same `/room-types/:id` URL as a fresh direct load renders the identical content as a
standalone full page; an unknown property slug renders "We couldn't find that hotel."; and
`/properties/:id/search` 404s to the new S15 page as expected.

**Judgment call, disclosed per standing rule 5 — the room-type "modal" mechanism.** This file's
Angular Step 2 instructions above offered two options (a named/auxiliary outlet, or
`Router.navigate` with `skipLocationChange`) for matching React's background-location modal
pattern; neither turned out to fit cleanly. The implementation instead opens `RoomTypeDialog` (a
native `<dialog>` + `showModal()`, mirroring the React client's own Step 6 native-dialog pattern)
locally from `PropertyDetailScreen` with no route change, and calls `Location.go('/room-types/:id')`
to push the URL onto the address bar — `pushState` never fires `popstate`, and Angular's Router only
reacts to `popstate`/`hashchange` via its `Location.subscribe`, so the Router genuinely never learns
about it and the property page stays mounted underneath. A direct load of that same URL never runs
this code path; it is a real route match against `RoomTypeDetailScreen`, rendered as a full page.
Closing the dialog calls `location.back()`; the same component also subscribes to `Location` so a
direct browser Back-button press (not the dialog's own close control) closes it too. Behavior
matches the spec ("modal on desktop, full page on a direct load, both at the same shareable URL");
the mechanism is a third option beyond the two this file suggested, which is the kind of
framework-shaped difference ui-specifications.md section 3 exists to hold.

No contract or shared-spec defect was found this step — `GET /properties/{propertyId}/room-types`
behaved exactly as `hotelapp-client-react`'s own Step 2 already characterized it (a non-paginated
array, and `GET /properties/{propertyId}`'s embedded `roomTypes` confirmed flat).

#### Angular Step 3 (search and results) — instructions for Copilot

**Scope.** S3 in full: the search form, sidebar filters, sort, result cards with discount pricing
and scarcity text, and client-side date pre-validation — React's item 3, ui-specifications.md's own
"most complex guest screen."

**Read first.** [ui-specifications.md](../stacks/angular/ui-specifications.md#s3--search-and-results)
in full; [state-management.md](../stacks/angular/state-management.md#caching-made-explicit) for the
`availability` never-cached rule and the `switchMap`-not-`mergeMap` requirement; the acceptance
criterion this screen's pricing display must render correctly,
[AC-CX-10](./acceptance-criteria.md#ac-cx-10--pricing-arithmetic-and-rounding-order) — this screen
does not compute the rounding itself (the server does), but a wrong render (e.g. rounding the
already-rounded server value a second time, or applying `Number()` to a money string) would silently
misrepresent a value the backend got right, so read the worked examples there before writing
`formatMoney`.

**Match React — do not re-derive.**

- **Every sort option uses the `field:asc`/`field:desc` convention** — inferred by React's own Step 3
  from `GET /properties`'s existing pattern, since the contract gives an explicit grammar for only
  one of the four. Do not invent a different query-parameter shape.
- **The room-type filter list is the static 5-value `room_type_code` enum**, not a per-property
  endpoint (none exists scoped that narrowly) — reuse the same shared label map built in Step 2
  (`roomTypeCategoryLabel`-equivalent) rather than a second copy.
- **Rate-category labels always come from `GET /rate-categories`, never the raw enum value** — this
  is the single rule React's project found violated repeatedly after this step first shipped it
  correctly (`MILITARY_VETERAN` leaking onto S7 and S8c later, fixed as a real defect — see this
  file's "Rate category shows its label everywhere" entry earlier). Build the one shared
  `rateCategoryLabel(options, value)` lookup **now**, in this step, and make every later step that
  renders a `rateCategory` (Step 5's S4/S6/S7, Step 6's S8c) call it — do not let this drift the way
  it did in React, where it took a separate defect-fix pass to close.
- **Match `hotelapp-client-react/src/features/search/SearchScreen.tsx`** for layout: the search form
  row, a `flex flex-col gap-6 lg:flex-row` split with a `lg:w-64 lg:shrink-0` filter sidebar
  (`fieldset`/`legend` for each filter group — room type, amenities, accessible-only, nightly-rate
  min/max) and a flex-1 results column with a sort control and an `aria-live="polite"` results count
  ("N room types available."). A `<select>` "Clear selection" link appears only when a rate category
  other than `NONE` is chosen, per
  [domain-glossary.md](./domain-glossary.md#rate-category)'s note that this is a UI
  affordance resetting to `NONE` rather than a distinct value.
- **Match `hotelapp-client-react/src/features/search/components/ResultCard.tsx`** for the result
  card and its pricing block layout exactly: nightly rate first, a struck-through base rate only
  when a discount applied (`line-through` on `text-sm font-normal text-slate-500`), the
  "N nights · $total total" line, the rate-category label line only when not `NONE`, and scarcity
  text (`text-sm font-medium text-amber-700`) — "Only 1 room left" at exactly 1, "Only N rooms left"
  at 2–3, nothing above 3. This card reuses Step 2's `occupancyLabel`/`rateUnit` for the Conference
  Room wording, same as React's does.
- **Empty is a success, not an error.** A `200` with zero results renders "No rooms available for
  these dates." plus "Try different dates" and "Clear filters" — never an error treatment, per
  [ui-specifications.md](../stacks/angular/ui-specifications.md#s3--search-and-results).
- **Client-side date pre-validation mirrors the server's messages exactly**, sourced from
  [error-handling.md](../stacks/angular/error-handling.md#400--validation_failed)'s field-code table
  — check-out after check-in, not in the past, at most 30 nights.

**Angular-specific concerns.**

- **`AvailabilityStore.search` must use `switchMap`, never `mergeMap`**, per
  [state-management.md](../stacks/angular/state-management.md#feature-stores) — a late response from
  an abandoned search (someone adjusting dates rapidly) must not overwrite a newer one. This is the
  single highest-value store test in this suite per
  [testing-standards.md](../stacks/angular/testing-standards.md#store-tests): emit the slow response
  after the fast one and assert the newer result wins.
- **Filter and search-parameter state reads from the URL via `toSignal(route.queryParamMap)`**,
  feeding the store's `rxMethod` — one path, per
  [state-management.md](../stacks/angular/state-management.md#url-state). Debounce free-text/numeric
  filter inputs ~300ms with `debounceTime` before writing to the router, using `replaceUrl: true`
  for intermediate writes, mirroring React's debounce-and-diff-against-current-URL pattern (which
  fixed a real bug in Step 1 — an unconditional-on-mount effect stripping an unrelated URL param).
  Reproduce the fix, not the bug: diff against the router's *current* query params before writing,
  not a stale closure value.
- **`ReferenceDataStore`** (root-provided, fetched once per session) is the source for `amenities`
  and `rate-categories` here — do not fetch them per-component or refetch on every filter change,
  per [state-management.md](../stacks/angular/state-management.md#caching-made-explicit).

**Tests required.** No acceptance criterion covers search/availability display directly (pricing
*arithmetic* is AC-CX-10, proven server-side; this screen only renders the result). Per
[testing-standards.md](../stacks/angular/testing-standards.md#screens-worth-extra-attention), S3's
entry is explicit: "URL is the source of truth" — filter changes update query parameters, and
activating the route with parameters already present populates the form and filters correctly.
Per the standing rule 2 above, ship this step's date-validation pure functions with their own tests
from the start — **do not repeat React's own gap here**: React's Step 3 shipped this exact screen
with zero new tests, a real, disclosed gap that had to be partially closed in Step 4 and fully
closed only after a second escalation in Step 5. Angular has React's own outcome notes as a warning
that this is a step where the coverage discipline is easy to skip under time pressure.

**Done when.** `npm run ci` passes, `AvailabilityStore`'s `switchMap`-discards-stale-response test
passes, and side by side with React's `:5173` (standing rule 6) the search form, filter sidebar, and
result cards read as the same product — including the exact wording and placement of scarcity text
and the struck-through base-rate treatment, which are easy to approximate rather than match exactly.

### Angular Step 3 (search and results) — done 2026-09-29

`hotelapp-client-angular@ead4083`. Built S3 in full: the search form (dates, guests, special rate
with "Clear selection"), a `lg:flex-row` filter sidebar (room type, amenities, accessible-only,
nightly-rate min/max, each its own `fieldset`/`legend`), sort, and result cards with discount
pricing (struck-through base rate, "N nights · $total total", rate-category label) and scarcity
text. `AvailabilityStore` (route-provided) uses `switchMap`; `ReferenceDataStore` (root-provided)
fetches `GET /amenities`/`GET /rate-categories` once per session via a `loadOnce` guard standing in
for React's `staleTime: Infinity`. Client-side date pre-validation (`shared/util/date-validation.ts`)
reuses error-handling.md's exact field-code wording. Filter/search state reads from the URL via
`toSignal(route.queryParamMap)`, mirroring Step 1's debounce-and-diff-against-current-params fix for
the nightly-rate min/max inputs.

**Verified by execution**: `npm run ci` green, 48 tests across 12 files (11 new: date-validation,
the shared `rateCategoryLabel` lookup, `AvailabilityStore` including the switchMap-discards-stale-
response test, `ReferenceDataStore`, and `SearchScreen`'s component states tested via
`RouterTestingHarness` rather than a manually-constructed `ActivatedRoute`). Initial bundle 80.50 KB
gzip, still comfortably under budget. **Manually verified against a live `hotelapp-server-nodejs`**
with the database's existing seeded rooms (Harborview Grand: 4 KING, 3 DOUBLE, 2 SUITE, 1
CONFERENCE_ROOM): KING shows no scarcity text, DOUBLE "Only 3 rooms left", SUITE "Only 2 rooms
left", the Conference Room "Only 1 room left" alongside "Capacity 20"/"$349.00 / day" wording; the
seeded AAA/CAA 10% rate plan renders a struck-through base rate and "AAA/CAA rate applied" on every
card; `numGuests=3` correctly excludes KING (`maxOccupancy` 2); check-out before check-in shows the
client-side message without ever calling `GET /availability`; Lakeside Inn (which has no SUITE room
type) searched with `roomTypeCode=SUITE` renders the empty-success state, never an error. Side by
side with React's `:5173` for the identical URL, the accessibility tree and rendered text came back
byte-identical.

**Judgment call, disclosed per standing rule 5 — NOT_FOUND's page-level treatment.** This file's
instructions above specified only the copy ("We couldn't find that hotel.") for S3's `NOT_FOUND`
case, not its layout. The implementation matches the React client's own judgment call (and this
repo's `PropertyDetailScreen`) rather than inventing a different one: an unknown property replaces
the entire screen with a centered message and a "Back to our hotels" link, not an inline alert next
to a now-useless search form and empty sidebar — discovered as a real gap during manual
verification (the first pass showed a generic alert while `GET /rate-categories`'s filter sidebar
stayed visible and interactive around it) and fixed before commit, covered by the existing test.

No contract or shared-spec defect was found this step — `GET /availability`'s pricing block, the
`field:asc`/`field:desc` sort convention, and the reference-list endpoints all behaved exactly as
`hotelapp-client-react`'s own Step 3 already characterized them.

#### Angular Step 4 (auth: login, registration, route guards) — instructions for Copilot

**Scope.** S5 (login and registration) and the three route guards, matching React's item 4.

**Read first.**
[ui-specifications.md](../stacks/angular/ui-specifications.md#s5--login-and-registration) in full;
[architecture-specification.md](../stacks/angular/architecture-specification.md#routing)'s guard
code sample; [security-implementation.md](../stacks/angular/security-implementation.md#route-guards-and-their-real-status);
[state-management.md](../stacks/angular/state-management.md#form-state--signal-forms) for the
onBlur/re-validate-on-change rule and the existing-credential exemption; every mention of sessions
in [security-implementation.md](../stacks/angular/security-implementation.md) and the
[decision-log.md](./decision-log.md) entry on the JWT-to-sessions reversal (entry 2), so no part of
the removed design is reintroduced.

**Match React — do not re-derive.**

- **`Retry-After` is delta-seconds, never an HTTP-date** — carry this assumption forward rather than
  re-investigating it; React's Step 4 already flagged that the contract does not specify the format
  either way and the code comment overstates its own confidence — write the Angular equivalent's
  comment more accurately than that, since this is a chance to fix the overstatement rather than
  copy it.
- **`INVALID_CREDENTIALS` is form-level, never field-level, on login** — "That email or password is
  incorrect." The server deliberately does not say which credential is wrong; a field-level error
  here would invent information the API withholds on purpose, per
  [error-handling.md](../stacks/angular/error-handling.md#401--authentication).
- **Match `hotelapp-client-react/src/features/auth/components/AuthLayout.tsx`** for the shared
  login/register shell: `mx-auto max-w-sm px-4 py-16`, an `<h1>`, content, then a footer link
  preserving `?next=` between the two routes. Match
  `hotelapp-client-react/src/features/auth/LoginScreen.tsx` for the form itself: labeled inputs with
  `rounded-md border border-slate-300 px-3 py-2 text-sm`, a full-width primary submit button
  (`rounded-md bg-slate-900 px-4 py-2 text-sm font-medium text-white disabled:opacity-50`), and a
  password field with a show/hide toggle (React's `PasswordField` component) rather than a bare
  `type="password"` input.
- **Registration shows "At least 12 characters" up front, with no character-class hint and no
  strength meter** — per
  [security-principles.md](./security-principles.md#passwords), there are no
  character-class requirements, and the UI must not imply any.
- **A login/register password field is exempt from live format validation** (it verifies an existing
  credential once set) — the login screen's password input gets no shape validation beyond
  "required," per
  [ui-specifications.md](../stacks/angular/ui-specifications.md#1-conventions-for-every-screen)'s
  exemption. This does **not** apply to registration's password field, which is *setting* a new
  value and does enforce the 12-character minimum live.
- **`RequireStaff`/`RequireManager`-equivalent guards are built but not wired into any route yet** —
  `/admin` doesn't exist until the deferred admin phase. Prove them with a guard unit test per
  [testing-standards.md](../stacks/angular/testing-standards.md#guard-tests), the same "built,
  tested, unwired" pattern React's Step 4 used.

**Angular-specific concerns.**

- **Guards are functional `CanActivateFn`s reading the `SessionStore`**, per
  [architecture-specification.md](../stacks/angular/architecture-specification.md#routing)'s exact
  code sample: `authGuard` returns `true` or a redirect `UrlTree` to `/login` with `next` set to
  `state.url`; `staffGuard`/`managerGuard` compare **rank**, never set membership
  (`role >= FRONT_DESK_STAFF`, matching
  [api-contracts.md](./api-contracts.md#authorization) and
  [AC-AZ-06](./acceptance-criteria.md#ac-az-06--front-desk-staff-cannot-perform-manager-only-actions)'s
  rank-not-membership requirement, provable the same way Node's Step 1 proved AC-AZ-11 — by direct
  test, not inference).
- **No `isResolved`-check-and-wait pattern is needed in the guard body** — bootstrap already resolved
  before the router evaluates any guard, a structural guarantee Step 1 established. Do not port
  React's `if (!isResolved) return <FullPageSkeleton />` pattern into the guard itself; it has
  nothing to wait for here. (Guards may still read `isResolved` defensively per
  [security-implementation.md](../stacks/angular/security-implementation.md#route-guards-and-their-real-status),
  but there is no race to defend against.)
- **No separate form/validation library** — Signal forms (stable in Angular 22) or typed reactive
  forms, validated with Angular's own validator functions, consistent within a feature. This is a
  genuine asymmetry from React, which needs `react-hook-form` + `zod` for the same behavior — do not
  add an equivalent pair of dependencies here; none is needed, per
  [dependency-policy.md](../stacks/angular/dependency-policy.md#the-approved-set).
- **Server field errors from `errors[]` apply via `setErrors` on the matching control** — this is why
  contract `field` names and control names must match exactly, per
  [coding-standards.md](../stacks/angular/coding-standards.md#async-and-data). Angular does not move
  focus to an invalid control automatically on `setErrors`; call `focus()` on the first invalid
  control explicitly after a failed submit, per
  [error-handling.md](../stacks/angular/error-handling.md#announcing-errors) — a real behavioral gap
  from React Hook Form's `setFocus`, not a copy-paste detail.
- **Grep the finished code**: `grep -rniE "bearer|jwt|accessToken|refreshToken|auth/refresh"
  src/` must return nothing, per
  [security-implementation.md](../stacks/angular/security-implementation.md#what-must-never-reappear).
  Also confirm `HttpClientXsrfModule`/`withXsrfConfiguration()` were not reached for — an
  Angular-specific trap named in the same section, since this API relies on `SameSite=Lax`, not a
  CSRF header.

**Tests required.** [AC-SE-01](./acceptance-criteria.md#ac-se-01--login-establishes-a-session),
[AC-SE-06](./acceptance-criteria.md#ac-se-06--expired-and-unknown-sessions-are-indistinguishable),
[AC-SE-10](./acceptance-criteria.md#ac-se-10--credential-errors-do-not-reveal-whether-an-account-exists),
[AC-AZ-06](./acceptance-criteria.md#ac-az-06--front-desk-staff-cannot-perform-manager-only-actions),
and [AC-AZ-09](./acceptance-criteria.md#ac-az-09--registration-cannot-escalate)'s frontend-visible
half are the acceptance criteria whose *server-side* guarantee this screen's behavior must not
contradict — per this stack's own
[testing-standards.md](../stacks/angular/testing-standards.md#the-honest-boundary), this repo does
not re-prove them (that is the backends' job, against a real database); it proves instead that,
given a known API response shaped like each of those outcomes, the screen renders what
[ui-specifications.md](../stacks/angular/ui-specifications.md#s5--login-and-registration) specifies.
Per [testing-standards.md](../stacks/angular/testing-standards.md#guard-tests): `authGuard` returns
a redirect with `next` set when there is no session; `staffGuard` admits Front Desk and Manager;
`managerGuard` admits only Manager; being at the right property does not grant a higher rank. **This
is also the step where [AC-SE-05](./acceptance-criteria.md#ac-se-05--a-session-works-interchangeably-against-both-backends)
first becomes checkable from this client**: once this step lands, run the manual cross-backend
walkthrough from
[environment-setup-guide.md](../stacks/angular/environment-setup-guide.md#getting-a-backend)'s
"Both at once" section by hand — log in against one backend, point Angular's runtime config at the
other, reload, confirm the session is still honored — and record the result in this step's outcome
note, the same manual proof Node's own Step 1 recorded.

**Done when.** `npm run ci` passes, the guard test suite passes, and side by side with React's
`:5173` (standing rule 6) the login and registration forms, the password-field show/hide toggle, and
the form-level vs. field-level error placement all read as the same product.

### Angular Step 4 (auth: login, registration, route guards) — done 2026-09-29

`hotelapp-client-angular`. Built S5 in full (login, registration, shared `AuthLayout`/
`PasswordField`) and all three route guards (`authGuard` wired to nothing yet since no protected
route exists; `staffGuard`/`managerGuard` built and unit-tested, unwired, same "built, tested,
unwired" pattern as React's own Step 4). Typed Reactive Forms (`FormGroup`/`FormControl`), not
Signal Forms — no reactive-forms pattern was established yet in this codebase, and
error-handling.md's own code sample for server field-error application (`this.form.get(fe.field)?.
setErrors(...)`) is written against classic reactive forms, so that's the one this step follows
rather than re-deriving signal-forms' different error-reporting shape. A live phone-number mask
routes through the `FormControl`'s own `valueChanges` (not a second native `(input)` listener
alongside `formControlName`'s own) to avoid a write-order race between two listeners on one native
event under zoneless change detection. `shared/util/errors/messages.ts` is the one place an
`ApiError` becomes user-facing text, per error-handling.md's exact module location and shape
(`ERROR_MESSAGES`, `fieldMessage`, `resolveError`) — the first time this client has needed it past
inline `NOT_FOUND` checks, so it's written to serve every future screen that needs it, not just S5.

**Verified by execution**: `npm run ci` green (80 tests, 8 new files: `messages.spec.ts`,
`phone.spec.ts`'s new `isCompletePhoneNumber` coverage, three guard spec files, `login-screen.spec.ts`,
`register-screen.spec.ts`). Initial bundle 81.69 KB gzip, still under budget. `grep -rniE
"bearer|jwt|accessToken|refreshToken|auth/refresh" src/` returns nothing.

**Manually verified against a live `hotelapp-server-nodejs` and, for the cross-backend check,
`hotelapp-server-springboot` too**: registered a fresh guest (phone masked live as typed,
`"2035550100"` → `"(203) 555-0100"`), redirected to `/` and the header showed the logged-in
session; logged out; `INVALID_CREDENTIALS` rendered as the exact form-level message with the form
values retained, never attached to a field; re-logging in with the correct password succeeded and
redirected by role; `EMAIL_ALREADY_REGISTERED` attached to the `email` control with the "Log in
instead" link. **AC-SE-05 walkthrough** (this step's own required manual proof): registered a
guest against Node, then edited `public/config.js`'s `apiBaseUrl` to point at Spring Boot on
`:8080` and reloaded with no fresh login — the header still showed the same logged-in guest,
confirming the session cookie is honored interchangeably by both backends, matching Node's own
Step 1 outcome note. Reverted `config.js` afterward.

**A real contract-vs-implementation defect was found and disclosed, not silently worked around.**
`hotelapp-server-nodejs`'s `POST /auth/register` schema (`auth.schema.ts`) has `phone:
z.string().max(32).optional()` — missing `.nullable()`, unlike `PATCH /me`'s own phone field in
`account.schema.ts`, which correctly has both. Sending `{"phone": null}` (this client's original,
React-mirroring approach for "the guest left this optional field blank") is rejected with `400
VALIDATION_FAILED` / `{field: "phone", code: "REQUIRED", message: "Expected string, received
null"}`, confirmed live by curl; omitting the key entirely succeeds. **Fixed client-side, not in
the Node repo**, per "stay in this stack": `RegisterRequest.phone` is now `phone?: string`, and
`RegisterScreen` omits the key entirely rather than sending `null` when the field is blank. Flagged
for a `hotelapp-server-nodejs` fix (add `.nullable()` to match `account.schema.ts`) and a matching
check in `hotelapp-client-react`, which sends the same `phone: values.phone || null` shape and
likely has the identical latent gap, apparently never manually verified against Node for this
specific case (its own Step 4 outcome note only mentions verification, not which backend).

**Judgment calls, disclosed per standing rule 5.** `staffGuard`/`managerGuard`'s redirect target for
an authenticated-but-insufficient-rank user is `/` (home) rather than React's `RequireStaff`
redirecting to `/` and `RequireManager` redirecting to `/admin` — this repo has no `/admin` route
tree yet at all (Node's admin/reporting phase is still deferred), so React's "nested under
`RequireStaff`, redirect to the parent" target doesn't exist here yet; `managerGuard` re-checks
authentication and the staff-rank floor itself rather than assuming a `staffGuard` ran first,
since no route nests them together yet. Revisit both guards' redirect targets once the admin route
tree is actually built. The `RATE_LIMITED` `Retry-After` header-format comment was rewritten to
state what's actually verified (delta-seconds observed from both backends so far, format not
specified by the contract) rather than React's own overstated "always... never" phrasing, per this
step's own instruction to fix that comment here rather than copy it.

No other contract or shared-spec defect was found this step — `POST /auth/login`'s response shape,
`INVALID_CREDENTIALS`'s identical-timing/identical-message behavior for unknown-email vs.
wrong-password, and the session cookie's cross-backend interchangeability all behaved exactly as
documented.

#### Angular Step 5 (booking flow: summary, payment, confirmation) — instructions for Copilot

**Scope.** S4 (booking summary), S6 (payment), S7 (confirmation) — React's item 5, "the central
feature" of the guest journey.

**Read first.**
[ui-specifications.md](../stacks/angular/ui-specifications.md#s4--booking-summary),
[ui-specifications.md](../stacks/angular/ui-specifications.md#s6--payment-form), and
[ui-specifications.md](../stacks/angular/ui-specifications.md#s7--confirmation) in full;
[data-model.md](./data-model.md#cancellation-policy) for the deadline formula this screen must mirror
client-side; [security-implementation.md](../stacks/angular/security-implementation.md#payment-data)
for what must never happen to card-shaped input;
[api-contracts.md](./api-contracts.md#post-reservations--guest) for the exact request/response
shape and the deterministic `…0000` decline case.

**Match React — do not re-derive.**

- **The cancellation-deadline formula must mirror the backend exactly, to the second**: `check_in_date
  AT TIME ZONE property.timezone - INTERVAL '48 hours'`, per
  [data-model.md](./data-model.md#cancellation-policy). React's
  `lib/cancellationDeadline.ts` computes this with no date library, using
  `Intl.DateTimeFormat`'s `timeZoneName: "longOffset"` to get the exact UTC offset for the property's
  IANA zone at the relevant instant (DST included) — port this exact algorithm (parse the offset out
  of the `GMT±HH:MM` formatted part, apply it, subtract 48 hours), not a reinterpretation, since a
  reinterpretation is exactly how three independent implementations (Spring Boot, Node, this one)
  could each compute a defensible-looking but subtly different answer. This needed a dedicated test
  pinned to
  [AC-CX-04](./acceptance-criteria.md#ac-cx-04--deadline-respects-the-propertys-timezone-not-the-servers)'s
  two-timezone example and
  [AC-CX-05](./acceptance-criteria.md#ac-cx-05--dst-transition-does-not-shift-the-deadline-arithmetic)'s
  DST-transition case in React, after shipping once without one — write Angular's test for the same
  two cases from the start, per standing rule 2.
- **`formatTimestamp`-equivalent spells out every `Intl.DateTimeFormat` component explicitly**
  (`year`, `month`, `day`, `hour`, `minute`, `timeZoneName: "short"`, `timeZone`) rather than using
  `dateStyle`/`timeStyle`, because those two options cannot be combined with `timeZoneName` — a real
  API limitation React's Step 5 hit, not a style choice.
- **Match `hotelapp-client-react/src/features/booking/components/BookingSummaryCard.tsx`** for the
  shared summary card used (in `"full"` variant) on S4 and (in `"condensed"` variant) on S6: hotel
  name and, on the full variant only, address; room type name and bed configuration; dates with
  nights; guests; rate category when not `NONE` (via the Step 3 `rateCategoryLabel` lookup — never
  re-render the raw enum here); a price breakdown row (`nightlyRate × nights` on the left,
  right-aligned total) followed by a bordered "Total" row; and, on the full variant only, the
  cancellation policy in plain language using the property's timezone.
- **Match `hotelapp-client-react/src/features/booking/PaymentScreen.tsx`** for S6: a
  non-dismissible amber demo-payment banner as the first thing in the form region (`rounded-md
  border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900`, exact copy: "This is a demo. No
  payment is processed and no card details are stored. Do not enter a real card number."), a
  collapsible `<details>`/`<summary>` "Test card numbers" panel, and a submitting-state full-screen
  overlay (`fixed inset-0 z-50 flex items-center justify-center bg-white/80`, "Confirming your
  booking…") that blocks the form. Card number formats in live groups of four capped at 16 digits
  (`lib/cardNumber.ts`'s `formatCardNumber`) and expiry/CVV strip to digits-only and cap at their
  real max length (`lib/digitsOnly.ts`) — port both algorithms; they are pure functions with no
  framework dependency.
- **The `Idempotency-Key` is generated once, in a field/component initializer, never inside the
  submit handler** — React's `useRef(crypto.randomUUID())`, created on mount and stable across
  repeat submit attempts. A per-attempt key defeats the header's whole purpose (a double-click or a
  retry-after-decline would create two reservations). This is
  [testing-standards.md](../stacks/angular/testing-standards.md#screens-worth-extra-attention)'s own
  named highest-value test for S6 — assert the key is identical across two submit attempts.
- **No price field is ever sent** — `POST /reservations`'s payload carries the booking parameters and
  the payment block only; the server resolves pricing. Per
  [security-implementation.md](../stacks/angular/security-implementation.md#input-validation), build
  the request body explicitly rather than serializing the whole form.
- **`ROOM_UNAVAILABLE`, `PAYMENT_DECLINED`, and `NOT_FOUND` each get their exact, distinct
  presentation** from [error-handling.md](../stacks/angular/error-handling.md#2-the-mapping) — do not
  collapse them into one generic failure banner. `ROOM_UNAVAILABLE` in particular "must never read as
  a validation failure," per that document's own emphasis, since it is the client-visible face of the
  database exclusion constraint and the guest did nothing wrong.
- **Match `hotelapp-client-react/src/features/booking/ConfirmationScreen.tsx`** for S7: the
  confirmation number as "the most prominent element on the page" (`font-mono text-3xl font-bold
  tracking-wide`) with a copy button, full booking details below in the same summary-card shape as
  S4/S6, a note that a confirmation email "would be sent in a production deployment," and a
  `print:hidden`/`print:py-0` print stylesheet treatment on the action row.

**Angular-specific concerns.**

- **`BookingStore` backs S4/S6/S7**, per
  [state-management.md](../stacks/angular/state-management.md#feature-stores)'s store table — a
  single route-provided store spanning all three screens, since booking context (room type, dates,
  guests, rate category) must survive the screens' transitions and, per S4's own requirement, a full
  page reload during the login detour. **Booking context lives in the URL query string, not the
  store**, per
  [state-management.md](../stacks/angular/state-management.md#url-state) — a store is discarded on
  navigation away and back, which would silently lose the booking context exactly the way
  `ui-specifications.md` calls "the worst UX failure available in this application." Re-derive
  pricing from the URL parameters plus a fresh `GET /availability` call on S4/S6 mount, matching
  React's `useBookingContext` hook's approach, rather than trying to carry a rich object through
  router state.
- **No `useBlocker`-equivalent is needed for the payment submission overlay.** React's Step 5
  explicitly avoided React Router's `useBlocker` (incompatible with the declarative router this
  application needs for the room-type modal) in favor of a `beforeunload` listener plus a disabling
  overlay. Angular has a real, better-supported equivalent — a `CanDeactivateFn` guard, per
  [ui-specifications.md](../stacks/angular/ui-specifications.md#per-screen-notes)'s own S6 row, which
  explicitly calls for `CanDeactivateFn` plus a `beforeunload` listener together: the guard covers
  in-app navigation attempts, `beforeunload` covers tab-close/refresh/external navigation, which
  `CanDeactivateFn` cannot intercept. Use both — this is a case where Angular's Router gives a
  cleaner answer than React's did, not a gap to work around.
- **The idempotency key and card-shaped form state are held in the S6 component's own
  signal/form state, never patched into `BookingStore`** — per
  [security-implementation.md](../stacks/angular/security-implementation.md#payment-data), card data
  must never reach a store, `localStorage`, a URL, or a log line, at any level, in any environment.
  The booking submission is therefore a direct API-service call from the component, not a store
  method, mirroring why React's payment mutation lives in the component rather than a shared hook
  used elsewhere.

**Tests required.** No acceptance criterion covers the frontend rendering of a successful booking
directly; [AC-OB-01](./acceptance-criteria.md#ac-ob-01--two-concurrent-bookings-for-the-last-room-exactly-one-wins)
(the database exclusion constraint) is what `ROOM_UNAVAILABLE` is the client-visible face of, and
[AC-CX-04](./acceptance-criteria.md#ac-cx-04--deadline-respects-the-propertys-timezone-not-the-servers)/
[AC-CX-05](./acceptance-criteria.md#ac-cx-05--dst-transition-does-not-shift-the-deadline-arithmetic)
are what the ported cancellation-deadline function must agree with. Per
[testing-standards.md](../stacks/angular/testing-standards.md#screens-worth-extra-attention): the
`Idempotency-Key`-identical-across-attempts test (S6, "the single most valuable test in this suite");
a test asserting card number, CVV, and expiry never appear in any outgoing request URL or in
`localStorage`; the login-detour test for S4 (booking context survives a route away and back via the
URL — "guards the worst available UX failure"). Ship `cancellationDeadline`'s port with its own test
from the start, pinned to the same two worked examples React's did, per standing rule 2 — do not
repeat React's own gap here either (Step 5 shipped this exact function with zero tests initially, an
escalated, disclosed gap recorded earlier in this file).

**Done when.** `npm run ci` passes, both named highest-value tests above pass, and a real
click-through succeeds against a live backend: register or log in → S4 → S6 with `4242 4242 4242
4242` → S7 → a fresh reload of the confirmation URL (a real fetch, not a stale cache) → back to S6
with a card ending `0000` → field-level decline message with the form retained. Side by side with
React's `:5173` (standing rule 6), the demo-payment banner, the price-breakdown block, and the
confirmation number's prominent treatment all read as the same product.

### Angular Step 5 (booking flow: summary, payment, confirmation) — done 2026-09-29

`hotelapp-client-angular`. Built S4 (`BookingSummaryScreen`), S6 (`PaymentScreen`), S7
(`ConfirmationScreen`), the shared `BookingSummaryCard` (full/condensed variants), and a
route-provided `BookingStore` spanning all three screens per state-management.md's table — booking
context itself stays in the URL query string, never the store, so it survives the S5 login detour
and a full page reload. Ported `cancellation-deadline.ts`, `card-number.ts`, and `digits-only.ts`
from the React client verbatim (same `Intl.DateTimeFormat` `longOffset`/spelled-out-components
approach), each shipped with its own test from the start — `cancellation-deadline.spec.ts` pinned
to the same AC-CX-04/AC-CX-05 worked examples React's Step 5 used, per this file's standing rule
about not repeating that gap a second time. `format.ts` gained `formatDate`/`formatTimestamp`
alongside the existing `formatMoney`. Reactive Forms again (not Signal Forms), continuing Step 4's
established pattern; a Luhn check plus expiry/CVV validators live directly in `payment-screen.ts`,
matching where Step 4's `phoneValidator` lives.

**Angular-specific implementation, per this step's own instructions:** `CanDeactivateFn` +
`beforeunload` together block navigation during submission — Angular's real, better-supported
equivalent of React's `useBlocker` workaround. The guard is wired into `app.routes.ts` via a
dynamic-`import()` wrapper rather than a static import of the guard function, specifically so
`PaymentScreen`'s own lazy `loadComponent` chunk stays lazy (confirmed in the production build:
`payment-screen` is its own ~14 KB chunk, not folded into the eagerly-loaded route config). Card
data (number, CVV, expiry) and the Idempotency-Key (`crypto.randomUUID()`, generated once on
construction, never per submit attempt) live only in `PaymentScreen`'s own component state, never
in `BookingStore` — per security-implementation.md#payment-data. Since this stack has no
TanStack-Query-style shared cache to pre-warm the way React's Step 5 did, the just-created
reservation is instead carried from S6 to S7 via `Router.navigate(..., { state })` and read back
via `history.state` (guarded against stale reuse by checking the carried object's `id` matches the
current route param) — S7 falls back to a real `GET /reservations/{id}` via `BookingStore` on a
direct load/share/reload, same observable behavior as React's cache-warm-then-fallback approach.

**A real bug was found and fixed during manual verification, not just by the test suite.** The
`CanDeactivateFn` guard reads `isSubmitting()` to decide whether to allow leaving the payment
screen — but `onSubmit()`'s own success path calls `router.navigate()` to leave for S7 while
`isSubmitting` was still `true` (it was only cleared in a later `finally`), so the guard blocked
its *own* component's successful exit. Confirmed live: clicking "Confirm booking" twice produced
two `201`s for the *same* reservation id (the Idempotency-Key correctly deduped the actual
booking), yet the URL never changed to the confirmation route until this was fixed by clearing
`isSubmitting` immediately before the success-path `navigate()` call, not only in `finally`. No
unit test caught this — the stubbed-guard/router test setup doesn't reproduce it — only the
required live click-through did, which is exactly why that step is mandatory rather than optional
once the automated suite is green. Recorded in repo memory as a pattern to watch for in any future
`CanDeactivateFn`.

**Verified by execution**: `npm run ci` green (129 tests total, 25 test files, up from 104/24 —
new: `format.spec.ts`'s `formatDate`/`formatTimestamp` cases, `cancellation-deadline.spec.ts`,
`card-number.spec.ts`, `digits-only.spec.ts`, `booking.store.spec.ts`, `booking-summary-screen.spec.ts`,
`payment-screen.spec.ts`). The two named highest-value tests from this step's own instructions both
pass: the Idempotency-Key-identical-across-two-submit-attempts test, and a test confirming card
number/CVV/expiry never appear in the outgoing request body as a raw display-formatted string nor
in `localStorage`. The login-detour test for S4 confirms an anonymous guest hitting
`/properties/:id/book` with a full query string is redirected to `/login?next=` carrying that exact
path and query intact. Production build confirms `payment-screen`, `booking-summary-screen`, and
`confirmation-screen` are each their own lazy chunk.

**Manually verified against a live `hotelapp-server-nodejs`**, side by side with the pattern
established in prior steps: registered a fresh guest, searched Harborview Grand for the seeded
KING room type, hit the auth gate anonymously and confirmed the full booking context (room type,
dates, guests, rate category) survived the register round-trip back to S4; S4 rendered the price
breakdown and cancellation deadline with zone abbreviation ("Nov 12, 2026, 12:00 AM EST") exactly
per spec; continued to S6, watched the card-number field live-format into groups of four while
typing; submitted `4242 4242 4242 4242` and landed on S7 with a real confirmation number; reloaded
the confirmation URL fresh and confirmed it re-fetched rather than reusing stale state; returned to
S6 and submitted a Luhn-valid card ending `0000`, confirming the exact field-level decline message
with the form retained.

No contract or shared-spec defect was found this step — `POST /reservations`'s request/response
shape, the `Idempotency-Key` replay behavior, and the deterministic decline case all matched
api-contracts.md exactly.

#### Angular Step 6 (guest reservation history, modify, cancel: S8b/S8c) — instructions for Copilot

**Scope.** S8b (the four-tab reservation list) and S8c (detail, with status-gated modify/cancel)
only — matching React's own split of item 6, which deliberately separated reservation management
from profile/password the same way the backends did.

**Read first.**
[ui-specifications.md](../stacks/angular/ui-specifications.md#s8--guest-account-and-booking-history)
in full, specifically the S8b/S8c subsections; the cancellation and modification acceptance criteria
this screen's action-gating must agree with:
[AC-CX-01](./acceptance-criteria.md#ac-cx-01--just-before-the-deadline-refundable),
[AC-CX-02](./acceptance-criteria.md#ac-cx-02--exactly-at-the-deadline-not-refundable),
[AC-CX-03](./acceptance-criteria.md#ac-cx-03--just-after-the-deadline-not-refundable-but-still-cancellable),
[AC-CX-06](./acceptance-criteria.md#ac-cx-06--modification-is-blocked-after-the-deadline),
[AC-CX-07](./acceptance-criteria.md#ac-cx-07--modification-is-allowed-before-the-deadline-and-re-prices).

**Match React — do not re-derive.**

- **The server's `cancellation.isRefundableNow` is authoritative — this screen never recomputes
  "now < deadline" itself.** React's Step 6 built the action-gating table entirely off `status` and
  that one server-computed boolean; do the same rather than re-deriving the boundary client-side,
  which would risk disagreeing with the server by the same class of second-level timing error
  [AC-CX-02](./acceptance-criteria.md#ac-cx-02--exactly-at-the-deadline-not-refundable) exists to
  catch.
- **Cancelling inside the refundable window is allowed, not hidden** — the button is relabelled
  ("Cancel reservation (non-refundable)"), never removed, once past the deadline. Hiding it would
  misrepresent the policy, per
  [ui-specifications.md](../stacks/angular/ui-specifications.md#s8--guest-account-and-booking-history).
- **Match `hotelapp-client-react/src/features/account/ReservationListScreen.tsx`** for S8b: a
  `role="tablist"` of four tabs (Upcoming/Past/Cancelled/All) sharing one `GET /reservations`
  endpoint with different query parameters — there is no separate "history" endpoint — with distinct
  empty copy per tab, and list rows showing hotel name, room type, dates (struck through when
  cancelled), a status badge, confirmation number, total, and a "View" link. Default sort
  `checkInDate:desc`.
- **Match `hotelapp-client-react/src/features/account/ReservationDetailScreen.tsx` and
  `components/CancelDialog.tsx`** for S8c: the cancel confirmation dialog states the refund outcome
  explicitly before the guest confirms — "You'll receive a full refund of $X" or "This cancellation
  is non-refundable. You will not receive a refund." — with button labels "Cancel reservation" /
  "Keep reservation," never "Cancel"/"OK," which invert ambiguously on a cancel-a-thing dialog, per
  [ui-specifications.md](../stacks/angular/ui-specifications.md#s8--guest-account-and-booking-history).
  React's dialog is mounted only while open (`{open && <CancelDialog />}`) rather than driven by an
  `open` prop on an always-mounted component — a fresh mount per open needs no reset-on-open effect
  and gets native focus-return for free; Angular's equivalent is an `@if`-gated Angular ARIA dialog
  for the same reason.
- **A page load of an already-cancelled reservation falls back to `cancellation.isRefundableNow`
  for its outcome wording**, since `GET /reservations/{id}`'s documented shape carries no
  `cancelledAt`/exact-refund detail for a reservation cancelled in an earlier session — only a
  same-session cancel (using the cancel mutation's own response) gets the precise wording. This is a
  disclosed contract gap, not a bug to silently work around; flag it again here if it is still open
  when this step is built.
- **`INVALID_STATUS_TRANSITION` triggers a refetch before re-rendering actions**, per
  [error-handling.md](../stacks/angular/error-handling.md#409--conflicts) — the client's view of
  state is stale, and the message ("This reservation has changed. We've refreshed it — please try
  again.") should read as an action taken, not a scolding.

**Angular-specific concerns.**

- **`MyReservationsStore` backs S8b/S8c**, per
  [state-management.md](../stacks/angular/state-management.md#feature-stores). Its post-mutation
  reload table applies here directly: `PATCH /reservations/{id}` reloads that reservation,
  `MyReservationsStore`, and `AvailabilityStore`; `POST .../cancel` reloads the same set, per
  [state-management.md](../stacks/angular/state-management.md#post-mutation-reloads).
- **Tab and page state read from the router's query parameters via `toSignal`**, same URL-state
  pattern as every prior list screen in this application.
- **The cancel and change-dates dialogs are Angular ARIA dialog primitives**, which supply focus
  trapping and `aria-modal` from the framework rather than hand-rolled — stable as of Angular 22, per
  [ui-specifications.md](../stacks/angular/ui-specifications.md#per-screen-notes)'s S8c row.

**Tests required.** Per
[testing-standards.md](../stacks/angular/testing-standards.md#screens-worth-extra-attention), S8c's
named requirement: "Action availability across the full status × deadline matrix from the spec" —
build this as one parameterized test covering every `{status, isRefundableNow}` combination in the
table in
[ui-specifications.md](../stacks/angular/ui-specifications.md#s8--guest-account-and-booking-history),
not a handful of spot checks. Per standing rule 2, any new pure function this step introduces (a
tab-to-query-parameter mapping, a change-summary comparison, mirroring React's
`lib/reservationTabs.ts` and `lib/reservationChangeSummary.ts`) ships with its own test in the same
commit — React's own equivalent step got this right unprompted after the Step 3/5 escalations, and
Angular should not need the same lesson taught twice.

**Done when.** `npm run ci` passes, the full status × deadline matrix test passes, and a real
click-through against a live backend using a reservation from Step 5 succeeds: the Upcoming tab
shows it, a date change re-prices and shows the new-vs-old total when they differ, and cancelling
shows the refund wording before confirming and the outcome note after. Side by side with React's
`:5173` (standing rule 6), the tab bar, status badges, and cancel dialog read as the same product.

**Outcome.** `MyReservationsStore` backs both S8b and S8c per state-management.md, holding a list
(tab/page-driven `GET /reservations`) and a single detail together — since the two screens never
mount simultaneously in this app's single-outlet routing, `PATCH`/cancel only reload the *current*
reservation in the store; an unmounted S8b's list naturally refetches fresh on next entry per
state-management.md's "a store for an unmounted feature does not exist to reload" rule, so no
cross-store event-signal plumbing was needed for this pair. `CancelDialog` and `ChangeDatesDialog`
use the same native `<dialog>` + `showModal()` pattern as Step 2's `RoomTypeDialog` — `@angular/aria`
22.2.0 still has no Dialog primitive (checked `node_modules/@angular/aria/types/*.d.ts` again; none),
despite this step's own instructions saying otherwise, so the disclosed gap from Step 2 stands
rather than building against a primitive that doesn't exist. Ported `reservation-tabs.ts` and
`reservation-change-summary.ts` from the React client's `lib/reservationTabs.ts` and
`lib/reservationChangeSummary.ts`, each shipped with its own test from the start per standing rule 2.

**A real bug was found only by the required live click-through, not by the automated suite** —
the same class of bug as Step 5's `CanDeactivateFn`/`isSubmitting` timing issue, a different
instance of "a shared signal already moved on by the time you read it for a diff."
`ChangeDatesDialog`'s confirmation compared the re-priced total against its own `reservation` input
at message-render time, but that input mirrors `MyReservationsStore`'s live `reservation` signal,
which the store's own `patchReservation` success handler already overwrites with the *new* pricing
before the dialog's `await` resolves — so the message compared the new total to itself and
silently dropped the "(was $X)" clause every time. Confirmed live: submitting a date change that
moved the total from $747.00 to $996.00 rendered "Your total is $996.00." instead of "Your new
total is $996.00 (was $747.00)." Fixed by snapshotting the pre-mutation total in `ngOnInit()` and
diffing the confirmation message against that snapshot, never against the live input — with a
dedicated regression test added (`change-dates-dialog.spec.ts`) that mutates the same store signal
the way the real store does, so this exact failure mode can't silently regress.

**Verified by execution**: `npm run ci` green (137 tests, 31 test files, up from 129/29 — new:
`reservation-tabs.spec.ts`, `reservation-change-summary.spec.ts`, `my-reservations.store.spec.ts`,
`reservation-list-screen.spec.ts` (including the tab-empty-copy and error-retry cases),
`reservation-detail-screen.spec.ts` (the full status × `isRefundableNow` matrix as one parameterized
test block, per this step's own named requirement), `change-dates-dialog.spec.ts` (the total-mutation
regression above). Production build confirms `reservation-list-screen` and `reservation-detail-screen`
are each their own lazy chunk.

**Manually verified against a live `hotelapp-server-nodejs`**: registered a fresh guest, booked the
seeded Harborview Grand KING room type end to end (Steps 4–5's flow), then from
`/account/reservations` confirmed the Upcoming tab showed it with hotel name, room type, dates,
status badge, total, and confirmation number; opened the detail screen and used "Change dates" to
extend the stay twice (re-pricing and reassigning rooms both times, confirmed by the room number
changing), each time reading the corrected "Your new total is $X (was $Y)." message; then cancelled
inside the refundable window and saw "You'll receive a full refund of $996.00." before confirming,
the same amount as the outcome note after, and native `<dialog>` focus returning to the invoking
button automatically on close both times; the Cancelled tab then showed the reservation with its
dates struck through and a muted "Cancelled" badge; a fresh page reload of the now-cancelled
detail screen correctly fell back to "This reservation was cancelled. It was refundable." (the
disclosed `cancelledAt`/exact-refund contract gap from React's own Step 6 applies identically here).
Side by side with React's `:5173`, the tab bar, status badges, and dialogs read as the same product.

No contract or shared-spec defect was found this step — the bug above was entirely in this
client's own code, not a disagreement with `api-contracts.md`.

#### Angular Step 7 (guest profile, password: S8a/S8d) — instructions for Copilot

**Scope.** S8a (profile) and S8d (password change) — the other half of item 6, matching React's
final guest-facing step. **Closes Angular's entire guest-facing scope (items 1-6)** once this step
lands, the same milestone React and Node each reached at the end of their own Step 7/6.

**Read first.**
[ui-specifications.md](../stacks/angular/ui-specifications.md#s8--guest-account-and-booking-history)'s
S8a/S8d subsections; [api-contracts.md](./api-contracts.md#patch-me--guest) for the
omitted-vs-`null` `PATCH` semantics; [api-contracts.md](./api-contracts.md#put-mepassword--guest);
[security-principles.md](./security-principles.md#passwords).

**Match React — do not re-derive.**

- **`PATCH /me`'s "omitted is unchanged, explicit `null` clears it" semantics is the hard part of
  this step.** React solved it by tracking React Hook Form's `dirtyFields` and building the request
  body from only the touched fields (`lib/buildProfilePatch.ts`), sending `null` for a field the
  guest cleared to empty rather than `""`. Angular's Signal forms / reactive forms expose an
  equivalent per-control dirty state — build the same "only dirty fields, empty string becomes
  `null`" patch builder, ship it with a test from the start (per standing rule 2), and treat `address`
  as all-or-nothing: if any address sub-field is dirty, resend the **whole** current address object,
  matching the contract's treatment of `address` as one top-level field rather than independently
  changeable sub-fields.
- **`email` is never a form field** — render it as read-only plain text with "Email cannot be
  changed." as helper text, not a disabled input, avoiding the disabled-field accessibility ambiguity
  a `readonly`/`disabled` input control raises.
- **`PUT /me/password`'s `INVALID_CREDENTIALS` is field-level here** ("That password is incorrect.,"
  attached to "current password"), a deliberate departure from the shared error map's form-level
  wording for the same code on the login screen — per
  [ui-specifications.md](../stacks/angular/ui-specifications.md#s8--guest-account-and-booking-history)'s
  explicit S8d text. **This screen must not treat a `401`-adjacent code as a dead-session signal and
  must not route to login on success** — the contract is explicit that the caller stays logged in,
  the opposite of every other place this application sees a session-shaped error code. Confirm the
  global `401`/`ACCOUNT_INACTIVE` interceptor rule correctly does not fire for `INVALID_CREDENTIALS`
  here, since it is keyed on error code, not screen.
- **Match `hotelapp-client-react/src/features/account/ProfileScreen.tsx`** for S8a: a read view
  (labeled value pairs) with an "Edit profile" button, switching to a form view on click, with
  "Save changes"/"Cancel" actions; phone renders through the shared phone-mask formatter both in the
  input and in read mode, reformatting even pre-existing unmasked data on load (React found a real
  bug here — a seeded phone number stored without formatting still needed to display masked).
- **Match `hotelapp-client-react/src/features/account/PasswordScreen.tsx`** for S8d: three password
  fields (current, new, confirm), a success message that explicitly notes other devices have been
  signed out (true per the contract's `SessionService.revokeAllExcept` behavior, worth surfacing
  since it is genuinely useful information), and — per the App-wide input-validation audit recorded
  earlier in this file — a 12–24 character range on the *new* password field specifically (12 is the
  fixed NIST-cited minimum from
  [security-principles.md](./security-principles.md#passwords) and must not be
  reopened; 24 is a UX ceiling well under bcrypt's 72-byte truncation point). The **current**-password
  field gets no format validation beyond "required" — it verifies an existing credential, per the
  same exemption Step 4's login password used.
- **Every numeric-only field in this application is masked and length-capped, not merely hinted** —
  the phone field here follows the same live-strip-non-digits-and-cap pattern established in earlier
  steps (port `lib/phone.ts`'s exact 11-digit-starting-with-1 country-code-stripping fix: a naive
  10-digit slice would silently truncate the wrong end of an 11-digit number with a leading country
  code, a real bug React found against actual seeded data before shipping this).

**Angular-specific concerns.**

- **`ProfileStore` backs S8a/S8d**, per
  [state-management.md](../stacks/angular/state-management.md#feature-stores). `PATCH /me` reloads
  `ProfileStore` **and** `SessionStore` — the header's user-area first name must update immediately,
  not wait for the session to happen to refetch on its own, per
  [state-management.md](../stacks/angular/state-management.md#post-mutation-reloads)'s explicit row
  for this mutation. `PUT /me/password` reloads nothing — the caller's own session stays valid, per
  the same table.
- **This closes the loop on the `rateCategoryLabel` and Conference Room label utilities built in
  earlier steps** if S8a or S8d ever needs to render either — confirm no new duplicate lookup is
  introduced here; there should be nothing left to add by this step for either.

**Tests required.** No acceptance criterion covers profile editing or password change directly at
the frontend layer (session revocation behavior —
[AC-SE-07](./acceptance-criteria.md#ac-se-07--password-change-revokes-other-sessions-but-not-the-callers)
— is proven server-side; this screen only needs to render the resulting success message correctly
and must not itself force a re-login). Ship `buildProfilePatch`'s Angular port with its own test
from the start, per standing rule 2, pinned to the same omitted/empty-string/`null` cases React's
test covers, plus the address all-or-nothing case.

**Done when.** `npm run ci` passes, the profile-patch test passes, and a real click-through against
a live backend succeeds: edit and save a profile field, confirm the header updates immediately;
clear an optional field and confirm it round-trips as `null` on reload, not an empty string; change
the password and confirm the caller stays logged in. Side by side with React's `:5173` (standing
rule 6), the profile read/edit views and the password form read as the same product. **This is also
the point to do a full guest-facing side-by-side pass across all seven steps**, the same milestone
check Node's own guest-facing slice reached at the end of its Step 6 — before moving on to admin or
Phase 8 integration, confirm nothing drifted visually across the earlier steps while later ones were
being built.

**Outcome — done 2026-09-29.** `npm run ci` green (32 test files, 143 tests; `profile-screen` and
`password-screen` confirmed as their own lazy chunks). `ProfileStore`, `MeApi`, and
`shared/util/build-profile-patch.ts` (with its own pinned test, including the address
all-or-nothing case) all ported per plan. Two real contract-vs-implementation gaps were found by a
live click-through against `hotelapp-server-nodejs`, both worked around client-side rather than in
the Node repo, per "stay in this stack":

1. `GET /me`'s `address` is `null` for a guest who has never set one, not an object of empty
   strings — `Profile.address` is typed `Address | null` here (a spec correction against the
   React client's own `Profile` type, which still declares it non-nullable and only survives by
   accident via defensive `?.` at read sites).
2. `PATCH /me`'s `address.line2` rejects an explicit `null` (Node's zod schema has it
   `.optional()` but not `.nullable()`, unlike every other address field) — confirmed by curling
   live. Spring Boot's own `ProfileService.textOrNull` treats "omitted" and "null" identically for
   every address field including `line2`, so the fix (`build-profile-patch.ts` omits the `line2`
   key entirely rather than sending `null`) is compatible with both backends; sending `null` was
   only ever compatible with one. Flagged here for a `account.schema.ts` fix (`line2` should be
   `.nullable()` too) next time the Node repo is touched, matching the still-open phone/register
   gap from Step 4.

Manually verified end to end: edited first name and full address, confirmed the header's
first-name display updated immediately (no reload, no session refetch); cleared phone and
confirmed it persisted as `null` on reload, not `""`; attempted a password change with the wrong
current password and got the field-level "That password is incorrect." message with no
navigation; changed the password successfully and confirmed the caller stayed on
`/account/password`, logged in, with the "signed out on your other devices" message shown. This
closes Angular's entire guest-facing scope (items 1–6).

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
