# Module Registry — Node / Express

Inventory of `hotelapp-server-nodejs`'s modules and what each owns.

**This is bookkeeping, not design.** Everything here derives from the layering and folder layout in
[architecture-specification.md](./architecture-specification.md#folder-layout) and the endpoint list in
[api-contracts.md](../../shared/api-contracts.md). If this document and either of those disagree, they
are right and this is stale.

Its purpose is orientation: a developer or coding agent asking "where does X live" should find the
answer here without reading the tree.

---

## Entry point and configuration

| Module | Owns | Must not |
|--------|------|----------|
| `server.ts` | App assembly, **middleware order**, listen, graceful shutdown | Contain business logic. Middleware order is normative — [architecture-specification.md](./architecture-specification.md#middleware-order) |
| `config/env.ts` | Reading and validating every environment variable, once, at startup | Be bypassed — `process.env` is read nowhere else |
| `db/client.ts` | The `PrismaClient` singleton | Be constructed a second time anywhere |
| `openapi/spec.ts` | The hand-maintained OpenAPI 3.1 document | Be generated — [architecture-specification.md](./architecture-specification.md#openapi) |

---

## Middleware

Registration order matters and is fixed. Listed in that order.

| Module | Owns |
|--------|------|
| `middleware/requestContext.ts` | `traceId` generation and the `AsyncLocalStorage` store. **First** |
| `middleware/requestLogger.ts` | One line per request: method, route pattern, status, duration. **Never bodies** |
| `middleware/rateLimit.ts` | 10 attempts / 15 min, keyed on IP **and** email, on the two auth routes |
| `middleware/session.ts` | Cookie → hash → `sessions` **joined to `users`** → validity → sliding expiry → `req.context` |
| `middleware/authorize.ts` | `requireGuest` / `requireStaff` / `requireManager`, by **rank** |
| `middleware/validate.ts` | Zod validation of body, query, and params |
| `middleware/errorHandler.ts` | `AppError` / `ZodError` / Prisma error → Problem Details. **Last, four arguments** |

The two that carry the most consequence: `session.ts` reads `role` and `is_active` from the joined user
row on every request, which is what makes deactivation immediate
([AC-AZ-11](../../shared/acceptance-criteria.md#ac-az-11--inactive-accounts-cannot-authenticate)); and
`errorHandler.ts` registered anywhere but last silently never runs.

---

## Routes → endpoints

All 42 endpoints from
[api-contracts.md](../../shared/api-contracts.md#endpoint-index).

| Module | Endpoints |
|--------|-----------|
| `routes/auth.routes.ts` | `POST /auth/register`, `/auth/login`, `/auth/logout`, `GET /auth/me` |
| `routes/properties.routes.ts` | `GET /properties`, `/properties/{id}`, `/properties/{id}/room-types`, `/room-types/{id}`, `/amenities`, `/rate-categories` |
| `routes/availability.routes.ts` | `GET /availability` |
| `routes/me.routes.ts` | `GET /me`, `PATCH /me`, `PUT /me/password` |
| `routes/reservations.routes.ts` | `GET`/`POST /reservations`, `GET`/`PATCH /reservations/{id}`, `POST /reservations/{id}/cancel` |
| `routes/admin/reservations.routes.ts` | `GET /admin/reservations`, `/{id}`, `POST .../check-in`, `.../check-out`, `.../cancel` |
| `routes/admin/inventory.routes.ts` | Admin properties, room types, amenities, photos, rooms — 12 endpoints |
| `routes/admin/ratePlans.routes.ts` | `GET`/`PUT /admin/properties/{id}/rate-plans` |
| `routes/admin/calendar.routes.ts` | `GET /admin/properties/{id}/calendar` |
| `routes/admin/reports.routes.ts` | `GET .../reports/occupancy`, `.../reports/arrivals` |
| `routes/health.routes.ts` | `GET /health` |

---

## Services

One per feature. Owns transaction boundaries; knows nothing about HTTP.

| Module | Owns |
|--------|------|
| `authService.ts` | Register, login, logout. **Dummy-hash timing equality** on unknown email |
| `sessionService.ts` | Token generation, hashing, validation, sliding expiry, revocation cascades |
| `propertyService.ts` | Public catalogue reads |
| `availabilityService.ts` | The availability query and price resolution per result |
| `bookingService.ts` | **The allocation retry loop, outside the transaction** |
| `reservationService.ts` | Guest reservation reads, modification, cancellation, refund determination |
| `adminReservationService.ts` | Admin list, check-in, check-out, staff cancel with fee waiver |
| `inventoryService.ts` | Properties, room types, photos, rooms |
| `ratePlanService.ts` | Whole-set rate-plan replacement |
| `calendarService.ts` | Segment assembly for the room/rate calendar |
| `reportService.ts` | Occupancy and arrivals |

`bookingService.ts` is the one worth reading first: the retry-outside-transaction structure in
[error-handling.md](./error-handling.md#the-no-overbooking-path-precisely) is the project's central
guarantee expressed in code.

---

## Domain — pure functions, no I/O

**The most important folder in the repo.** These four rules must agree with their Java counterparts to
the cent and to the second.

| Module | Owns | Pinned by |
|--------|------|-----------|
| `domain/pricing.ts` | Discount resolution, **round the nightly rate then multiply** | [AC-CX-10](../../shared/acceptance-criteria.md#ac-cx-10--pricing-arithmetic-and-rounding-order) |
| `domain/cancellation.ts` | Deadline = check-in midnight in the property's zone **minus exactly 172,800 s** | [AC-CX-04](../../shared/acceptance-criteria.md#ac-cx-04--deadline-respects-the-propertys-timezone-not-the-servers), [AC-CX-05](../../shared/acceptance-criteria.md#ac-cx-05--dst-transition-does-not-shift-the-deadline-arithmetic) |
| `domain/allocation.ts` | Candidate ordering: lowest `room_number`, natural sort | [AC-OB-07](../../shared/acceptance-criteria.md#ac-ob-07--allocation-order-is-deterministic) |
| `domain/status.ts` | Legal transitions | [AC-CX-09](../../shared/acceptance-criteria.md#ac-cx-09--illegal-cancellations-are-rejected) |

**No I/O, no Prisma, no Express, no `Date.now()`.** A time source is a parameter. If a rule is hard to
unit test here, it has leaked back into a service.

**The `AppError` hierarchy (`errors/errors.ts`) is not here** — it computes nothing, and lives in
its own folder. See "Error handling architecture" in
[architecture-specification.md](./architecture-specification.md#error-handling-architecture).

---

## Repositories

Each takes `Db = PrismaClient | Prisma.TransactionClient` as its first argument, so the **service** owns
the transaction boundary.

`userRepo` · `sessionRepo` · `propertyRepo` · `roomTypeRepo` · `roomRepo` · `reservationRepo` ·
`paymentRepo` · `ratePlanRepo` · `amenityRepo`

| Rule | Why |
|------|-----|
| Always `select` explicitly | A bare `findMany` pulls `password_hash` and `token_hash` into memory |
| Never open a transaction | Breaks the service's ownership |
| Never import the global client | Silently escapes the caller's transaction |

`reservationRepo` holds the two hand-written queries — the availability anti-join and the calendar
segment query — both fully parameterized.

---

## Ownership of the tricky bits

Where the things most likely to be reimplemented in the wrong place actually live.

| Concern | Sole owner |
|---------|-----------|
| Session token generation and hashing | `services/sessionService.ts` |
| The 5-minute `expires_at` write-throttle | `middleware/session.ts` |
| Rank comparison (not set membership) | `middleware/authorize.ts` |
| `traceId` generation and propagation | `middleware/requestContext.ts` |
| Prisma error → `AppError` | `db/prismaErrors.ts` |
| **Exclusion-constraint (`23P01`) detection** | `db/prismaErrors.ts` — and see below |
| The allocation retry | `services/bookingService.ts`, outside the transaction |
| Pricing arithmetic and rounding order | `domain/pricing.ts` |
| Cancellation-deadline computation | `domain/cancellation.ts` |
| Confirmation-number generation and collision retry | `services/bookingService.ts` |
| `Prisma.Decimal` → decimal string | `dto/` mappers |
| Log redaction | `lib/logger.ts`, via pino `redact` |
| Every environment variable | `config/env.ts` |

> **`db/prismaErrors.ts` is the most fragile module in this backend**, and it is fragile because of the
> migration asymmetry rather than because of anything in this repo. Prisma has no mapped error code for
> SQLSTATE `23P01`, so detection depends on a raw-query error code or on message text —
> [error-handling.md](./error-handling.md#prisma--problem-details).
>
> The integrity guarantee does **not** live here; it lives in the database constraint, and a
> double-booking is impossible regardless of how this module classifies the error. What lives here is
> whether the client gets `409 ROOM_UNAVAILABLE` or `500 INTERNAL_ERROR` — fail-closed either way.
>
> Its guards are
> [AC-OB-01](../../shared/acceptance-criteria.md#ac-ob-01--two-concurrent-bookings-for-the-last-room-exactly-one-wins)
> against real PostgreSQL, and the unmapped-SQLSTATE log line in
> [logging-observability.md](./logging-observability.md#the-exclusion-constraint-detection-canary).
> A Prisma upgrade is the event that would break it.

---

## Generated, not authored

Two artifacts in this repo are outputs rather than sources, which is unusual enough to state:

| Artifact | Produced by | Never |
|----------|------------|-------|
| `prisma/schema.prisma` | `prisma db pull` against a migrated database | Hand-edited to introduce a schema change |
| `node_modules/.prisma/client` | `prisma generate` | Committed |

And one thing that does **not** exist in this repo, deliberately: **`prisma/migrations/`**. Flyway is the
sole DDL executor — [versioning-strategy.md](../../shared/versioning-strategy.md#database-schema-migrations).
Its absence is the decision, so a directory appearing there is a regression rather than an addition.
