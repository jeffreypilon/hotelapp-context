# Logging and Observability — Spring Boot

What `hotelapp-server-springboot` logs, in what shape, and what it deliberately does not collect.

**Unlike the frontends, a backend genuinely needs logging** — it is the only record of what happened
on the server. But this project has **no log aggregation, no APM, and no metrics collector**
([non-functional-requirements.md](../../shared/non-functional-requirements.md#availability)), so the
target is logs a developer reads in a terminal or a container log, correlated by `traceId`. Nothing
here ships anywhere.

---

## Structured JSON, one line per event

SLF4J over Logback, with a JSON encoder (`logstash-logback-encoder`) in every profile except local
development, where the default pattern layout is more readable. JSON because a log line is grepped
and `jq`'d far more often than read as prose, and because structured fields are what make `traceId`
correlation work.

```json
{"@timestamp":"2026-09-26T19:04:11.482Z","level":"WARN","logger":"…BookingService",
 "traceId":"0192f3a1-9e33-7d40-b512-2ac8d5f3e211","method":"POST","path":"/api/v1/reservations",
 "status":409,"code":"ROOM_UNAVAILABLE","durationMs":38,"message":"request rejected"}
```

| Level | Used for |
|-------|----------|
| `ERROR` | `5xx`, unhandled exceptions, startup failures |
| `WARN` | `4xx` worth noticing, degraded-but-handled conditions (see the canaries below) |
| `INFO` | Startup, shutdown, one line per request, scheduled-job outcomes |
| `DEBUG` | Query shapes, allocation decisions. Off by default |
| `TRACE` | Not used |

`LOG_LEVEL` from the environment via `logging.level.com.hotelapp`, defaulting to `INFO`. Framework
loggers stay at `WARN` — Spring and Hibernate at `INFO` produce a great deal of startup noise that
buries the lines this application writes.

**`4xx` at `WARN` or `INFO`, `5xx` at `ERROR`.** Logging client errors at `ERROR` makes the log
useless — a `404` is routine. Inverting it is worse. Stated in
[error-handling.md](./error-handling.md#5-what-must-never-happen) and repeated here because it is the
rule most often broken during debugging.

**Parameterized logging always**: `log.warn("rejected {} for {}", code, id)`. Concatenation builds
the string even when the level is disabled.

---

## `traceId` via the MDC

Generated in `web/TraceIdFilter` — ordered **first** — and placed in the SLF4J MDC, which the JSON
encoder includes on every line automatically.

| Rule | Why |
|------|-----|
| Generated once, at ingress | A second id per layer breaks correlation |
| On **every** log line for that request | It is the only way to reassemble a request's log |
| In every Problem Details body | Lets a user's "Reference: …" reach the right log |
| **Never** taken from a client header | A client-controlled correlation id is a log-injection and log-poisoning vector |

**The MDC is thread-local, which is the one thing to get right here.** Two consequences:

- **Clear it in a `finally` block.** A pooled thread that keeps a previous request's `traceId`
  attributes the next request's logs to the wrong one — worse than having no id, because it is
  actively misleading.
- **`@Async` and any executor lose it.** The only background work is the scheduled session cleanup,
  which should set its own id rather than inherit one. If executors are ever added, `MDC.getCopyOfContextMap()`
  must be propagated explicitly.

This is the Spring-specific counterpart to the Node backend's `AsyncLocalStorage` problem, and it is
strictly simpler — the MDC is built in and the encoder picks it up without a call site knowing.

---

## Redaction — the hard rule

> **Never logged, at any level, in any environment:**
>
> - `Cookie` and `Set-Cookie` headers, and any raw session token
> - `payment.cardNumber`, `payment.cvv`, `payment.expiryMonth`, `payment.expiryYear`
> - `password`, `currentPassword`, `newPassword`, `passwordHash`
> - The datasource URL and password
> - **Full request or response bodies**, as a blanket rule

Per
[security-principles.md](../../shared/security-principles.md#logging-and-data-handling). Three
Spring-specific enforcement points, because the realistic violation is a debugging convenience rather
than malice:

**1. Never enable `CommonsRequestLoggingFilter` with `setIncludePayload(true)`.** It logs every body
on every route, including `POST /reservations`. This is the specific mechanism by which card data
would reach a log file in this stack, and it is a one-line change someone makes while debugging.

**2. Override `toString()` on the payment record.** A Java `record`'s generated `toString()` includes
every component, so `log.debug("request: {}", request)` prints the card number. Redact in
`toString()` itself rather than relying on nobody logging the object — that makes the safe behavior
the default:

```java
public record PaymentRequest(String cardNumber, int expiryMonth, int expiryYear,
                             String cvv, String cardholderName) {
  @Override public String toString() {
    return "PaymentRequest[cardNumber=****, cvv=***, cardholderName=" + cardholderName + "]";
  }
}
```

**3. Never log an entity.** `User.toString()` would include `passwordHash` unless deliberately
overridden, and entities do not leave the service layer anyway.

**`logging.level.org.hibernate.SQL` stays off outside local debugging**, and
`org.hibernate.orm.jdbc.bind` — which logs bound parameter values — stays off **always**. That
second one would log a password on the login query.

---

## Canaries — conditions that are handled but must be visible

These are the reason a backend's logging is not just "write down the errors". Each recovers
gracefully, so the user sees something reasonable and **nothing else would ever reveal them.**

| Condition | Level | Why it matters |
|-----------|-------|----------------|
| **An unrecognized SQLSTATE reaching the generic `500` handler** | `ERROR`, with the SQLSTATE and constraint name | See below |
| A `23514` `CHECK` violation | `WARN` | Reaching a database `CHECK` means application validation has a gap. The response is a correct `400`; the gap is invisible otherwise |
| An allocation retry firing at all | `INFO`, with the attempt number | Normal under contention. A **spike** means genuine contention or a broken candidate query |
| Allocation exhausting all three attempts | `WARN` | The `409 ROOM_UNAVAILABLE` is correct; three consecutive losses is worth seeing |
| A confirmation-number collision retry | `WARN` | Should be vanishingly rare. Frequency implies a weak generator |
| A session `expires_at` slide failing | `WARN` | The request still succeeds; silently the session stops extending |
| `UnexpectedRollbackException` | `ERROR` | Almost always means the allocation retry has been moved inside the transaction — see [error-handling.md](./error-handling.md#transactions) |
| `LazyInitializationException` | `ERROR` | An entity escaped the service layer, which [architecture-specification.md](./architecture-specification.md#dtos) forbids |

### The exclusion-constraint detection asymmetry

> **This backend has the reliable path, and the log line exists to prove it stays reliable.**
>
> The PostgreSQL JDBC driver exposes SQLSTATE as structured data via `SQLException.getSQLState()`, so
> `23P01` is matched on a value. The Node backend cannot do that — **Prisma has no mapped error code
> for `23P01`** and must use a raw-query error code or match message text, per that stack's
> [error-handling.md](../nodejs/error-handling.md#prisma--problem-details). This is a direct
> consequence of the migration-ownership decision: the constraint is applied by Flyway and Prisma only
> introspects it, so Prisma has no model of it.
>
> **Neither backend's integrity guarantee depends on detection.** The constraint is enforced by
> PostgreSQL; a double-booking is impossible regardless of how either backend classifies the error.
> What depends on detection is the **response** — `409 ROOM_UNAVAILABLE` when detected,
> `500 INTERNAL_ERROR` when not. Fail-closed either way.
>
> **This stack's fragility is different and worth logging for.** `findCause` must walk the Hibernate
> wrapping chain two or three levels to reach the `SQLException`; a Hibernate or driver upgrade that
> changes the nesting breaks it exactly as silently. So: **log every unrecognized SQLSTATE at `ERROR`
> with the SQLSTATE and constraint name as structured fields.** A break then appears as `500`s
> carrying `sqlState: "23P01"` — unmistakable — rather than as an unexplained error rate.
>
> ```java
> log.error("Unmapped database error [sqlState={}, constraint={}]", state, constraint, ex);
> ```
>
> `AC-OB-01` in [testing-standards.md](./testing-standards.md) is the primary guard; this line is the
> production-shaped backstop.

### What `ddl-auto=validate` gives this backend for free

A startup failure when entity mappings disagree with the real schema. **Log that clearly**: a
`SchemaManagementException` at boot means the canonical migrations have moved ahead of this repo's
entities, which is the expected and desired outcome of the ownership rule — not a bug to work around
by relaxing `ddl-auto`.

**Log the Flyway migration outcome at `INFO`**: version before, version after, and each migration
applied. Because this backend is the sole DDL executor, that log is the project's only record of when
the schema changed, and it is worth being explicit rather than leaving it to Flyway's default output.

---

## Request logging

One `INFO` line per request, on completion, from a filter or interceptor:

```
method, path (route pattern, not the raw URI), status, durationMs, traceId,
code (when an error), userId (when authenticated)
```

**The route pattern, not the raw URI.** `/api/v1/reservations/{id}` rather than
`/api/v1/reservations/0192f3a1-…`, so lines aggregate and a reservation id does not appear in every
line. `HandlerMapping.BEST_MATCHING_PATTERN_ATTRIBUTE` supplies it.

**No query string**, as a blanket rule rather than a per-route judgment.

`userId` but never email, name, or any other personal field.

---

## Health

`GET /health`, per
[api-contracts.md](../../shared/api-contracts.md#get-health--public): `200` with
`{status, database, version, backend: "springboot"}`, `503` when the database is unreachable.

> **A custom controller, not Actuator's `/actuator/health`.** The contract fixes the path and the
> body, and Actuator's shape is its own. Exposing both would mean two health endpoints with different
> responses. Actuator is otherwise absent —
> [architecture-specification.md](./architecture-specification.md#deliberately-absent) — partly for
> this reason and partly because `/actuator/env` and `/actuator/configprops` expose resolved
> configuration including secrets.

The database check is a real `SELECT 1`, not a cached flag —
[AC-CC-05](../../shared/acceptance-criteria.md#ac-cc-05--health-check-reflects-real-database-state)
asserts it reflects actual state.

**Health is not logged at `INFO` per call.** If anything ever polls it, it would drown the log.

---

## Startup and shutdown

**Startup, at `INFO`:** port, active profile, log level, the Flyway version applied, and the resolved
database host and name — **never the full datasource URL or password.** A startup banner is the most
common place a connection string with a password gets printed.

**Graceful shutdown:** `server.shutdown=graceful` with a timeout, so in-flight requests finish before
the connection pool closes. Log each phase. Without it, a restart during a booking leaves the client
with no response — the transaction itself is safe, since the database rolls back.

---

## Deliberately absent

| Absent | Why |
|--------|-----|
| Log shipping — Loki, ELK, CloudWatch | Nowhere to ship to. Logs go to stdout, which is where a container log collector would pick them up if one existed |
| APM — New Relic, Datadog, Elastic APM | Nothing collects, and each is an agent in the process |
| Micrometer, Prometheus, `/actuator/metrics` | No scraper. The one performance check worth having is an `EXPLAIN` assertion in the test suite, per [non-functional-requirements.md](../../shared/non-functional-requirements.md#response-time-targets) |
| Actuator beyond the custom health controller | Exposes configuration and internals — [security-implementation.md](./security-implementation.md#secrets) |
| OpenTelemetry, Sleuth, distributed tracing | One service. `traceId` already correlates within it, and there is no collector |
| Sentry or any error-reporting service | Nowhere to send to |
| Audit logging as a system | Partially covered by columns; named as a real gap in [security-principles.md](../../shared/security-principles.md#out-of-scope-and-why-that-line-is-acceptable) |
| Log rotation, file appenders | stdout only; rotation is the container runtime's job |
| Alerting | Nothing is running to alert on |
| `org.hibernate.orm.jdbc.bind` logging | Would log bound parameters, including passwords |
| Request/response body logging | Forbidden — see redaction |
