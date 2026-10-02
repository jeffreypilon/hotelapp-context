# Docker demo stack

Runs HotelApp — one frontend, one backend, one database — in containers, so it can be demoed on
a laptop with nothing installed but Docker. This is **separate from, and does not replace**, the
native local-dev workflow in `../shared/devops-pipeline-overview.md`'s "Local development"
section — that one is still the normal day-to-day loop.

## Prerequisites

Docker Desktop (or an equivalent Docker + Compose install). Nothing else — no PostgreSQL, no JDK,
no Node, no Maven required on the host.

## Running a combination

Pick one frontend and one backend profile, and set `API_BASE_URL` to match the backend:

```bash
# React + Spring Boot
API_BASE_URL=http://localhost:8080/api/v1 docker compose --profile react --profile spring up --build

# React + Node
API_BASE_URL=http://localhost:3000/api/v1 docker compose --profile react --profile node up --build

# Angular + Spring Boot
API_BASE_URL=http://localhost:8080/api/v1 docker compose --profile angular --profile spring up --build

# Angular + Node
API_BASE_URL=http://localhost:3000/api/v1 docker compose --profile angular --profile node up --build
```

Run these from this `docker/` directory. Then open:

- React: http://localhost:5173
- Angular: http://localhost:4200

The database, migrations, and seed data are shared across all four combinations — the `db`,
`flyway`, and `seed` services have no profile and always run.

## Stopping / resetting

```bash
docker compose down          # stop containers, keep the seeded database (named volume `pgdata`)
docker compose down -v       # also drop the database -- next `up` re-migrates and reseeds
```

## Ports

| Service | Host port | Note |
|---|---|---|
| Postgres | 5433 | Not 5432, so this can run alongside the native PostgreSQL used for local dev |
| Spring Boot | 8080 | Same as native dev |
| Node | 3000 | Same as native dev |
| React | 5173 | Same as native dev (`vite`) |
| Angular | 4200 | Same as native dev (`ng serve`) |

Because the app ports match native dev's own ports, **stop any native frontend/backend dev
servers before running this stack** (or vice versa) — only Postgres is offset to coexist.

## Switching backends without a rebuild

Both frontends read their API base URL from `window.__HOTELAPP_CONFIG__`, set by a `config.js`
file loaded before the app bundle (`architecture-specification.md`'s "Configuration" section).
The frontend containers' entrypoint (`docker/write-config.sh` in each client repo) overwrites that
file at container *startup* from the `API_BASE_URL` environment variable above — the built image
itself is backend-agnostic, so switching backends is a different `up` command, not a different
image.

## What this is not

This is the single-backend "just run it" stack (Phase 8 item 2 in
`../shared/phased-implementation-plan.md`). The separate two-backend Compose smoke test
(`../shared/devops-pipeline-overview.md#2-the-docker-compose-smoke-test` — both backends live
against one database, no frontend, scripted AC-SE-05/AC-OB-01 cross-backend proof) is Phase 8 item
1 and has not been built yet.
