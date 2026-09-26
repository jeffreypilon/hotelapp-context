# Environment Setup Guide — React

Clone to running, for `hotelapp-client-react`. Written to be followed literally — this is the document a
reviewer actually runs, so it is complete rather than abbreviated.

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| **Node.js** — current LTS | Pinned in `.nvmrc` and `package.json` `engines`. `nvm use` picks it up |
| **npm 10+** | Ships with current LTS Node |
| **Git** | |
| **A running backend** | Either one. See [Getting a backend](#getting-a-backend) |
| **PostgreSQL 18.6** | Only if running a backend natively rather than via Docker |

No global CLI install is needed — everything runs through npm scripts.

---

## Quick start

```bash
git clone https://github.com/jeffreypilon/hotelapp-client-react.git
cd hotelapp-client-react
nvm use                    # or ensure current LTS is active
npm ci                     # NOT npm install — respects the committed lockfile
cp .env.example .env.local
npm run dev                # http://localhost:5173
```

`npm ci` rather than `npm install` is deliberate: a lockfile that is not respected is not a lockfile, and
a reviewer should get the dependency tree the author had.

The dev server prints the port. If 5173 is taken, Vite picks the next one and prints it — and the backend's
allowed-origins list must then include that port, which is the most common first-run snag. See
[Troubleshooting](#troubleshooting).

---

## Configuration

### `.env.example` (committed)

```dotenv
# Base URL of the backend API, including /api/v1.
# Node/Express backend:  http://localhost:3000/api/v1
# Spring Boot backend:   http://localhost:8080/api/v1
VITE_API_BASE_URL=http://localhost:3000/api/v1
```

That is the whole configuration surface. **`.env.local` is git-ignored; `.env.example` is committed** and is
the documentation of what a fresh clone needs, per
[security-principles.md](../../shared/security-principles.md#secrets-and-configuration).

**There are no secrets here.** This client holds no credential of any kind — no API key, no token. The
session cookie is set by the server and is invisible to this code. A value that looks like a secret has
been added by mistake.

### Pointing at either backend

Two mechanisms, because development and a built artifact have different needs.

**In development** — edit `.env.local` and restart the dev server. Vite inlines `VITE_*` at build time, so
a restart is required; a hot reload will not pick it up.

```dotenv
VITE_API_BASE_URL=http://localhost:8080/api/v1   # switch to Spring Boot
```

**In a built bundle** — do **not** rebuild. The built app reads `public/config.js`, served beside
`index.html` and loaded before the bundle:

```js
// dist/config.js  — edit this file, reload the page, no rebuild
window.__HOTELAPP_CONFIG__ = { apiBaseUrl: "http://localhost:8080/api/v1" };
```

`config/env.ts` prefers `window.__HOTELAPP_CONFIG__` and falls back to the build-time value, per
[architecture-specification.md](./architecture-specification.md#configuration). This is what makes
"point either frontend at either backend by changing one configuration value" literally true of a built
bundle — the claim
[phased-implementation-plan.md](../../shared/phased-implementation-plan.md) makes for Phase 8.

**The same global name and mechanism are used by the Angular client**, so one deployment step covers both.

---

## Getting a backend

This client is useless without one. In order of convenience:

### Docker Compose (easiest, once Phase 8 exists)

```bash
cd ../hotelapp-server-nodejs        # or hotelapp-server-springboot
docker compose up -d
```

Brings up PostgreSQL, applies migrations, seeds demo data, and starts the API. **Not available until Phase
8** — noted so this section is not mistaken for a working instruction today.

### Natively

1. **PostgreSQL 18.6 running**, with a database for the app. 18.6 specifically: the schema uses
   `uuidv7()`, a PostgreSQL 18 core function, so 17 or earlier will not apply the migrations. See
   [data-model.md](../../shared/data-model.md#target-platform).
2. **Apply migrations with Flyway**, against the canonical SQL in `hotelapp-context/shared/migrations/`.
   Flyway is the only tool that applies DDL — see
   [versioning-strategy.md](../../shared/versioning-strategy.md#database-schema-migrations). **The Node
   backend cannot migrate a database by itself**, which surprises people; run Flyway from the Spring Boot
   repo or via the standalone Flyway CLI.
3. **Seed demo data**, per that backend's own setup guide.
4. **Start the backend** — `:3000` for Node, `:8080` for Spring Boot.
5. **Confirm it is up and which one it is:**

```bash
curl http://localhost:3000/api/v1/health
# {"status":"UP","database":"UP","version":"1.0.0","backend":"nodejs"}
```

The `backend` field tells you which implementation answered, which matters when both are running.

### Both at once

Legitimate and useful: both backends can run against the same database, which is how the
interchangeability demo works. Because **browsers scope cookies by host and not by port**, a session
established against `localhost:3000` is honored by `localhost:8080` — see
[AC-SE-05](../../shared/acceptance-criteria.md#ac-se-05--a-session-works-interchangeably-against-both-backends).
Point this client at one, log in, then point it at the other and reload: you are still logged in.

---

## CORS, and the thing that will bite first

The backend must allow this client's origin **with credentials**. Every authenticated request carries the
session cookie, so:

- The backend's `CORS_ALLOWED_ORIGINS` must include `http://localhost:5173` — or whatever port Vite
  actually chose.
- `Access-Control-Allow-Credentials: true` must be set, which the backends do per
  [api-contracts.md](../../shared/api-contracts.md#cross-cutting-requirements).
- A wildcard origin will **not** work. The browser refuses a wildcard on a credentialed request, so this
  fails before it is insecure.

**A CORS rejection looks like a network failure in the browser**, not like an HTTP error — the request
never reaches your code. So "We couldn't reach the server" on a backend you can `curl` successfully is
almost always CORS or a wrong base URL.

---

## npm scripts

| Script | Does |
|--------|------|
| `npm run dev` | Vite dev server with HMR |
| `npm run build` | Production build to `dist/` |
| `npm run preview` | Serve `dist/` locally — the only way to test the runtime-config mechanism |
| `npm run lint` | ESLint, zero warnings tolerated |
| `npm run format:check` | Prettier, verify only |
| `npm run format` | Prettier, write |
| `npm run typecheck` | `tsc --noEmit` |
| `npm test` | Vitest, watch mode |
| `npm run test:run` | Vitest, once — what CI runs |
| `npm run test:coverage` | Coverage report, not gated |

`npm run preview` is worth knowing about: the runtime `config.js` mechanism only exists in a build, so it
cannot be exercised through `npm run dev`.

---

## Verifying the setup works

Not just "the page loads" — check the things that commonly fail silently:

1. **Property list renders** at `http://localhost:5173/` with seeded hotels. If empty, the database is
   unseeded, not broken.
2. **A search returns results.** Pick dates a week out. Exercises `GET /availability`, the most complex
   query.
3. **Register an account.** Confirms `POST /auth/register`, and that the cookie is being set — check
   DevTools → Application → Cookies for `hotelapp_session` with `HttpOnly` ✓ and `SameSite=Lax`.
4. **Reload the page.** You should still be logged in. This confirms the `GET /auth/me` bootstrap; if you
   are logged out, the cookie is not being sent and the cause is `credentials` or CORS.
5. **Complete a booking** with test card `4242 4242 4242 4242`. You should reach a confirmation number.
6. **Check `localStorage` and `sessionStorage` are empty.** They must be. Anything there is a violation of
   [security-implementation.md](./security-implementation.md).

Step 6 is the one people skip and the one that catches a real policy breach.

---

## Troubleshooting

| Symptom | Cause |
|---------|-------|
| "We couldn't reach the server" but `curl` works | CORS, or a base URL missing `/api/v1`. Check the browser console for the CORS message — the network tab alone will not say |
| Logged out on every reload | Cookie not sent: `credentials: 'include'` missing, or the origin is not in the backend's allow-list |
| `401` on one screen only | That screen's request bypassed the fetch wrapper. All HTTP goes through `api/client.ts` |
| Vite on an unexpected port | 5173 was taken. Add the actual port to the backend's allowed origins |
| Config change ignored in dev | `VITE_*` is build-time; restart the dev server |
| Config change ignored in a build | Edit `dist/config.js`, not `.env.local` |
| Empty property list, no error | Database not seeded |
| Backend won't start: migration errors | Flyway has not run, or PostgreSQL is not 18.x |
| `npm ci` fails | Node version mismatch — `nvm use` |
| Cookie absent in DevTools | Backend never set it. Check the login response for `Set-Cookie` |

---

## What is not part of setup

| Not needed | Why |
|------------|-----|
| A `.env` for secrets | This client has none |
| A proxy configuration | The client calls the API's absolute origin; CORS handles it |
| An OpenAPI codegen step | Types are hand-written — [architecture-specification.md](./architecture-specification.md#the-api-client-layer) |
| A Docker build for development | Native dev is the inner loop; Compose is for verification and for other people |
| Any global npm install | Everything is a local dependency |
