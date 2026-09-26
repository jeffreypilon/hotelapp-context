# Logging and Observability — Angular

Deliberately thin, and it should stay that way.

**There is nowhere to send client telemetry.** This project has no hosted environment, no log aggregation, no
APM, and no error-reporting backend — per
[non-functional-requirements.md](../../shared/non-functional-requirements.md#availability) and
[devops-pipeline-overview.md](../../shared/devops-pipeline-overview.md#deliberately-absent). Building a
client-side observability layer with no receiver would be inventing infrastructure to look thorough, which is
the opposite of what this project is for.

So this document covers two real things: what a developer sees in the console, and what a **user** sees when
something fails.

---

## What the user sees

The only observability that matters here, because it is the only kind anyone actually consumes.

Every failure produces visible, actionable feedback, per
[error-handling.md](./error-handling.md). The requirements worth restating as rules:

- **No silent failures.** A spinner that stops with nothing rendered is the worst possible outcome — worse
  than an error message, because the user cannot tell whether to wait, retry, or leave.
- **`traceId` is surfaced for `INTERNAL_ERROR`**, as small print: "Reference: 0192f3a1-9e33-…". It is the only
  correlation mechanism this project has, and it is the difference between "it broke" and a developer finding
  the request in the backend log.
- **The global `ErrorHandler`** catches uncaught exceptions and renders the S15 fallback with a reload action.

`traceId` is the whole observability story, and it is worth noticing that it works: the backend puts one in
every Problem Details response and echoes it into its own logs, so a user reporting a reference number is
enough to find the server-side cause. That is a complete loop with no infrastructure.

---

## The console logger

One small injectable service, `shared/util/logger.ts`. Not a library.

```ts
@Injectable({ providedIn: 'root' })
export class Logger {
  debug(msg: string, ctx?: object): void { /* … */ }
  info(msg: string, ctx?: object): void { /* … */ }
  warn(msg: string, ctx?: object): void { /* … */ }
  error(msg: string, err?: unknown, ctx?: object): void { /* … */ }
}
```

| Level | Development | Production build |
|-------|-------------|------------------|
| `debug` | Console | **Suppressed** |
| `info` | Console | **Suppressed** |
| `warn` | Console | Console |
| `error` | Console | Console |

It exists for two reasons rather than as ceremony: `console.log` in committed code is forbidden by
[coding-standards.md](./coding-standards.md#forbidden), so there has to be a permitted alternative; and the
redaction rule below needs one place to live.

**What is worth logging at `warn` or `error`:**

| Situation | Level | Why |
|-----------|-------|-----|
| An `ApiError` whose `code` is not in the mapping | `warn` | The backend added a code — a legal non-breaking change. This is the signal that this client needs updating |
| An `errors[]` `field` matching no form control | `warn` | Real contract drift between client and server |
| An uncaught exception reaching `ErrorHandler` | `error` | With the stack |
| `safeImageUrl` rejecting a URL | `warn` | Either bad admin data or an injection attempt |
| Config resolution falling back to the compiled value | `info` | Explains a wrong-backend surprise in one line |
| A store's `rxMethod` receiving an error after its stream was expected to continue | `warn` | The `tapResponse` failure mode from [testing-standards.md](./testing-standards.md#store-tests), which is otherwise symptomless |

The first two are the valuable ones. Both are cases where the code recovers gracefully and the user sees
something reasonable, which means **nothing else would ever reveal them**. The last is Angular-specific and
worth having precisely because a dead `rxMethod` stream produces no error at all — the store simply stops
responding.

---

## Redaction — the one hard rule

> **Never logged, at any level, in any environment:**
>
> - `payment.cardNumber`, `payment.cvv`, `payment.expiryMonth`, `payment.expiryYear`
> - `password`, `currentPassword`, `newPassword`
> - Any request body from `POST /reservations` or the auth endpoints
> - Cookie values — unreachable anyway, since the session cookie is `HttpOnly`
> - Full request or response bodies, as a blanket rule

Per [security-principles.md](../../shared/security-principles.md#logging-and-data-handling), the realistic
way this gets violated is not malice but a well-meaning "log the whole request" during debugging. So the
logger takes a `ctx` object and **redacts known-sensitive keys before writing**, rather than trusting each
call site:

```ts
const REDACT = new Set(['cardNumber', 'cvv', 'expiryMonth', 'expiryYear',
                        'password', 'currentPassword', 'newPassword']);
```

Redaction is recursive over nested objects, since the payment block arrives nested under `payment`.

**The HTTP interceptor never logs a request or response body.** It may log method, path, and status. That
restriction is what makes the card-data rule in
[security-implementation.md](./security-implementation.md#payment-data) enforceable rather than aspirational,
and it matters more here than in the React client: an interceptor sits across *every* request, so a logging
line added there for debugging captures everything at once.

**The global `ErrorHandler` must not log an `ApiError` body either.** It receives unhandled promise
rejections, which means a request failure the interceptor already handled can reach it; filter those by
instance, both to avoid double-reporting and to avoid logging a payload the interceptor deliberately did not.

---

## Angular DevTools

Angular DevTools is a browser extension rather than a dependency, so there is nothing to include or exclude
from the bundle — a small advantage over the React client, which ships its Query devtools behind a dynamic
import.

Worth knowing: with signals and `provideZonelessChangeDetection()`, the DevTools profiler is the practical way
to confirm `OnPush` and `computed()` are doing what
[coding-standards.md](./coding-standards.md#signals-and-reactivity) assumes — particularly on the calendar
grid (S11), the one screen where render cost is real.

---

## Deliberately absent

| Absent | Why |
|--------|-----|
| Sentry, Rollbar, Bugsnag, or any error-reporting service | Nowhere to send to, and it would mean a third-party script in an origin that handles credentials — forbidden by [dependency-policy.md](./dependency-policy.md) |
| Google Analytics, Segment, PostHog, any analytics | No analytics requirement exists. Also a third-party script |
| LogRocket, FullStory, Hotjar, any session replay | Would record a payment form and a guest's personal details. Actively inappropriate here regardless of infrastructure |
| Real User Monitoring, Web Vitals reporting | Nowhere to send to. Vitals are measurable locally in DevTools when needed |
| A log-shipping endpoint on the backend | The API has no logging endpoint, and adding one would be inventing contract surface |
| Distributed tracing, OpenTelemetry in the browser | The backend's `traceId` already provides correlation, and there is no collector |
| Feature flags | No deployment to flag against |
| A user-facing feedback widget | Third-party script; and there is no one receiving feedback |

**If a hosted environment ever exists**, the first thing worth adding is error reporting, and the decision
would need revisiting alongside the third-party-script prohibition in
[dependency-policy.md](./dependency-policy.md) — that prohibition is the actual blocker, not the absence of a
receiver. Recorded here so the sequence is clear; not a plan.
