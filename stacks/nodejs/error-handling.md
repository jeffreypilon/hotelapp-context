# Error Handling — Node / Express

How `hotelapp-server-nodejs` produces RFC 9457 Problem Details responses.

> ### Sections 1–5 are shared, verbatim, with the other backend
>
> **Sections 1 through 5 below are byte-identical to
> [`stacks/springboot/error-handling.md`](../springboot/error-handling.md).** The two backends must be
> byte-for-byte interchangeable on the wire: the same condition must produce the same status, the
> same `code`, the same `title`, and the same `detail` from either implementation, or the OpenAPI
> diff passes while the two backends behave differently — which is the failure this whole project
> is organized against.
>
> **Any diff in sections 1–5 is a defect.** Section 6 holds the Node / Express implementation and is the
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

## 6. Node / Express implementation

TypeScript, Express, Prisma. Structure per
[architecture-specification.md](./architecture-specification.md).

### Where each layer lives

| Concern | Location |
|---------|----------|
| `traceId` generation | `middleware/requestContext.ts` — first middleware registered |
| Schema validation | Zod schemas per route, in `routes/*/schema.ts` |
| Domain failures | `AppError` subclasses thrown from the service layer |
| Prisma error translation | `db/prismaErrors.ts` |
| Problem Details serialization | `middleware/errorHandler.ts` — **last** middleware registered |

### The error type

One class hierarchy, so a service throws a meaning rather than assembling a response:

```ts
export class AppError extends Error {
  constructor(
    readonly status: number,
    readonly code: ProblemCode,
    readonly detail: string,
    readonly errors?: FieldError[],
  ) { super(detail); }
}

export class NotFoundError extends AppError {
  constructor(resource: string) { super(404, 'NOT_FOUND', `The requested ${resource} was not found.`); }
}
export class RoomUnavailableError extends AppError { /* 409 ROOM_UNAVAILABLE */ }
export class InvalidStatusTransitionError extends AppError { /* 409 */ }
export class CancellationWindowClosedError extends AppError { /* 409 */ }
```

**Services throw; they never return a response shape.** A service that returns
`{ ok: false, status: 409 }` has moved HTTP concerns into the layer that must not know about
them — see
[architecture-specification.md](./architecture-specification.md#layering).

### The error middleware

```ts
export function errorHandler(err: unknown, req: Request, res: Response, _next: NextFunction) {
  const traceId = req.context.traceId;
  const problem = toProblem(err, req, traceId);   // AppError | ZodError | Prisma error | unknown
  if (problem.status >= 500) logger.error('request failed', { traceId, err });
  else logger.warn('request rejected', { traceId, code: problem.code, status: problem.status });
  res.status(problem.status)
     .type('application/problem+json')
     .json(problem);
}
```

`.type('application/problem+json')` is explicit. Express defaults `res.json` to
`application/json`, and a client checking the content type would not see a problem document.

**Three Express-specific hazards, each a real source of a wrong response:**

1. **The error handler must be registered last**, after every route and every other middleware.
   Registered earlier, it never runs and Express's default HTML error page is returned instead.
2. **Express 4 does not forward async rejections.** An `async` handler that rejects produces an
   unhandled rejection and a hung request, not a `500`. Either wrap every async handler in a
   `catchAsync` helper or run on Express 5, where rejections propagate to the error middleware.
   **Pick one and apply it to every route** — a single unwrapped handler is a request that hangs.
3. **A four-argument signature is required.** `(err, req, res, next)` is how Express recognizes an
   error handler; drop the fourth parameter and it silently becomes ordinary middleware.

### Zod → `VALIDATION_FAILED`

```ts
function fromZod(e: ZodError): AppError {
  const errors = e.issues.map(i => ({
    field: i.path.join('.'),                 // -> "payment.cardNumber"
    code: mapZodCode(i),                     // -> REQUIRED | MIN | INVALID_FORMAT | UNKNOWN_FIELD
    message: i.message,
  }));
  return new AppError(400, 'VALIDATION_FAILED',
    `The request body contains ${errors.length} invalid field(s).`, errors);
}
```

`i.path.join('.')` yields the dotted path section 2 requires. Use `.strict()` on every object
schema so an unknown key raises `unrecognized_keys` → `UNKNOWN_FIELD`; without it Zod strips
unknown keys silently, which violates the reject-unknown-fields rule in
[api-contracts.md](../../shared/api-contracts.md#request-validation).

### Prisma → Problem Details

Prisma wraps database errors, so the constraint name must be dug out rather than read off:

```ts
export function fromPrisma(e: unknown): AppError | null {
  if (e instanceof Prisma.PrismaClientKnownRequestError) {
    if (e.code === 'P2002') {                       // unique violation (SQLSTATE 23505)
      const target = String(e.meta?.target ?? '');
      if (target.includes('email'))        return new AppError(409, 'EMAIL_ALREADY_REGISTERED', …);
      if (target.includes('room_number')) return new AppError(409, 'ROOM_NUMBER_IN_USE', …);
      if (target.includes('slug'))         return new AppError(409, 'SLUG_IN_USE', …);
    }
    if (e.code === 'P2003') return validationFailed(…);   // FK violation
    if (e.code === 'P2025') return new NotFoundError(…);
  }
  if (isExclusionViolation(e)) return new RoomUnavailableError();
  return null;                                            // -> 500
}
```

> **The exclusion constraint is the hard case in this stack, and it needs stating plainly.**
> Prisma has **no dedicated error code for an exclusion-constraint violation** — `23P01` is not
> one of its mapped `P2xxx` codes. It surfaces as a `PrismaClientUnknownRequestError` whose
> message text contains the SQLSTATE and the constraint name. So `isExclusionViolation` matches on
> the message, which is brittle in exactly the way this project tries to avoid.
>
> **Two mitigations, both required.** First, prefer issuing the reservation insert through
> `$queryRaw` inside the transaction, where the driver's error carries a structured `code` field
> and the check becomes `code === '23P01'` rather than a string match. Second — and regardless —
> [AC-OB-01](../../shared/acceptance-criteria.md#ac-ob-01--two-concurrent-bookings-for-the-last-room-exactly-one-wins)
> must be a real integration test against real PostgreSQL, because it is the only thing that will
> catch this detection breaking after a Prisma upgrade. A unit test with a mocked Prisma client
> would pass while the guarantee was gone.
>
> This is a direct consequence of the migration-ownership decision in
> [versioning-strategy.md](../../shared/versioning-strategy.md#database-schema-migrations): the
> constraint is applied by Flyway and Prisma only introspects it, so Prisma has no model of it and
> cannot give a typed error for it. The Spring Boot side has a cleaner path here — the asymmetry
> is real and is the price already named in that document.

### Transactions

`prisma.$transaction(async tx => { … })`. Throwing inside rolls back. The allocation retry from
section 3 is **around** the transaction, not inside it — a rolled-back transaction cannot be
continued:

```ts
for (const room of candidates.slice(0, 3)) {
  try { return await prisma.$transaction(tx => createReservation(tx, room, input)); }
  catch (e) { if (isExclusionViolation(e)) continue; throw e; }
}
throw new RoomUnavailableError();
```

### The final safety net

```ts
process.on('unhandledRejection', (reason) => { logger.error('unhandled rejection', { reason }); process.exit(1); });
process.on('uncaughtException',  (err)    => { logger.error('uncaught exception', { err });    process.exit(1); });
```

Exit rather than continue: a process that has thrown outside a request is in an unknown state, and
serving further requests from it risks wrong answers rather than visible failures. A supervisor
restarts it. These handlers exist to make the failure loud and logged, not to recover.
