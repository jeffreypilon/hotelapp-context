# Error Handling — Spring Boot

How `hotelapp-server-springboot` produces RFC 9457 Problem Details responses.

> ### Sections 1–5 are shared, verbatim, with the other backend
>
> **Sections 1 through 5 below are byte-identical to
> [`stacks/nodejs/error-handling.md`](../nodejs/error-handling.md).** The two backends must be
> byte-for-byte interchangeable on the wire: the same condition must produce the same status, the
> same `code`, the same `title`, and the same `detail` from either implementation, or the OpenAPI
> diff passes while the two backends behave differently — which is the failure this whole project
> is organized against.
>
> **Any diff in sections 1–5 is a defect.** Section 6 holds the Spring Boot implementation and is the
> only part that differs.
>
> This is the backend counterpart to the paired `error-handling.md` files in the two frontend
> stacks, which are held to the same standard for user-facing message text.

The error format and the code catalogue are fixed in
[api-contracts.md](../../shared/api-contracts.md#error-responses). This document says what raises
each code and where the handling lives.

---

## 1. What both backends must emit

The response body is fixed by
[api-contracts.md](../../shared/api-contracts.md#error-responses). This section restates the
*obligations*, not the format — where the two disagree, that document wins.

```json
{
  "type": "https://hotelapp.example/problems/validation-failed",
  "title": "Validation failed",
  "status": 400,
  "detail": "The request body contains 2 invalid fields.",
  "instance": "/api/v1/reservations",
  "code": "VALIDATION_FAILED",
  "traceId": "0192f3a1-9e33-7d40-b512-2ac8d5f3e211",
  "errors": [
    { "field": "checkOutDate", "code": "AFTER_CHECK_IN", "message": "checkOutDate must be after checkInDate." },
    { "field": "numGuests",    "code": "MIN",            "message": "numGuests must be at least 1." }
  ]
}
```

| Obligation | Detail |
|-----------|--------|
| `Content-Type` | `application/problem+json` on **every** error response, including `500` |
| Members always present | `type`, `title`, `status`, `detail`, `instance`, `code`, `traceId` |
| `status` | Must equal the HTTP status. A body saying `400` returned as `200` is worse than either alone |
| `code` | The client's branch key. Drawn only from the catalogue in section 2 |
| `type` | `https://hotelapp.example/problems/` + the `code` lowercased with underscores replaced by hyphens |
| `title` | Fixed per `code`, never varies by occurrence |
| `detail` | Specific to the occurrence, safe to show a user, and **never** containing a stack trace, SQL fragment, hostname, file path, driver message, or class name |
| `instance` | The request path, without the query string |
| `traceId` | Correlates to the server log for this request — see section 4 |
| `errors[]` | Present only for `VALIDATION_FAILED` |

**`type` is derived, not free-form.** `ROOM_UNAVAILABLE` →
`https://hotelapp.example/problems/room-unavailable`. Deriving it mechanically from `code`
removes the chance of the two backends inventing different URIs for the same condition.

**The client branches on `code`, never on `detail`.** That is stated as a client obligation in
[api-contracts.md](../../shared/api-contracts.md#error-responses) and is what makes `detail`
free to be reworded — but only if `code` is *always* right. A handler that returns the correct
status with the wrong `code` breaks both frontends while looking fine in a manual test.

---

## 2. The catalogue, and what raises each code

Every error this API can return. The `code` and `status` columns are fixed by
[api-contracts.md](../../shared/api-contracts.md#problem-catalogue); the third column is what
this document adds — **the condition each backend must map to it.**

| `code` | Status | Raised when |
|--------|--------|-------------|
| `VALIDATION_FAILED` | 400 | Body or query parameter fails schema validation; an unknown field is present; a path parameter is not a well-formed UUID |
| `AUTHENTICATION_REQUIRED` | 401 | No session cookie, or a session row that is absent, `revoked_at IS NOT NULL`, or `expires_at <= now()` |
| `INVALID_CREDENTIALS` | 401 | Login with an unknown email **or** a wrong password — indistinguishable by design |
| `ACCOUNT_INACTIVE` | 403 | `users.is_active = false`, on login **or** on any authenticated request |
| `INSUFFICIENT_ROLE` | 403 | Authenticated, role rank below the endpoint's tier |
| `PROPERTY_OUT_OF_SCOPE` | 403 | `FRONT_DESK_STAFF` addressing a property other than `home_property_id` |
| `NOT_FOUND` | 404 | No such row, **or** a row the caller may not see (a guest requesting another guest's reservation) |
| `EMAIL_ALREADY_REGISTERED` | 409 | Unique violation on `users_email_lower_key` during registration |
| `ROOM_UNAVAILABLE` | 409 | No free room for the requested type and dates, **or** SQLSTATE `23P01` from `reservations_no_overlap_excl` after the allocation retries are exhausted |
| `INVALID_STATUS_TRANSITION` | 409 | A status transition the lifecycle forbids — checking in a cancelled reservation, checking out one never checked in, cancelling a terminal one |
| `CANCELLATION_WINDOW_CLOSED` | 409 | A modification attempted when `now() >= cancellation_deadline` |
| `ROOM_NUMBER_IN_USE` | 409 | Unique violation on `rooms_property_number_key` |
| `SLUG_IN_USE` | 409 | Unique violation on `properties_slug_key` |
| `PAYMENT_DECLINED` | 402 | The simulated decline — a card number ending `0000` |
| `RATE_LIMITED` | 429 | The auth rate limiter tripped. **Must carry `Retry-After`** |
| `INTERNAL_ERROR` | 500 | Anything unhandled |

**No code outside this table may be returned.** Adding one is a contract change made in
[api-contracts.md](../../shared/api-contracts.md) first — and note it is a *non-breaking*
change per
[versioning-strategy.md](../../shared/versioning-strategy.md#what-counts-as-a-breaking-change),
which is exactly why both frontends fall back by status class on an unrecognized code.

### `title` and `detail`, fixed per code

Both backends emit these strings. `title` is invariant; `detail` is a template.

| `code` | `title` | `detail` template |
|--------|---------|-------------------|
| `VALIDATION_FAILED` | Validation failed | The request body contains {n} invalid field(s). |
| `AUTHENTICATION_REQUIRED` | Authentication required | This request requires an active session. |
| `INVALID_CREDENTIALS` | Invalid credentials | The email or password is incorrect. |
| `ACCOUNT_INACTIVE` | Account inactive | This account is not active. |
| `INSUFFICIENT_ROLE` | Insufficient role | This operation requires a higher permission level. |
| `PROPERTY_OUT_OF_SCOPE` | Property out of scope | This account does not have access to that property. |
| `NOT_FOUND` | Not found | The requested {resource} was not found. |
| `EMAIL_ALREADY_REGISTERED` | Email already registered | An account with that email address already exists. |
| `ROOM_UNAVAILABLE` | Room unavailable | No room of the requested type is available for those dates. |
| `INVALID_STATUS_TRANSITION` | Invalid status transition | A reservation with status {status} cannot be {action}. |
| `CANCELLATION_WINDOW_CLOSED` | Cancellation window closed | The free-cancellation window for this reservation has closed. |
| `ROOM_NUMBER_IN_USE` | Room number in use | That room number already exists at this property. |
| `SLUG_IN_USE` | Slug in use | That slug is already in use by another property. |
| `PAYMENT_DECLINED` | Payment declined | The payment was declined. |
| `RATE_LIMITED` | Rate limited | Too many attempts. Try again later. |
| `INTERNAL_ERROR` | Internal error | An unexpected error occurred. |

`detail` is **not** what the user sees — each frontend maps `code` to its own copy via its
`error-handling.md`. These strings exist so the two backends produce identical bodies and so a
`curl` response is self-explanatory.

### `errors[]` field codes

Only for `VALIDATION_FAILED`. `field` is the **JSON** field name in `camelCase`, matching what
the client sent, because both frontends apply these to form controls by name — a `field` of
`check_out_date` would silently fail to attach to anything.

| Field `code` | Meaning |
|--------------|---------|
| `REQUIRED` | Absent or null where required |
| `MIN` / `MAX` | Outside the permitted numeric or length bound |
| `AFTER_CHECK_IN` | `checkOutDate` not after `checkInDate` |
| `PAST_DATE` | A date before today in the property's timezone |
| `MAX_STAY` | Stay exceeds 30 nights |
| `INVALID_EMAIL` | Not a well-formed address |
| `INVALID_FORMAT` | Fails a format rule — Luhn, UUID, IANA zone, ISO country |
| `OUT_OF_RANGE` | Outside an allowed set or interval |
| `UNKNOWN_FIELD` | A field the endpoint does not accept |

For a nested field, `field` is dotted from the request root: `payment.cardNumber`,
`address.postalCode`.

---

## 3. Mapping rules that must not diverge

Where two independent implementations most easily disagree. Each is a required test in both
backends.

### SQLSTATE → HTTP

The database is the arbiter for several invariants, so its error codes are part of the API's
behavior.

| SQLSTATE | Constraint | Becomes |
|----------|-----------|---------|
| `23P01` | `reservations_no_overlap_excl` | `409 ROOM_UNAVAILABLE` — **after** allocation retries are exhausted |
| `23505` | `users_email_lower_key` | `409 EMAIL_ALREADY_REGISTERED` |
| `23505` | `rooms_property_number_key` | `409 ROOM_NUMBER_IN_USE` |
| `23505` | `properties_slug_key` | `409 SLUG_IN_USE` |
| `23505` | `reservations_confirmation_number_key` | **Never surfaces.** Regenerate and retry |
| `23505` | `room_types_property_name_key` | `409` with `detail` naming the duplicate |
| `23503` | any foreign key | `400 VALIDATION_FAILED` on the referencing field |
| `23514` | any `CHECK` | `400 VALIDATION_FAILED` — reaching one means application validation has a gap |
| `23502` | `NOT NULL` | `400 VALIDATION_FAILED` |
| anything else | — | `500 INTERNAL_ERROR` |

**Map on the constraint name, not on the SQLSTATE alone.** Four different unique violations
share `23505`, and a handler that returns `EMAIL_ALREADY_REGISTERED` for a duplicate room
number is the predictable outcome of branching on the code alone.

**A `23514` `CHECK` violation reaching a client is a bug**, not a validation path. The
constraints in [data-model.md](../../shared/data-model.md) are a backstop; application
validation should have rejected it first. Return `400`, and log at `warn` — it means a
validation rule is missing.

### The no-overbooking path, precisely

The project's central guarantee, and the one place a retry loop is part of the contract:

1. Select candidate rooms of the requested type at the property: not out of service, no
   overlapping non-cancelled reservation. Order by `room_number` ascending, natural sort.
2. No candidates → `409 ROOM_UNAVAILABLE` without attempting an insert.
3. Insert the reservation for the first candidate, **inside the transaction** that also inserts
   the payment.
4. `23P01` → the room was taken between the read and the insert. Roll back, drop that candidate,
   retry from step 3 with the next.
5. **Three attempts**, then `409 ROOM_UNAVAILABLE`.

Per
[api-contracts.md](../../shared/api-contracts.md#get-availability--public) and required by
[AC-OB-01](../../shared/acceptance-criteria.md#ac-ob-01--two-concurrent-bookings-for-the-last-room-exactly-one-wins)
and
[AC-OB-07](../../shared/acceptance-criteria.md#ac-ob-07--allocation-order-is-deterministic).
The retry count and the ordering are both normative: they are what make two concurrent bookings
produce exactly one `201` and one `409`, identically in either backend.

### Ownership: `404` versus `403`

Asymmetric on purpose, and the asymmetry is the security control:

| Caller | Situation | Response |
|--------|-----------|----------|
| Guest | Another guest's reservation | **`404 NOT_FOUND`** |
| Guest | An admin endpoint | `403 INSUFFICIENT_ROLE` |
| Front-desk staff | Another property's resource | **`403 PROPERTY_OUT_OF_SCOPE`** |
| Front-desk staff | A manager-only endpoint | `403 INSUFFICIENT_ROLE` |

A `403` to the guest would confirm the reservation exists — an enumeration oracle over other
guests' bookings. Staff get the honest `403` because they are trusted principals and a
misleading `404` sends them chasing a data problem. Reasoning in
[security-principles.md](../../shared/security-principles.md#authorization); required by
[AC-AZ-01](../../shared/acceptance-criteria.md#ac-az-01--a-guest-cannot-read-another-guests-reservation)
and
[AC-AZ-05](../../shared/acceptance-criteria.md#ac-az-05--front-desk-staff-cannot-reach-another-property).

**The ownership check must precede the mutation.** A handler that cancels and then checks
ownership returns `404` and has still cancelled the booking —
[AC-AZ-03](../../shared/acceptance-criteria.md#ac-az-03--a-guest-cannot-cancel-another-guests-reservation)
asserts the reservation is unchanged, not merely that the status code is right.

### Order of checks

Normative, because it determines what an unauthorized caller can learn:

```
1. Rate limit        → 429
2. Authentication    → 401
3. Account active    → 403 ACCOUNT_INACTIVE
4. Role rank         → 403 INSUFFICIENT_ROLE
5. Property scope    → 403 PROPERTY_OUT_OF_SCOPE
6. Request validation→ 400
7. Existence + ownership → 404
8. Business rules    → 409 / 402
```

Validation comes **after** authorization, so an unauthenticated caller never learns whether
their body was well-formed. Reversing 6 and 7 would leak existence through validation
messages.

### Timing equality on login

`INVALID_CREDENTIALS` must take comparable time whether the email exists or not: verify the
submitted password against a **dummy bcrypt hash** when no user is found. Skipping the hash on
the unknown-email path returns in ~2 ms against ~200 ms, which is a usable account oracle.
Required by
[AC-SE-10](../../shared/acceptance-criteria.md#ac-se-10--credential-errors-do-not-reveal-whether-an-account-exists).

---

## 4. `traceId` and logging

One `traceId` per request — a UUID generated at ingress, put in the response body of every
error, and attached to **every** log line for that request.

| Rule | Why |
|------|-----|
| Generated once, at ingress | A second id per layer breaks correlation |
| Present on every log line for the request | It is the only way to reassemble a request's log |
| Returned in every Problem Details body | Lets a user's "Reference: …" reach the right log |
| Never derived from a client-supplied header | A client-controlled correlation id is a log-injection vector |

**`500 INTERNAL_ERROR` logs the full cause at `error` and returns none of it.** The stack trace,
the exception class, the SQL — all to the log, none to the client, with `traceId` as the bridge.
That is the whole point of the generic `detail`: it costs nothing in debuggability because the
`traceId` recovers everything.

Masking obligations, per
[security-principles.md](../../shared/security-principles.md#logging-and-data-handling) — never
logged at any level: the `Cookie` and `Set-Cookie` headers, raw session tokens,
`payment.cardNumber`, `payment.cvv`, `payment.expiryMonth`, `payment.expiryYear`, `password`,
`currentPassword`, `newPassword`, and `password_hash`. Masking is configured at the framework
level, not per handler, so a new endpoint inherits it. Detail in
[logging-observability.md](./logging-observability.md).

**Request-body logging is disabled on `POST /reservations` specifically**, regardless of level.
It is the one endpoint whose body contains card-shaped input, and one well-meaning "log the
request" during debugging is the realistic way that data gets written to disk.

---

## 5. What must never happen

| Never | Why |
|-------|-----|
| A framework's default error page or JSON shape | Both frontends parse `problem+json` and branch on `code`; a default body has neither |
| A stack trace, SQL, class name, or file path in `detail` | Information disclosure — [security-principles.md](../../shared/security-principles.md#logging-and-data-handling) |
| `200` with an error-shaped body | Clients branch on status first |
| A `500` for a condition with a real code | Hides a handled case as an outage and loses the client's ability to respond |
| A bare `409` without a `code` | The client cannot distinguish "room gone" from "already cancelled" |
| An unhandled promise rejection or uncaught exception escaping the handler | Produces a framework default body, or no response at all |
| Swallowing an error to return an empty success | The worst failure mode available: the client shows success for work that did not happen |
| A `4xx` logged at `error` | Client errors are routine; logging them at `error` makes the log useless. `warn` at most, `info` typically |
| A `5xx` **not** logged at `error` | The inverse, and worse |

---

## 6. Spring Boot implementation

Java, Spring Boot, Spring Data JPA. Structure per
[architecture-specification.md](./architecture-specification.md).

### Where each layer lives

| Concern | Location |
|---------|----------|
| `traceId` generation | `web/TraceIdFilter` — ordered first, puts the id in the MDC |
| Schema validation | Bean Validation annotations on request DTOs, plus `@Validated` on controllers |
| Domain failures | `AppException` subclasses thrown from the service layer |
| JPA / SQL translation | `web/ProblemDetailExceptionHandler` |
| Problem Details serialization | the same `@RestControllerAdvice` |

### The advantage, and the trap

**Spring Boot produces RFC 9457 `ProblemDetail` natively**, which is why that format was chosen
in [api-contracts.md](../../shared/api-contracts.md#error-responses). The trap is that the
built-in behavior is *close* to this contract without matching it: it omits `code` and `traceId`,
and its `detail` strings are Spring's, not the table in section 2. So the defaults must be
overridden rather than relied on — an endpoint that falls through to Spring's default handling
returns a body both frontends will mis-parse.

```java
@RestControllerAdvice
class ProblemDetailExceptionHandler extends ResponseEntityExceptionHandler {

  @ExceptionHandler(AppException.class)
  ResponseEntity<ProblemDetail> handle(AppException ex, HttpServletRequest req) {
    return ResponseEntity.status(ex.status())
        .contentType(MediaType.APPLICATION_PROBLEM_JSON)
        .body(problem(ex.status(), ex.code(), ex.detail(), req, ex.fieldErrors()));
  }
}
```

`extends ResponseEntityExceptionHandler` then overriding its hooks is what stops Spring's own
`MethodArgumentNotValidException` handling from emitting a non-conforming body.

**Set `spring.mvc.problemdetails.enabled=false`.** Leaving it on gives two competing sources of
problem documents, and which one answers depends on the exception path — so some errors carry
`code` and some do not.

### The error type

```java
public class AppException extends RuntimeException {
  private final int status;
  private final ProblemCode code;
  private final List<FieldError> fieldErrors;
}

public class NotFoundException extends AppException { /* 404 NOT_FOUND */ }
public class RoomUnavailableException extends AppException { /* 409 ROOM_UNAVAILABLE */ }
public class InvalidStatusTransitionException extends AppException { /* 409 */ }
public class CancellationWindowClosedException extends AppException { /* 409 */ }
```

`RuntimeException`, not a checked exception: a checked exception would force `throws` clauses
through the service interfaces and invite someone to catch and swallow it to keep a signature
clean.

**Services throw; they never return a response shape.** See
[architecture-specification.md](./architecture-specification.md#layering).

### Bean Validation → `VALIDATION_FAILED`

```java
@Override
protected ResponseEntity<Object> handleMethodArgumentNotValid(
    MethodArgumentNotValidException ex, HttpHeaders h, HttpStatusCode s, WebRequest req) {
  var errors = ex.getBindingResult().getFieldErrors().stream()
      .map(fe -> new FieldError(fe.getField(), mapCode(fe), fe.getDefaultMessage()))
      .toList();
  return problemResponse(400, VALIDATION_FAILED, …, errors);
}
```

`fe.getField()` already yields the dotted path (`payment.cardNumber`) that section 2 requires.

Two Jackson settings are load-bearing, not preferences:

| Setting | Why |
|---------|-----|
| `spring.jackson.deserialization.fail-on-unknown-properties=true` | The reject-unknown-fields rule. Off by default, and silently accepting unknown fields violates [api-contracts.md](../../shared/api-contracts.md#request-validation) |
| `@JsonInclude(NON_NULL)` on the Problem Details type **only** | Keeps `errors` out of non-validation bodies rather than emitting `"errors": null`. **Do not set this globally** — `spring.jackson.default-property-inclusion` must stay `always`, or nullable data fields are omitted and this backend disagrees on the wire with the Node one. See [api-contracts.md](../../shared/api-contracts.md#conventions) |

`HttpMessageNotReadableException` must also be handled: unknown-field rejection surfaces there,
not as a `MethodArgumentNotValidException`, and unhandled it becomes a `400` with Spring's own
body and no `code`.

### JPA / SQL → Problem Details

Hibernate wraps the driver exception, so the cause chain must be walked to reach the SQLSTATE:

```java
@ExceptionHandler(DataIntegrityViolationException.class)
ResponseEntity<ProblemDetail> handle(DataIntegrityViolationException ex, HttpServletRequest req) {
  var sql = findCause(ex, SQLException.class);
  var state = sql != null ? sql.getSQLState() : null;
  var constraint = constraintNameOf(ex);          // from ConstraintViolationException
  return switch (state) {
    case "23P01" -> problem(409, ROOM_UNAVAILABLE, …);
    case "23505" -> switch (constraint) {
        case "users_email_lower_key"      -> problem(409, EMAIL_ALREADY_REGISTERED, …);
        case "rooms_property_number_key"  -> problem(409, ROOM_NUMBER_IN_USE, …);
        case "properties_slug_key"        -> problem(409, SLUG_IN_USE, …);
        default -> problem(409, …);
      };
    case "23503", "23502", "23514" -> problem(400, VALIDATION_FAILED, …);
    default -> problem(500, INTERNAL_ERROR, …);
  };
}
```

> **This stack has the cleaner path on the exclusion constraint.** The PostgreSQL JDBC driver
> exposes SQLSTATE as structured data via `SQLException.getSQLState()`, so `23P01` is matched on a
> value rather than on message text — where the Node side must currently pattern-match a message
> because Prisma has no mapped code for it (see that stack's
> [error-handling.md](../nodejs/error-handling.md)).
>
> Two caveats keep this from being free. Hibernate wraps the cause two or three levels deep, so
> `findCause` must walk the chain rather than calling `getCause()` once. And
> `org.hibernate.exception.ConstraintViolationException` — the source of the constraint name — is
> easy to confuse with `jakarta.validation.ConstraintViolationException`, which is Bean Validation
> and an entirely different condition. Importing the wrong one compiles and then never matches.

### Transactions

`@Transactional` on the **service** method, never the controller or the repository — the boundary
rule from
[architecture-specification.md](./architecture-specification.md#layering).

Two Spring-specific traps around the allocation retry:

**The retry must be outside the transaction.** Once a transaction is marked rollback-only,
continuing inside it throws `UnexpectedRollbackException` at commit. So the retry loop lives in a
method that is *not* `@Transactional` and calls a `@Transactional` one:

```java
public Reservation book(BookingRequest r) {
  for (Room room : candidates(r).stream().limit(3).toList()) {
    try { return txService.createReservation(room, r); }
    catch (DataIntegrityViolationException e) {
      if (isExclusionViolation(e)) continue;
      throw e;
    }
  }
  throw new RoomUnavailableException();
}
```

**Self-invocation defeats `@Transactional`.** Calling `this.createReservation(...)` bypasses the
proxy and runs with no transaction at all — the insert and the payment insert would then not be
atomic. Inject the transactional component as a separate bean, as above.

Also: `DataIntegrityViolationException` may be thrown at **flush** rather than at the repository
call, which with JPA's deferred flushing can be at commit — so the `catch` must wrap the whole
transactional call, not just a `save()`.

### The final safety net

```java
@ExceptionHandler(Exception.class)
ResponseEntity<ProblemDetail> handleUnexpected(Exception ex, HttpServletRequest req) {
  log.error("Unhandled exception [traceId={}]", MDC.get("traceId"), ex);
  return problem(500, INTERNAL_ERROR, "An unexpected error occurred.", req, null);
}
```

Registered last by ordering. It logs the full stack and returns none of it.

**Spring Security exceptions bypass `@RestControllerAdvice`** — they are raised in the filter
chain, before the dispatcher servlet. So `AuthenticationEntryPoint` and `AccessDeniedHandler` must
be configured to emit the same Problem Details shape, or `401` and `403` responses come back in
Spring Security's default format while every other error conforms. This is the single most likely
way this stack ends up non-conforming, because the misses are on the two most common error codes
and neither shows up in a happy-path test.
