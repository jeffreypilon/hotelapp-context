# Testing Standards — Spring Boot

What gets tested in `hotelapp-server-springboot`, at which layer, and what these suites do not cover.

> ### Sections 1–5 are shared, verbatim, with the other backend
>
> **Sections 1 through 5 below are byte-identical to
> [`stacks/nodejs/testing-standards.md`](../nodejs/testing-standards.md).** Both backends must
> satisfy the *same* 44 acceptance criteria, at the same layers, with the same care about the same
> traps. Letting each repo decide its own coverage matrix is how one backend ends up untested on the
> criterion the other one caught a bug with.
>
> **Any diff in sections 1–5 is a defect.** Section 6 holds the Spring Boot tooling and is the only part
> that differs.

[acceptance-criteria.md](../../shared/acceptance-criteria.md) is normative. This document maps its
criteria to test layers and says how to run them in this stack.

---

## 1. The layers, and what each one is for

| Layer | Runs against | Covers |
|-------|-------------|--------|
| **Unit** | Nothing — pure functions | Pricing arithmetic, cancellation-deadline computation, allocation ordering, status-transition legality, confirmation-number format |
| **Repository / persistence** | **Real PostgreSQL 18.6** | Queries, mappings, constraint behavior |
| **Integration (API)** | **Real PostgreSQL**, full app, HTTP in | Every acceptance criterion in section 3 |
| **Contract** | The generated OpenAPI document | Structural equivalence with the other backend |

**A real PostgreSQL instance is mandatory for anything above the unit layer.** Not H2, not an
in-memory substitute, not a mocked client. This is not a preference:

