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
| 6 | Backend implementation | ⬜ **In progress** — Steps 0-5 done (skeleton, sessions, catalogue, availability, booking, reservation management), Spring Boot only; two structural refactors also done |
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

**Done means:** Step 0's slice ran and its findings were folded back into
[api-contracts.md](./api-contracts.md); both backends pass every criterion in
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
