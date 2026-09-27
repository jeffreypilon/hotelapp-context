# Coding Standards — Node / Express

Conventions for `hotelapp-server-nodejs`. TypeScript, Express, Prisma.

Naming that crosses layers — JSON, SQL, URLs, enum values, booleans, dates, money — is fixed in
[glossary-of-conventions.md](../../shared/glossary-of-conventions.md#the-identifier-casing-rule) and
is **not** re-derived here. Layering and folder layout are fixed in
[architecture-specification.md](./architecture-specification.md). This document covers what those
two leave open.

---

## TypeScript

`strict: true`, plus `noUncheckedIndexedAccess`, `noImplicitOverride`, and
`exactOptionalPropertyTypes`. **`any` is a review finding.**

That matters more here than in the frontends, for a specific reason: `schema.prisma` is a
**generated** artifact regenerated from the database
([architecture-specification.md](./architecture-specification.md#the-migration-asymmetry-and-what-it-means-for-this-repo)),
so the Prisma client's types change when the schema changes. The compiler is the mechanism that
turns a schema change into a build error rather than a runtime surprise, and `any` disables exactly
that.

| Rule | Detail |
|------|--------|
| `type` over `interface` | `interface` only where declaration merging is needed — nowhere here |
| No TypeScript `enum` | `as const` objects or string-literal unions; they match the API's string values directly |
| Contract enums | Unions mirroring PostgreSQL exactly: `type Role = 'GUEST' \| 'FRONT_DESK_STAFF' \| 'PROPERTY_MANAGER'` |
| No default exports | Named only |
| Explicit return types on exported functions | Inferred locally |
| `import type` for type-only imports | Lets the transpiler drop them |
| No non-null `!` | Except immediately after an explicit guard |

**Money is `Prisma.Decimal` internally and a `string` on the wire. Never `number`, anywhere.**
Per
[glossary-of-conventions.md](../../shared/glossary-of-conventions.md#money-dates-and-formatting-in-code).
`Number(decimal)` and `decimal.toNumber()` are both review findings — the value came from
`numeric(10,2)` and must reach the DTO mapper intact.

**Dates: `Date` for `timestamptz`, a `YYYY-MM-DD` string for `date` columns.** Never construct a
`Date` from a date-only string and read its local components — that shifts the day for half the
world's timezones, and the "dates only, no times" rule from
[project-overview.md](../../shared/project-overview.md) makes it a business-logic bug rather than a
formatting one.

---

## Module and file conventions

| Thing | Convention | Example |
|-------|-----------|---------|
| Route module | `<feature>.routes.ts` | `reservations.routes.ts` |
| Service | `<feature>Service.ts` | `bookingService.ts` |
| Repository | `<entity>Repo.ts` | `reservationRepo.ts` |
| Domain module | `<rule>.ts`, pure | `pricing.ts` |
| DTO | `<feature>.dto.ts` | `reservation.dto.ts` |
| Middleware | `camelCase.ts` | `errorHandler.ts` |
| Test | `<subject>.test.ts`, beside the subject or under `test/` | `pricing.test.ts` |
| Folder | `kebab-case` | `admin/` |

- **One exported concern per file.** A `services/index.ts` re-exporting everything defeats the
  layering by making every import look identical.
- **Functions, not classes**, for services and repositories. There is no state to encapsulate and no
  inheritance in play; a module of exported functions is the smaller idea. The one exception is the
  `AppError` hierarchy, where subclassing is the point.
- **Dependencies are parameters, not imports, where a test needs to substitute them.** A repository
  takes its `Db` client as its first argument, per
  [architecture-specification.md](./architecture-specification.md#layering); a service takes its
  time source. No DI container.

---

## Naming

| Thing | Convention |
|-------|-----------|
| Function, variable | `camelCase` |
| Type, class | `PascalCase` |
| Constant | `SCREAMING_SNAKE_CASE` |
| Boolean | `is` / `has` / `can` prefix |
| Async function | Named for what it returns, not `...Async` |
| Repository read | `findX` (nullable) / `getX` (throws `NotFoundError`) |
| Repository write | `insertX` / `updateX` / `deleteX` |
| Service method | The business action: `bookReservation`, `checkIn`, `cancelReservation` |

**The `find` / `get` distinction is load-bearing.** `findReservation` returns `Reservation | null`
and the caller decides; `getReservation` throws `NotFoundError`. Mixing them means every call site
re-decides how absence is handled, and the `404`-versus-`403` rule in
[error-handling.md](./error-handling.md#ownership-404-versus-403) depends on absence being handled
consistently.

Domain terms follow
[domain-glossary.md](../../shared/domain-glossary.md): `reservation`, never `booking`, for the
entity; `property`, never `hotel`.

---

## Async

- `async`/`await` throughout. No `.then()` chains, no callbacks.
- **Every `await` that can reject is either inside a `try` that maps the error, or allowed to
  propagate to the error middleware.** Never a bare `await` inside a `try {} catch {}` that
  swallows.
- **Every async route handler is wrapped** — `catchAsync` on Express 4, or Express 5 where
  rejections propagate. One unwrapped handler is one endpoint that hangs instead of returning `500`;
  see [architecture-specification.md](./architecture-specification.md#middleware-order).
- `Promise.all` for genuinely independent work; sequential `await` otherwise. Do not parallelize
  database calls inside one transaction — a Prisma transaction client is not safe for concurrent use.
- **No floating promises.** `@typescript-eslint/no-floating-promises` as an **error**: an unawaited
  promise is a silent failure, which section 5 of
  [error-handling.md](./error-handling.md#5-what-must-never-happen) forbids outright.

---

## Errors

- **Services throw `AppError` subclasses. Services never touch `res`.** See
  [error-handling.md](./error-handling.md).
- **Never `throw new Error('...')` for a condition with a code.** A bare `Error` becomes
  `500 INTERNAL_ERROR`, which hides a handled case as an outage.
- **Never catch to return a falsy success.** Returning `null` on failure pushes error handling to
  every call site and eventually to none.
- `catch (e: unknown)`, then narrow. Never `catch (e: any)`.
- Prisma errors are translated in **one** place, `db/prismaErrors.ts`. A second translation site is
  how `EMAIL_ALREADY_REGISTERED` ends up returned for a duplicate room number.

---

## Prisma

- **Always `select`, never a bare `findMany`.** Prisma returns every column by default, which pulls
  `password_hash` and `token_hash` into memory where they can reach a log or a response. An explicit
  `select` makes that impossible rather than unlikely.
- **`include` for relations**, in one query. The N+1 hazards are room-type photos and amenities.
- **Never `$executeRawUnsafe` or `$queryRawUnsafe` with interpolated input.** `$queryRaw` with tagged
  template parameters only. The single exception is the test-suite `TRUNCATE`, which takes no input.
- **Repositories accept `Db = PrismaClient | Prisma.TransactionClient`.** A repository importing the
  global client silently escapes its caller's transaction — the failure this convention exists to
  prevent.
- **`schema.prisma` is never hand-edited** to introduce a schema change. It is regenerated by
  `prisma db pull`. `Unsupported("daterange")` on `stay_period` is correct output and must not be
  "fixed".

---

## Validation

- **Zod schemas per route, in `routes/*/schema.ts`.** Validation happens once, at the HTTP boundary;
  services trust their inputs.
- **`.strict()` on every object schema.** Without it Zod strips unknown keys silently, which violates
  the reject-unknown-fields rule in
  [api-contracts.md](../../shared/api-contracts.md#request-validation) and would fail
  [AC-CC-02](../../shared/acceptance-criteria.md#ac-cc-02--unknown-request-fields-are-rejected).
- **Derive the request type from the schema** — `z.infer<typeof schema>` — so the two cannot drift.
- **Never accept a server-owned field.** `price`, `role`, `status`, `confirmationNumber`,
  `cancellationDeadline`, and every `*_at` are absent from every request schema. The absence *is* the
  control, and `.strict()` is what enforces it.

---

## Logging

- `logger` from `lib/logger.ts`. **`console.log` in committed code is a review finding.**
- Every log line carries the request's `traceId`, per
  [error-handling.md](./error-handling.md#4-traceid-and-logging).
- **Never log a request or response body.** Method, path, status, and duration only.
- Never log: `Cookie`, `Set-Cookie`, a session token, `password_hash`, `payment.cardNumber`,
  `payment.cvv`, `payment.expiry*`, or any `password` field. Masking is at the logger, not per call
  site. Detail in [logging-observability.md](./logging-observability.md).
- `4xx` at `warn` or `info`; `5xx` at `error`. Inverting this makes the log useless.

---

## Comments

Comment **why**, never **what**. Worth a comment in this codebase, because each is a decision a later
reader would otherwise "simplify" into a bug:

- Why the allocation retry is **outside** the transaction.
- Why the exclusion-constraint detection matches what it does, and that
  [AC-OB-01](../../shared/acceptance-criteria.md#ac-ob-01--two-concurrent-bookings-for-the-last-room-exactly-one-wins)
  is what guards it.
- Why the session `expires_at` write is throttled to 5 minutes.
- Why `role` is read from the joined user row rather than cached.
- Why the nightly rate is rounded **before** multiplying by nights.
- Why `schema.prisma` is not hand-edited.

No commented-out code. No `TODO` without an owner and a reason. No JSDoc restating a signature the
types already give.

---

## Forbidden

| Never | Why |
|-------|-----|
| `any`, `@ts-ignore` | See TypeScript above. `@ts-expect-error` with a reason is the narrow exception |
| `number` for money | Precision loss on `numeric(10,2)` |
| `console.log` | Use the logger |
| Returning a Prisma object from a route | Makes the API shape a function of the schema; risks leaking `password_hash` — [architecture-specification.md](./architecture-specification.md#dtos) |
| `$queryRawUnsafe` with input | SQL injection |
| A repository opening a transaction | Breaks the service's ownership of the boundary |
| `prisma migrate dev` / `deploy` | Prisma does not apply DDL — [versioning-strategy.md](../../shared/versioning-strategy.md#database-schema-migrations) |
| Hand-editing `schema.prisma` to change the schema | Same |
| `process.env` read outside `config/env.ts` | Unvalidated config reaching a URL as `undefined` |
| `undefined` in a DTO where the contract says nullable | `JSON.stringify` drops it, producing an absent field where `null` is required — [api-contracts.md](../../shared/api-contracts.md#conventions) |
| A second money or date formatter | One place, or the rule breaks quietly |
| A bare `throw new Error` for a known condition | Becomes a `500`, hiding a handled case |
| Business logic in a route handler | Wrong layer, and not comparable with the Spring Boot backend |
| `Date.now()` / `new Date()` inline in a service | Defeats the injectable clock the cancellation criteria need |
| Synchronous `fs` or `crypto` on the request path | Blocks the event loop |
| An unawaited promise | Silent failure |
