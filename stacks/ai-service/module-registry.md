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
| `transport/` | `services/`, `domain/`, `config/` | `langchain`, `openai`, `psycopg`, `httpx` |
| `services/` | `gateways/`, `repositories/`, `domain/`, `config/`, `langchain*` | `fastapi`, `fastmcp`, `authlib` |
| `gateways/` | `domain/`, `config/`, `httpx` | `repositories/`, `psycopg`, any `langchain*` |
| `repositories/` | `domain/`, `config/`, `psycopg` | `gateways/`, `httpx`, any `langchain*` |
| `domain/` | the standard library | everything else in this project |

These are enforced in CI by an import-linter rule, not by good intentions — see
[devops-pipeline.md](./devops-pipeline.md).

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
| `search.py` | Natural language → `GET /availability` parameters, via one structured-output call. **Never** executes the search itself; it produces parameters and hands them to the gateway |
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
> the application. Its public surface mirrors the endpoints it wraps — `get_availability`,
> `get_property`, `get_reservation`, `patch_reservation`, `cancel_reservation` — and it adds no
> method that composes or derives anything, because deriving is what the backends are for.

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