- The **exclusion constraint** is a PostgreSQL feature no substitute implements. An H2-backed test
  of [AC-OB-01](../../shared/acceptance-criteria.md#ac-ob-01--two-concurrent-bookings-for-the-last-room-exactly-one-wins)
  would pass while the guarantee was entirely absent — the worst possible test outcome.
- `daterange` and the `&&` overlap operator do not exist elsewhere, so every availability test would
  be testing different SQL than production runs.
- `uuidv7()` is a PostgreSQL 18 core function; on 17 or earlier the schema will not even apply.
- The `timestamptz` and `AT TIME ZONE` semantics behind the cancellation deadline differ between
  engines.

Testcontainers, or a CI service container, per
[devops-pipeline.md](./devops-pipeline.md).

**Migrations in tests come from Flyway against the canonical SQL** in
`hotelapp-context/shared/migrations/`, never from an ORM generating a test schema. A test database
built by a different mechanism than production is a test database that can disagree with it — and
under the migration-ownership rule in
[versioning-strategy.md](../../shared/versioning-strategy.md#database-schema-migrations) there is
only one legitimate mechanism.

---

## 2. Test data and isolation

**Each test gets a clean database state.** Either roll back a surrounding transaction, or truncate
the mutable tables between tests. Truncation must preserve the reference data a migration
inserts — the seven `amenities` rows are a contract, per
[data-model.md](../../shared/data-model.md#amenities-and-room_type_amenities), and re-seeding
them per test is waste.

**Order-independent.** A suite that passes only in declaration order is hiding shared state. Run it
in a randomized order at least in CI.

**Builders, not literal fixtures.** `aReservation().withStatus(CHECKED_IN).atProperty(p)` states
what a test is about; a forty-line object literal does not. One builder per entity, with defaults
that satisfy every constraint so a test overrides only what it cares about.

**The clock must be injectable.** Several criteria are unverifiable otherwise —
[AC-CX-01](../../shared/acceptance-criteria.md#ac-cx-01--just-before-the-deadline-refundable)
through AC-CX-05 all pin behavior at a specific instant relative to a deadline. This is a design
requirement on the application, not a testing trick, and retrofitting it means touching every
"now" in the codebase.

**Property timezone must vary across tests.** Fixtures should include at least one
`America/New_York` and one `America/Los_Angeles` property, because
[AC-CX-04](../../shared/acceptance-criteria.md#ac-cx-04--deadline-respects-the-propertys-timezone-not-the-servers)
is precisely about not collapsing them.

**Run the suite under at least two process timezones.** `TZ=UTC` and something like
`TZ=Asia/Tokyo`. A process-timezone dependency in the deadline arithmetic is invisible under a
single setting and is exactly the divergence the stored-deadline design exists to prevent.

---

## 3. Acceptance-criteria coverage — the required matrix

**Every criterion in [acceptance-criteria.md](../../shared/acceptance-criteria.md) is a required
test in this repository.** All 44 of them. That document is normative; this table is the mapping
from criterion to test layer, and it is identical in both backends because the criteria are.

### No overbooking — the central guarantee

| Criterion | Layer | Notes on getting it right |
|-----------|-------|---------------------------|
| [AC-OB-01](../../shared/acceptance-criteria.md#ac-ob-01--two-concurrent-bookings-for-the-last-room-exactly-one-wins) | Integration, **concurrent** | Two genuinely parallel requests. Assert on the **pair** of outcomes: exactly one `201`, one `409 ROOM_UNAVAILABLE`, one reservation row, one payment row. A test that awaits the first before issuing the second passes against an implementation with the race |
| AC-OB-02 | Integration | Departure and arrival on the same date do not conflict — the `'[)'` bound |
| AC-OB-03 | Integration, table-driven | All six overlap shapes (a–f). Case (f) plus AC-OB-02 pins the boundary exactly |
| AC-OB-04 | Integration | Two overlapping rows legitimately coexist when one is `CANCELLED` — the partial-index predicate |
| AC-OB-05 | Integration | Check-out does **not** release remaining dates. The criterion most likely to be "fixed" into a bug |
| AC-OB-06 | Integration | Search **and** booking-time allocation both exclude out-of-service rooms |
| AC-OB-07 | Integration | Lowest `room_number` by natural sort, deterministically. Without this the two backends could allocate differently and no test would notice |
| AC-OB-08 | Integration | `availableRoomCount` excludes out-of-service and overlapping |

**The strongest form of AC-OB-01**, worth writing at least once: hold a transaction open with a
conflicting reservation inserted but uncommitted, then issue the booking request and assert it
blocks and then fails. That confirms the constraint rather than a lucky interleaving.

### Cancellation boundary

| Criterion | Layer | Notes |
|-----------|-------|-------|
| AC-CX-01 | Integration, clock-controlled | One minute before the deadline → refundable, full refund block present |
| AC-CX-02 | Integration, clock-controlled | **Exactly at the deadline → NOT refundable.** The boundary is exclusive; this exists as its own criterion so neither backend gets to interpret it |
| AC-CX-03 | Integration, clock-controlled | One minute after → not refundable but **still cancellable**. A `409` here encodes the most common misreading of the policy |
| AC-CX-04 | Integration | Two property timezones, and the suite run under two process timezones |
| [AC-CX-05](../../shared/acceptance-criteria.md#ac-cx-05--dst-transition-does-not-shift-the-deadline-arithmetic) | Integration | The DST case. Expected `2026-03-07T04:00:00Z` — a **fixed 48-hour duration**, not midnight two calendar days earlier. Verify against the zone database, not against arithmetic done by hand |
| AC-CX-06 | Integration | Modification blocked after the deadline → `409 CANCELLATION_WINDOW_CLOSED`, reservation unchanged |
| AC-CX-07 | Integration | Modification before the deadline re-prices at **current** rates and may move the reservation to a different room |
| AC-CX-08 | Integration | `waiveFee: true` forces refundability past the deadline |
| AC-CX-09 | Integration, table-driven | Cancel rejected from `CANCELLED`, `CHECKED_IN`, `CHECKED_OUT` |
| [AC-CX-10](../../shared/acceptance-criteria.md#ac-cx-10--pricing-arithmetic-and-rounding-order) | **Unit** + integration | Round the nightly rate **first**, then multiply. Include a case where the two orders differ — the document's own example does not distinguish them. Assert the JSON **type** is a string, not a number |

AC-CX-10 is the one criterion needing both layers: unit tests for the arithmetic exhaustively,
plus one integration assertion that the wire format is a decimal string.

### Authorization

| Criterion | Layer | Notes |
|-----------|-------|-------|
| AC-AZ-01 | Integration | **`404`, not `403`.** Assert the status explicitly; a "consistency" refactor to `403` creates an enumeration oracle |
| AC-AZ-02 | Integration | Own reservations only. Also assert a `guestUserId` parameter cannot widen scope |
| AC-AZ-03 | Integration | `404` **and** the reservation is unchanged — a handler that mutates before checking ownership passes on the status alone |
| AC-AZ-04 | Integration, **table-driven over the whole `/admin/*` route list** | Not a hand-picked subset, so a newly added admin route is covered by default |
| AC-AZ-05 | Integration | **`403 PROPERTY_OUT_OF_SCOPE`**, and a `propertyId` parameter is ignored rather than honored. The asymmetry with AC-AZ-01 must be asserted in both directions |
| AC-AZ-06 | Integration, table-driven | Right property, wrong tier. Scope and rank are independent |
| AC-AZ-07 | Integration | A manager reaches every property; a `propertyId` parameter **is** honored (unlike AC-AZ-05) |
| AC-AZ-08 | Integration | A manager passes every staff-level check without being enumerated in it — the rank rule |
| AC-AZ-09 | Integration | `role` in a registration body → `400`, no user created. Repeat against `PATCH /me` with `role` and `isActive` |
| AC-AZ-10 | Integration | Public endpoints need nothing and leak no room numbers, room ids, or counts |
| AC-AZ-11 | Integration | Deactivation takes effect on the **next request** of a live session — the property a token design could not have |

### Sessions

| Criterion | Layer | Notes |
|-----------|-------|-------|
| AC-SE-01 | Integration | Cookie attributes `HttpOnly`, `Secure`, `SameSite=Lax`, `Path=/api/v1`. `token_hash` is the SHA-256 of the cookie value. **The raw token appears nowhere in the database.** Assert the body contains no `accessToken`, `token`, or `expiresIn` — guarding against a later reintroduction |
| AC-SE-02 | Integration | A fresh login creates a new row; the old stays valid; no client-supplied token is adopted |
| AC-SE-03 | Integration | `revoked_at` set, cookie cleared, and **the same cookie replayed gives `401`**. The replay is the real assertion |
| AC-SE-04 | Integration | Idempotent; `204` with no cookie at all; other devices unaffected |
| [AC-SE-05](../../shared/acceptance-criteria.md#ac-se-05--a-session-works-interchangeably-against-both-backends) | **Cross-backend** — see below |
| AC-SE-06 | Integration | Expired, revoked, and fabricated tokens produce byte-identical `401`s apart from `traceId` |
| AC-SE-07 | Integration | Password change revokes other sessions, keeps the caller's |
| AC-SE-08 | Integration, clock-controlled | Slides when >5 min stale; **does not write when fresh**; never past `issued_at + 30 days`. The throttle is invisible in manual testing and is where the two backends most easily diverge |
| AC-SE-09 | Integration | 10 failures then `429` with `Retry-After`; **a correct password inside the window still gets `429`** |
| AC-SE-10 | Integration | Unknown email and wrong password are indistinguishable, including in timing. Verify against a dummy hash on the unknown-email path |

**AC-SE-05 cannot be fully satisfied in this repository.** It needs both backends running against
one database, which is the Docker Compose smoke test in
[devops-pipeline-overview.md](../../shared/devops-pipeline-overview.md#2-the-docker-compose-smoke-test).

What this repo **must** carry is the single-process half: **seed a `sessions` row directly, then
assert this backend honors it.** That proves this backend does not depend on having created the
session itself, which is the property the cross-backend test exercises for real. Without it, a
backend could pass every other session test while keeping state in process memory.

### Cross-cutting

| Criterion | Layer | Notes |
|-----------|-------|-------|
| AC-CC-01 | Integration | `application/problem+json`; all seven members present; `status` equals the HTTP status; `errors[]` on validation only |
| AC-CC-02 | Integration | Unknown field → `400`, with the field named in `errors[]` |
| AC-CC-03 | Integration | The envelope on every list endpoint; `pageSize=101` and `page=0` → `400`, **not clamped**; the same page twice with the same sort returns the same rows in the same order (the `id` tiebreak) |
| AC-CC-04 | **Contract** | Valid OpenAPI 3.1; the automated form is the normalized CI diff |
| AC-CC-05 | Integration | `200` with `database: UP` and a `backend` field; `503` when the database is unreachable |

---

## 4. Beyond the criteria

The criteria cover what must be *provably* correct. Ordinary correctness still needs tests:

- **Every endpoint's happy path**, at least one integration test each — all 42 in
  [api-contracts.md](../../shared/api-contracts.md).
- **Repository tests** for each non-trivial query, especially the availability query and the
  calendar segment query.
- **An `EXPLAIN` assertion that the availability query uses the GiST index**, per
  [non-functional-requirements.md](../../shared/non-functional-requirements.md#response-time-targets).
  A plan regression — a sequential scan — is the realistic performance failure here, and it is
  invisible to a latency assertion at demo data volumes.
- **Serialization tests**: money as a decimal string, dates as `YYYY-MM-DD`, `timestamptz` as ISO
  with offset, enums unchanged in `SCREAMING_SNAKE_CASE`.
- **The confirmation-number format**: `HA` plus eight Crockford base32 characters, and a
  unique-violation retry that never surfaces to a client.
- **Session cleanup**: the periodic job deletes rows past `expires_at` and nothing else.

---

## 5. What is not tested here

Stated so the boundary is explicit rather than assumed:

- **Frontend behavior of any kind** — that is
  `stacks/react/testing-standards.md` and `stacks/angular/testing-standards.md`.
- **End-to-end through a browser.** There are none in this project; the acknowledged gap in
  [devops-pipeline-overview.md](../../shared/devops-pipeline-overview.md#deliberately-absent).
- **Load, stress, and soak testing.** No throughput target exists to regress against —
  [non-functional-requirements.md](../../shared/non-functional-requirements.md#throughput-and-concurrency).
  AC-OB-01 tests correctness *under concurrency*, which is a different and weaker claim than
  performance under load, and this project makes only the former.
- **The other backend.** Equivalence is established by the OpenAPI diff and by both repos
  implementing this same matrix, not by one testing the other.

**No coverage threshold gate**, per
[devops-pipeline-overview.md](../../shared/devops-pipeline-overview.md#deliberately-absent). A
percentage rewards tests that execute lines. The bar here is enumerable instead: all 44 criteria,
every endpoint's happy path, every serialization rule. Coverage is reported so a gap is visible,
and not enforced.

---

## 6. Spring Boot tooling

### Stack

| Concern | Choice |
|---------|--------|
| Runner | JUnit 5 |
| Assertions | AssertJ |
| HTTP assertions | `MockMvc` for slices, `TestRestTemplate` for full-stack |
| Database | **Testcontainers** (`org.testcontainers:postgresql`), image `postgres:18.6` |
| Migrations in tests | **Flyway**, the same mechanism as production |
| Clock | The injected `Clock` bean, replaced with `Clock.fixed(...)` |
| Builders | Hand-written, in `src/test/java/.../builder/` |

> **Design Decision — Testcontainers rather than H2 or an embedded database.** Not a preference; a
> requirement. H2 has no exclusion constraints, no `daterange`, no `&&` operator, and no
> `uuidv7()` — so an H2-backed suite would pass while the project's central guarantee was entirely
> absent. `postgres:18.6` is pinned because the schema will not apply to 17 or earlier.
>
> `@ServiceConnection` on the container field removes the datasource-property wiring entirely, which
> is the modern Spring Boot way and worth using.

### Flyway in tests is the same mechanism as production

**This is where the migration asymmetry favors this backend.** Flyway already runs here on startup,
so the test schema is built by the *same* tool, from the *same* canonical SQL, as production. There
is no separate test-schema path to keep in step — unlike the Node backend, which must invoke the
Flyway CLI as a distinct setup step because Prisma cannot build the schema at all.

```java
@SpringBootTest(webEnvironment = RANDOM_PORT)
@Testcontainers
abstract class IntegrationTestBase {
  @Container @ServiceConnection
  static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:18.6");
}
```

A `static` container is shared across the class hierarchy, so it starts once per run rather than per
class.

**`ddl-auto` stays `validate` in the test profile.** Setting it to `create-drop` for tests is the
common shortcut and would defeat the point: `validate` failing in a test is the signal that entity
mappings have drifted from the canonical schema, and it is one of the few places that drift is
caught automatically.

Flyway's location points at the canonical SQL by the same mechanism the application uses — the
build-time copy described in
[architecture-specification.md](./architecture-specification.md#this-backend-owns-schema-application).

### Isolation

`@Transactional` on a test rolls back automatically, which is convenient and **must not be used for
the concurrency test** — AC-OB-01 needs two real committed transactions, and a shared rollback
wrapper makes it untestable. Use truncation there:

```sql
TRUNCATE payments, reservations, sessions, rooms, room_type_photos,
         room_type_amenities, room_types, rate_plans, properties, users
RESTART IDENTITY CASCADE;
```

preserving the migration-inserted `amenities` rows.

Also note `@Transactional` on a `@SpringBootTest` with `RANDOM_PORT` does **not** roll back work
done by the server thread — the test's transaction and the request's are different. Use truncation
for anything going over real HTTP.

### The concurrency test

```java
var pool = Executors.newFixedThreadPool(2);
var latch = new CountDownLatch(1);
Callable<Integer> attempt = () -> { latch.await(); return post("/api/v1/reservations", body).getStatusCode().value(); };
var f1 = pool.submit(attempt); var f2 = pool.submit(attempt);
latch.countDown();
assertThat(List.of(f1.get(), f2.get())).containsExactlyInAnyOrder(201, 409);
assertThat(countReservations(roomId)).isEqualTo(1);
```

The `CountDownLatch` is what makes the requests genuinely simultaneous — submitting two tasks to a
pool does not guarantee overlap. Assert order-independently.

### Clock control

```java
@TestConfiguration
class FixedClockConfig {
  @Bean @Primary
  Clock fixedClock() { return Clock.fixed(Instant.parse("2026-11-12T04:59:00Z"), ZoneOffset.UTC); }
}
```

Injected via `@Import`, or `@MockBean Clock` per test. **Never `Instant.now()` inline in production
code** — that is what makes AC-CX-01 through AC-CX-05 possible, and it is the reason `ClockConfig` is
listed as required rather than optional in
[architecture-specification.md](./architecture-specification.md#package-layout).

### Test slices, and when not to use them

| Annotation | Use for |
|------------|---------|
| Plain JUnit, no Spring | `domain/` pure functions — the fastest and highest-value layer |
| `@DataJpaTest` + Testcontainers | Repository queries and mappings |
| `@WebMvcTest` + `MockMvc` | Controller binding, validation, status codes, with services mocked |
| `@SpringBootTest` + Testcontainers | **Every acceptance criterion** in section 3 |

**The acceptance criteria belong in full-stack tests, not slices.** A `@WebMvcTest` with a mocked
service can assert a `409` is returned when the service throws — it cannot assert the exclusion
constraint fired, the transaction rolled back, and exactly one row exists. Several criteria are
specifically about database behavior, and a slice test of those would be theatre.

`@MockBean` is deliberately rare here. Mocking the repository layer in a criterion test removes the
database, which is the component under test.

### Unit tests

`domain/` is pure static functions and needs no Spring context —
`Pricing`, `Cancellation`, `Allocation`, `ReservationStatusRules`. Exhaustive cases for
`BigDecimal` rounding order, DST boundaries, and transition legality run in milliseconds. If a rule
is hard to unit test here, it has leaked out of `domain/` and back into a service.

`BigDecimal` assertions use `isEqualByComparingTo` where scale is irrelevant and
`isEqualTo` where it is not — `new BigDecimal("224.1")` and `new BigDecimal("224.10")` are equal by
comparison and **not** by `equals`, and the contract requires two decimal places on the wire.

### Gradle / Maven tasks

| Task | Runs |
|------|------|
| `test` | Unit + slices, no container |
| `integrationTest` | `@SpringBootTest` + Testcontainers |
| `check` | Both — what CI runs |
| `integrationTest -Duser.timezone=Asia/Tokyo` | The timezone-independence pass |

Separating `test` from `integrationTest` matters for the same reason as in the Node backend: the
container-free task is the loop a developer runs while writing `domain/` logic.
