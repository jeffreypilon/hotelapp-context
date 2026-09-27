# Dependency Policy — Node / Express

What may be added to `hotelapp-server-nodejs`, what may not, and how to decide.

The governing rule is from
[security-principles.md](../../shared/security-principles.md#dependencies): **prefer the platform's own
primitives over a small package.** Every dependency is added attack surface and added maintenance, and
a backend's dependency tree is the part of this project with the most realistic supply-chain exposure —
it runs with database credentials.

The "deliberately absent" table in
[architecture-specification.md](./architecture-specification.md#deliberately-absent) already settled
several cases; this document does not reopen them.

---

## The approved set

Versions pinned exactly, `package-lock.json` committed, `npm ci` in CI.

| Package | Role | Why it earns its place |
|---------|------|------------------------|
| `express` | HTTP | Decided at system level |
| `@prisma/client`, `prisma` | Data access | Decided at system level |
| `zod` | Request validation | One declaration gives validation and the inferred request type |
| `bcrypt` (or `bcryptjs`) | Password hashing | **Must emit `$2b$` modular-crypt strings** so Spring Security verifies them — the cross-stack requirement that chose bcrypt over Argon2id |
| `pino` | Structured logging | Fast, JSON-first, and its `redact` option enforces the masking rule at the logger rather than per call site |
| `cookie-parser` | Cookie reading | Trivial, and hand-rolling cookie parsing is a poor use of judgment |
| `helmet` | Security headers | One line for the header set in [security-principles.md](../../shared/security-principles.md#security-headers) |
| `cors` | CORS | Credentialed CORS with an origin allow-list is fiddly enough to be worth the package |
| `express-rate-limit` | Auth rate limiting | Or a hand-rolled counter; see below |
| `typescript`, `tsx` | Build and dev | |
| `vitest`, `supertest`, `@testcontainers/postgresql` | Testing | [testing-standards.md](./testing-standards.md) |
| `eslint`, `prettier`, `@typescript-eslint/*` | Lint and format | Both fail CI |

**`crypto` is built in** — session tokens (`randomBytes`), token hashing (`createHash`), and
confirmation numbers all use it. No package needed, and reaching for `uuid` or `nanoid` would add a
dependency to do what `node:crypto` already does.

**`AsyncLocalStorage` is built in** and is how `traceId` propagates —
[logging-observability.md](./logging-observability.md#traceid). No context-propagation library.

> **`express-rate-limit` is the one borderline entry.** The requirement is 10 attempts per 15 minutes
> keyed on IP and email, in-process, on two routes. That is roughly forty lines with a `Map` and a
> timestamp, and writing it would be defensible. The package is kept because its window accounting and
> its `Retry-After` handling are the fiddly parts and are already correct, and because
> [AC-SE-09](../../shared/acceptance-criteria.md#ac-se-09--login-rate-limiting) requires a correct
> password inside the window to still be refused — which a naive hand-rolled limiter tends to get wrong
> by checking credentials first. Either choice is fine; the reasoning is recorded so it is a decision.

---

## Explicitly not allowed

Each is a decision already made elsewhere, restated as a prohibition so it is not relitigated one pull
request at a time.

| Not allowed | Instead | Decided in |
|-------------|---------|-----------|
| **`prisma migrate` as a workflow** (the CLI is a dependency; the subcommand is banned) | Flyway applies DDL; Prisma introspects | [versioning-strategy.md](../../shared/versioning-strategy.md#database-schema-migrations) |
| A JWT library — `jsonwebtoken`, `jose` | **There are no tokens** | [security-implementation.md](./security-implementation.md#what-must-never-appear-in-this-codebase) |
| A session library — `express-session`, `connect-pg-simple` | The `sessions` table is the authority; a second session abstraction would compete with it |
| NestJS, Fastify, Koa, tRPC | Express plus explicit layering, legible without framework-specific knowledge | [architecture-specification.md](./architecture-specification.md#deliberately-absent) |
| A DI container — `tsyringe`, `inversify` | Constructor-style wiring in `server.ts`; a container hides the wiring a reviewer wants to see | same |
| A second ORM or query builder — Knex, Kysely, TypeORM, Drizzle | Prisma is the decision. A second would mean two schema representations |
| A date library — Moment, date-fns, Day.js, Luxon | `Intl.DateTimeFormat` and `Date`. The one hard case — the cancellation deadline in a property's IANA zone — is `Intl` with a `timeZone` option |
| A money library — Dinero, currency.js | `Prisma.Decimal` internally, decimal **string** on the wire. No arithmetic library needed for one multiply and one round |
| A validation alternative — Joi, class-validator, yup | Zod, once. Two validators means two places a rule can be wrong |
| `lodash`, `underscore`, `ramda` | Native array and object methods cover everything here |
| An OpenAPI generator — `tsoa`, `zod-to-openapi` | The document is hand-maintained so it can be made structurally comparable with the other backend's | [architecture-specification.md](./architecture-specification.md#openapi) |
| Redis, `ioredis`, any cache client | Only the session lookup would benefit; named as the scale-up path in [api-contracts.md](../../shared/api-contracts.md#authentication) |
| A job queue — BullMQ, Agenda | The only periodic work is session cleanup: one scheduled `DELETE` |
| `ws`, `socket.io` | Nothing in the product is real-time |
| APM or error-reporting agents — Sentry, Datadog, New Relic | Nowhere to send to, and each is code running in-process with database credentials | [logging-observability.md](./logging-observability.md#deliberately-absent) |
| PM2, clustering libraries | No load target exists | [non-functional-requirements.md](../../shared/non-functional-requirements.md#throughput-and-concurrency) |
| `dotenv` in production code | `dotenv/config` in the dev script only. In a container the environment is the environment |
| A mocking library for Prisma — `prisma-mock`, `jest-mock-extended` | **Actively harmful here.** A mocked Prisma client would let [AC-OB-01](../../shared/acceptance-criteria.md#ac-ob-01--two-concurrent-bookings-for-the-last-room-exactly-one-wins) pass while the exclusion constraint was absent — see below |

### Why mocking Prisma is prohibited, specifically

This is the one prohibition unique to this backend and it follows directly from the
migration asymmetry.

**Prisma has no mapped error code for SQLSTATE `23P01`** —
[error-handling.md](./error-handling.md#prisma--problem-details). Detection of an exclusion-constraint
violation relies on the driver's structured code via `$queryRaw`, or on matching message text. A mocked
client returns whatever the test author decided it returns, so a mocked test of the no-overbooking path
asserts that *the mock behaves as expected* — which is true regardless of whether the real detection
works, and regardless of whether the constraint exists at all.

So the integration tests against real PostgreSQL are not merely better here; they are **the only thing
that can catch this breaking** after a Prisma upgrade. Mocking the client would remove the project's
only guard on its central guarantee while making the test suite look green.

---

## Adding something new

Five questions, in order. A "no" at any point is the answer.

1. **Does Node, TypeScript, or Prisma already do this?** `node:crypto`, `AsyncLocalStorage`, `Intl`,
   `URL`, `structuredClone`, `AbortController`, `node:timers/promises`. The answer is yes more often
   than people expect, and a backend's standard library is much larger than a browser's.
2. **Is it already prohibited above?** Then it needs a documented decision reversal, not a pull request.
3. **What does it pull in transitively, and does it have native bindings?** A native module is a build
   prerequisite on every machine and in every container — `bcrypt` is accepted as one, and a second
   should be argued for.
4. **Is it maintained and typed?** Recent releases, a real issue tracker, first-party types.
   `@types/*` from DefinitelyTyped is acceptable; no types at all is not.
5. **Could fifty lines replace it?** If yes, write the fifty lines. They will be understood, tested,
   and free of a supply-chain relationship to a process holding database credentials.

Each addition is a separate commit with the reason in the message, per
[glossary-of-conventions.md](../../shared/glossary-of-conventions.md#commit-message-convention).
"Added while working on X" in a large commit is how a dependency arrives without anyone deciding.

---

## Maintenance

- **Exact versions**, no `^` or `~`. A reviewer cloning this repo gets the build the author had.
- `package-lock.json` committed; `npm ci` in CI, never `npm install`.
- **`prisma` and `@prisma/client` move together.** A mismatch produces confusing runtime errors, and a
  `prisma` upgrade is the specific event that could break `23P01` detection — so an upgrade means
  running the integration suite deliberately, not just the unit tests.
- **`devDependencies` and `dependencies` are kept honest**, so a production install does not pull the
  test tree.
- **No automated dependency updates** — no Dependabot, no Renovate. A declined cost, explained in
  [security-principles.md](../../shared/security-principles.md#out-of-scope-and-why-that-line-is-acceptable),
  which also names it as the easiest thing here to add later.
- **Remove what stops being used.** An unused dependency in a process with database credentials is pure
  liability.
