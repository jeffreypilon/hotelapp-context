# Architecture Overview

The shape of the HotelApp system: what the pieces are, how a request flows through them, and
how two backends written in different languages are kept behaviorally identical.

This document describes structure. It does not restate the schema
([data-model.md](./data-model.md)) or the endpoint contract
([api-contracts.md](./api-contracts.md)); where those decide something, this document points
at them.

---

## The system in one paragraph

Two interchangeable frontends and two interchangeable backends share one PostgreSQL
database. Every frontend speaks to every backend through one REST contract, and nothing else
crosses between components — no shared code, no message queue, no server-side rendering, no
backend-to-backend calls. The point of the architecture is the interchangeability itself:
four components, two swappable pairs, one contract holding them together.

---

## Components

```
┌─────────────────────────┐     ┌─────────────────────────┐
│  hotelapp-client-react  │     │ hotelapp-client-angular │
│                         │     │                         │
│  React + Tailwind CSS   │     │  Angular + Tailwind CSS │
│  SPA, browser only      │     │  SPA, browser only      │
└────────────┬────────────┘     └────────────┬────────────┘
             │                               │
             │      REST over HTTPS          │
             │   application/json            │
             │   session cookie (HttpOnly)   │
             │                               │
             └───────────────┬───────────────┘
                             │
          ┌──────────────────┴──────────────────┐
          │      one REST contract, /api/v1     │
          │   shared/api-contracts.md is the    │
          │      single normative source        │
          └──────────────────┬──────────────────┘
                             │
             ┌───────────────┴───────────────┐
             │                               │
┌────────────┴─────────────┐     ┌───────────┴──────────────┐
│ hotelapp-server-nodejs   │     │hotelapp-server-springboot│
│                          │     │                          │
│ TypeScript + Express     │     │ Java + Spring Boot        │
│ Prisma                   │     │ Spring Data JPA/Hibernate │
└────────────┬─────────────┘     └───────────┬──────────────┘
             │                               │
             │        SQL (parameterized)    │
             └───────────────┬───────────────┘
                             │
                 ┌───────────┴────────────┐
                 │   PostgreSQL 18.6      │
                 │                        │
                 │  one physical database │
                 │  schema: data-model.md │
                 │                        │
                 │  · exclusion constraint│
                 │    (no overbooking)    │
                 │  · sessions table      │
                 │    (shared login state)│
                 └────────────────────────┘
```

Exactly one backend and one frontend run at a time in normal use; the other two exist to be
swapped in. All four can run simultaneously against the same database, which is what makes
the cross-backend session demo in
[acceptance-criteria.md](./acceptance-criteria.md) possible.

| Component | Repo | Role |
|-----------|------|------|
| React client | `hotelapp-client-react` | Browser SPA. Public browsing, guest booking, admin area |
| Angular client | `hotelapp-client-angular` | The same application, same features, different framework |
| Node backend | `hotelapp-server-nodejs` | REST API. TypeScript, Express, Prisma |
| Spring Boot backend | `hotelapp-server-springboot` | The same API. Java, Spring Boot, JPA/Hibernate |
| Database | — | PostgreSQL 18.6, one instance, one schema |
| Context | `hotelapp-context` | This repo. Specifications only, no code |

---

## Request flow

A representative authenticated read, `GET /api/v1/reservations`:

```
1. Browser          SPA calls fetch(..., { credentials: "include" })
                    Session cookie attached automatically by the browser
                          │
2. CORS             Backend validates Origin against configured allow-list
                          │
3. Session          Hash the cookie token, look up sessions by token_hash,
                    join users. Reject if revoked, expired, or unknown → 401
                    Slide expires_at if more than 5 minutes stale
                          │
4. Authorization    Compare the user's role against the endpoint's required
                    tier; for property-scoped routes, check home_property_id
                          │
5. Validation       Parse and validate query parameters; reject unknown fields
                          │
6. Business logic   Service layer: build the query, apply pricing or policy
                    rules, map rows to response DTOs
                          │
7. Data access      Prisma or JPA issues parameterized SQL
                          │
8. PostgreSQL       Executes. Constraints are the last line of defense
                          │
9. Response         200 with the paginated envelope, or a Problem Details
                    document on any failure path
```

Steps 2–5 are cross-cutting middleware in both backends; steps 6–7 are per-endpoint. The
ordering is normative: **authentication precedes authorization precedes validation**, so an
unauthenticated request never reveals whether its body was well-formed, and a request from
the wrong role never reveals whether the resource exists.

A write follows the same path with one addition: steps 6–8 run inside a **single database
transaction**, so a partial booking cannot be observed. `POST /reservations` is the
significant case — it allocates a room, inserts the reservation, and inserts the payment
atomically.

