# Environment Setup Guide — Node / Express

Clone to running, for `hotelapp-server-nodejs`. Written to be followed literally.

> ## Read this first: you cannot start here
>
> **This backend cannot create its own database schema.** Flyway is the sole DDL executor and Prisma
> only introspects — [versioning-strategy.md](../../shared/versioning-strategy.md#database-schema-migrations).
> So the schema must exist **before** this backend is useful, and creating it is not a step this repo
> can perform with `npm` alone.
>
> Three ways to get a migrated database, in order of convenience:
>
> 1. **Start the Spring Boot backend once.** It runs Flyway on startup. Then stop it and run this one.
> 2. **Run the Flyway CLI** (or its Docker image) against `hotelapp-context/shared/migrations/`.
> 3. **`docker compose up`** in either backend repo, once Phase 8 exists.
>
> This is the one genuine asymmetry between the two backends, it is a cost the ownership decision
> accepted deliberately, and it is stated here rather than discovered halfway through setup.

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| **Node.js** — current LTS | Pinned in `.nvmrc` and `package.json` `engines` |
| **npm 10+** | Ships with current LTS |
| **PostgreSQL 18.6** | **18 specifically** — the schema uses `uuidv7()`, a PostgreSQL 18 core function. 17 or earlier will not apply the migrations |
| **Docker** | For Testcontainers in the test suite, and for the Flyway CLI image |
| **A migrated database** | See above |
| Git | |

---

## Quick start

```bash
git clone https://github.com/jeffreypilon/hotelapp-server-nodejs.git
cd hotelapp-server-nodejs
nvm use
npm ci                         # NOT npm install — respects the lockfile

cp .env.example .env

# 1. create the database
createdb hotelapp

# 2. apply the canonical migrations — NOT a prisma command
docker run --rm \
  -v "$(cd ../hotelapp-context/shared/migrations && pwd)":/flyway/sql \
  --network host \
  flyway/flyway:latest \
  -url=jdbc:postgresql://localhost:5432/hotelapp \
  -user=postgres -password=postgres \
  migrate

# 3. generate the Prisma client from the migrated schema
npx prisma db pull             # regenerates schema.prisma from the database
npx prisma generate            # generates the typed client

# 4. seed demo data
npm run seed

# 5. run
npm run dev                    # http://localhost:3000
```

Step 2 is the one that surprises people. **There is no `npm run migrate`** in this repo, and adding
one would be a decision reversal rather than a convenience — see the box above.

Step 3 is required after every schema change, per
[versioning-strategy.md](../../shared/versioning-strategy.md#keeping-the-two-orm-mappings-in-step).

Confirm it worked:

```bash
curl http://localhost:3000/api/v1/health
# {"status":"UP","database":"UP","version":"1.0.0","backend":"nodejs"}
```

---

## `.env.example` (committed)

```dotenv
# ---- Database ----
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/hotelapp

# ---- Server ----
PORT=3000
NODE_ENV=development
LOG_LEVEL=info

# ---- Auth ----
BCRYPT_COST=12
SESSION_IDLE_TTL_HOURS=8
SESSION_ABSOLUTE_TTL_DAYS=30
SESSION_SLIDE_THRESHOLD_MINUTES=5

# ---- CORS ----
# Comma-separated. NEVER a wildcard — the browser refuses it on credentialed requests.
CORS_ALLOWED_ORIGINS=http://localhost:5173,http://localhost:4200

# ---- Rate limiting ----
AUTH_RATE_LIMIT_ATTEMPTS=10
AUTH_RATE_LIMIT_WINDOW_MINUTES=15
```

**`.env` is git-ignored; `.env.example` is committed** and is the documentation of what a fresh clone
needs, per
[security-principles.md](../../shared/security-principles.md#secrets-and-configuration).

> **Both frontend origins are listed.** `5173` is Vite (React) and `4200` is the Angular CLI. Either
> frontend must be able to point at either backend by changing one value, so both backends allow both
> frontend origins.

> **The session TTL values must match the Spring Boot backend's exactly.** A divergence produces users
> who appear logged out by one backend and not the other — the kind of bug configuration makes easy
> and code review does not catch. [data-model.md](../../shared/data-model.md#sessions) holds the
> normative values.

---

## Seeding

`npm run seed` loads demo data at the volumes in
[non-functional-requirements.md](../../shared/non-functional-requirements.md#scale): 3 properties,
~300 rooms, ~3,000 reservations spanning 18 months back and 6 months forward, ~200 guests, and 8 admin
users.

**Seed to those volumes, not to the minimum.** A booking flow tested against three reservations proves
nothing about the availability query or the admin calendar, and a demo with an empty calendar looks
like a form rather than a system.

**Seeding is not a migration.** The seven `amenities` rows come from a migration, because the codes are
a contract — [data-model.md](../../shared/data-model.md#amenities-and-room_type_amenities). Everything
else is this script, which is re-runnable and truncates first.

Admin logins are printed by the script. Passwords are dev-only and documented in its output rather
than here.

---

## Working against the other frontend, or alongside the other backend

**Either frontend against this backend:** nothing to change here, as long as the frontend's origin is
in `CORS_ALLOWED_ORIGINS`. The frontend points at `http://localhost:3000/api/v1`.

**Both backends at once** is legitimate and is how interchangeability is demonstrated. Run this on
`3000` and Spring Boot on `8080`, **against the same database**. Because browsers scope cookies by
host and not by port, a session established against one is honored by the other —
[AC-SE-05](../../shared/acceptance-criteria.md#ac-se-05--a-session-works-interchangeably-against-both-backends).

```bash
# log in against Node, then use the cookie against Spring Boot
curl -c /tmp/c.txt -X POST localhost:3000/api/v1/auth/login \
  -H 'Content-Type: application/json' -d '{"email":"…","password":"…"}'
curl -b /tmp/c.txt localhost:8080/api/v1/auth/me      # -> 200, same user
```

Two things to watch when both run: **`PORT` must differ** (obviously), and PostgreSQL's default
`max_connections` is 100 — two backends with pools of 10–20 each are fine, but do not raise both pools
carelessly.

---

## Tests

```bash
npm run test:unit          # pure domain logic. No container, sub-second
npm run test:integration   # Testcontainers + Flyway CLI + full suite
npm run test:run           # both — what CI runs
npm run test:tz            # the suite under TZ=UTC and TZ=Asia/Tokyo
```

**The integration suite needs Docker and a path to the canonical migrations.** Global setup starts
`postgres:18.6` and invokes the Flyway CLI against `hotelapp-context/shared/migrations/` — it does
**not** use `prisma migrate`, for the reason in
[testing-standards.md](./testing-standards.md#the-flyway-prerequisite-in-tests). Set
`HOTELAPP_MIGRATIONS_DIR` if the context repo is not a sibling checkout.

`test:unit` is deliberately container-free: it is the loop a developer runs while writing `domain/`
logic.

---

## npm scripts

| Script | Does |
|--------|------|
| `npm run dev` | `tsx watch` with reload |
| `npm run build` | Compile to `dist/` |
| `npm start` | Run the build |
| `npm run lint` / `format:check` / `typecheck` | Each fails CI |
| `npm run seed` | Demo data |
| `npm run prisma:pull` | `prisma db pull && prisma generate` — after a schema change |
| `npm run ci` | lint && format:check && typecheck && test:run && build |

**There is deliberately no `migrate` script.** Its absence is the decision, and a wrapper would invite
someone to add `prisma migrate deploy` behind it.

---

## Troubleshooting

| Symptom | Cause |
|---------|-------|
| `relation "properties" does not exist` | Migrations never ran. See the box at the top |
| `function uuidv7() does not exist` | PostgreSQL is not 18.x |
| Prisma: "column does not exist" on one endpoint | `schema.prisma` is stale. Run `npm run prisma:pull` |
| Startup logs a Flyway version ahead of what you expect | The database is migrated past this client's generated schema. Re-pull |
| Frontend gets a network error, `curl` works | CORS. The frontend's origin is not in `CORS_ALLOWED_ORIGINS`, or the base URL is missing `/api/v1` |
| Logged out on every frontend reload | The cookie is not reaching the backend — check the origin allow-list and that the client sends credentials |
| Sessions expire sooner than in Spring Boot | The `SESSION_*` values differ between the two backends |
| `npm ci` fails | Node version mismatch — `nvm use` |
| Integration tests hang or fail to start | Docker is not running, or the migrations path is wrong |
| Every request looks like it came from one IP | `trust proxy` misconfigured behind a proxy — [security-implementation.md](./security-implementation.md#rate-limiting) |

---

## What is not part of setup

| Not needed | Why |
|------------|-----|
| `prisma migrate` of any kind | Prisma does not apply DDL |
| A `prisma/migrations/` directory | Same — it does not exist in this repo |
| Hand-editing `schema.prisma` | It is generated |
| Writing migration SQL here | It is authored in `hotelapp-context` |
| A Docker build for development | Native is the inner loop; Compose is for verification and for other people |
| A global npm install | Everything is a local dependency |
