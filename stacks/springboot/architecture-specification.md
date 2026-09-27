# Architecture Specification — Spring Boot

Structure of `hotelapp-server-springboot`: layering, package layout, the data-access layer, and
where transactions begin and end.

Java, Spring Boot, Spring Data JPA / Hibernate, PostgreSQL 18.6. The system-level shape — two
frontends, two backends, one database, REST as the only integration point — is in
[architecture-overview.md](../../shared/architecture-overview.md) and is not restated here.

---

## Fixed at the system level

| Constraint | Source |
|-----------|--------|
| Three layers: HTTP → service → data access | [architecture-overview.md](../../shared/architecture-overview.md#backend-architecture-in-outline) |
| Transactions begin and end in the **service** layer | same |
| **No JPA entity is ever serialized to JSON** — explicit DTOs only | same |
| Stateless process; all state in PostgreSQL, including sessions | same |
| Business logic in application code, not the database — one exception | same |
| The exception: no-overbooking, enforced by the exclusion constraint | [data-model.md](../../shared/data-model.md#no-overbooking) |
| **Flyway is the sole DDL executor; `ddl-auto=validate`** | [versioning-strategy.md](../../shared/versioning-strategy.md#database-schema-migrations) |
| Publishes OpenAPI 3.1 at `/api/v1/openapi.json`, diffable against the other backend | [api-contracts.md](../../shared/api-contracts.md#cross-cutting-requirements) |

---

## This backend owns schema application

> **This is the asymmetry**, decided in
> [versioning-strategy.md](../../shared/versioning-strategy.md#database-schema-migrations) and
> logged as a reversal in
> [decision-log.md](../../shared/decision-log.md) entry 3. The two backends are not peers on this
> axis: **this one applies the schema, and the Node backend consumes the result.**
>
> - **Flyway runs here, on startup**, against the canonical
>   `hotelapp-context/shared/migrations/V<nnn>__*.sql`. This repo's `flyway_schema_history` table
>   is the project's single migration history.
> - **Hibernate never generates DDL:** `spring.jpa.hibernate.ddl-auto=validate` in every
>   environment, including tests. A startup failure there is the check working — it means the
>   entity mappings and the real schema disagree.
> - **The migration SQL is not authored in this repo.** It is authored in `hotelapp-context` and
>   merged there first. This repo points Flyway at it; it does not own it.
> - Because Flyway runs here, **this backend is the convenient one to stand up first**, and Phase 6
>   builds it before the Node backend for exactly that reason —
>   [phased-implementation-plan.md](../../shared/phased-implementation-plan.md).
>
> **How Flyway reaches files in another repository** is a real question with no elegant answer, and
> the options are worth naming rather than leaving implicit:
>
> | Option | Trade-off |
> |--------|-----------|
> | A build step copying the SQL into `target/classes/db/migration` before run | Simple, no extra tooling, and the copy is a build artifact rather than committed duplication. **Preferred** |
> | `spring.flyway.locations=filesystem:../hotelapp-context/shared/migrations` | No copy step, but assumes a sibling checkout — breaks in CI and in a container without a mount |
> | A git submodule | Reproducible, and adds submodule mechanics to every clone |
> | Committing a copy into this repo | Two copies of the canonical schema, which defeats the decision |
>
> The copy-at-build approach is recommended and the reasoning recorded so a later reader does not
> assume the others were overlooked. Setup detail in
> [environment-setup-guide.md](./environment-setup-guide.md); the CI form is in
> [devops-pipeline.md](./devops-pipeline.md).
>
> **`validate` must not be relaxed to `update` or `create-drop`, in any profile including test.**
> `update` would let Hibernate silently alter the schema this repo is supposed to be validating
> against, which reintroduces the two-writers problem the whole decision exists to prevent.

---

## Layering

```
HTTP layer          Routing, request binding, validation, status codes,
web/                Problem Details serialization.
                    Knows HTTP. Knows nothing about JPA.
      │
Service layer       Business rules: pricing, policy, allocation, transitions.
service/            OWNS TRANSACTION BOUNDARIES (@Transactional lives here).
                    Knows nothing about HTTP or about JPA specifics.
      │
Data access         Spring Data repositories, JPQL, entities.
repository/         Knows nothing about business rules.
```

Rules that make the layering real rather than nominal:

- **A controller contains no business rule.** It binds, validates, calls one service method, and
  returns a DTO. A conditional on `reservation.getStatus()` in a controller is logic in the wrong
  layer.
- **A service never imports `jakarta.servlet` or `org.springframework.http`.** Services throw
  `AppException` subclasses; the `@RestControllerAdvice` turns those into responses. See
  [error-handling.md](./error-handling.md).
- **`@Transactional` is on the service method only** — never a controller, never a repository.
- **An entity never leaves the service layer.** Services return domain objects or DTOs, not
  entities, which also avoids lazy-loading exceptions after the transaction closes.
- **No layer skipping.** A controller calling a repository bypasses the rules that make the
  response correct.

> **Design Decision — a hand-written service layer rather than leaning on Spring Data projections
> and `@RepositoryRestResource`.** Spring can expose repositories as REST endpoints directly, and
> that would be far less code. It is wrong here for two reasons. The API shape is fixed by
> [api-contracts.md](../../shared/api-contracts.md) and does not match what repository-derived
> endpoints produce. And more importantly, **the Node backend must implement the same rules, and a
> reviewer has to compare them** — pricing, the cancellation deadline, allocation order, and status
> transitions live in named service methods in both backends so the two read side by side. The
> layering is as much a documentation decision as a design one.

---

## Package layout

By layer at the top, by feature within.

```
com.hotelapp
  HotelAppApplication.java

  config/
    WebConfig.java              CORS, content negotiation
    SecurityConfig.java         Filter chain, entry point, access-denied handler
    JacksonConfig.java          fail-on-unknown-properties, serialization
    OpenApiConfig.java
    ClockConfig.java            Clock bean — REQUIRED, see below

  web/
    TraceIdFilter.java          Ordered first; traceId into the MDC
    SessionAuthFilter.java      Cookie -> session+user; sets the SecurityContext
    ProblemDetailExceptionHandler.java   @RestControllerAdvice
    AuthController.java  PropertyController.java  AvailabilityController.java
    ReservationController.java  MeController.java  HealthController.java
    admin/
      AdminReservationController.java  InventoryController.java
      RatePlanController.java  CalendarController.java  ReportController.java

  service/
    AuthService.java  SessionService.java  PropertyService.java
    AvailabilityService.java  BookingService.java  ReservationTxService.java
    ReservationService.java  AdminReservationService.java
    InventoryService.java  RatePlanService.java  CalendarService.java
    ReportService.java

  domain/
    Pricing.java                Rate resolution + rounding — PURE, static
    Cancellation.java           Deadline computation — PURE, static
    Allocation.java             Candidate ordering — PURE, static
    ReservationStatusRules.java Legal transitions — PURE, static
    AppException.java + subclasses

  repository/
    UserRepository.java  SessionRepository.java  PropertyRepository.java
    RoomTypeRepository.java  RoomRepository.java  ReservationRepository.java
    PaymentRepository.java  RatePlanRepository.java  AmenityRepository.java

  entity/
    User  Session  Property  RoomType  RoomTypePhoto  Amenity
    Room  RatePlan  Reservation  Payment

  dto/
    request/  response/  mapper/
```

**`domain/` holds the pure static functions and is the most important package in the repo.**
Pricing, the cancellation deadline, allocation order, and legal status transitions are the four
rules the two backends must agree on to the cent and to the second. Keeping them as pure functions
with no Spring, JPA, or HTTP dependency means they are unit-testable without a context and
comparable directly with their TypeScript counterparts. This is where
[AC-CX-10](../../shared/acceptance-criteria.md#ac-cx-10--pricing-arithmetic-and-rounding-order)
and
[AC-CX-04](../../shared/acceptance-criteria.md#ac-cx-04--deadline-respects-the-propertys-timezone-not-the-servers)
are satisfied.

**`ReservationTxService` is separate from `BookingService` on purpose.** `@Transactional`
self-invocation does not work — calling `this.createReservation(...)` bypasses the proxy and runs
with no transaction, so the reservation and payment inserts would not be atomic. The allocation
retry must also live outside the transaction. Splitting the transactional method into its own bean
is what makes both correct. Detail in
[error-handling.md](./error-handling.md#transactions).

**`ClockConfig` is required, not optional.** A `Clock` bean injected wherever "now" is needed is
what makes the cancellation-boundary criteria testable at all —
[AC-CX-01](../../shared/acceptance-criteria.md#ac-cx-01--just-before-the-deadline-refundable)
through AC-CX-05 need the clock controlled. `Instant.now()` called directly is untestable and
retrofitting the bean later means touching every call site.

---

## Filter chain and request flow

Order is normative; it determines what an unauthorized caller can learn, per
[error-handling.md](./error-handling.md#order-of-checks).

```
1. TraceIdFilter          traceId -> MDC. Ordered FIRST.
2. CORS filter            configured origins, allowCredentials = true
3. Rate limit filter      auth endpoints only -> 429
4. SessionAuthFilter      cookie -> session+user -> SecurityContext
5. Spring Security authz  URL rules -> 401 / 403
6. DispatcherServlet
7. Bean Validation        -> 400
8. Controller -> Service
```

> **The most likely way this stack ends up non-conforming.** Steps 4 and 5 raise their exceptions
> **inside the filter chain, before the dispatcher servlet**, so `@RestControllerAdvice` never sees
> them. Without a custom `AuthenticationEntryPoint` and `AccessDeniedHandler` emitting the same
> Problem Details shape, `401` and `403` come back in Spring Security's default format — with no
> `code` and no `traceId` — while every other error conforms. Those are the two most common error
> codes in the API and neither appears in a happy-path test, so this is worth treating as a
> checklist item rather than an implementation detail. Same point in
> [error-handling.md](./error-handling.md#the-final-safety-net).

**`SecurityConfig` requirements:** stateless session management
(`SessionCreationPolicy.STATELESS`) so Spring never creates its own `HttpSession` alongside the
application's `sessions` table; CSRF disabled, because the API relies on `SameSite=Lax` rather than
a token — reasoning in
[security-principles.md](../../shared/security-principles.md#sessions); and authorization rules
comparing **rank**, so `hasAuthority('FRONT_DESK_STAFF')` also admits a manager, or the rule is
expressed as a role hierarchy.

---

## Session handling

The whole authentication mechanism, per
[api-contracts.md](../../shared/api-contracts.md#authentication). Implemented as a filter rather
than through Spring Security's `RememberMe` or session support, because the `sessions` table is the
authority and Spring's own session abstractions would be a second, competing one.

`SessionAuthFilter`:

1. Read the `hotelapp_session` cookie. Absent → continue unauthenticated; Spring Security's rules
   then produce `401` where required.
2. SHA-256 the token, look up `sessions` by `token_hash`, **joined to `users`** in one query.
3. Reject when `revoked_at IS NOT NULL` or `expires_at <= now()`.
4. Reject when `users.is_active = false` → `403 ACCOUNT_INACTIVE`.
5. Slide `expires_at` to `now() + 8h`, capped at `issued_at + 30 days`, **only if more than 5
   minutes stale**.
6. Set the `SecurityContext` authentication with the user's role and `home_property_id`.

**The join in step 2 is not an optimization.** Reading `role` and `home_property_id` from the
joined user row on every request is what makes a role change or deactivation take effect
immediately —
[AC-AZ-11](../../shared/acceptance-criteria.md#ac-az-11--inactive-accounts-cannot-authenticate)
asserts exactly this, and a cached authority would fail it.

**The 5-minute write-throttle is required, not an optimization either.** Without it every
authenticated request writes a row. With a different threshold this backend would appear to expire
sessions at a different time than the Node one — see
[data-model.md](../../shared/data-model.md#sessions).

The slide is a write inside a read request, so it needs its own short transaction; do not widen the
request's transaction to cover it.

---

## JPA and Hibernate usage

### Entity mapping

Hand-written to match the schema in
[data-model.md](../../shared/data-model.md), which `ddl-auto=validate` then checks.

| Column type | Java mapping |
|-------------|--------------|
| `uuid` | `UUID`, `@GeneratedValue` omitted — the database default `uuidv7()` supplies it |
| `numeric(10,2)` | `BigDecimal`. **Never `double` or `float`** |
| `date` | `LocalDate` |
| `timestamptz` | `OffsetDateTime` (or `Instant`) |
| PostgreSQL enum | `@JdbcTypeCode(SqlTypes.NAMED_ENUM)` with a Java enum |
| `daterange` generated column | `@Generated` with `insertable = false, updatable = false`, or unmapped |
| `inet` | `String` — no JDBC type warrants more here |

Because the id is database-generated, `@GeneratedValue(strategy = IDENTITY)` is wrong — use
`@Generated(event = INSERT)` or read the value back, so Hibernate does not try to supply one.

### Query rules

- **`FetchType.LAZY` on every association, no exceptions.** JPA defaults `@ManyToOne` to `EAGER`,
  which produces joins nobody asked for on every query touching a reservation.
- **Fetch joins where a collection is needed**, so the N+1 hazards — room-type photos and amenities
  on property and search responses — are one query rather than one per row. Named in
  [data-model.md](../../shared/data-model.md#orm-generation-notes).
- **The availability query is a native query**, because it needs the `&&` range operator and a
  `NOT EXISTS` anti-join that JPQL cannot express. Every date, id, and count is a **bound
  parameter** — the most parameter-dense query in the application and the one place SQL injection
  could plausibly be introduced. See
  [security-implementation.md](./security-implementation.md).
- **Dynamic sort clauses go through an allow-list**, mapping API field names to column names. An
  identifier cannot be a bound parameter, so interpolating a "validated" sort field into SQL is the
  classic version of this bug.
- **`@Transactional(readOnly = true)` on read paths**, which lets Hibernate skip dirty checking and
  documents intent.

### Transactions

`@Transactional` on the service method. The booking transaction — allocate, insert the reservation,
insert the payment — is atomic so a payment row never exists without its reservation.

Two traps, both covered with code in
[error-handling.md](./error-handling.md#transactions): the allocation retry must be **outside** the
transaction, since continuing in a rollback-only transaction throws `UnexpectedRollbackException`
at commit; and `DataIntegrityViolationException` may surface at **flush** rather than at `save()`,
so the `catch` must wrap the whole transactional call.

---

## DTOs

Every response is built from an explicit DTO, mapped in `dto/mapper/`. **No entity is ever returned
from a controller.**

Two reasons, both concrete. Serializing an entity makes the API's shape a function of the schema,
so a column added by a migration silently appears in responses — including, worst case,
`password_hash` or `token_hash`. And a lazy association serialized after the transaction closes
throws `LazyInitializationException`, which turns a mapping choice into a runtime failure on a
specific endpoint.

Java `record` types for DTOs: immutable, concise, and Jackson-friendly.

Mappers handle the contract's serialization rules: `BigDecimal` → decimal **string** (via
`@JsonSerialize(using = ToStringSerializer.class)` or an explicit mapper), `LocalDate` →
`YYYY-MM-DD`, `OffsetDateTime` → ISO 8601 with offset. Per
[glossary-of-conventions.md](../../shared/glossary-of-conventions.md#the-identifier-casing-rule).

**`BigDecimal` must serialize as a string, not a number.** Jackson's default is a JSON number,
which both frontends would receive as a JavaScript `double` — the precision loss the string
convention exists to prevent. This is one line of configuration and one of the easiest ways to
violate the contract while every test passes.

> **Design Decision — no MapStruct or ModelMapper.** Hand-written mappers are more code and are
> preferred here: the mapping is where the serialization rules above are enforced, and a generated
> or reflective mapper makes those rules invisible. The `BigDecimal`-as-string rule in particular is
> exactly the kind of thing a convention-based mapper gets wrong silently.

---

## OpenAPI

`springdoc-openapi` generates the document from controllers and DTOs, served at
`/api/v1/openapi.json`.

> **Design Decision — generated here, hand-maintained in the Node backend.** A deliberate
> asymmetry. `springdoc-openapi` is mature and derives the document from the annotations that
> already exist, so generating it costs nothing. The Node backend has no equivalent of comparable
> maturity, and two *different* generators would produce documents differing everywhere and nowhere
> meaningfully — `operationId` style, schema naming, how optionality is expressed — which is what
> makes a naive diff useless.
>
> The consequence is that the diff job must **normalize both documents** before comparing: sort
> keys, drop `summary`, `description`, examples, and `x-*` extensions, then compare structurally.
> That requirement is already stated in
> [devops-pipeline-overview.md](../../shared/devops-pipeline-overview.md#1-the-openapi-diff), and
> this asymmetry is the concrete reason it exists.

Annotations must state what the generator cannot infer: `BigDecimal` fields as
`type: string, format: decimal`, and the `application/problem+json` error responses per endpoint.

---

## Deliberately absent

| Absent | Why |
|--------|-----|
| `update` or `create-drop` for `ddl-auto` | Flyway is the sole DDL executor — see above |
| Spring Data REST / `@RepositoryRestResource` | The API shape is fixed by the contract, and hand-written services are comparable with the Node backend's |
| Spring Session | The `sessions` table is the authority; a second session abstraction would compete with it |
| MapStruct, ModelMapper | See DTOs above |
| Lombok | `record` types cover DTOs; entities need real accessors. One less annotation processor in a project meant to be read |
| Spring Cloud, service discovery, config server | One service, no distributed infrastructure |
| Caching — `@Cacheable`, Redis | Only the session lookup would benefit; named as the scale-up path in [api-contracts.md](../../shared/api-contracts.md#authentication) |
| `@Async`, a task executor beyond scheduled cleanup | The only periodic work is session cleanup: one scheduled `DELETE` |
| WebFlux / reactive | The contract is blocking request/response; reactive would add complexity with no concurrency target to justify it |
| Actuator beyond a health endpoint | Nothing collects metrics — [non-functional-requirements.md](../../shared/non-functional-requirements.md#availability) |
| Stored procedures, triggers | Business logic stays in application code — [architecture-overview.md](../../shared/architecture-overview.md#where-business-logic-lives) |
