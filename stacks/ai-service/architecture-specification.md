# Architecture Specification — AI Service (Python / FastAPI)

Structure of `hotelapp-ai-service`: layering, folder layout, the three entry points, the
retrieval pipeline, and where LLM calls are allowed to happen.

Python 3.13, FastAPI, LangGraph, pgvector, PostgreSQL 18.6. The system-level shape — what the AI
capabilities are, why this is a separate service, and the decisions that bind it — is in
[ai-enablement-overview.md](../../shared/ai-enablement-overview.md) and is not restated here.

---

## Fixed at the system level

| Constraint | Source |
|-----------|--------|
| Business data is read over **REST, never SQL** | [ai-enablement-overview.md §3](../../shared/ai-enablement-overview.md#3-component-shape) |
| This service owns `ai_*` tables and **no others** | same |
| Embeddings live in the existing PostgreSQL, via pgvector | [§4](../../shared/ai-enablement-overview.md#4-data-and-storage) |
| **Flyway is still the sole DDL executor** — this service never creates schema | [versioning-strategy.md](../../shared/versioning-strategy.md#database-schema-migrations) |
| The model holds no credentials; the caller's session is passed through | [§5](../../shared/ai-enablement-overview.md#5-the-authorization-model-and-why-it-is-the-interesting-part) |
| HTTP API mounts under `/api/v1/`, so the session cookie is in scope | same |
| MCP server is a **resource server**, never an authorization server | [§6](../../shared/ai-enablement-overview.md#6-the-mcp-server) |
| Hybrid retrieval → RRF → rerank → top-5 | [§7](../../shared/ai-enablement-overview.md#7-retrieval-architecture) |
| Every existing acceptance criterion must still pass with this service **stopped** | [§10](../../shared/ai-enablement-overview.md#10-non-functional-targets) |

---

## The REST-only rule, and what it means for this repo

> **This service cannot query business data.** That is not a gap to fix; it is the constraint the
> component exists inside, recorded in
> [ai-enablement-overview.md §3](../../shared/ai-enablement-overview.md#3-component-shape).
>
> **The REST contract is the only way in.** In this repository that means:
>
> - There is **no** `reservations`, `properties`, `room_types` or `users` access from Python, in
>   any form — no SQL, no read replica, no "just for reporting" exception. `grep` for those table
>   names in `repositories/` should return nothing.
> - Pricing, availability, cancellation deadlines and allocation are **never recomputed here**.
>   They are fetched. If an answer needs a number, the number comes from an endpoint that already
>   computed it under test.
> - The service works against **either backend**, unmodified, selected by configuration. If a
>   behaviour depends on which backend is running, that is a defect in one of the backends and
>   belongs in [defect-log.md](../../shared/defect-log.md), not a branch here.
> - A backend being down degrades AI features to an explicit unavailable state. It never degrades
>   into guessing.
>
> **Why, in one line:** an AI layer that computes its own availability can hallucinate a room that
> does not exist, and no amount of prompt engineering fixes a wrong number that was computed
> correctly from the wrong source.
>
> **Consequences that show up as real work in this repo:** every tool and every RAG answer that
> touches live data makes an HTTP call with the caller's session; `gateways/hotelapp.py` is the
> single chokepoint for that and is the most heavily tested module in the service; and
> integration tests need a running backend, not a database fixture — see
> [testing-standards.md](./testing-standards.md).

---

## Layering

```
Transport layer     FastAPI routers, MCP tool definitions, OAuth endpoints.
transport/          Knows HTTP and MCP. Knows nothing about retrieval,
                    prompts, or models.
      │
Service layer       Orchestration: the retrieval graph, parameter extraction,
services/           ingestion, evaluation. Owns every LLM call and every
                    prompt. The only layer allowed to import langchain.
      │
      ├─────────────────────────────┐
      ▼                             ▼
Gateway layer               Repository layer
gateways/                   repositories/
The only code that          The only code that emits SQL.
calls a HotelApp            Touches ai_* tables only.
backend.

domain/             Pure functions. No I/O, no clock, no model calls.
                    Imported by any layer; imports nothing but stdlib.
```

Four rules, each of which is checkable:

1. **`transport/` never imports `langchain`, `openai`, or `psycopg`.** A router's job is to parse,
   authorize, delegate and serialize.
2. **`services/` never imports `fastapi` or `mcp`.** The same orchestration is reachable from a
   REST route, an MCP tool, and a test, which is only true if it does not know which one called.
3. **`gateways/` and `repositories/` never import each other.** HTTP and SQL are separate worlds;
   joining them is the service layer's job.
4. **`domain/` imports nothing from this project.** Same discipline as `domain/` in both backends
   — pure, deterministic, unit-tested directly.

> **Design Decision — `domain/` exists here for the same reason it exists in the backends.**
> Reciprocal Rank Fusion, chunk-boundary selection and citation formatting are pure functions with
> non-obvious behaviour and real edge cases (ties in RRF, a chunk boundary landing mid-sentence, a
> citation spanning two chunks). Both backends already isolate their four pure functions this way
> and unit-test them without infrastructure. The AI service is not exempt from that discipline
> merely because the rest of it is probabilistic — if anything, the deterministic parts matter
> *more* here, because they are the only parts that can be asserted exactly.

---

## Folder layout

```
hotelapp-ai-service/
  pyproject.toml              uv-managed; dependencies pinned, see dependency-policy.md
  src/hotelapp_ai/
    main.py                   FastAPI app assembly; nothing else
    config/
      settings.py             pydantic-settings; validated once at startup
    transport/
      rest/
        assistant.py          POST /api/v1/assistant/ask        (SSE)
        search.py             POST /api/v1/assistant/search
        health.py             GET  /api/v1/assistant/health
        problem.py            RFC 9457 serialization
      mcp/
        tools.py              tool definitions; one place, both transports
        stdio.py              stdio entry point — public tool surface only
        http.py               HTTP entry point — full surface, OAuth-protected
        resource_metadata.py  RFC 9728 /.well-known document
      oauth/
        server.py             Authlib authorization server
        consent.py            server-rendered consent page
        introspection.py      opaque-token validation
    services/
      assistant.py            the LangGraph retrieval graph
      search.py               natural language → availability parameters
      ingestion.py            corpus → chunks → embeddings → ai_chunks
      evaluation.py           RAGAS harness over the golden set
    gateways/
      hotelapp.py             the ONLY HotelApp backend client
    repositories/
      documents.py            ai_documents
      chunks.py               ai_chunks; the hybrid query lives here
      eval_runs.py            ai_eval_runs
    domain/
      fusion.py               Reciprocal Rank Fusion — pure
      chunking.py             boundary selection — pure
      citations.py            chunk → citation rendering — pure
    prompts/                  prompt templates, versioned as files
  corpus/                     source documents; see the corpus section below
  eval/
    golden_set.yaml           committed question/answer pairs
  tests/
    unit/                     domain/ and pure service logic
    integration/              against a running backend + Testcontainers Postgres
```

`main.py` assembles and does nothing else — no route logic, no startup side effects beyond wiring.
Both MCP entry points import the *same* `tools.py`; a tool defined twice is a tool that will
diverge.

---

## Three entry points, one service

Unusual enough to be worth stating plainly: this service is reachable three ways, and they share
everything below the transport layer.

| Entry point | Protocol | Auth | Surface |
|-------------|----------|------|---------|
| `POST /api/v1/assistant/*` | HTTP + SSE | HotelApp session cookie, forwarded | F2, F3 |
| MCP over stdio | JSON-RPC on stdio | none — local subprocess | public tools only |
| MCP over HTTP | JSON-RPC over HTTP | OAuth 2.1, audience-bound | full tool surface |

The tool surface split is a security boundary, not a packaging convenience — the reasoning is in
[§6](../../shared/ai-enablement-overview.md#6-the-mcp-server) and must not be relaxed to "make
local testing easier."

### Streaming

`POST /api/v1/assistant/ask` streams over **Server-Sent Events**, not WebSockets. The exchange is
one-directional once the question is sent, SSE reconnects on its own, and it needs no protocol
upgrade through any intermediary. Three event types are emitted: `token` for generated text,
`citation` when a source is attached, and `done` with the final usage and cost figures.

> **Design Decision — perceived latency is the first token, so the graph streams before it
> finishes.** Retrieval and reranking complete before generation starts, so the first token
> arrives after the slowest *retrieval* step rather than after the whole answer. The
> [§10](../../shared/ai-enablement-overview.md#10-non-functional-targets) target of 1.5s to first
> token is achievable only this way; a buffered response would make the same work feel three times
> slower.

---

## The retrieval graph

`services/assistant.py` holds one LangGraph state graph. Its shape mirrors
[§7](../../shared/ai-enablement-overview.md#7-retrieval-architecture) exactly, so the
specification and the code can be diffed by eye:

```
  rewrite_query
        │
        ├──► dense_retrieve ──┐
        │                     ├──► fuse (RRF) ──► rerank ──► grade
        └──► sparse_retrieve ─┘                                │
                                                   ┌───────────┴───────────┐
                                            sufficient                insufficient
                                                   │                       │
                                                generate            decompose_and_retry
                                                   │                       │
                                                  end                  (once only)
```

> **Design Decision — the retry edge is bounded to one pass, in code, not in the prompt.**
> A graph that can loop is a graph that can loop forever, and an LLM asked to decide "should I try
> again" will sometimes say yes indefinitely. The retry counter lives in graph state and the
> conditional edge reads it; the model is never asked how many times it has tried. This is the
> only cyclic edge in the graph, and `tests/unit` asserts that a forced-insufficient grade
> terminates after exactly two retrieval passes.

LangGraph is used **only** for this graph. F2's parameter extraction is a single structured-output
call and uses LangChain directly — wrapping it in a state machine would add a dependency on
machinery it does not need.

---

## Ingestion, and three artefacts that are not hypothetical

`services/ingestion.py` turns `corpus/*.pdf` into `ai_chunks`. The corpus is authored as Markdown
and rendered to PDF by a committed script, so the reviewable source stays diffable while the
pipeline ingests the form a hotel would actually hand over — see
[ai-enablement-overview.md §8](../../shared/ai-enablement-overview.md#8-the-document-corpus).

The renders are deliberately *realistic* — letterhead, running headers, page numbers, tables,
figures — rather than pristine. Extracting text from the first rendered corpus with `pypdf`
surfaced three artefacts, each verified by running it rather than anticipated:

| Artefact | What it does | Required handling |
|----------|--------------|-------------------|
| **Justified text produces irregular inter-word spacing** | `may  cover  a  maximum  of  30  nights` — two or more spaces between words, from the renderer padding lines to justify | Normalise all runs of whitespace to a single space **before** chunking, matching, or embedding |
| **Line wrapping splits phrases** | `...maximum of 30` / `nights.` — a phrase spans a line break | Same normalisation. A substring search on raw extracted text silently fails, which is how a policy-consistency check passes while testing nothing |
| **Running headers and footers bleed into the text** | `HotelApp Hotels | Cancellation and Rate-Type Policy` appears once per page, as does the revision line | Strip repeated per-page furniture before chunking, or every chunk carries boilerplate that dilutes its embedding and pollutes retrieval |

> **Design Decision — normalisation happens at ingestion, not at query time.**
> It is tempting to normalise when comparing and leave the stored text as extracted. That stores
> the artefacts in the embedding: a chunk whose text carries doubled spaces and a repeated page
> header embeds to a slightly different point than the same prose would, and the error is
> invisible because nothing fails — retrieval just gets quietly worse. Normalise once, store
> clean text, and the stored vector represents the prose rather than the layout.

Ingestion is **idempotent per document hash** (`ai_documents.content_hash`): an unchanged document
is skipped rather than re-chunked and re-embedded, which is what keeps a re-run free rather than
another bill from the embeddings provider.

**Figures are invisible to this pipeline.** `pypdf` extracts text, not images. Every figure in the
corpus therefore carries a caption, and no fact may exist only in a picture — a constraint recorded
in `corpus/README.md` and enforced by review rather than by code.

---

## Calling the backends

`gateways/hotelapp.py` is the only module that may construct a request to a HotelApp backend.

- **Async `httpx` client**, created once at startup, reused. LLM-adjacent workloads are I/O-bound
  and a per-request client is the easiest way to exhaust connections under concurrency.
- **The caller's session cookie is forwarded verbatim.** The gateway has no credentials of its
  own and no code path that adds any. A request arriving without a session calls the public
  endpoints or fails — it never escalates.
- **Problem Details pass through semantically.** A `409` from `POST /reservations/{id}/cancel`
  becomes an MCP tool error carrying the original `code`, not a paraphrase. Clients branch on
  `code`, here as everywhere — see [error-handling.md](./error-handling.md).
- **Timeouts are explicit and short.** A backend that is slow must not make the assistant look
  broken; it makes a *tool call* look broken, which the graph can report.

---

## Repositories and SQL

`repositories/` uses **psycopg 3 with bound parameters**. There is no ORM.

> **Design Decision — no ORM, and no migrations from Python.**
> This service owns three tables and writes perhaps a dozen distinct queries, one of which — the
> hybrid dense + sparse retrieval — is hand-tuned SQL that no ORM would express better. An ORM
> would add a schema-modelling layer whose authority would immediately conflict with Flyway's,
> which is exactly the trap [decision-log.md](../../shared/decision-log.md) entry 3 describes for
> Prisma. Explicit SQL with explicit column lists also matches the house rule the backends already
> follow: never `SELECT *`, never serialize a row straight out.

The `ai_*` tables arrive in `shared/migrations-ai/V001__ai_tables.sql`, authored in `hotelapp-context` like every other
migration. Python asserts at startup that the expected tables and the `vector` extension exist,
and **fails fast** if they do not — the same posture as Spring Boot's `ddl-auto=validate`.

---

## Configuration

`config/settings.py` validates the whole environment once at startup via `pydantic-settings`, and
the app refuses to start on a missing or malformed value rather than failing on the first request
that needs it.

| Setting | Purpose |
|---------|---------|
| `HOTELAPP_API_BASE_URL` | Which backend to call. Default Spring Boot's `:8080`, switchable at container start |
| `LLM_PROVIDER` | `openai` \| `ollama` |
| `OPENAI_API_KEY` | Absent is a valid state — the service starts and reports AI features unavailable |
| `EMBEDDING_MODEL` | Default `text-embedding-3-small` |
| `DATABASE_URL` | `ai_*` tables only |
| `OAUTH_ISSUER`, `OAUTH_SIGNING_KEY` | Authorization server identity |
| `LANGFUSE_*` | Tracing; optional, absent disables tracing without failing |

**A missing API key degrades; it does not crash.** That is load-bearing for the Compose demo —
see the availability row in
[§10](../../shared/ai-enablement-overview.md#10-non-functional-targets).

---

## Deliberately absent

| Absent | Why |
|--------|-----|
| **An ORM** | See above |
| **Celery, Redis, a task queue** | Streaming is in-process over SSE. A queue becomes necessary when generation outlives a request, which at these response targets it does not |
| **A second datastore** | pgvector in the existing database — [§4](../../shared/ai-enablement-overview.md#4-data-and-storage) |
| **WebSockets** | SSE is one-directional and sufficient; see above |
| **Conversation persistence across sessions** | The assistant is stateless between visits. Chat history belongs to the request, not to a new table, until there is a product reason for it |
| **Model fine-tuning, LoRA adapters, a model registry** | [§2](../../shared/ai-enablement-overview.md#2-scope) |
| **A second agent framework** | LangGraph covers the one place branching is needed. AutoGen and CrewAI would each run one agent |
| **Direct database access to business tables** | The whole point. See the REST-only rule above |
