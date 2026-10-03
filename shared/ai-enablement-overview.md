# AI Enablement Overview

What HotelApp's AI capabilities are, where they live, and why they are shaped this way. This
document is authoritative for the AI feature set, the `hotelapp-ai-service` component boundary,
the retrieval architecture, and the evaluation strategy. It is the AI counterpart to
[architecture-overview.md](./architecture-overview.md) and does not restate what that document
already decides.

Phase 9 in [phased-implementation-plan.md](./phased-implementation-plan.md) builds what is
specified here.

---

## 1. Why this exists at all

HotelApp's premise is **two frontends and two backends against one REST contract**, and the
point of the project is demonstrating architectural judgment rather than shipping a product.
AI enablement has to earn its place against that premise, not sit beside it as a bolted-on
demo.

It earns its place three ways:

1. **It extends the interchangeability thesis rather than contradicting it.** The AI service is
   a fifth consumer of the same contract the frontends consume. It is backend-agnostic for the
   same reason they are, and it is proven against both backends for the same reason they are.
2. **It is where the hospitality industry actually is in 2026.** Agentic booking went live in
   Google's AI Mode in August 2026 on the Universal Commerce Protocol; Perplexity, Sabre and
   Mindtrip all shipped conversational booking paths. As of mid-2026 only ~11% of hotel
   organizations can be booked by an AI agent at all. An MCP-addressable hotel system is
   current, not speculative.
