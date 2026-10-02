# Error Handling — AI Service

How `hotelapp-ai-service` fails: the problem codes it adds, how backend errors pass through it,
how a failure mid-stream is reported, and what an MCP client sees.

The error catalogue itself is owned by
[api-contracts.md](../../shared/api-contracts.md) and the cross-backend mapping rules by both
backends' own `error-handling.md`. **This document does not restate either.** It covers the three
things that are new here: a probabilistic dependency, a streaming response, and a second protocol.

> **This document is not part of the byte-identical pair.** `stacks/nodejs/error-handling.md` and
> `stacks/springboot/error-handling.md` share sections 1–5 because those two components must be
> indistinguishable on the wire. This service is a different kind of component and is not held to
> that equivalence — but it emits the same RFC 9457 shape, and clients branch on `code` here
> exactly as they do everywhere else.

---

## 1. New problem codes

These are **additions to the catalogue in
[api-contracts.md](../../shared/api-contracts.md)**, which remains their owner. Listed here with
what raises each.

| Code | HTTP | Raised when |
|------|------|-------------|
| `AI_UNAVAILABLE` | `503` | No provider configured, provider unreachable, or the circuit is open. The expected state when the Compose demo runs without an API key |
| `AI_TIMEOUT` | `504` | The provider exceeded the call's explicit deadline |
| `AI_RATE_LIMITED` | `429` | The **provider** rate-limited us. Distinct from `RATE_LIMITED`, which means *this service* limited the caller — conflating them tells the guest to slow down when the problem is upstream |
| `AI_CONTENT_FILTERED` | `422` | The provider refused to answer on policy grounds |
| `RETRIEVAL_FAILED` | `503` | The vector store is unreachable or the hybrid query failed. Separate from `AI_UNAVAILABLE` because the remedies differ entirely |
| `QUESTION_TOO_LONG` | `400` | Input exceeds the configured ceiling, checked before any model call so an oversized input costs nothing |

`AI_UNAVAILABLE` is the **expected, designed** state rather than an exceptional one — see §4.

---

## 2. Backend errors pass through semantically

When a tool or a RAG answer needs live data, `gateways/hotelapp.py` calls a backend, and that
backend may legitimately refuse.

> **A Problem Details response from a backend is translated, never re-interpreted.** A `409
> CANCELLATION_WINDOW_CLOSED` from `POST /reservations/{id}/cancel` surfaces with that same
> `code`. It does not become a generic failure, and it is **never** handed to the model to
> paraphrase into an explanation of its own.

The reason is the one this project has been consistent about since Phase 1: clients branch on
`code`, never on `detail`. A model asked to explain a refusal will produce fluent text that
sometimes states the wrong rule — "you can cancel up to 24 hours before" when the system enforces
48. The code is authoritative; prose about the code is generated from a fixed template keyed on
it, exactly as both frontends already do via their error-message tables.

**`401` from a backend is not retried, ever.** It means the forwarded session is dead, and the
global rule in [state-management.md](../react/state-management.md) applies unchanged. Retrying
would be the token-refresh behaviour [decision-log.md](../../shared/decision-log.md) entry 2
removed from this project.

---

## 3. Failing mid-stream

`POST /api/v1/assistant/ask` streams over SSE, which creates a problem the rest of the project
does not have: **once the response has started, the status code is already sent.** A failure
during generation cannot become a `503`.

The contract:

| When the failure happens | What the client sees |
|--------------------------|----------------------|
| Before the first byte | Ordinary Problem Details response with the right status |
| After streaming has begun | A terminal SSE `error` event carrying the same `{code, detail, traceId}` body, then the stream closes |

```
event: error
data: {"code":"AI_TIMEOUT","detail":"…","traceId":"…"}
```

> **Design Decision — a mid-stream failure is a terminal event, never a silently truncated
> stream.** A stream that simply stops is indistinguishable from a network drop, and the client
> cannot tell whether the answer was complete. Both frontends must treat a `done` event as the
> only successful terminator, and anything else — `error`, or a close without `done` — as a
> failure. Partial text already rendered is **not** retracted; it is marked incomplete, because
> removing text a guest has already read is worse than labelling it.

Retrieval happens before generation, so retrieval failures are always pre-stream and get a real
status code. That ordering is deliberate.

---

## 4. Unavailability is a designed state, not an error path

The availability requirement in
[ai-enablement-overview.md §10](../../shared/ai-enablement-overview.md#10-non-functional-targets)
is load-bearing: **the rest of HotelApp must be unaffected when this service is down or
unconfigured.**

- With no API key the service **starts normally** and reports `AI_UNAVAILABLE` on AI endpoints.
  It does not crash-loop, and it does not block the Compose demo.
- `GET /api/v1/assistant/health` reports provider reachability and backend reachability
  **separately**, because "up" and "able to do anything useful" are different facts.
- A circuit breaker opens after repeated provider failures and returns `AI_UNAVAILABLE`
  immediately rather than making every guest wait for a timeout that is already known to be
  coming.
- Both frontends render AI features as unavailable rather than broken. No existing screen regresses
  — booking, search and account management never depended on this service.

---

## 5. MCP errors

MCP has its own error shape, so Problem Details are translated at the transport edge in
`transport/mcp/`:

- **The `code` survives the translation.** An MCP tool error carries the originating problem code
  in its structured content, so an agent can act on `CANCELLATION_WINDOW_CLOSED` rather than
  parse a sentence.
- **Authorization failures are not explained.** A token that fails audience validation gets a
  `401` with the RFC 9728 `WWW-Authenticate` challenge and nothing more. Telling a caller *why*
  its token was rejected is an oracle.
- **A tool that cannot run returns an error, not an empty success.** An agent handed `[]` will
  report "no rooms available," which is a wrong answer rather than a failure — the single most
  damaging error-handling mistake available in this service.
- **Schema validation happens before dispatch**, in the service, not in the prompt. A malformed
  tool call is rejected without reaching a backend.

---

## 6. What must never happen

| Never | Why |
|-------|-----|
| A provider's raw error text reaching a client | It can echo prompt content, which may include retrieved documents or guest data |
| A model being asked to explain or paraphrase a problem code | It will eventually state a rule the system does not enforce |
| An empty result substituted for a failure | "No availability" and "could not check availability" are different answers, and only one is honest |
| A `401` from a backend triggering a retry or re-auth | [decision-log.md](../../shared/decision-log.md) entry 2 |
| A truncated stream without a terminal event | Indistinguishable from a network failure |
| An AI failure degrading a non-AI feature | Breaks the additive-ness guarantee, and the test suite asserts against it |
| A prompt, completion, or retrieved chunk in an error log at INFO | [logging-observability.md](./logging-observability.md) |
