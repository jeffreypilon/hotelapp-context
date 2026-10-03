# Module Registry — AI Service

Inventory of every module in `hotelapp-ai-service`, what it owns, and what it is allowed to
import. The folder layout itself is in
[architecture-specification.md](./architecture-specification.md#folder-layout); this document is
the per-module detail and the import rules that make the layering checkable rather than
aspirational.

**A capability lives in exactly one module.** Where two modules appear to do the same thing, one
is wrong — the same rule the specification repository applies to its own documents.

---

## Import rules, stated once

| Layer | May import | May **not** import |
|-------|-----------|-------------------|
| `transport/rest/` | `services/`, `domain/`, `config/` | `langchain`, `openai`, `psycopg`, `httpx` |
| `transport/mcp/` | `services/`, `domain/`, `config/`, **and `gateways/` directly** | `langchain`, `openai`, `psycopg` |
| `services/` | `gateways/`, `repositories/`, `domain/`, `config/`, `langchain*` | `fastapi`, `fastmcp`, `authlib` |
| `gateways/` | `domain/`, `config/`, `httpx` | `repositories/`, `psycopg`, any `langchain*` |
| `repositories/` | `domain/`, `config/`, `psycopg` | `gateways/`, `httpx`, any `langchain*` |
| `domain/` | the standard library | everything else in this project |

These are enforced in CI by an import-linter rule, not by good intentions — see
[devops-pipeline.md](./devops-pipeline.md).

> **Design Decision — `transport/mcp/` is allowed to call `gateways/` directly; `transport/rest/`
> is not.** Found and resolved during AI Step 5, not planned in advance. The REST transport routes
> every call through `services/` because its routes need a response already shaped by orchestration
> logic (or none exists, as for pure reads that still go through a service for consistency). Most
> MCP tools have no orchestration step at all — `list_properties`, `get_property`,
> `list_room_types` are 1:1 proxies over a single gateway call, and inserting a `services/` module
> that only forwards the call would be ceremony with no behavior. The one MCP tool that *does* have
> real logic, `search_availability`'s no-property fan-out, lives in `services/availability.py` as
> the table above requires — this exception is for pure proxying only, never for anything with
> actual orchestration in it. The invariant this project actually cares about — **`gateways/hotelapp.py`
> is the only module that ever calls a backend**, and **no model call happens outside `services/`**
> — holds either way, which is why the import-linter contract carves out exactly one edge
> (`gateways.hotelapp -> httpx`) rather than exempting `transport/mcp/` from the `httpx`-forbidden
> rule generally: `services/llm_client.py`'s own `httpx` import is still caught if `transport/mcp/`
> ever reaches it.

---

## `transport/` — protocol edges

| Module | Owns |
|--------|------|
| `rest/assistant.py` | `POST /api/v1/assistant/ask`. SSE framing, the three event types, client-disconnect handling |
| `rest/search.py` | `POST /api/v1/assistant/search`. Natural-language search request and response shapes |
| `rest/health.py` | `GET /api/v1/assistant/health`. Reports provider reachability and backend reachability separately |
| `rest/problem.py` | RFC 9457 serialization. **The only module that builds a Problem Details body** |
| `mcp/tools.py` | Every MCP tool definition and its JSON schema. **Imported by both transports; a tool defined anywhere else is a defect** |
| `mcp/stdio.py` | stdio entry point. Registers the public tool subset only |
| `mcp/http.py` | HTTP entry point. Registers the full surface; requires a validated token |
| `mcp/resource_metadata.py` | The RFC 9728 `/.well-known/oauth-protected-resource` document, and audience validation (RFC 8707) |
| `oauth/server.py` | Authlib authorization server: `/authorize`, `/token`, metadata |
| `oauth/consent.py` | The server-rendered consent page and its form handling |
| `oauth/introspection.py` | Opaque-token validation, and the token → `sessions` row binding |

> `rest/health.py` reports **two** liveness facts, deliberately. "The AI service is up" and "the
> AI service can do anything useful" are different questions, and collapsing them is how a green
> health check coexists with a broken assistant.

---

## `services/` — orchestration

| Module | Owns |
|--------|------|
| `assistant.py` | The LangGraph retrieval graph and its state. Every node, the single bounded retry edge, and the grading step |
| `search.py` | Natural language → `GET /availability` parameters, via one structured-output call against the live property list. When a property is named or implied, one `get_availability` call, verbatim envelope passthrough. When none is resolvable, one call **per property**, merged and re-paginated — the response shape never changes, only how many backend calls produce it |
| `ingestion.py` | `corpus/` → parsed → chunked → embedded → `ai_chunks`. Idempotent per document hash |
| `evaluation.py` | The RAGAS harness over `eval/golden_set.yaml`; writes `ai_eval_runs` |

**`services/` is the only layer permitted to construct a prompt or call a model.** A model call
in `transport/` or a repository is a layering violation, and is the specific mistake that makes a
service impossible to test without a provider key.

---

## `gateways/` — the one way out

| Module | Owns |
|--------|------|
| `hotelapp.py` | Every HTTP call to a HotelApp backend. The shared `httpx.AsyncClient`, session-cookie forwarding, timeouts, and Problem Details pass-through |

> **This is the chokepoint that enforces the REST-only rule.** It is the most heavily tested module
> in the service and the first place to look when an answer contains a number that disagrees with
> the application. Its public surface mirrors the endpoints it wraps — `get_properties`,
> `get_property`, `get_availability`, `get_reservation`, `patch_reservation`,
> `cancel_reservation` — and it adds no method that composes or derives anything, because deriving
> is what the backends are for. `get_properties` exists specifically so F2 can resolve a property
> named or implied in free text ("a room in Burlington") against the **live** property list rather
> than names baked into a prompt, which would go stale the moment a property is renamed or added.

---

## `repositories/` — the only SQL

| Module | Owns |
|--------|------|
| `documents.py` | `ai_documents`: source metadata, content hash, ingestion timestamps |
| `chunks.py` | `ai_chunks`: the chunk rows, their vectors, and **the hybrid retrieval query** |
| `eval_runs.py` | `ai_eval_runs`: one row per evaluation run, with its metric values |

> `chunks.py` holds the single most consequential piece of SQL in the service — dense similarity
> and full-text ranking in one statement, each producing its own ranked set for fusion. It is
> explicitly **not** mockable in integration tests
> ([dependency-policy.md](./dependency-policy.md#why-mocking-the-retrieval-path-is-prohibited-specifically)),
> because a mocked version asserts the author's belief about PostgreSQL rather than PostgreSQL.

No repository reads a business table. `grep -rE 'reservations|properties|room_types|users'` over
`repositories/` returning a hit is a defect, and CI greps for exactly that.

---

## `domain/` — pure functions

The AI service's equivalent of the four pure functions both backends isolate. No I/O, no clock,
no model, no randomness.

| Module | Owns | Why it is pure |
|--------|------|----------------|
| `fusion.py` | Reciprocal Rank Fusion over two ranked lists | Rank arithmetic with real edge cases — ties, a document present in one list only, an empty list. Deterministic and exactly assertable |
| `chunking.py` | Chunk-boundary selection and heading-path propagation | Boundary decisions must be reproducible: the same document must chunk identically on every ingest, or citations drift between runs |
| `citations.py` | Chunk → rendered citation, including heading path and document title | Pure formatting, and the part a reader actually checks |

Each ships with unit tests in the same commit, per the standing rule both frontend repos adopted
after Phase 7 — new pure logic with non-obvious behaviour is not exempt because it is small.

**`citations.py`'s output format is fixed**, so the SSE contract and a future frontend have a
stable target rather than an implicit one: a numbered footnote per citation, document title, then
the specific section —

```
[1] Cancellation and Rate-Type Policy — The standard cancellation window
```

The number matches the order citations are emitted as `citation` events during the stream, so a
client can render footnote markers inline without re-deriving the association itself.

---

## `prompts/` — versioned as files

Prompts are files, not string literals, and not rows in a SaaS prompt manager
([dependency-policy.md](./dependency-policy.md#explicitly-not-allowed)).

| File | Used by |
|------|---------|
| `answer.md` | `services/assistant.py` generation node |
| `grade_retrieval.md` | the grading node |
| `rewrite_query.md` | the conversational-rewrite node |
| `extract_search_params.md` | `services/search.py` |

A prompt change is a code change: it shows up in review, it is attributable in `git blame`, and
it is gated by the evaluation suite like any other behavioural change.

---

## Not yet built

Recorded so their absence reads as sequencing rather than oversight.

| Missing | Waiting on |
|---------|-----------|
| A staff-facing service module (F4) | Admin endpoints and the admin UI in both frontends — [ai-enablement-overview.md §2](../../shared/ai-enablement-overview.md#2-scope) |
| Profile and password MCP tools | Deliberately deferred, possibly permanently — [future-enhancements.md](../../shared/future-enhancements.md) |
| A semantic cache module | Planned for `services/`, after first-pass latency and cost are measured rather than guessed |
