# Logging and Observability — AI Service

Structured logging, trace propagation, redaction, and LLM tracing for `hotelapp-ai-service`.

> **This document is deliberately *not* thin, and that is a divergence worth explaining.** The
> equivalent document in the other four stacks is short on purpose — there is no environment to
> observe, so console logging plus redaction is the whole story
> ([devops-pipeline-overview.md](../../shared/devops-pipeline-overview.md#deliberately-absent)).
> That reasoning does not transfer here. A probabilistic component whose behaviour depends on a
> remote model, whose quality cannot be asserted by a unit test, and which spends money per
> request is **not debuggable from logs alone**. Tracing is how a wrong answer is diagnosed at
> all, and cost per request is a number this project claims and therefore has to measure.

---

## 1. Structured logging

`structlog`, JSON to stdout, one event per line. No `print()`, ever
([coding-standards.md](./coding-standards.md#forbidden)).

Levels follow the project convention:

| Level | Used for |
|-------|----------|
| `ERROR` | A request failed in a way that needs attention |
| `WARN` | Degraded but handled — circuit opened, provider rate-limited, retrieval returned nothing |
| `INFO` | One line per request, plus lifecycle events |
| `DEBUG` | Demo-visibility detail, including **redacted** prompt and retrieval traces — off by default |

`LOG_LEVEL=DEBUG` enabling redacted body-level detail mirrors what both backends already do, and
exists for the same reason: a live demo benefits enormously from being able to show the work.

---

## 2. `traceId`

The project-wide `traceId` convention is unchanged. In Python it propagates through
**`contextvars`**, which is the direct equivalent of Node's `AsyncLocalStorage` and survives
`await` boundaries without being threaded through every signature.

- An inbound `traceId` is **adopted**, not replaced. A request originating in React carries one
  trace through the frontend, this service, and the backend it calls.
- `gateways/hotelapp.py` **forwards the `traceId` header** on every backend call, so a single
  identifier spans all three components.
- The same `traceId` is attached to the Langfuse trace, which is what makes a log line and a model
  trace joinable.

---

## 3. Redaction

Masking happens **at the logger**, via `structlog` processors — not at call sites. A rule enforced
per call site is a rule that is eventually forgotten at one of them.

| Masked | Why |
|--------|-----|
| `cookie`, `set-cookie` | The session is the entire credential |
| `authorization` | OAuth tokens |
| `api_key`, `openai_api_key` | Provider credentials |
| `prompt`, `completion`, `question`, `answer` | May contain guest data, and prompts carry retrieved content |
| Retrieved chunk text | Corpus content is not secret, but it is bulky and can carry guest-specific context once assembled |
| `email`, `phone`, address fields | Same PII rules as everywhere in this project |

**Chunk *identifiers* are logged; chunk *text* is not.** That is the distinction that makes
retrieval debuggable without putting document bodies in logs — you can see exactly which chunks
were selected, and look them up.

---

## 4. One line per request

Every request emits a single structured INFO line on completion:

```json
{
  "event": "assistant.ask",
  "traceId": "…",
  "route": "POST /api/v1/assistant/ask",
  "status": 200,
  "durationMs": 2840,
  "retrievalMs": 310,
  "rerankMs": 95,
  "generationMs": 2401,
  "firstTokenMs": 1180,
  "chunkIds": ["…", "…"],
  "model": "…",
  "promptTokens": 1840,
  "completionTokens": 212,
  "costUsd": "0.0043",
  "cacheHit": false,
  "backend": "springboot"
}
```

Three fields deserve justification:

- **`firstTokenMs` is separate from `durationMs`.** Perceived latency is the first token; the
  [§10](../../shared/ai-enablement-overview.md#10-non-functional-targets) target is stated against
  it, so it has to be measured rather than inferred.
- **`costUsd` is a string**, not a float — the project's money rule applies to money this service
  spends, not just money it displays
  ([coding-standards.md](./coding-standards.md#money-is-a-string-and-parsing-it-is-a-defect)).
- **`backend` records which backend answered.** When the same question behaves differently across
  Spring Boot and Node, this is the field that makes that visible — and a difference there is a
  backend defect, not an AI one.

---

## 5. LLM tracing

**Langfuse, self-hosted**, so the "no cloud" posture holds
([devops-pipeline-overview.md](../../shared/devops-pipeline-overview.md#deliberately-absent)).
Optional at runtime: absent configuration disables tracing without failing anything.

A trace captures what a log line cannot:

- The **resolved prompt** actually sent, after template rendering.
- **Every retrieved chunk with its scores** — dense, sparse, fused, and post-rerank — which is the
  only practical way to tell a retrieval failure from a generation failure.
- Each **graph node** as a span, including whether the retry edge fired.
- **Token counts and cost** per call, aggregated per request.
- The **evaluation score** for that trace, when it came from a golden-set run.

> **Design Decision — tracing is treated as a debugging tool, not a logging destination.** It
> stores prompts and retrieved text, which §3 deliberately keeps out of logs. That is acceptable
> because Langfuse is self-hosted, access-controlled, and part of the development environment
> rather than a third party — but it means **tracing must never become a route by which guest data
> leaves the deployment**. A hosted tracing provider would change this decision, not just its
> configuration.

---

## 6. What is not here

| Absent | Why |
|--------|-----|
| APM, metrics backends, alerting | Nothing is running to observe — unchanged from the project-wide decision |
| Log aggregation | stdout, read by `docker compose logs` |
| Distributed tracing across infrastructure | `traceId` correlation is sufficient at three components |
| Dashboards | Langfuse supplies enough for development; building more would be observing a system nobody operates |
| User-behaviour analytics | Not a product |

The one thing deliberately *added* relative to the rest of the project is **per-request cost
attribution**, because it is a claim this project makes — and an unmeasured cost figure is a guess.
