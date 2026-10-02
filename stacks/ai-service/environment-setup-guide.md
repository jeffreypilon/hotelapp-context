# Environment Setup Guide — AI Service

Clone to running, literally.

> **These commands are specified but have not been executed.** No code exists in
> `hotelapp-ai-service` yet. Following the convention this project has used since Phase 5: treat
> everything below as **a plan to validate**, not as verified fact, and rewrite this document with
> what actually worked — including the errors and their workarounds — as soon as the first code
> runs. Every other stack's guide earned its accuracy that way.

---

## Prerequisites

| Need | Version | Note |
|------|---------|------|
| Python | **3.13** | Pinned via `requires-python`; match it locally or `uv` will tell you |
| `uv` | latest | Packaging and virtualenv management — [dependency-policy.md](./dependency-policy.md#packaging) |
| Docker | any current | Testcontainers, and the Compose demo |
| A running HotelApp backend | — | Spring Boot on `:8080` by default |
| A migrated database | — | Including `V002__ai_tables.sql` |
| An OpenAI API key | — | **Optional.** Without it the service starts and reports `AI_UNAVAILABLE` |

---

## 1. The database needs pgvector, and the stock image does not have it

> **Phase 9 changes `docker/docker-compose.yml` in `hotelapp-context`:**
>
> ```yaml
> db:
>   image: pgvector/pgvector:pg18    # was postgres:18.6
> ```
>
> The official Postgres images ship only core extensions. pgvector is a third-party C extension
> that must be compiled against a specific major version, and the stock image carries no build
> tools or headers — so `CREATE EXTENSION vector` fails with the control file simply absent.
> `pgvector/pgvector:pg18` is the official build with the extension precompiled.
>
> **This change is deliberately deferred to Phase 9** so the Phase 8 demo stack stays exactly as
> shipped and verified. It is not optional once the AI service exists.

Native local development needs the same thing: a PostgreSQL 18.6 with pgvector available, or the
Compose database on `:5433`.

## 2. Migrations

Unchanged from the rest of the project: **Flyway applies the canonical SQL**, this service never
creates schema ([versioning-strategy.md](../../shared/versioning-strategy.md#database-schema-migrations)).

`V002__ai_tables.sql` is authored in `hotelapp-context/shared/migrations/` and creates the
`vector` extension plus `ai_documents`, `ai_chunks`, `ai_eval_runs`.

The Compose `flyway` service already mounts `../shared/migrations`, so it picks `V002` up with no
Compose change. Running the non-AI stack will therefore create the `ai_*` tables and leave them
empty, which is correct and harmless.

The service **asserts at startup** that the tables and the extension exist, and fails fast if they
do not — the same posture as Spring Boot's `ddl-auto=validate`.

---

## 3. Install and configure

```bash
git clone git@github.com:jeffreypilon/hotelapp-ai-service.git
cd hotelapp-ai-service

uv sync --frozen          # NOT `uv add` -- respects the committed lockfile
cp .env.example .env      # then edit
```

`.env.example`:

```bash
# ---- Which backend to call ----
HOTELAPP_API_BASE_URL=http://localhost:8080/api/v1

# ---- Database: ai_* tables only ----
DATABASE_URL=postgresql://postgres:password@localhost:5432/hotelapp

# ---- Provider ----
LLM_PROVIDER=openai          # openai | ollama
OPENAI_API_KEY=              # absent is valid -- AI features report unavailable
EMBEDDING_MODEL=text-embedding-3-small

# ---- Server ----
PORT=8000
LOG_LEVEL=info               # DEBUG adds redacted prompt/retrieval traces

# ---- CORS: never a wildcard ----
CORS_ALLOWED_ORIGINS=http://localhost:5173,http://localhost:4200

# ---- OAuth (MCP over HTTP) ----
OAUTH_ISSUER=http://localhost:8000
OAUTH_SIGNING_KEY=

# ---- Tracing: optional, absent disables it ----
LANGFUSE_HOST=
LANGFUSE_PUBLIC_KEY=
LANGFUSE_SECRET_KEY=
```

> **`PORT=8000` and the `/api/v1/` mount are both load-bearing.** The session cookie is scoped
> `Path=/api/v1`, and cookie scope is host plus path and **ignores port** — so
> `localhost:8000/api/v1/assistant/...` receives the cookie that `localhost:8080` set. Mount the
> API anywhere else and pass-through authorization silently stops working, with no error to
> explain why.

---

## 4. Ingest the corpus

```bash
uv run hotelapp-ai ingest          # corpus/ -> parse -> chunk -> embed -> ai_chunks
uv run hotelapp-ai ingest --stats  # chunk counts, token counts, estimated cost
```

Idempotent per document hash: re-running skips unchanged documents. **Changing
`EMBEDDING_MODEL` invalidates every stored vector** and requires a full re-ingest — it is a
migration, not a configuration tweak
([dependency-policy.md](./dependency-policy.md#maintenance)).

---

## 5. Run it

```bash
uv run hotelapp-ai serve           # FastAPI on :8000, REST + MCP-over-HTTP
uv run hotelapp-ai mcp-stdio       # MCP over stdio, public tool surface only
```

Verify:

```bash
curl http://localhost:8000/api/v1/assistant/health
curl http://localhost:8000/.well-known/oauth-protected-resource
```

`/health` reports provider reachability and backend reachability **separately** — "up" and "able
to do anything useful" are different questions.

---

## 6. Connect Claude Desktop (the stdio demo)

Add to Claude Desktop's MCP configuration:

```json
{
  "mcpServers": {
    "hotelapp": {
      "command": "uv",
      "args": ["run", "--directory", "/absolute/path/to/hotelapp-ai-service",
               "hotelapp-ai", "mcp-stdio"],
      "env": { "HOTELAPP_API_BASE_URL": "http://localhost:8080/api/v1" }
    }
  }
}
```

Restart Claude Desktop. The hotel's catalogue, availability search and prepared booking links
become available as tools.

**Reservations and writes are deliberately absent over stdio** — that surface requires the HTTP
transport and a real OAuth flow, for the reasons in
[security-implementation.md](./security-implementation.md#stdio-safe-by-construction-not-by-configuration).
No credential goes in that `env` block to "unlock" more.

---

## 7. Tests and evaluation

```bash
uv run pytest tests/unit              # fast, no infrastructure
uv run pytest tests/integration       # needs Docker: Testcontainers + Flyway
uv run hotelapp-ai eval               # RAGAS over eval/golden_set.yaml
uv run ruff check . && uv run ruff format --check . && uv run mypy src
```

`tests/integration` needs Docker **and a running backend** — this service reads business data over
REST, so there is no database fixture that can stand in for one
([testing-standards.md](./testing-standards.md)).

`eval` makes real provider calls and **costs money**. It is not part of `pytest`.

---

## 8. Running under Compose

```bash
cd ../hotelapp-context/docker
API_BASE_URL=http://localhost:8080/api/v1 OPENAI_API_KEY=sk-... \
  docker compose --profile react --profile spring --profile ai up --build
```

The AI service is its own profile. **The existing four frontend/backend combinations keep working
untouched and without an API key** — that is the additive-ness guarantee from
[§10](../../shared/ai-enablement-overview.md#10-non-functional-targets), and it is why `ai` is a
profile rather than an always-on service.

| Service | Host port |
|---------|-----------|
| AI service | 8000 |
| Langfuse (optional) | 3001 |

---

## Troubleshooting

| Symptom | Cause |
|---------|-------|
| `type "vector" does not exist` | Database is stock `postgres:18.6`, not `pgvector/pgvector:pg18` — see §1 |
| Startup fails on missing `ai_chunks` | Flyway has not run `V002`. Start Spring Boot once, or run the Flyway CLI |
| Assistant answers but cannot see the guest's reservations | The session cookie is not reaching this service. Check the API is mounted under `/api/v1` and the browser origin is in `CORS_ALLOWED_ORIGINS` |
| `AI_UNAVAILABLE` on every request | No `OPENAI_API_KEY`. This is a supported state, not a fault |
| Retrieval returns nothing after a model change | `EMBEDDING_MODEL` changed without a re-ingest — §4 |
| Claude Desktop shows no tools | Absolute path wrong in the config, or the process failed at startup. Run the `mcp-stdio` command by hand to see the error |