3. **It closes the gap between "built an AI feature" and "operated one."** See
   [§9 Evaluation](#9-evaluation--the-part-that-is-usually-missing).

---

## 2. Scope

### In scope

| # | Capability | Depends on |
|---|-----------|-----------|
| F1 | **MCP server** — HotelApp's catalogue, availability and reservations exposed as MCP tools, so any MCP-capable agent can read and transact against it | REST contract only |
| F2 | **Natural-language availability search** — free-text intent resolved to the existing `GET /availability` parameters | REST contract + structured outputs |
| F3 | **Guest assistant (RAG)** — grounded question answering over hotel policy and property documents, with citations | Full retrieval pipeline |
| F4 | **Staff operations assistant** — constrained-tool answering over reservations and occupancy for Front Desk and Manager roles | F3 + admin endpoints |

F4 is **deferred until the admin UI exists** in both frontends. F1–F3 are guest-facing and are
the Phase 9 delivery.

### Out of scope, deliberately

Listed so the omissions read as choices. Each was considered and declined.

| Excluded | Why |
|----------|-----|
| **Fine-tuning a model** | Retrieval plus a well-constrained prompt answers every question this corpus supports. Fine-tuning would add a training pipeline, a model registry and a reproducibility burden to buy accuracy this domain does not need. It is the clearest example of a technique that is worth knowing and wrong to use here |
| **Multi-agent orchestration (AutoGen, CrewAI)** | F1–F3 are single-purpose request/response flows. Introducing a second and third agent framework to run one agent each would be resume-driven architecture. LangGraph alone covers the one place real branching is needed (F3's retrieve → grade → optionally re-retrieve loop) |
| **Agentic RAG on every query** | It costs roughly 10× a naive pipeline and adds 2–10s of latency. Applied selectively to multi-hop questions, it is correct; applied by default it is waste. See [§7](#7-retrieval-architecture) |
| **GraphRAG, knowledge graphs** | The corpus is tens of documents with shallow structure. A graph layer solves a problem this corpus does not have |
| **Image generation, speech, OCR of scanned documents** | Not features of a booking system. The source corpus is authored text, not scans |
| **Text-to-SQL for the staff assistant** | Benchmarks of 85%+ collapse to 10–20% against real enterprise schemas without a semantic layer. F4 uses constrained tools over existing endpoints instead. See [§5](#5-the-authorization-model-and-why-it-is-the-interesting-part) |
| **A dedicated vector database** | See the Design Decision in [§4](#4-data-and-storage) |
| **Cloud deployment or a hosted inference endpoint** | Unchanged from [devops-pipeline-overview.md](./devops-pipeline-overview.md#deliberately-absent). There is still no environment to deploy to |

---

## 3. Component shape

```
                          ┌───────────────────────────┐
  Claude Desktop /        │                           │
  any MCP client   ──────►│   hotelapp-ai-service     │
                          │   (Python, FastAPI)       │
  React / Angular  ──────►│                           │
                          │   MCP server  │  REST API │
                          └───────┬───────────┬───────┘
                                  │           │
                    REST, caller's│session     │ SQL, own tables only
                                  ▼           ▼
                   ┌──────────────────┐   ┌──────────────────────┐
                   │ hotelapp-server- │   │ PostgreSQL 18.6      │
                   │ springboot :8080 │   │  ai_documents        │
                   │       ── or ──   │   │  ai_chunks (vector)  │
                   │ hotelapp-server- │   │  ai_eval_runs        │
                   │ nodejs    :3000  │   └──────────────────────┘
                   └────────┬─────────┘
                            │
                            ▼
                   the same PostgreSQL,
                   business tables
```

Two rules define the boundary, and everything else follows from them:

> **Design Decision — the AI service reads business data over REST, never over SQL.**
> It would be faster to query `reservations` directly. Doing so would duplicate the pricing
> formula, the availability anti-join and the cancellation-deadline arithmetic in a third
> language, which is precisely the drift this project exists to prevent — and it would put the
> no-overbooking guarantee behind a code path the exclusion constraint does not arbitrate.
> Going through the contract costs a network hop and buys: one implementation of every business
> rule, a service that works unmodified against either backend, and an AI layer that **cannot
> fabricate availability or pricing**, because it never computes them. The latency cost is
> acceptable against the response targets in [§10](#10-non-functional-targets).

> **Design Decision — the AI service owns its own tables and no others.**
> `ai_documents`, `ai_chunks` and `ai_eval_runs` are read and written directly by this service.
> Business tables are never touched directly, in either direction. The boundary is therefore
> legible from the schema alone: anything prefixed `ai_` belongs to this service, everything
> else reaches it through HTTP.

### Why a sixth repository rather than code inside a backend

Putting the pipeline inside one backend would make the two backends non-interchangeable, which
is the project's single load-bearing property. Implementing it in both would mean maintaining a
retrieval pipeline in Java and TypeScript simultaneously — the duplication problem this
repository exists to prevent, in its most expensive form. The LangChain and LangGraph ecosystem
is also materially more mature in Python than in either target language.

So: a separate service, in the language the tooling actually lives in, consumed over HTTP by
whatever needs it. `hotelapp-ai-service` joins the existing five repositories.

---

## 4. Data and storage

Embeddings live in the **same PostgreSQL 18.6 instance**, via `pgvector`.

> **Design Decision — pgvector, not a dedicated vector database.**
> HotelApp's corpus is on the order of a few thousand chunks. Published production evidence
> puts pgvector's comfortable ceiling in the millions of vectors — 2M chunks at 98.3% recall@10
> and 35ms P50 on a modest instance, with dedicated engines only pulling ahead in the low tens
> of millions. This corpus sits three to four orders of magnitude below that line.
> Adding Pinecone or Weaviate would introduce a second datastore, a second consistency model, a
> sixth Compose container and a network hop, to solve a scaling problem this project will never
> have. Keeping vectors in Postgres additionally allows **hybrid retrieval in one transactional
> query** (see [§7](#7-retrieval-architecture)), which a split store makes awkward.
> The costs are real and accepted: HNSW index builds are slow, and heavily *filtered* vector
> search degrades. Neither binds at this size.

**Migration ownership is unchanged.** Flyway remains the sole DDL executor and the canonical SQL
still lives in [`shared/migrations/`](./migrations/) — see
[versioning-strategy.md](./versioning-strategy.md#database-schema-migrations) and
[decision-log.md](./decision-log.md) entry 3. The `ai_*` tables and the `vector` extension
arrive as a new `migrations-ai/V001__ai_tables.sql`, applied by a **separate** Flyway run so that optional AI schema never becomes mandatory schema. **The Python service never creates its own
schema**, for the same reason the Node backend does not. `V001` is immutable.

---

## 5. The authorization model, and why it is the interesting part

Prompt injection is OWASP's top LLM vulnerability for the third consecutive year, with live
CVEs against shipped assistants through 2025–2026, and no published defense survives adaptive
attack. Any design that depends on the model refusing to misbehave is already broken.

So this design does not depend on that.

> **Design Decision — the model never holds credentials; the caller's session is passed
> through.**
> The AI service holds no service account and no elevated database role. Every backend call it
> makes carries **the session cookie of the guest who asked**, so the backend's existing
> authorization applies without modification. The blast radius of a perfectly successful prompt
> injection is therefore bounded by what that same guest could already do through the UI: they
> can be tricked into seeing their own reservation, never someone else's. Authorization is a
> property of the request, not of the model's good behaviour.

Three further controls, none of which rely on model compliance:

- **Tools are narrow and allow-listed.** The model may call `search_availability`; it may not
  call "run a query." Each tool's parameters are schema-validated before dispatch, by the
  service, not by the prompt.
- **Write operations are explicitly gated.** Reservation creation and cancellation require a
  confirmation step the caller performs, never an action the model takes unprompted. See F1's
  tool table in `stacks/ai-service/architecture-specification.md`.
- **Retrieved document text is untrusted input.** Corpus content is delimited and labelled as
  data in the prompt, and the service assumes a document could contain injected instructions
  even though this corpus is authored in-repo.

This slots under the existing threat model in
[security-principles.md](./security-principles.md) rather than replacing it.

### A consequence that constrains the URL layout

The session cookie is scoped `HttpOnly; Secure; SameSite=Lax; Path=/api/v1` — note the **path**.
Cookie scope is host plus path and **ignores port**, which is exactly why a session works across
`:8080` and `:3000` for [AC-SE-05](./acceptance-criteria.md). The same mechanism is what makes
pass-through authorization possible here, but only if the path matches:

> **Design Decision — the AI service's HTTP API is mounted under `/api/v1/`, on its own port.**
> Endpoints are `/api/v1/assistant/...`, not `/ai/...`. A browser will not attach the session
> cookie to a path outside `/api/v1`, so any other prefix would leave the AI service with no
> caller identity to pass through, and would force either a second auth mechanism or a
> privileged service account — the exact thing [§5](#5-the-authorization-model-and-why-it-is-the-interesting-part)
> rules out. The port differing from the backends' is irrelevant to cookie scope, and
> `HttpOnly` means the frontend never reads or forwards the token itself; the browser does it.

---

## 6. The MCP server

F1 exposes HotelApp to any MCP-capable agent. It is the project's most current capability and
the one with no retrieval dependency at all — it is a typed, authorized translation layer over
the REST contract.

### Two transports, with different jobs

Both ship. They are not redundant; they expose **different tool surfaces**, and that difference
is the security design rather than a limitation.

| Transport | Runs as | Auth | Tool surface |
|-----------|---------|------|--------------|
| **stdio** | Local subprocess launched by the client (e.g. Claude Desktop) | None — trust boundary is the local machine | **Public only**: catalogue, availability, prepared booking links |
| **HTTP** | Networked service | OAuth 2.1, audience-bound token | **Full**: the above plus the caller's own reservations, and writes |

> **Design Decision — stdio is deliberately limited to the anonymous surface.**
> A locally-launched subprocess has no authenticated user, and inventing one (a config-file
> credential, a long-lived token on disk) would create exactly the standing secret that
> [security-principles.md](./security-principles.md) exists to prevent. Restricting stdio to
> data that is already public makes it *safe by construction* rather than safe by configuration,
> and it still demonstrates the thing worth demonstrating in thirty seconds: an agent
> discovering and reasoning over real hotel inventory. Anything touching a guest's own data
> requires the HTTP transport and a real authorization flow.

### The server is a resource server, not an authorization server

> **Design Decision — HotelApp implements the 2026-07-28 MCP authorization model, not the
> original one.**
> The first MCP specification (2025-03-26) expected the MCP server to *be* its own authorization
> server. The 2025-06-18 revision reclassified it as a **pure OAuth 2.1 resource server**, and
> every revision since has built on that separation. So this MCP server validates tokens and
> serves resources; it never issues a token and never logs a user in. It implements RFC 9728
> Protected Resource Metadata and rejects any token not audience-bound to itself (RFC 8707).
> Most material still shows the superseded model, so conforming to the current one is a
> deliberate, checkable choice.

The authorization server role is filled by a **small AS inside `hotelapp-ai-service`**, built on
[Authlib](https://docs.authlib.org/), reusing HotelApp's existing `users` and `sessions` for the
login and consent step.

> **Design Decision — HotelApp hosts its own authorization server rather than adopting Keycloak,
> Hydra, or a hosted provider.**
> Every off-the-shelf option brings its own user store. HotelApp already owns identity — `users`,
> `sessions`, the `PROPERTY_MANAGER`/`FRONT_DESK_STAFF` rank hierarchy, and a bcrypt cost chosen
> so both backends verify each other's hashes. Adopting an external AS would mean either a second
> source of truth for who a user is, or building federation between the two, in a project whose
> stated thesis is that duplication is where drift begins. A hosted provider would additionally
> break the offline Compose demo. The protocol primitives come from a vetted library rather than
> being hand-written; what this project supplies is the integration and the storage.

**Opaque tokens, not JWTs.** OAuth 2.1 does not require a JWT, and
[decision-log.md](./decision-log.md) entry 2 removed bearer-JWT authentication from this project
deliberately — along with `Authorization` from the CORS allow-list and the whole client-side
token subsystem. Access tokens here are opaque and validated by introspection, which is the
same shape as the existing session token. The MCP authorization story therefore **extends** that
decision instead of reversing it.

**Dynamic Client Registration is not implemented.** The 2026-07-28 revision deprecated DCR in
favour of Client ID Metadata Documents, retaining it only for backward compatibility. The one
client is pre-registered; CIMD is documented as the forward path. This is less work *and* more
current than building the deprecated mechanism.

**The consent screen is a server-rendered page in the AI service**, not a React or Angular
screen. It is reached once, by a machine client's browser handoff, and it is not part of the
guest-facing UI — putting it in the frontends would mean two more screens to keep byte-identical
between them, for a page neither frontend's users navigate to.

### Tool surface, first cut

| Tool | Backing endpoint | Auth | Writes |
|------|-----------------|------|--------|
| `list_properties`, `get_property`, `list_room_types` | `GET /properties*`, `GET /room-types/{id}` | public | |
| `search_availability` | `GET /availability` | public | |
| `prepare_booking` | none — returns a deep link | public | |
| `list_reservations`, `get_reservation` | `GET /reservations*` | OAuth | |
| `modify_reservation` | `PATCH /reservations/{id}` | OAuth | ✅ |
| `cancel_reservation` | `POST /reservations/{id}/cancel` | OAuth | ✅ |

Profile and password tools are deliberately omitted from the first cut.

### The agent prepares bookings; it does not pay for them

> **Design Decision — `prepare_booking` returns a deep link into the existing booking flow
> rather than creating a reservation.**
> Two reasons, one practical and one principled.
> *Practical:* `reservation_status` is `CONFIRMED | CHECKED_IN | CHECKED_OUT | CANCELLED` with no
> pending state, `reservations_status_timestamps_chk` enumerates those four exhaustively, and
> `reservations_no_overlap_excl` is partial on `status = 'CONFIRMED'` — so an unpaid reservation
> would not hold its room. Introducing a pending state means a new migration, a rewritten CHECK
> constraint, a decision about whether holds block inventory (and therefore hold expiry and a
> sweeper), `ReservationStatusRules` changes in **both** backends, and a reworked S6 in **both**
> frontends. That is a larger change than this entire service, and it lands on the one constraint
> the project is built around.
> *Principled:* payment card data should not cross an agent boundary, which is the problem the
> Universal Commerce Protocol and similar 2026 efforts exist to solve and have not finished
> solving. The agent does discovery, comparison and selection — the genuinely useful part — and
> hands a ready-to-pay link to the guest, who completes payment in the first-party UI. The
> handoff *is* the demonstration.

> **Design Decision — the link targets S3 (search results), not S4 (booking summary).**
> S4 (`/properties/:propertyId/book`) renders state carried from S3's in-app navigation, not URL
> parameters — [ui-specifications.md](../stacks/react/ui-specifications.md#s4--booking-summary)
> is explicit that it has no query-parameter entry point. S3 (`/properties/:propertyId/search`) is
> the one screen whose full state lives in the URL and is shareable, using the same parameter
> names as `GET /availability`. So `prepare_booking` links to S3 with the check-in/check-out
> dates, guest count, and `roomTypeCode` pre-filled to the one room type it found — landing the
> guest one click ("Select room") from the real booking flow, not literally inside it. This was
> caught during AI Step 5's design discussion, by checking the claim below against the actual
> screen contract rather than assuming it. It still requires no frontend change: S3 already reads
> every one of these parameters from the URL today.
`cancel_reservation` and `modify_reservation` remain real, consequential writes against real
business rules, so the write surface is not theatre.

---

## 7. Retrieval architecture

Naive retrieval — embed, top-k, stuff the prompt — fails at the retrieval step in roughly 40%
of production cases, and the 2026 production standard is hybrid retrieval with reranking.
F3 implements that standard:

| Stage | What runs | Why |
|-------|-----------|-----|
| 1. Query processing | Light rewrite for conversational follow-ups ("what about the other one?") | Pronoun-laden follow-ups retrieve nothing without it |
| 2a. Dense retrieval | `pgvector` cosine similarity, top-50 | Semantic match: "can I bring my dog" ↔ "pet policy" |
| 2b. Sparse retrieval | PostgreSQL full-text (`ts_rank`), top-50 | Exact-term match: room codes, property names, numbers |
| 3. Fusion | Reciprocal Rank Fusion over 2a and 2b | Rank-based fusion needs no score calibration between two unlike scales |
| 4. Rerank | Local cross-encoder, top-50 → top-5 | Cross-encoders score query and passage *together*; the single largest precision gain in the pipeline |
| 5. Generation | Answer constrained to retrieved context, with citations | A cited answer is auditable; an uncited one is unfalsifiable |
| 6. Grading | LangGraph conditional edge: if retrieval is graded insufficient, decompose and retry **once** | Multi-hop coverage without paying agentic cost on every query |

Stage 6 is the *only* place agentic behaviour appears, and it is bounded to a single retry.
That is the selective application of agentic RAG referenced in [§2](#2-scope).

**Chunking** is semantic rather than fixed-width, with the document's own heading path preserved
on each chunk so a citation can name its section. Changing the strategy later means re-embedding
the whole corpus, so the choice is pinned by the golden set in [§9](#9-evaluation--the-part-that-is-usually-missing)
before the corpus is built out.

---

## 8. The document corpus

RAG needs documents, and HotelApp's database holds structured records only. The corpus is
therefore authored as part of Phase 9: roughly 15–25 PDFs covering cancellation and rate-type
policy, per-property house rules, check-in and check-out procedure, accessibility statements,
amenity detail, loyalty tiers, and local area guides. Shape and terms follow how large chains
actually publish: policy attaches to the **rate type** rather than the brand, with a 48-hour
baseline window and non-refundable advance-purchase rates.

> **Design Decision — the corpus is authored *from* the implemented business rules, not
> independently of it.**
> The cancellation window stated in a policy PDF must be the window
> [acceptance-criteria.md](./acceptance-criteria.md) specifies and both backends enforce —
> 48 hours before check-in, in the property's own IANA timezone. A corpus written to sound
> realistic instead of to match would produce the worst failure mode available to this system:
> an assistant confidently quoting a policy the API then refuses to honour. The corpus is
> downstream of the specification exactly as the four implementations are, and
> [§9](#9-evaluation--the-part-that-is-usually-missing) tests that it stayed that way.

---

## 9. Evaluation — the part that is usually missing

Evaluation is in scope as a first-class deliverable, not as a closing task. HotelApp already
expresses correctness as 44 behavioural criteria in
[acceptance-criteria.md](./acceptance-criteria.md); AI correctness is expressed the same way
rather than by vibes.

**Three layers:**

1. **A golden question set** — 50–100 question/expected-answer pairs derived from the corpus and
   the acceptance criteria, committed to the repository. Built *before* the retrieval parameters
   are tuned, so the parameters are chosen against evidence rather than impression.
2. **RAGAS metrics in CI**, reported separately for retrieval and generation, because they fail
   independently and can mask each other:
   - *Context precision / context recall* — did retrieval find the right chunks?
   - *Faithfulness* — is the answer supported by what was retrieved?
   - *Answer relevancy* — did it answer the question actually asked?
3. **Tracing in Langfuse** — self-hosted, so the "no cloud" posture holds. Every request records
   prompt, retrieved chunks, model, latency, token count and **cost**.

> **Design Decision — a policy-consistency check is part of the suite, not just RAG metrics.**
> A test asserts that the corpus's stated rules agree with the rules the backends enforce: ask
> the assistant the cancellation question, and the answer must match what
> `POST /reservations/{id}/cancel` actually does at the boundary. Standard RAG metrics would
> happily score a fluent, well-retrieved, perfectly faithful answer that contradicts the running
> system — faithfulness measures agreement with the *document*, not with the *application*. This
> project's entire thesis is drift prevention between parallel implementations; the corpus is
> now one of those implementations.

**Quality gate**: faithfulness and context recall have committed floor values; a change that
drops either below its floor fails CI the same way a failing integration test does.

---

## 10. Non-functional targets

Extends [non-functional-requirements.md](./non-functional-requirements.md); that document
remains authoritative for the rest of the system.

| Measure | Target | Note |
|---------|--------|------|
| F2 natural-language search, end to end | < 2.0s p95 | One model call plus the existing availability query |
| F3 first streamed token | < 1.5s p95 | Streamed over SSE; perceived latency is the first token, not the last |
| F3 complete answer | < 6s p95 | Includes retrieval, rerank and generation |
| F1 MCP tool call | < 1.5s p95 | A thin translation over an existing endpoint |
| Cost per guest question | tracked per request, reported in CI | Measured, not estimated — postings ask for this number and most portfolios cannot produce it |
| Availability when the provider is unreachable | **The rest of HotelApp is unaffected** | AI features degrade to an explicit unavailable state; booking, search and account management never depend on the AI service being up |

The last row is load-bearing. The AI service is **strictly additive**: every existing
acceptance criterion must still pass with the service stopped.

---

## 11. Provider and model selection

The provider is swappable behind one interface. **OpenAI is the default**; a local Ollama
configuration exists so the Compose demo still runs with no API key and no network, preserving
the "a reviewer needs only Docker" property established in Phase 8.

| Role | Default | Rationale |
|------|---------|-----------|
| Generation — the answer the guest reads | **GPT-5.4 mini** | Classification-shaped calls below use the cheaper tier; this is the one output a guest sees, so it is worth the better model |
| Query rewrite, retrieval grading, F2 parameter extraction | **GPT-5.4 nano** | All three are classification/extraction-shaped decisions, not prose — production retrieval-grading implementations (Corrective RAG, Adaptive RAG) commonly use a small model for exactly this, at roughly a third nano's cost of mini |
| Embeddings | `text-embedding-3-small` | $0.02/1M tokens — this corpus costs cents to embed. Upgrade to `-3-large` only if the golden set shows retrieval is the bottleneck |
| Reranking | Local open-source cross-encoder | No major provider sells a reranker on this key; running it locally keeps the offline path intact and the per-query cost at zero |
| Offline fallback | Ollama | Weaker, slower, free, and sufficient to prove the architecture does not depend on a vendor |

**Per-call ceilings**: `max_tokens ≈ 500` for generation (a few paragraphs plus citations — grading
and rewrite need far fewer and are capped tighter in practice), **timeout ≈ 10s per model call**.
This is a kill-switch ceiling for a genuinely hung call, not the latency target — the 6s p95
*target* for a complete answer in [§10](#10-non-functional-targets) is the number this is measured
against.

> **Design Decision — retrieval grading is an LLM call, not a similarity threshold, and this was
> the original design, not a late addition.** `module-registry.md` already specifies
> `prompts/grade_retrieval.md` and `coding-standards.md` already names grading among the places a
> model's output feeds code. The reasoning is concrete, not theoretical: a score threshold rewards
> topic overlap even when a chunk does not answer the question — exactly the failure AI Step 2
> found by hand, where an untuned reranker placed an unrelated breakfast-hours chunk ahead of the
> actual pet-policy answer. A small model asked "does this actually answer the question" catches
> that; a number does not. Because the task is classification-shaped, it uses the nano tier above,
> not the tier reserved for guest-facing prose.

Switching provider must not require a rebuild — configuration only, matching the precedent set
by the frontends' runtime `config.js` mechanism.

**Semantic caching** sits in front of generation: roughly a third of chatbot traffic is
semantically repetitive, and published results put cache-hit cost reduction in the 40–80% band.
It is also the cheapest way to make a live demo feel fast on the second question.

---

## 12. What this adds to the existing contract

New endpoints are specified in [api-contracts.md](./api-contracts.md) alongside the existing 42
and follow its conventions without exception: `kebab-case` paths, `camelCase` bodies, RFC 9457
Problem Details, the same session cookie, the same error catalogue plus AI-specific codes.

Both frontends consume them. Both backends remain **entirely unaware of the AI service** — the
dependency points one way only, which is what keeps the existing acceptance criteria valid and
the two backends interchangeable.

---

## 13. Defaults and remaining open questions

### Settled

| Question | Answer |
|----------|--------|
| MCP transports | **Both.** stdio for the zero-friction local demo (public tools only), HTTP + OAuth 2.1 for the authenticated surface — see [§6](#6-the-mcp-server) |
| MCP write surface | `cancel_reservation`, `modify_reservation`, and `prepare_booking` (a link, not a write). No profile or password tools in the first cut |
| Booking and payment | Deep-link handoff; the agent never submits card data and never creates a reservation |
| Authorization server | Hosted in `hotelapp-ai-service` on Authlib, reusing HotelApp identity. Opaque tokens. No DCR |
| Consent screen | Server-rendered in the AI service, not in either frontend |
| Default backend | **Spring Boot** (`:8080`). It is the Flyway executor and must be running against a fresh database anyway. Switchable at container start, same mechanism as the frontends |
| Provider | OpenAI by default, Ollama for the offline path — see [§11](#11-provider-and-model-selection) |

### Still open

1. **How does an OAuth token become a backend-callable identity?** For the browser assistant this
   is trivial: the session cookie is sent to `/api/v1/assistant/...` and forwarded unchanged. MCP
   over HTTP presents an OAuth access token instead, and the backends only understand session
   cookies. The recommended answer is that the authorization server **creates a `sessions` row at
   consent time and binds it to the issued token**, so introspection yields a session the AI
   service may use for that user only, and revoking the token revokes the session. That keeps the
   no-standing-privilege property from [§5](#5-the-authorization-model-and-why-it-is-the-interesting-part)
   intact. It needs confirming against the session model's sliding-expiry and absolute-cap rules
   before it is written into `api-contracts.md`.
2. **Semantic cache invalidation when the corpus changes.** A cached answer outlives the document
   that justified it. Simplest correct answer is to key the cache on a corpus version and discard
   on re-ingest; worth confirming that re-ingest is rare enough for that to be free.
3. **Embedding dimension.** `text-embedding-3-small` is the default, but the golden set in
   [§9](#9-evaluation--the-part-that-is-usually-missing) decides whether retrieval quality
   justifies `-3-large`. Pinned by evidence, not preference — and changing it later means
   re-embedding the corpus.
