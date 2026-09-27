# Coding Standards — Spring Boot

Conventions for `hotelapp-server-springboot`. Java, Spring Boot, Spring Data JPA.

Naming that crosses layers — JSON, SQL, URLs, enum values, booleans, dates, money — is fixed in
[glossary-of-conventions.md](../../shared/glossary-of-conventions.md#the-identifier-casing-rule) and
is **not** re-derived here. Layering and package layout are fixed in
[architecture-specification.md](./architecture-specification.md). This document covers what those
two leave open.

---

## Java

An LTS release, pinned in the build file. Records, sealed types, pattern matching, and `var` for
locals where the type is obvious from the right-hand side.

| Rule | Detail |
|------|--------|
| `record` for DTOs and value objects | Immutable, concise, Jackson-friendly |
| `final` on fields by default | Mutability is opt-in, and entities are the only real exception |
| Constructor injection, not `@Autowired` on fields | Makes dependencies visible and the class constructible in a test without Spring |
| `Optional` as a **return** type only | Never a parameter, never a field |
| Java `enum` for contract enums, matching PostgreSQL exactly | `Role.FRONT_DESK_STAFF` — the names are the wire values |
| No wildcard imports | |
| No `null` returns from services | `Optional` or a thrown `AppException` |

**Money is `BigDecimal`. Never `double` or `float`, anywhere, for any reason.** Per
[glossary-of-conventions.md](../../shared/glossary-of-conventions.md#money-dates-and-formatting-in-code).
And `BigDecimal` needs two further rules that are easy to miss:

- **Never `new BigDecimal(double)`** — `new BigDecimal(0.1)` is `0.1000000000000000055511...`. Use
  `new BigDecimal("0.10")` or `BigDecimal.valueOf`.
- **Compare with `compareTo`, not `equals`.** `new BigDecimal("224.1").equals(new BigDecimal("224.10"))`
  is `false` because `equals` includes scale. This bites hardest in tests, and the contract requires
  two decimal places on the wire — so `setScale(2, HALF_UP)` at the boundary is not optional.

**Dates: `LocalDate` for `date` columns, `OffsetDateTime` for `timestamptz`.** Never `java.util.Date`,
never `Calendar`, never `Timestamp` in application code. The "dates only, no times" rule from
[project-overview.md](../../shared/project-overview.md) means confusing `LocalDate` with
`LocalDateTime` is a business-logic bug, not a type annoyance.

**`ZoneId`, never a fixed offset**, for the cancellation deadline. A hardcoded `-05:00` produces the
wrong answer across a DST boundary — the exact failure
[AC-CX-05](../../shared/acceptance-criteria.md#ac-cx-05--dst-transition-does-not-shift-the-deadline-arithmetic)
exists to catch.

---

## Spring conventions

- **Constructor injection everywhere.** No field `@Autowired`, no setter injection. A single-constructor
  bean needs no annotation at all.
- **`@Service`, `@Repository`, `@RestController`, `@Component`** used for what they mean. Not
  `@Component` on everything.
- **`@Transactional` on service methods only**, never a controller or repository — the boundary rule
  from [architecture-specification.md](./architecture-specification.md#layering).
- **`@Transactional(readOnly = true)` on read paths.** Lets Hibernate skip dirty checking, and
  documents intent.
- **No self-invocation of an annotated method.** `this.someTransactionalMethod()` bypasses the proxy
  and runs with no transaction — which is why `ReservationTxService` is a separate bean. This is the
  single most consequential Spring gotcha in this codebase, because the failure is silent: the
  reservation and payment inserts stop being atomic and nothing complains.
- **`@ConfigurationProperties` with validation** for config, not scattered `@Value`. One typed object,
  validated at startup, rather than an `${}` placeholder resolving to a literal string.
- **Never `@Transactional` on a `private` or `final` method.** The proxy cannot intercept it, and it
  fails silently in the same way.

---

## Package and file conventions

| Thing | Convention | Example |
|-------|-----------|---------|
| Controller | `<Feature>Controller` | `ReservationController` |
| Service | `<Feature>Service` | `BookingService` |
| Repository | `<Entity>Repository` | `ReservationRepository` |
| Entity | The singular noun | `Reservation` |
| Request DTO | `<Action><Entity>Request` | `CreateReservationRequest` |
| Response DTO | `<Entity>Response` / `<Entity>SummaryResponse` | `ReservationResponse` |
| Mapper | `<Entity>Mapper` | `ReservationMapper` |
| Domain rule | The rule, as a static utility | `Pricing`, `Cancellation` |
| Exception | `<Condition>Exception` | `RoomUnavailableException` |
| Test | `<Subject>Test` / `<Subject>IT` | `PricingTest`, `BookingIT` |

`...IT` for integration tests, so the build can separate the container-free task from the
container-backed one — see
[testing-standards.md](./testing-standards.md).

**`domain/` classes are `final` with a private constructor and static methods.** They are pure
functions, not beans: no Spring, no JPA, no injection. That is what makes them exhaustively
unit-testable without a context and directly comparable with their TypeScript counterparts.

Domain terms follow
[domain-glossary.md](../../shared/domain-glossary.md): `Reservation`, never `Booking`, for the
entity; `Property`, never `Hotel`.

---

## Naming

| Thing | Convention |
|-------|-----------|
| Method, variable | `camelCase` |
| Class, record, enum | `PascalCase` |
| Constant | `SCREAMING_SNAKE_CASE`, `static final` |
| Boolean accessor | `isX()` / `hasX()` / `canX()` |
| Repository read | `findX` returning `Optional` / `getX` throwing |
| Repository write | Spring Data `save`, or explicit `insertX` / `updateX` for JPQL |
| Service method | The business action: `bookReservation`, `checkIn`, `cancelReservation` |

**The `find` / `get` distinction is load-bearing.** `findById` returns `Optional` and the caller
decides; `getById` throws `NotFoundException`. Mixing them means every call site re-decides how
absence is handled, and the `404`-versus-`403` rule in
[error-handling.md](./error-handling.md#ownership-404-versus-403) depends on that being consistent.

---

## JPA

- **`FetchType.LAZY` on every association, no exceptions.** JPA defaults `@ManyToOne` to `EAGER`,
  producing joins nobody asked for on every query touching a reservation.
- **Fetch joins where a collection is needed.** The N+1 hazards are room-type photos and amenities.
- **Never return an entity from a controller.** A lazy association serialized after the transaction
  closes throws `LazyInitializationException`, and serializing an entity makes the API shape a
  function of the schema — [architecture-specification.md](./architecture-specification.md#dtos).
- **No bidirectional association without a reason.** Most here are one-directional; a needless inverse
  side is another place to keep consistent.
- **`equals`/`hashCode` on entities use the id only**, and must tolerate a null id before persist.
  Lombok's generated versions over all fields are wrong for entities, which is one reason Lombok is
  absent.
- **Native queries use bound parameters for every value.** The availability query is the
  parameter-dense one and the place injection could plausibly be introduced. A dynamic sort field goes
  through an **allow-list** mapping API names to columns — an identifier cannot be a bound parameter,
  so interpolating a "validated" sort field is the classic form of this bug.
- **`ddl-auto` stays `validate`.** In every profile, including test. See
  [architecture-specification.md](./architecture-specification.md#this-backend-owns-schema-application).

---

## Validation

- **Bean Validation annotations on request DTOs**, `@Valid` on the controller parameter. Validation
  happens once, at the HTTP boundary; services trust their inputs.
- **`spring.jackson.deserialization.fail-on-unknown-properties=true`.** Off by default, and leaving it
  off violates the reject-unknown-fields rule in
  [api-contracts.md](../../shared/api-contracts.md#request-validation) and fails
  [AC-CC-02](../../shared/acceptance-criteria.md#ac-cc-02--unknown-request-fields-are-rejected).
- **`HttpMessageNotReadableException` must be handled**, because that is where unknown-field rejection
  surfaces — not as a `MethodArgumentNotValidException`. Unhandled, it returns Spring's own `400` body
  with no `code`.
- **Never accept a server-owned field.** `price`, `role`, `status`, `confirmationNumber`,
  `cancellationDeadline`, and every `*At` are absent from every request record. The absence *is* the
  control, and `fail-on-unknown-properties` is what enforces it.
- **Cross-field rules are custom validators or service checks**, not annotations pretending to be:
  `checkOutDate > checkInDate` and `numGuests <= maxOccupancy` (which needs a second table) both
  belong in the service.

---

## Errors

- **Services throw `AppException` subclasses. Services never touch `HttpServletResponse`.** See
  [error-handling.md](./error-handling.md).
- **Never `throw new RuntimeException("...")` for a condition with a code.** It becomes
  `500 INTERNAL_ERROR`, hiding a handled case as an outage.
- **Never catch to return `null` or an empty `Optional` on failure.** That pushes error handling to
  every call site and eventually to none.
- **Never catch `Exception` broadly** except in the one global handler.
- SQL and JPA exceptions are translated in **one** place, the `@RestControllerAdvice`. A second
  translation site is how `EMAIL_ALREADY_REGISTERED` ends up returned for a duplicate room number.
- **`ConstraintViolationException` is ambiguous** — `org.hibernate.exception` is a database constraint,
  `jakarta.validation` is Bean Validation. Importing the wrong one compiles and never matches.

---

## Logging

- SLF4J, `private static final Logger log = LoggerFactory.getLogger(X.class)`. **`System.out.println`
  is a review finding.**
- The `traceId` comes from the MDC, set by `TraceIdFilter`, so every line carries it without being
  passed around — per [error-handling.md](./error-handling.md#4-traceid-and-logging).
- **Parameterized logging**: `log.warn("rejected {} for {}", code, id)`, never string concatenation.
  Concatenation builds the string even when the level is disabled.
- **Never log a request or response body.** Method, path, status, and duration only.
- Never log: `Cookie`, `Set-Cookie`, a session token, `passwordHash`, `payment.cardNumber`,
  `payment.cvv`, `payment.expiry*`, or any password field. Masking is configured, not per call site.
  Detail in [logging-observability.md](./logging-observability.md).
- `4xx` at `warn` or `info`; `5xx` at `error` **with the exception as the last argument** so the stack
  is captured. Inverting the levels makes the log useless.
- **Never log and rethrow.** One or the other, or every failure appears several times.

---

## Comments

Comment **why**, never **what**. Worth a comment in this codebase, because each is a decision a later
reader would otherwise "simplify" into a bug:

- Why `ReservationTxService` is a separate bean (self-invocation defeats `@Transactional`).
- Why the allocation retry is **outside** the transaction.
- Why `findCause` walks the chain rather than calling `getCause()` once.
- Why the session `expires_at` write is throttled to 5 minutes.
- Why `role` is read from the joined user row rather than cached in an authority.
- Why the nightly rate is rounded **before** multiplying by nights.
- Why `ddl-auto` is `validate` and must stay there.
- Why `AuthenticationEntryPoint` and `AccessDeniedHandler` are customized.

No commented-out code. No `TODO` without an owner and a reason. No Javadoc restating a signature.

---

## Forbidden

| Never | Why |
|-------|-----|
| `double` / `float` for money | Precision loss. Also `new BigDecimal(double)` |
| `BigDecimal.equals` for value comparison | Scale-sensitive; use `compareTo` |
| `System.out.println` | Use SLF4J |
| Returning an entity from a controller | `LazyInitializationException`, and leaks schema into the contract |
| Field `@Autowired` | Hides dependencies; breaks construction in tests |
| Self-invoking a `@Transactional` method | Silently runs without a transaction |
| `@Transactional` on a controller or repository | Wrong boundary |
| `ddl-auto` other than `validate` | Flyway is the sole DDL executor |
| Authoring migration SQL in this repo | It is authored in `hotelapp-context` — [versioning-strategy.md](../../shared/versioning-strategy.md#database-schema-migrations) |
| String-concatenated SQL or JPQL | SQL injection |
| Interpolating a sort field into a query | Use an allow-list |
| `Instant.now()` inline in a service | Defeats the injected `Clock` the cancellation criteria need |
| `java.util.Date`, `Calendar`, `Timestamp` in application code | Use `java.time` |
| A fixed UTC offset for a property timezone | Wrong across DST |
| Catching `Exception` outside the global handler | Swallows conditions with real codes |
| Business logic in a controller | Wrong layer, and not comparable with the Node backend |
| Lombok | `record` covers DTOs; entity `equals`/`hashCode` must be id-only |
| `@EnableJpaAuditing` / `@CreatedDate` | `created_at` and `updated_at` have database defaults |
