# Logging and Observability — Node / Express

What `hotelapp-server-nodejs` logs, in what shape, and what it deliberately does not collect.

**Unlike the frontends, a backend genuinely needs logging** — it is the only record of what happened
on the server. But this project has **no log aggregation, no APM, and no metrics collector**
([non-functional-requirements.md](../../shared/non-functional-requirements.md#availability)), so the
target is logs a developer reads in a terminal or a container log, correlated by `traceId`. Nothing
here ships anywhere.

---

## Structured JSON, one line per event

`lib/logger.ts` wraps **pino**. JSON rather than pretty text, because a log line is grepped and
`jq`'d far more often than read as prose, and because structured fields are what make `traceId`
correlation work.

```json
{"level":"warn","time":"2026-09-26T19:04:11.482Z","traceId":"0192f3a1-9e33-7d40-b512-2ac8d5f3e211",
 "method":"POST","path":"/api/v1/reservations","status":409,"code":"ROOM_UNAVAILABLE","durationMs":38,
 "msg":"request rejected"}
```

`pino-pretty` in development only, via the npm script — never in the production path, where it adds
a transform for no benefit.

| Level | Used for |
|-------|----------|
| `error` | `5xx`, unhandled rejections, startup failures |
| `warn` | `4xx` worth noticing, degraded-but-handled conditions (see the canaries below) |
| `info` | Startup, shutdown, one line per request, scheduled-job outcomes |
| `debug` | Query shapes, allocation decisions. Off by default |
| `trace` | Not used |

`LOG_LEVEL` from the environment, defaulting to `info`.

**`4xx` at `warn` or `info`, `5xx` at `error`.** Logging client errors at `error` makes the log
useless — a `404` is routine. Inverting it is worse. Stated in
[error-handling.md](./error-handling.md#5-what-must-never-happen) and repeated here because it is
the rule most often broken during debugging.

---

## `traceId`

One per request, generated in `middleware/requestContext.ts` — the **first** middleware registered.

| Rule | Why |
|------|-----|
| Generated once, at ingress | A second id per layer breaks correlation |
| On **every** log line for that request | It is the only way to reassemble a request's log |
| In every Problem Details body | Lets a user's "Reference: …" reach the right log |
| **Never** taken from a client header | A client-controlled correlation id is a log-injection and log-poisoning vector |

**Propagation without threading it through every signature** is the one real ergonomic problem. Use
`AsyncLocalStorage`:

```ts
export const requestStore = new AsyncLocalStorage<{ traceId: string }>();
// requestContext middleware: requestStore.run({ traceId }, next)
// logger: mixin: () => ({ traceId: requestStore.getStore()?.traceId })
```

Passing `traceId` as a parameter through service and repository signatures is the alternative and is
worse: it pollutes every function with a logging concern, and one omission silently breaks
correlation for a whole code path. `AsyncLocalStorage` is the Node-specific mechanism for this and is
the reason a service can log without knowing about requests.

`pino`'s `mixin` option attaches it automatically, so a call site cannot forget.

---

## Redaction — the hard rule

> **Never logged, at any level, in any environment:**
>
> - `Cookie` and `Set-Cookie` headers, and any raw session token
> - `payment.cardNumber`, `payment.cvv`, `payment.expiryMonth`, `payment.expiryYear`
> - `password`, `currentPassword`, `newPassword`, `password_hash`
> - `DATABASE_URL` — it contains the password
> - **Full request or response bodies**, as a blanket rule

Per
[security-principles.md](../../shared/security-principles.md#logging-and-data-handling). Configured
at the logger, not per call site, because the realistic violation is not malice but a well-meaning
"log the whole request" during debugging:

```ts
pino({ redact: {
  paths: ['req.headers.cookie', 'res.headers["set-cookie"]',
          '*.cardNumber', '*.cvv', '*.expiryMonth', '*.expiryYear',
          '*.password', '*.currentPassword', '*.newPassword', '*.password_hash',
          'password', 'cardNumber', 'cvv'],
  censor: '[REDACTED]' } });
```

`pino`'s `redact` operates on the serialized object, so it catches a field even when someone logs a
whole object by accident. **That is the point** — a deny-list applied at the boundary is the only
version of this rule that survives contact with a debugging session.

**Request-body logging is off on every route**, and `POST /reservations` specifically must never have
it re-enabled. Method, path, status, and duration only.

**`err` serialization must be explicit.** Pino serializes an `Error` to `{type, message, stack}`;
an `AppError` carrying a `detail` derived from user input is fine, but an error object that has
captured a request body is not. Log `err` through pino's standard serializer, never by spreading it.

---

## Canaries — conditions that are handled but must be visible

These are the reason a backend's logging is not just "write down the errors". Each recovers
gracefully, so the user sees something reasonable and **nothing else would ever reveal them.**

| Condition | Level | Why it matters |
|-----------|-------|----------------|
| **An unrecognized SQLSTATE reaching the generic `500` handler** | `error`, with the SQLSTATE and constraint name | See the section below — this is the exclusion-constraint canary |
| A `23514` `CHECK` violation | `warn` | Reaching a database `CHECK` means application validation has a gap. The response is a correct `400`; the gap is invisible otherwise |
| An allocation retry firing at all | `info`, with the attempt number | Normal under contention. A **spike** means genuine contention or a broken candidate query |
| Allocation exhausting all three attempts | `warn` | The `409 ROOM_UNAVAILABLE` is correct; three consecutive losses is worth seeing |
| A confirmation-number collision retry | `warn` | Should be vanishingly rare. Frequency implies a weak generator |
| A session `expires_at` slide failing | `warn` | The request still succeeds; silently the session stops extending |
| `prisma db pull` drift — a column in the database absent from the client | `error` at startup | The Node counterpart of Spring's `ddl-auto=validate` failure. See below |

### The exclusion-constraint detection canary

> **This is the most important log line in this backend.** Per
> [error-handling.md](./error-handling.md#prisma--problem-details) and
> [architecture-specification.md](./architecture-specification.md#the-migration-asymmetry-and-what-it-means-for-this-repo),
> **Prisma has no mapped error code for SQLSTATE `23P01`.** Detection relies on the driver's
> structured `code` when the insert goes through `$queryRaw`, or on matching the message text
> otherwise.
>
> **The integrity guarantee does not depend on that detection.** The exclusion constraint is applied
> by Flyway and enforced by PostgreSQL; a double-booking is impossible regardless of how this
> backend classifies the resulting error. What depends on detection is the **response**: detected, it
> is `409 ROOM_UNAVAILABLE` and the allocation retry proceeds; undetected, it falls through to
> `500 INTERNAL_ERROR`. **Fail-closed — the booking is still refused.** That distinction is worth
> being precise about, because "our no-overbooking guarantee depends on string matching" would be
> alarming and is not true.
>
> **The observability requirement:** log every unrecognized SQLSTATE at `error` **with the SQLSTATE
> and constraint name included as structured fields**. A Prisma upgrade that changes the message
> format then shows up as `500`s carrying `sqlState: "23P01"` — an unmistakable signal — rather than
> as an unexplained error rate. Without that field, the same break looks like a generic `500` and
> could persist unnoticed.
>
> ```ts
> logger.error({ traceId, sqlState, constraint, err }, 'unmapped database error');
> ```
>
> `AC-OB-01` in
> [testing-standards.md](./testing-standards.md) is the primary guard; this log line is the
> production-shaped backstop for the case where the test suite has not run yet.

### The schema-drift check at startup

Spring Boot gets `ddl-auto=validate` for free. This backend has no equivalent, because
`schema.prisma` is generated rather than validated — so a database migrated past what this client
knows about produces a runtime error on one endpoint rather than a startup failure.

**Log the Flyway schema version at startup**, read from `flyway_schema_history`, at `info`. It
costs one query and turns "this backend is running against a newer schema than it was generated
from" into a visible fact at boot rather than a mystery later. This is the closest this stack gets to
the validation the other one has by default, and it exists because of the migration asymmetry.

---

## Request logging

One `info` line per request, on completion:

```
method, path (route pattern, not the raw URL), status, durationMs, traceId,
code (when an error), userId (when authenticated)
```

**The route pattern, not the raw path.** `/api/v1/reservations/:id` rather than
`/api/v1/reservations/0192f3a1-…`, so lines aggregate and a reservation id does not end up in
every log line.

**No query string.** Search parameters are harmless, but a blanket rule is easier to hold than a
per-route judgment, and it means a future endpoint cannot leak through this path.

`userId` but never email, name, or any other personal field.

---

## Health

`GET /health`, per
[api-contracts.md](../../shared/api-contracts.md#get-health--public): `200` with
`{status, database, version, backend: "nodejs"}`, `503` when the database is unreachable.

The database check is a real `SELECT 1`, not a cached flag —
[AC-CC-05](../../shared/acceptance-criteria.md#ac-cc-05--health-check-reflects-real-database-state)
asserts it reflects actual state. The `backend` field is how a tester confirms which implementation
answered, which matters during the cross-backend session walkthrough.

**Health is not logged at `info` per call.** If anything ever polls it, it would drown the log.

---

## Startup and shutdown

**Startup, at `info`:** port, `NODE_ENV`, log level, the Flyway schema version, and the resolved
database host and name — **never the full `DATABASE_URL`.** A startup banner is the most common place
a connection string with a password gets printed.

**Graceful shutdown on `SIGTERM`:** stop accepting connections, let in-flight requests finish,
`prisma.$disconnect()`, exit. Log each step. Without it, a restart during a booking transaction
leaves the client with no response — the transaction itself is safe, since the database rolls back.

**Unhandled rejection or uncaught exception:** log at `error` with the full reason, then **exit**.
Per [architecture-specification.md](./architecture-specification.md#middleware-order), a process
that threw outside a request is in an unknown state, and serving further requests risks wrong answers
rather than visible failures.

---

## Deliberately absent

| Absent | Why |
|--------|-----|
| Log shipping — Loki, ELK, CloudWatch | Nowhere to ship to. Logs go to stdout, which is where a container log collector would pick them up if one existed |
| APM — New Relic, Datadog, Elastic APM | Nothing collects, and each is an agent in the process |
| Prometheus metrics, `/metrics` | No scraper. The one performance check worth having is an `EXPLAIN` assertion in the test suite, per [non-functional-requirements.md](../../shared/non-functional-requirements.md#response-time-targets) |
| OpenTelemetry, distributed tracing | One service. `traceId` already correlates within it, and there is no collector |
| Sentry or any error-reporting service | Nowhere to send to |
| Audit logging as a system | Partially covered by columns (`cancelled_by_user_id`, `checked_in_at`, session `ip_address`); named as a real gap in [security-principles.md](../../shared/security-principles.md#out-of-scope-and-why-that-line-is-acceptable) |
| Log rotation, file output | stdout only; rotation is the container runtime's job |
| Alerting | Nothing is running to alert on |
| Request/response body logging | Forbidden — see redaction |
