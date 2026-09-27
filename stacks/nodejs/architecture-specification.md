# Architecture Specification — Node / Express

Structure of `hotelapp-server-nodejs`: layering, folder layout, the data-access layer, and where
transactions begin and end.

TypeScript, Express, Prisma, PostgreSQL 18.6. The system-level shape — two frontends, two
backends, one database, REST as the only integration point — is in
[architecture-overview.md](../../shared/architecture-overview.md) and is not restated here.

---

## Fixed at the system level

| Constraint | Source |
|-----------|--------|
| Three layers: HTTP → service → data access | [architecture-overview.md](../../shared/architecture-overview.md#backend-architecture-in-outline) |
| Transactions begin and end in the **service** layer | same |
| **No ORM entity is ever serialized to JSON** — explicit DTOs only | same |
| Stateless process; all state in PostgreSQL, including sessions | same |
| Business logic in application code, not the database — one exception | same |
| The exception: no-overbooking, enforced by the exclusion constraint | [data-model.md](../../shared/data-model.md#no-overbooking) |
| **Prisma never applies DDL** | [versioning-strategy.md](../../shared/versioning-strategy.md#database-schema-migrations) |
| Publishes OpenAPI 3.1 at `/api/v1/openapi.json`, diffable against the other backend | [api-contracts.md](../../shared/api-contracts.md#cross-cutting-requirements) |

---

## The migration asymmetry, and what it means for this repo

> **This backend cannot migrate a database.** That is not a gap to fix; it is the consequence of a
> deliberate decision recorded in
> [versioning-strategy.md](../../shared/versioning-strategy.md#database-schema-migrations) and
> logged as a reversal in
> [decision-log.md](../../shared/decision-log.md) entry 3.
>
> **`hotelapp-context/shared/migrations/V<nnn>__*.sql` is the canonical schema. Flyway applies it.
> Prisma reads the result.** In this repository that means:
>
> - `prisma migrate dev` and `prisma migrate deploy` are **not used**. There is no
>   `prisma/migrations/` directory in this repo.
> - `schema.prisma` is a **generated artifact**, produced by `prisma db pull` against an
>   already-migrated database, then `prisma generate`. It is committed — so a clone can build
>   without a database — but it is never hand-edited to introduce a schema change.
> - `prisma migrate diff` is permitted as an *authoring aid* only: use it to draft candidate SQL
>   for a schema change, review the output by hand, and commit it to `hotelapp-context` as a
>   canonical `V<nnn>__*.sql`. Never apply it from here.
> - Standing up this backend against a fresh database **requires Flyway to have run first**, from
>   the Spring Boot repo or the standalone Flyway CLI against the context repo's SQL. Setup steps
>   in [environment-setup-guide.md](./environment-setup-guide.md).
>
> **Why, in one line:** Prisma cannot express the exclusion constraint, the `daterange` generated
> column, the composite foreign keys, or the partial and functional indexes — so under
> Prisma-as-executor you would write raw SQL anyway *and* take on a second migration history. The
> full reasoning, including the alternatives rejected, is in the linked section.
>
> **Consequences that show up as real work in this repo:** `schema.prisma` regeneration is a step
> in every schema change ([versioning-strategy.md](../../shared/versioning-strategy.md#keeping-the-two-orm-mappings-in-step));
> CI checks out `hotelapp-context` as a second checkout and runs the Flyway CLI
> ([devops-pipeline.md](./devops-pipeline.md)); and Phase 6 builds Spring Boot first, so this
> backend has a migrated database to introspect from day one.

---

## Layering

```
HTTP layer          Routing, request parsing, validation, status codes,
routes/             Problem Details serialization.
                    Knows HTTP. Knows nothing about SQL or Prisma.
      │
Service layer       Business rules: pricing, policy, allocation, transitions.
services/           OWNS TRANSACTION BOUNDARIES.
                    Knows nothing about HTTP or about Prisma's query API.
      │
Data access         Prisma client. Queries and row→domain mapping.
repositories/       Knows nothing about business rules.
```

Rules that make the layering real rather than nominal:

- **A route handler contains no business rule.** It validates, calls one service method, and maps
  the result to a DTO. A conditional on `reservation.status` in a route is logic in the wrong
  layer.
- **A service never imports from `express`** — no `Request`, no `Response`, no `res.status`.
  Services throw `AppError` subclasses and the error middleware turns those into responses. See
  [error-handling.md](./error-handling.md).
- **A repository never opens a transaction.** It accepts an optional `tx` client so the service
  decides the boundary:

  ```ts
  export function findCandidateRooms(db: Db, q: AvailabilityQuery): Promise<Room[]>
  // Db = PrismaClient | Prisma.TransactionClient
  ```

  This one signature convention is what makes transaction ownership enforceable — a repository
  that reaches for the global `prisma` client silently escapes its caller's transaction.
- **No layer skipping.** A route calling a repository directly bypasses the business rules that
  make the response correct.

> **Design Decision — a service layer at all, rather than logic in route handlers.**
> Express projects commonly put everything in the handler, and for a small API that is defensible.
> It is wrong here for a specific reason: **the Spring Boot backend must implement the same rules,
> and a reviewer has to be able to compare them.** Pricing, the cancellation deadline, allocation
> order, and status transitions live in named service methods in both backends so the two can be
> read side by side. The layering is as much a documentation decision as a design one.

---

## Folder layout

By feature within each layer, so a change touches adjacent files.

```
src/
  server.ts                   Express app assembly, middleware order, listen
  config/
    env.ts                    Env parsing + validation, once, at startup

  middleware/
    requestContext.ts         traceId, registered FIRST
    session.ts                Cookie -> session+user lookup, sliding expiry
    authorize.ts              requireGuest / requireStaff / requireManager
    validate.ts               Zod request validation
    rateLimit.ts              Auth endpoint limiter
    errorHandler.ts           Problem Details, registered LAST

  routes/
    auth.routes.ts            register, login, logout, me
    properties.routes.ts      public catalogue
    availability.routes.ts
    reservations.routes.ts    guest reservations
    me.routes.ts              profile, password
    admin/
      reservations.routes.ts  list, detail, check-in, check-out, cancel
      inventory.routes.ts     properties, room types, photos, rooms
      ratePlans.routes.ts
      calendar.routes.ts
      reports.routes.ts
    health.routes.ts

  services/
    authService.ts  sessionService.ts  propertyService.ts
    availabilityService.ts  bookingService.ts  reservationService.ts
    adminReservationService.ts  inventoryService.ts  ratePlanService.ts
    calendarService.ts  reportService.ts

  repositories/
    userRepo.ts  sessionRepo.ts  propertyRepo.ts  roomTypeRepo.ts
    roomRepo.ts  reservationRepo.ts  paymentRepo.ts  ratePlanRepo.ts
    amenityRepo.ts

  domain/
    pricing.ts                Rate resolution + rounding — PURE
    cancellation.ts           Deadline computation — PURE
    allocation.ts             Candidate ordering — PURE
    status.ts                 Legal transitions — PURE

  errors/
    errors.ts                 AppError hierarchy   see "Error handling architecture" below

  dto/
    *.dto.ts                  Request and response shapes + mappers

  db/
    client.ts                 PrismaClient singleton
    prismaErrors.ts           Prisma error -> AppError

  openapi/
    spec.ts                   OpenAPI 3.1 document

prisma/
  schema.prisma               GENERATED by `prisma db pull`. Not hand-edited.
                              No migrations/ directory — see the asymmetry above.
```

**`domain/` holds the pure functions and is the most important folder in the repo.** Pricing,
the cancellation deadline, allocation order, and legal status transitions are the four rules the
two backends must agree on to the cent and to the second. Keeping them as pure functions with no
database or HTTP dependency means they are unit-testable exhaustively and comparable directly with
their Java counterparts. This is where
[AC-CX-10](../../shared/acceptance-criteria.md#ac-cx-10--pricing-arithmetic-and-rounding-order)
and
[AC-CX-04](../../shared/acceptance-criteria.md#ac-cx-04--deadline-respects-the-propertys-timezone-not-the-servers)
are satisfied.

### Error handling architecture

`errors.ts` (the `AppError` hierarchy) lives in its own `errors/` folder, not `domain/` — the same
correction made on the Spring Boot side, logged once for both stacks in
[decision-log.md](../../shared/decision-log.md) entry 4. The distinction:

- **`domain/` is pure business computation** — a function of its inputs, no I/O, no knowledge that
  HTTP or a database exists. `pricing.ts`, `cancellation.ts`, `allocation.ts`, and `status.ts` all
  satisfy this.
- **`errors/` is the vocabulary a domain or service-layer failure is reported through**, and its
  entire reason to exist is to be caught once, centrally, and turned into an RFC 9457 response —
  see [error-handling.md](./error-handling.md). `AppError` carries the same kind of
  `(httpStatus, code, title)` triple Spring's `ProblemCode` does. That is API-error-translation,
  not business computation, regardless of whether a subclass's name describes a domain condition
  (`RoomUnavailableError`) or nothing domain-specific at all (`ValidationError`,
  `RateLimitedError` — neither expresses anything about hotels). "No Express or Prisma import" and
  "computes a business rule" are different tests, and the folder layout had been satisfying only
  the first.

**Where a subclass's code/status comes from** is `error-handling.md`'s SQLSTATE and
field-validation tables (byte-identical with the Spring Boot document through section 5) — this
section owns the folder layout and the hierarchy shape; `error-handling.md` remains the one place
that maps a specific failure to a specific code.

---

## Middleware order

Normative. The order determines what an unauthorized caller can learn, per
[error-handling.md](./error-handling.md#order-of-checks).

```ts
app.use(helmet());                  // 1. security headers
app.use(cors(corsOptions));         // 2. CORS, credentials: true, configured origins
app.use(cookieParser());            // 3.
app.use(express.json({ limit: '100kb' }));
app.use(requestContext);            // 4. traceId -> req.context
app.use(requestLogger);             // 5. method, path, status. NEVER bodies
// per-route: rateLimit -> session -> authorize -> validate -> handler
app.use(notFoundHandler);           // second to last
app.use(errorHandler);              // LAST. Four-argument signature.
```

Three of these are load-bearing in a way that is easy to get wrong:

- **`errorHandler` last, with four arguments.** Registered earlier it never runs; with three
  arguments Express treats it as ordinary middleware. Either mistake yields Express's default HTML
  error page, which both frontends will fail to parse.
- **`express.json({ limit })`.** Without a limit, an unbounded body is an easy denial of service on
  an endpoint that needs none.
- **`requestLogger` logs method, path, and status only.** Never bodies — `POST /reservations`
  carries card-shaped input. See
  [logging-observability.md](./logging-observability.md).

**Async handlers.** Express 4 does not forward a rejected promise to the error middleware: the
request hangs and the rejection is unhandled. Either wrap every async handler in `catchAsync` or
run Express 5, where rejections propagate. **Choose one and apply it to every route** — one
unwrapped handler is one endpoint that hangs instead of returning `500`.

---

## Session handling

The whole authentication mechanism, per
[api-contracts.md](../../shared/api-contracts.md#authentication).

`middleware/session.ts` on every non-public route:

1. Read the `hotelapp_session` cookie. Absent → `401 AUTHENTICATION_REQUIRED`.
2. SHA-256 the token, look up `sessions` by `token_hash`, **joined to `users`** in one query.
3. Reject when `revoked_at IS NOT NULL` or `expires_at <= now()` → `401`.
4. Reject when `users.is_active = false` → `403 ACCOUNT_INACTIVE`.
5. Slide `expires_at` to `now() + 8h`, capped at `issued_at + 30 days`, **only if more than 5
   minutes stale**.
6. Attach `{ user, session }` to `req.context`.

**The join in step 2 is not an optimization.** Reading `role` and `home_property_id` from the
joined user row on every request is what makes a role change or a deactivation take effect
immediately —
[AC-AZ-11](../../shared/acceptance-criteria.md#ac-az-11--inactive-accounts-cannot-authenticate)
asserts exactly this, and a cached role would fail it.

**The 5-minute write-throttle is required, not an optimization either.** Without it every
authenticated request writes a row, turning a read path into a write path. With a different
threshold this backend would appear to expire sessions at a different time than Spring Boot's —
see [data-model.md](../../shared/data-model.md#sessions).

`authorize.ts` compares **rank**: `requireStaff` admits `PROPERTY_MANAGER` without enumerating it.
Property scope is re-derived from `req.context.user.home_property_id`, never read from a request
parameter.

---

## Prisma usage

### `schema.prisma` is generated, not authored

Regenerating it is a step in every schema change, per
[versioning-strategy.md](../../shared/versioning-strategy.md#keeping-the-two-orm-mappings-in-step):
`prisma db pull` against a migrated database, then `prisma generate`, then review the diff.

Expect introspection to render some constructs imperfectly — the `daterange` generated column
becomes `Unsupported("daterange")`, and the exclusion constraint appears as a GiST index or not at
all. **That is correct and must not be "fixed."** `stay_period` is generated and never written, so
omit it from the model or leave it `Unsupported`; the constraint is enforced by the database
regardless of whether Prisma knows about it.

### Query rules

- **Always `select`, never a bare `findMany`.** Prisma returns every column by default, which ships
  `password_hash` and `token_hash` into application memory and risks them reaching a log or a
  response. Explicit `select` makes the leak impossible rather than unlikely.
- **No lazy loading exists in Prisma**, so relations are fetched explicitly with `include`. The
  N+1 hazards are room-type photos and amenities on property and search responses; fetch them in
  one query with `include`, not per row in a loop.
- **The availability query is hand-written SQL** via `$queryRaw`, because it needs the `&&` range
  operator and a `NOT EXISTS` anti-join that Prisma's query builder cannot express. Every date,
  id, and count is a **bound parameter** — this is the most parameter-dense query in the
  application and the one place SQL injection could plausibly be introduced. See
  [security-implementation.md](./security-implementation.md).
- **`Prisma.Decimal` for money, never `number`.** Converting to `number` loses precision on a value
  that came from `numeric(10,2)`.

### Transactions

`prisma.$transaction(async tx => …)` in the **service** layer, passing `tx` down to repositories.
Throwing inside rolls back.

The booking transaction is the one that matters: allocate a room, insert the reservation, insert
the payment — atomically, so a payment row never exists without its reservation. The allocation
**retry wraps the transaction** rather than living inside it, because a rolled-back transaction
cannot be continued. Code in
[error-handling.md](./error-handling.md#the-no-overbooking-path-precisely).

---

## DTOs

Every response is built from an explicit DTO. **No Prisma result is ever passed to `res.json`.**

The reason is concrete rather than stylistic: `schema.prisma` is regenerated from the database, so
serializing a Prisma object makes the API's shape a function of the schema. A column added by a
migration would silently appear in responses — including, in the worst case, `password_hash` or
`token_hash`. Explicit DTOs mean a schema change cannot alter the contract without someone editing
a mapper.

Mappers live in `dto/` and handle the contract's serialization rules: `Prisma.Decimal` → decimal
**string**, `Date` → `YYYY-MM-DD` for date columns and ISO-8601-with-offset for `timestamptz`, and
`snake_case` → `camelCase`. Per
[glossary-of-conventions.md](../../shared/glossary-of-conventions.md#the-identifier-casing-rule).

**A nullable field is emitted as explicit `null`, never omitted**, per
[api-contracts.md](../../shared/api-contracts.md#conventions). The hazard in this stack is
`undefined`: `JSON.stringify` **silently drops** a property whose value is `undefined`, so a mapper
that writes `photoUrl: row.photoUrl ?? undefined` produces an absent field where the contract
requires `null`. Map to `?? null`, and type DTO fields as `string | null` rather than optional
(`photoUrl?: string`) so the compiler catches the difference. This is the exact point at which the
two backends would otherwise disagree on the wire — Spring's equivalent trap is
`default-property-inclusion`, and it was found by building the first real client in Phase 6 Step 0.

---

## OpenAPI

A hand-maintained OpenAPI 3.1 document in `openapi/spec.ts`, served at
`/api/v1/openapi.json`.

> **Design Decision — hand-maintained, not generated from code.**
> Generating from decorators or from Zod schemas is less work and is the wrong trade here. The
> document's job is to be **diffable against the Spring Boot backend's**
> ([devops-pipeline-overview.md](../../shared/devops-pipeline-overview.md#1-the-openapi-diff)), and
> a generator's output reflects its own conventions — `operationId` style, schema naming, how
> optionality is expressed. Two different generators produce two documents that differ everywhere
> and nowhere meaningfully, and the check gets switched off within a week.
>
> A hand-maintained document derived from
> [api-contracts.md](../../shared/api-contracts.md) can be made to match the other backend's
> structurally. The cost is that it can drift from the code; the mitigation is that the diff job
> and the integration tests both catch that.

---

## Deliberately absent

| Absent | Why |
|--------|-----|
| A framework beyond Express — NestJS, Fastify | Express plus explicit layering is legible without framework-specific knowledge, which matters for a project meant to be read |
| A DI container | Constructor-style wiring in `server.ts` is enough at this size; a container would obscure the wiring a reviewer wants to see |
| GraphQL | The contract is REST, fixed |
| `prisma/migrations/` | Prisma does not apply DDL — see the asymmetry above |
| Redis, any cache | Only the session lookup would benefit, and a single indexed read is fast enough — named as the scale-up path in [api-contracts.md](../../shared/api-contracts.md#authentication) |
| A job scheduler | The only periodic work is session cleanup: one scheduled `DELETE` |
| WebSockets | Nothing in the product is real-time |
| Clustering, PM2, multi-process | No load target exists — [non-functional-requirements.md](../../shared/non-functional-requirements.md#throughput-and-concurrency) |
| A repository abstraction over Prisma beyond `repositories/` | Prisma is already the abstraction; another layer would be indirection with no second implementation behind it |
| Generated OpenAPI | See above |
| Stored procedures, triggers | Business logic stays in application code — [architecture-overview.md](../../shared/architecture-overview.md#where-business-logic-lives) |