---

## Where business logic lives

**In the backend service layer.** Not in the database, not in the client, not in the ORM
mapping.

| Concern | Lives in | Why |
|---------|----------|-----|
| Pricing (discount, rounding, totals) | Backend service | Must be identical in both backends; specified in [data-model.md](./data-model.md#rate_plans) |
| Cancellation policy (48-hour rule) | Backend service | The deadline is computed once at booking and stored |
| Room allocation | Backend service, inside the insert transaction | Needs the database's arbitration on conflict |
| Status transitions | Backend service, with a database `CHECK` as backstop | The service decides legality; the constraint prevents impossible rows |
| Occupancy limits (`numGuests`) | Backend service | Cannot be expressed as a `CHECK` across tables |
| **No overbooking** | **Database** — exclusion constraint | The one invariant with a genuine race condition. One line in [data-model.md](./data-model.md#no-overbooking) |
| Referential integrity, enums, ranges | Database constraints | Cheap, absolute, and equally binding on both backends |
| Presentation, formatting, currency symbols | Frontend | Backends emit decimal strings and ISO dates; formatting is a locale concern |

> **Design Decision — no stored procedures, no triggers, one exception.**
> Business rules stay in application code, where they are testable in each stack's native
> test framework, visible in code review, and debuggable with ordinary tooling. Putting them
> in PL/pgSQL would make the database a third implementation to keep in sync with the other
> two — precisely the drift this architecture is organized to prevent.
>
> The exception is the no-overbooking exclusion constraint, which is in the database because
> it is the only rule where two correct-looking application implementations can still produce
> a wrong result under concurrency. The reasoning is in
> [data-model.md](./data-model.md#no-overbooking) and is not repeated here.
>
> Declarative constraints — foreign keys, `CHECK`, `UNIQUE`, `NOT NULL` — are not "logic in
> the database" in the sense being avoided. They are assertions that the schema's invariants
> hold, and both ORMs are configured to treat the schema as authoritative rather than
> generate it.

---

## How the two backends stay identical

This is the architectural problem the project actually exists to demonstrate, so it gets
stated directly rather than assumed.

**[api-contracts.md](./api-contracts.md) is the enforcement mechanism.** It is normative,
not descriptive: where an implementation and that document disagree, the implementation is
wrong. Every endpoint's path, method, auth tier, request shape, response shape, status codes,
and error codes are fixed there, and neither backend may add, rename, or reshape anything
without the contract changing first.

Four layers of enforcement, from cheapest to strongest:

1. **The shared schema.** Both backends run against one physical database with
   `ddl-auto=validate` (Spring) and migrations they do not author (Prisma). Neither can
   invent a column. Constraints, enums, and the exclusion constraint apply identically
   because there is literally one copy of them. See
   [versioning-strategy.md](./versioning-strategy.md#database-schema-migrations) for how one
   schema is migrated by two tools without collision.

2. **The OpenAPI diff check in CI.** Each backend publishes a generated OpenAPI 3.1 document
   at `/api/v1/openapi.json`. Because both are generated from the same contract, the two
   documents should be **semantically identical**, and CI diffs them. A meaningful diff is a
   contract violation in one of the two — this is specified in
   [api-contracts.md](./api-contracts.md#cross-cutting-requirements) and is the primary
   automated defense against drift. Mechanics in
   [devops-pipeline-overview.md](./devops-pipeline-overview.md).

3. **Shared acceptance criteria.** The behaviors most likely to diverge silently — pricing
   arithmetic and rounding order, the cancellation boundary, session validity, allocation
   order, error-code mapping — have explicit Given/When/Then criteria in
   [acceptance-criteria.md](./acceptance-criteria.md) that become integration tests in
   **both** backend repos. Same scenarios, same expected outputs, two languages.

4. **The interchangeability test itself.** Point either frontend at either backend and run
   the same manual walkthrough. Because sessions live in the shared database, a login against
   one backend is honored by the other, which makes "these are the same API" demonstrable in
   about thirty seconds rather than arguable.

**Known divergence seams.** Two implementations of one contract will not differ in obvious
places; they will differ in these, which is why each is pinned by a named specification:

| Seam | Pinned by |
|------|-----------|
| Decimal rounding and its order of operations | [data-model.md](./data-model.md#rate_plans) — round the nightly rate, then multiply |
| Timezone arithmetic for the cancellation deadline | [data-model.md](./data-model.md#cancellation-policy) — stored, computed once |
| Password hash interoperability | bcrypt cost 12, chosen so Node and Spring Security verify each other's hashes |
| Session TTL and write-throttle | [data-model.md](./data-model.md#sessions) — 8h / 30d / 5min, identical in both |
| Constraint violation → HTTP status | SQLSTATE `23P01` → `409 ROOM_UNAVAILABLE` |
| JSON serialization of money and dates | Decimal strings, ISO 8601 — [api-contracts.md](./api-contracts.md#conventions) |
| Unknown-field handling | Reject with `400`, never ignore |

---

## Frontend architecture, in outline

Detail belongs in `stacks/react/` and `stacks/angular/` (Phase 3). What is fixed at this
level:

- **Both are browser-only SPAs.** No SSR, no Next.js or Angular Universal, no server-side
  rendering of any kind. There is no Node process serving the React app in production;
  both build to static assets.
- **The backend base URL is configuration**, not a compile-time constant, because switching
  backends must not require a rebuild.
- **No client-side session storage.** The session cookie is `HttpOnly`; there is no token to
  keep. Client obligations are in
  [api-contracts.md](./api-contracts.md#client-obligations).
- **Both consume the same contract with no adapter layer.** If one frontend needs a
  translation shim over a response shape, the contract is wrong, not the frontend.
- **Three surfaces per client**: public browsing and search, the authenticated guest area,
  and the admin area. Route guards enforce the tier client-side for UX; the server enforces
  it for real.

---

## Backend architecture, in outline

Detail belongs in `stacks/nodejs/` and `stacks/springboot/` (Phase 4). What is fixed at this
level: both backends use the same **three-layer separation**, so the two codebases are
comparable side by side.

```
HTTP layer        Routing, request parsing, response serialization,
(controller)      status codes, Problem Details mapping.
                  Knows HTTP. Knows nothing about SQL.
      │
Service layer     Business rules: pricing, policy, allocation, transitions.
                  Owns transaction boundaries.
                  Knows nothing about HTTP or about the ORM's query API.
      │
Data access       Prisma client / JPA repositories. Queries and mapping.
(repository)      Knows nothing about business rules.
```

- **Transactions begin and end in the service layer.** Not in a controller, not implicitly
  around an ORM call.
- **No ORM entity is ever serialized directly to JSON.** Responses are built from explicit
  DTOs, so a schema change cannot silently alter the API — the most common way an
  ORM-backed service breaks its own contract.
- **Both are stateless processes.** All state is in PostgreSQL, including sessions. Nothing
  is cached in process memory across requests, which is what makes running both backends
  against one database coherent.

---

## What is deliberately not in this architecture

Stated plainly, because a reviewer should see that these were considered and declined rather
than overlooked:

| Absent | Why |
|--------|-----|
| API gateway, BFF, reverse proxy | Two clients, one API, no fan-out. A gateway would add a hop and no capability |
| Message queue, event bus, async jobs | Every operation is a synchronous request/response. Nothing needs a queue except the session cleanup job, which is a scheduled `DELETE` |
| Redis or any cache | Only the session lookup would benefit, and at demo scale a single-row indexed read is already fast enough. Named as the scale-up path in [api-contracts.md](./api-contracts.md#authentication) |
| Microservices | One bounded context. Splitting it would create distributed-transaction problems where none exist |
| Shared library between the two backends | Impossible across TypeScript and Java without a code generator, and the specification serves the same purpose more legibly |
| Backend-to-backend calls | The two backends do not know about each other. They are alternatives, not collaborators |
| Read replicas, connection proxies, sharding | See [non-functional-requirements.md](./non-functional-requirements.md) — single instance, stated honestly |
| GraphQL | The contract is REST, fixed. A second protocol would double the surface for no demonstrated need |
| WebSockets, server-sent events | Nothing in the product is real-time. The admin calendar is a page load |
| File/blob storage | Photos are URLs. Upload is out of scope — [data-model.md](./data-model.md#room_type_photos) |
| Email delivery | Confirmation email is a logged simulation; real transactional email is a stated stretch goal in [project-overview.md](./project-overview.md) |

---

## Deployment shape

Local native development now; Docker Compose later. No hosted environment, no Kubernetes.
See [devops-pipeline-overview.md](./devops-pipeline-overview.md) for the pipeline and
[non-functional-requirements.md](./non-functional-requirements.md) for what this means for
availability.

```
Local development (now)
  PostgreSQL 18.6   native install, localhost:5432
  backend           one of the two, localhost:3000 (Node) / :8080 (Spring)
  frontend          one of the two, Vite / ng serve dev server

Docker Compose (later)
  one compose file per backend choice, db + backend + frontend
```

Both backends on `localhost` share the same cookie jar regardless of port — cookies are
scoped by host, not by port — which is what makes the cross-backend session demo work
locally without any proxy. That property is load-bearing for
[acceptance-criteria.md](./acceptance-criteria.md#4-session-behavior) and is the reason the
session cookie's `Path` is `/api/v1` rather than something backend-specific.
