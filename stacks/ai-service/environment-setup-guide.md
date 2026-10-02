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
| A pgvector-capable database | — | **Only for this service.** See §1 |
| An OpenAI API key | — | **Optional.** Without it the service starts and reports `AI_UNAVAILABLE` |

> **`uv` is not assumed pre-installed.** On Windows, and verified in Step 0:
> ```powershell
> irm https://astral.sh/uv/install.ps1 | iex
> $env:Path = "$env:USERPROFILE\.local\bin;$env:Path"   # re-add in each new terminal
> uv python install 3.13                                 # uv manages its own interpreter
> ```

---

## 1. The database needs pgvector — but only this service's schema does

`pgvector` is a third-party C extension that must be compiled against a specific major version.
The official Postgres images ship only core extensions, so `CREATE EXTENSION vector` fails there
with the control file simply absent. Compose therefore uses **`pgvector/pgvector:pg18`**, the
official build with the extension precompiled.

> **The AI schema is applied by a separate Flyway run, and this matters more than it looks.**
> It was briefly a `V002` in `shared/migrations/`, and that was wrong. Everything in that
> directory is **mandatory**: Spring Boot's build copies every `V*.sql` onto its classpath and
> applies it at startup, and both backends' CI migrates a stock `postgres:18.6` image. A migration
> needing pgvector there made an *optional* sixth service a hard dependency of the whole project —
> **Spring Boot stopped starting at all** against a native database without pgvector, even for
> ordinary Phase 1–8 work, and both backends' CI would have broken next run.
>
> That contradicted the additive-ness guarantee in
> [ai-enablement-overview.md §10](../../shared/ai-enablement-overview.md#10-non-functional-targets).
> Found during Step 0, on a real machine.

**So you do not need pgvector in your native PostgreSQL** unless you want to run this service
against it. The four Phase 8 Compose combinations, native backend development, and both backends'
CI are all unaffected.

**For native AI development, point `DATABASE_URL` at the Compose database on `localhost:5433`** —
it already has pgvector, and it is on a non-colliding port precisely so it can run alongside your
native install:

```
DATABASE_URL=postgresql://postgres:postgres@localhost:5433/hotelapp
```

> **The two databases have different passwords, and that is not a typo.** It has caught people
> already.
>
> | Database | Host port | User | Password | Has pgvector |
> |----------|-----------|------|----------|--------------|
> | Native PostgreSQL 18 | `5432` | `postgres` | **`password`** | No |
> | Docker Compose | `5433` | `postgres` | **`postgres`** | Yes |
>
> The Compose credentials are a throwaway matching the CI pattern in
> [devops-pipeline-overview.md](../../shared/devops-pipeline-overview.md#backend-repos-hotelapp-server-nodejs-hotelapp-server-springboot);
> the native ones are whatever the local install was created with. **The port tells you which
> password to use** — `5432` takes `password`, `5433` takes `postgres`. A connection failure
> against either is almost always this.
>
> `.env.example` ships pointing at **native** (`5432`/`password`), because that is where the
> backends run by default. Change both the port and the password together, or neither.

Installing pgvector into a native Windows PostgreSQL is possible but requires compiling it with
MSVC, and is unnecessary given the above.

## 2. Migrations

**Flyway remains the sole DDL executor** and this service never creates schema
([versioning-strategy.md](../../shared/versioning-strategy.md#database-schema-migrations)). What
differs is *which* Flyway run:

| Location | History table | Applied by | Contains |
|----------|---------------|-----------|----------|
| `shared/migrations/` | `flyway_schema_history` | Spring Boot at startup; the `flyway` Compose service; both backends' CI | The 11 business tables |
| `shared/migrations-ai/` | `flyway_schema_history_ai` | The `flyway-ai` Compose service, under `--profile ai` only | `ai_documents`, `ai_chunks`, `ai_eval_runs`, and the `vector` extension |

Separate history tables keep the two independent — neither run sees the other's migrations as
missing. Numbering restarts at `V001` in the AI location because it is a separate history.

To apply the AI schema by hand against any database:

```bash
docker run --rm -v "$PWD/../hotelapp-context/shared/migrations-ai:/flyway/sql:ro" flyway/flyway:11 \
  -url=jdbc:postgresql://host.docker.internal:5433/hotelapp \
  -user=postgres -password=postgres -table=flyway_schema_history_ai migrate
```

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
| Startup fails on missing `ai_chunks` | The AI schema has not been applied. Run the `flyway-ai` Compose service (`--profile ai`) or the manual command in §2 |
| Assistant answers but cannot see the guest's reservations | The session cookie is not reaching this service. Check the API is mounted under `/api/v1` and the browser origin is in `CORS_ALLOWED_ORIGINS` |
| `AI_UNAVAILABLE` on every request | No `OPENAI_API_KEY`. This is a supported state, not a fault |
| Retrieval returns nothing after a model change | `EMBEDDING_MODEL` changed without a re-ingest — §4 |
| Claude Desktop shows no tools | Absolute path wrong in the config, or the process failed at startup. Run the `mcp-stdio` command by hand to see the error |
