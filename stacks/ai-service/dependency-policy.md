# Dependency Policy — AI Service (Python)

What may be added to `hotelapp-ai-service`, what may not, and how to decide.

The governing rule is from
[security-principles.md](../../shared/security-principles.md#dependencies): **prefer the
platform's own primitives over a small package.** That rule needs restating with more force here
than anywhere else in the project, because the Python AI ecosystem is the one place where the
default cultural answer to any problem is "pip install something," and because this service runs
with both database credentials and an LLM provider key.

The "deliberately absent" table in
[architecture-specification.md](./architecture-specification.md#deliberately-absent) already
settled several cases; this document does not reopen them.

---

## Packaging

**`uv`**, with `pyproject.toml` and a committed `uv.lock`. CI installs with `uv sync --frozen`,
which is this stack's equivalent of `npm ci` — a lockfile that is not respected is not a lockfile.

Python **3.13**. Pinned in `pyproject.toml` via `requires-python`, and matched by the Docker base
image, so a local run and a container run cannot silently differ.

> **Design Decision — `uv` rather than Poetry or bare pip.**
> Resolution and install speed matter here specifically: this dependency tree includes
> compiled extensions and is rebuilt on every Docker image build, which the Phase 8 demo path
> exercises constantly. `uv` also produces a genuine cross-platform lockfile, which pip's
> `requirements.txt` does not, and that lockfile is what makes the "it built on my laptop" claim
> mean anything.

---

## The approved set

Versions pinned exactly. Transitive resolution is frozen by `uv.lock`.

| Package | Role | Why it earns its place |
|---------|------|------------------------|
| `fastapi` | HTTP, SSE | Decided at system level |
| `uvicorn` | ASGI server | |
| `pydantic`, `pydantic-settings` | DTOs, config validation | One declaration gives validation, the type, and the OpenAPI schema |
| `httpx` | Backend client | Async, and the only way out to a backend — see `gateways/` |
| `psycopg[binary,pool]` | SQL | Explicit SQL with bound parameters; no ORM |
| `pgvector` | Vector type adapter | Registers the `vector` type with psycopg; the alternative is hand-encoding float arrays |
| `langchain`, `langchain-openai` | Loaders, splitters, embeddings, model clients | The component glue, not the orchestration |
| `langgraph` | The retrieval graph | The one place real branching exists |
| `fastmcp` | MCP server | Implements the protocol, both transports, and the resource-server pieces |
| `authlib` | OAuth 2.1 authorization server | Protocol primitives from a vetted library, not hand-rolled |
| `sentence-transformers` | Local cross-encoder reranker | Runs on CPU; keeps reranking free and offline |
| `pypdf` | Corpus ingestion | Reading the PDFs in `corpus/` |
| `fpdf2`, `pillow` (dev group) | Corpus rendering | Build-time only — `scripts/render_corpus.py` and `scripts/make_figures.py` turn the Markdown corpus into the PDFs `pypdf` reads. Not imported by `src/`, so they never ship in the runtime image |
| `ragas` | Evaluation | [testing-standards.md](./testing-standards.md) |
| `langfuse` | Tracing | Self-hosted; optional at runtime |
| `structlog` | Structured logging | [logging-observability.md](./logging-observability.md) |
| `pytest`, `pytest-asyncio`, `testcontainers[postgres]` | Testing | |
| `ruff`, `mypy` | Lint, format, type-check | All three fail CI |

**`hashlib`, `secrets`, `hmac` are built in.** Token generation and hashing use them. Reaching for
a package to produce a random token would add a dependency to do what the standard library does,
and this is the project that already made that call once — Node's session tokens use `node:crypto`
for the same reason.

**`ruff` replaces `black`, `isort`, and `flake8`.** One tool, one config, one CI step.

---

## Explicitly not allowed

| Not allowed | Why |
|-------------|-----|
| **SQLAlchemy, Django ORM, SQLModel, Alembic** | No ORM, and no second migration authority. Flyway owns DDL — [versioning-strategy.md](../../shared/versioning-strategy.md#database-schema-migrations). Alembic in this repo is the same defect as `prisma/migrations/` in the Node repo |
| **Any client for a second vector store** (`pinecone`, `weaviate`, `qdrant`, `chromadb`) | [ai-enablement-overview.md §4](../../shared/ai-enablement-overview.md#4-data-and-storage) |
| **`autogen`, `crewai`, `llama-index`** | One orchestration framework. Adding a second to run one agent is padding — [§2](../../shared/ai-enablement-overview.md#2-scope) |
| **`celery`, `redis` as a task queue** | [architecture-specification.md](./architecture-specification.md#deliberately-absent) |
| **`requests`** | Synchronous. One blocking call in an async service stalls the event loop, and the failure is load-dependent and hard to find. `httpx` only |
| **`python-jose`, `pyjwt`, anything JWT-shaped** | Tokens here are opaque — [decision-log.md](../../shared/decision-log.md) entry 2 and [§6](../../shared/ai-enablement-overview.md#6-the-mcp-server). A JWT library appearing in this tree means someone is re-litigating a reversal |
| **`transformers` / `torch` for generation** | The reranker's CPU cross-encoder is the only local model. Pulling a multi-gigabyte inference stack to generate text, when generation is an API call, would make the image unusable in the Phase 8 demo |
| **Prompt-management SaaS SDKs** | Prompts are files in `prompts/`, versioned in git with the code that uses them |
| **A mocking library used against the LLM provider in integration tests** | See below |

### Why mocking the retrieval path is prohibited, specifically

Unit tests may stub anything. **Integration tests may not mock retrieval or the database.**

The reason is the same one that prohibits mocking Prisma in the Node repo, and it is sharper here.
The hybrid query in `repositories/chunks.py` is where retrieval correctness actually lives: the
pgvector distance operator, the full-text ranking, and the fusion of two result sets with
incompatible score scales. A mocked retriever returns whatever the test author believed the query
would return, which means the test asserts the author's belief rather than PostgreSQL's behaviour
— and it keeps passing after the query stops working.

Integration tests run against a real Testcontainers PostgreSQL with the real `vector` extension and
real embeddings. The LLM provider *may* be stubbed in integration tests, because provider output is
non-deterministic and asserting on it is the evaluation suite's job, not pytest's — see
[testing-standards.md](./testing-standards.md).

---

## Adding something new

Four questions, in order. Stop at the first "no."

1. **Does the standard library already do this?** Python's standard library is large, and the
   answer is "yes" more often than the ecosystem's habits suggest.
2. **Does an already-approved package do this?** `pydantic` validates, `httpx` fetches,
   `langchain` already wraps most model and loader concerns. A second package covering the same
   ground means two ways to do one thing and a future argument about which.
3. **Is it maintained, and would its disappearance be survivable?** The AI tooling ecosystem
   churns faster than any other part of this project. A package that is the only route to a
   capability is a risk that must be named out loud.
4. **Does it change a decision that is recorded somewhere?** If so, that document changes first,
   or the package does not land. A dependency is not an argument.

New dependencies are added in their own commit, with the reason in the commit message, so
`git log -- pyproject.toml` reads as the history of these decisions.

---

## Maintenance

- `uv.lock` is committed and regenerated deliberately, never as a drive-by side effect of an
  unrelated change.
- **Pin the LangChain family together.** `langchain`, `langchain-openai` and `langgraph` move fast
  and across each other; upgrading one alone is how a working pipeline breaks for reasons that
  look like a prompt problem. Upgrade them in one commit and re-run the evaluation suite.
- **The evaluation suite is the upgrade gate.** For every other stack in this project a passing
  test suite is sufficient evidence that an upgrade is safe. Here it is not: a model, embedding
  or framework change can leave every test green while answer quality drops. An upgrade that moves
  a RAGAS floor is a failed upgrade, whatever the unit tests say — see
  [§9](../../shared/ai-enablement-overview.md#9-evaluation--the-part-that-is-usually-missing).
- **Embedding model changes are migrations, not upgrades.** Changing `EMBEDDING_MODEL` invalidates
  every stored vector. Re-embedding the corpus is part of the change, not a follow-up.
