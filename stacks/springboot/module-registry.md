# Module Registry — Spring Boot

Inventory of `hotelapp-server-springboot`'s packages and beans, and what each owns.

**This is bookkeeping, not design.** Everything here derives from the layering and package layout in
[architecture-specification.md](./architecture-specification.md#package-layout) and the endpoint list in
[api-contracts.md](../../shared/api-contracts.md). If this document and either of those disagree, they
are right and this is stale.

> **"Module" here means a package or a bean, not a Java module.** There is no `module-info.java`; the
> word is kept because it is the filename this document is required to have.

---

## Entry point and configuration

| Bean / class | Owns | Must not |
|--------------|------|----------|
| `HotelAppApplication` | Bootstrap | Contain logic |
| `config/SecurityConfig` | Filter chain, **`AuthenticationEntryPoint`, `AccessDeniedHandler`**, stateless policy, CSRF off, rank-based rules | Be left with Spring Security's default `401`/`403` bodies — [security-implementation.md](./security-implementation.md#spring-security-configuration) |
| `config/WebConfig` | CORS with explicit origins and credentials | Use a wildcard, or register CORS only in MVC and not on the filter chain |
| `config/JacksonConfig` | `fail-on-unknown-properties=true`, `BigDecimal` as **string** | Leave either at its default — both defaults violate the contract |
| `config/ClockConfig` | The `Clock` bean | Be omitted. The cancellation criteria are untestable without it |
| `config/OpenApiConfig` | `springdoc` customization | |
| `application.properties` | Non-secret defaults, **`ddl-auto=validate`**, Flyway locations | Hold a secret, or relax `ddl-auto` |

`ClockConfig` and the two custom Spring Security handlers are the three beans whose absence would not
fail any build and would each break something real — worth knowing as a set.

---

## Web layer

| Class | Owns |
|-------|------|
| `web/TraceIdFilter` | `traceId` into the **MDC**, ordered first, **cleared in a `finally`** |
| `web/SessionAuthFilter` | Cookie → hash → `sessions` **joined to `users`** → validity → sliding expiry → `SecurityContext` |
| `web/RequestLoggingFilter` | One line per request: method, route pattern, status, duration. **Never bodies** |
| `web/RateLimitFilter` | 10 attempts / 15 min, keyed on IP **and** email, on the two auth routes |
| `web/ProblemDetailExceptionHandler` | `@RestControllerAdvice`: `AppException`, validation, `DataIntegrityViolationException`, catch-all |

**`TraceIdFilter` must clear the MDC in a `finally`.** A pooled thread retaining a previous request's
`traceId` attributes the next request's logs to the wrong one, which is worse than having no id —
[logging-observability.md](./logging-observability.md#traceid-via-the-mdc).

**`ProblemDetailExceptionHandler` does not see filter-chain exceptions.** That is why `SecurityConfig`
carries its own entry point and access-denied handler; otherwise `401` and `403` return Spring's default
shape with no `code` or `traceId`.

---

## Controllers → endpoints

All 42 endpoints from
[api-contracts.md](../../shared/api-contracts.md#endpoint-index).

| Controller | Endpoints |
|------------|-----------|
| `AuthController` | `POST /auth/register`, `/auth/login`, `/auth/logout`, `GET /auth/me` |
| `PropertyController` | `GET /properties`, `/properties/{id}`, `/properties/{id}/room-types`, `/room-types/{id}`, `/amenities`, `/rate-categories` |
| `AvailabilityController` | `GET /availability` |
| `MeController` | `GET /me`, `PATCH /me`, `PUT /me/password` |
| `ReservationController` | `GET`/`POST /reservations`, `GET`/`PATCH /reservations/{id}`, `POST /reservations/{id}/cancel` |
| `admin/AdminReservationController` | `GET /admin/reservations`, `/{id}`, `POST .../check-in`, `.../check-out`, `.../cancel` |
| `admin/InventoryController` | Admin properties, room types, amenities, photos, rooms — 12 endpoints |
| `admin/RatePlanController` | `GET`/`PUT /admin/properties/{id}/rate-plans` |
| `admin/CalendarController` | `GET /admin/properties/{id}/calendar` |
| `admin/ReportController` | `GET .../reports/occupancy`, `.../reports/arrivals` |
| `HealthController` | `GET /health` — **custom, not Actuator** |

---

## Services

Owns transaction boundaries; knows nothing about HTTP.

| Bean | Owns |
|------|------|
| `AuthService` | Register, login, logout. **Dummy-hash timing equality** on unknown email |
| `SessionService` | Token generation, hashing, validation, sliding expiry, revocation cascades |
| `PropertyService` | Public catalogue reads |
| `AvailabilityService` | The native availability query and price resolution per result |
| `BookingService` | **The allocation retry loop — NOT `@Transactional`** |
| `ReservationTxService` | **The transactional insert of reservation + payment.** A separate bean |
| `ReservationService` | Guest reservation reads, modification, cancellation, refund determination |
| `AdminReservationService` | Admin list, check-in, check-out, staff cancel with fee waiver |
| `InventoryService` | Properties, room types, photos, rooms |
| `RatePlanService` | Whole-set rate-plan replacement |
| `CalendarService` | Segment assembly for the room/rate calendar |
| `ReportService` | Occupancy and arrivals |

> **`BookingService` and `ReservationTxService` are two beans on purpose**, and it is the most
> consequential structural detail in this backend. `@Transactional` self-invocation bypasses the proxy,
> so `this.createReservation(...)` would run with **no transaction** and the reservation and payment
> inserts would stop being atomic — silently. And the retry must be outside the transaction, because
> continuing in a rollback-only transaction throws `UnexpectedRollbackException` at commit. Splitting
> them makes both correct. Code in
> [error-handling.md](./error-handling.md#transactions).

---

## Domain — pure static functions, no Spring

**The most important package in the repo.** These four rules must agree with their TypeScript
counterparts to the cent and to the second.

| Class | Owns | Pinned by |
|-------|------|-----------|
| `domain/Pricing` | Discount resolution, **round the nightly rate then multiply**, `setScale(2, HALF_UP)` | [AC-CX-10](../../shared/acceptance-criteria.md#ac-cx-10--pricing-arithmetic-and-rounding-order) |
| `domain/Cancellation` | Deadline = check-in midnight in the property's `ZoneId` **minus exactly `Duration.ofHours(48)`** | [AC-CX-04](../../shared/acceptance-criteria.md#ac-cx-04--deadline-respects-the-propertys-timezone-not-the-servers), [AC-CX-05](../../shared/acceptance-criteria.md#ac-cx-05--dst-transition-does-not-shift-the-deadline-arithmetic) |
| `domain/Allocation` | Candidate ordering: lowest `room_number`, natural sort | [AC-OB-07](../../shared/acceptance-criteria.md#ac-ob-07--allocation-order-is-deterministic) |
| `domain/ReservationStatusRules` | Legal transitions | [AC-CX-09](../../shared/acceptance-criteria.md#ac-cx-09--illegal-cancellations-are-rejected) |
| `domain/PaymentValidation` | Luhn, expiry, CVV shape, brand derivation | — |

`final`, private constructor, static methods. **No Spring, no JPA, no `Instant.now()`** — a `Clock` is a
parameter. `Duration.ofHours(48)` rather than `plusDays(-2)`: the exact-duration reading is what
AC-CX-05 pins, and the two differ by an hour across a DST boundary.

**The exception hierarchy (`exception/AppException` + subclasses, `exception/ProblemCode`) is not
here** — it computes nothing, and lives in its own package. See "Exception handling architecture"
in [architecture-specification.md](./architecture-specification.md#exception-handling-architecture).

---

## Repositories and entities

`UserRepository` · `SessionRepository` · `PropertyRepository` · `RoomTypeRepository` ·
`RoomRepository` · `ReservationRepository` · `PaymentRepository` · `RatePlanRepository` ·
`AmenityRepository`

Entities: `User` · `Session` · `Property` · `RoomType` · `RoomTypePhoto` · `Amenity` · `Room` ·
`RatePlan` · `Reservation` · `Payment`

| Rule | Why |
|------|-----|
| `FetchType.LAZY` on every association | JPA defaults `@ManyToOne` to `EAGER` |
| Entities never leave the service layer | `LazyInitializationException`, and schema leaking into the contract |
| `equals`/`hashCode` on id only, null-tolerant | One of the reasons Lombok is absent |
| Native queries fully parameterized | The availability query is the parameter-dense one |
| `@GeneratedValue` omitted on ids | The database default `uuidv7()` supplies them |

`ReservationRepository` holds the two native queries — the availability anti-join and the calendar
segment query.

---

## DTOs

`dto/request/` (Java `record`s with Bean Validation annotations) · `dto/response/` (`record`s) ·
`dto/mapper/` (hand-written).

| Rule | Why |
|------|-----|
| **`BigDecimal` serializes as a string** | Jackson's default is a JSON number, which both frontends receive as a `double`. One line of configuration and one of the easiest contract violations to ship with every test passing |
| `PaymentRequest.toString()` is overridden to redact | A `record`'s generated `toString()` prints the card number — [logging-observability.md](./logging-observability.md#redaction--the-hard-rule) |
| No MapStruct or ModelMapper | The mapper is where the serialization rules are enforced; a convention-based mapper gets them wrong silently |

---

## Ownership of the tricky bits

| Concern | Sole owner |
|---------|-----------|
| Session token generation and hashing | `SessionService` |
| The 5-minute `expires_at` write-throttle | `SessionAuthFilter` |
| Rank comparison (not set membership) | `SecurityConfig`, via role hierarchy |
| `401` / `403` Problem Details | `SecurityConfig`'s entry point and access-denied handler — **not** the advice |
| Everything else error-shaped | `ProblemDetailExceptionHandler` |
| **SQLSTATE extraction from the Hibernate wrapping chain** | `ProblemDetailExceptionHandler.findCause` — see below |
| The allocation retry | `BookingService`, outside the transaction |
| The transactional insert | `ReservationTxService` |
| Pricing arithmetic and rounding order | `domain/Pricing` |
| Cancellation-deadline computation | `domain/Cancellation` |
| Confirmation-number generation and collision retry | `BookingService` |
| `BigDecimal` → decimal string | `dto/mapper/` + `JacksonConfig` |
| `traceId` | `TraceIdFilter` via the MDC |
| Log redaction | Logback configuration + `PaymentRequest.toString()` |
| Every configuration value | `@ConfigurationProperties` classes |

> **`findCause` is this backend's fragile point**, and it is worth comparing with the Node backend's.
> The PostgreSQL driver exposes SQLSTATE as **structured data** via `SQLException.getSQLState()`, so
> `23P01` is matched on a value — where Prisma has no mapped code and must use a raw-query code or match
> message text ([stacks/nodejs/error-handling.md](../nodejs/error-handling.md#prisma--problem-details)).
> **This is the more reliable of the two.**
>
> Its fragility is different: Hibernate wraps the cause two or three levels deep, so `findCause` walks
> the chain, and a Hibernate or driver upgrade that changes the nesting breaks it just as silently.
> Neither backend's integrity guarantee depends on detection — the constraint is enforced by PostgreSQL,
> and a failure to classify yields `500` instead of `409`, fail-closed either way.
>
> Guards:
> [AC-OB-01](../../shared/acceptance-criteria.md#ac-ob-01--two-concurrent-bookings-for-the-last-room-exactly-one-wins)
> against real PostgreSQL, and the unmapped-SQLSTATE log line in
> [logging-observability.md](./logging-observability.md#the-exclusion-constraint-detection-asymmetry).

---

## Build-time inputs, not sources

One thing in this repo's build is copied in rather than authored, which is unusual enough to state:

| Artifact | Comes from | Never |
|----------|-----------|-------|
| `target/classes/db/migration/V*.sql` | Copied from `hotelapp-context/shared/migrations/` at `generate-resources` | Authored or edited here |

**This backend executes those migrations and does not own them.** It is the project's sole DDL executor,
and the SQL it runs is reviewed in a different repository —
[versioning-strategy.md](../../shared/versioning-strategy.md#database-schema-migrations). A
`src/main/resources/db/migration/` directory with hand-written SQL in it would be a regression, not an
addition.
