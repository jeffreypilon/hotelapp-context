# Environment Setup Guide — Angular

Clone to running, for `hotelapp-client-angular`. Written to be followed literally — this is the document a
reviewer actually runs, so it is complete rather than abbreviated.

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| **Node.js** — current LTS | Pinned in `.nvmrc` and `package.json` `engines`. Angular 22 requires a recent LTS |
| **npm 10+** | Ships with current LTS Node |
| **Git** | |
| **A running backend** | Either one. See [Getting a backend](#getting-a-backend) |
| **PostgreSQL 18.6** | Only if running a backend natively rather than via Docker |

**No global `@angular/cli` install is required.** Use `npx ng` or the npm scripts below. A globally
installed CLI at a different major version than the project is a recurring source of confusing errors, so
the scripts deliberately do not depend on one.

---

## Quick start

```bash
git clone https://github.com/jeffreypilon/hotelapp-client-angular.git
cd hotelapp-client-angular
nvm use                    # or ensure current LTS is active
npm ci                     # NOT npm install — respects the committed lockfile
npm start                  # http://localhost:4200
```

`npm ci` rather than `npm install` is deliberate: a lockfile that is not respected is not a lockfile, and a
reviewer should get the dependency tree the author had.

The dev server serves on 4200 by default. If it is taken, pass `--port` — and the backend's allowed-origins
list must then include that port, which is the most common first-run snag. See
[Troubleshooting](#troubleshooting).

---

## Configuration

Angular has no `.env` mechanism of its own, so configuration reaches the app two ways, mirroring the React
client's arrangement as closely as the framework allows.

### Development — `src/environments/environment.development.ts`

```ts
export const environment = {
  // Base URL of the backend API, including /api/v1.
  // Node/Express backend:  http://localhost:3000/api/v1
  // Spring Boot backend:   http://localhost:8080/api/v1
  apiBaseUrl: 'http://localhost:3000/api/v1',
};
```

Committed, since it contains no secret. A `.env.example` equivalent is unnecessary here because the file
*is* the example — but the same rule from
[security-principles.md](../../shared/security-principles.md#secrets-and-configuration) applies: if
anything secret ever needs to reach this client, it does not go in a committed file.

**There are no secrets here.** This client holds no credential of any kind — no API key, no token. The
session cookie is set by the server and is invisible to this code. A value that looks like a secret has been
added by mistake.

### Pointing at either backend

**In development** — edit `environment.development.ts` and restart `npm start`. The value is compiled in, so
a restart is required; a hot reload will not pick it up.

**In a built bundle** — do **not** rebuild. The built app reads `public/config.js`, served beside
`index.html` and loaded before the bundle:

```js
// dist/browser/config.js  — edit this file, reload the page, no rebuild
window.__HOTELAPP_CONFIG__ = { apiBaseUrl: "http://localhost:3000/api/v1" };
```

`core/config/env.ts` prefers `window.__HOTELAPP_CONFIG__` and falls back to the compiled value, per
[architecture-specification.md](./architecture-specification.md#configuration). This is what makes "point
either frontend at either backend by changing one configuration value" literally true of a built bundle —
the claim [phased-implementation-plan.md](../../shared/phased-implementation-plan.md) makes for Phase 8.

**The global's name and the mechanism are deliberately identical to the React client's**, so one deployment
step covers both. Do not rename it here.

---

## Getting a backend

This client is useless without one. In order of convenience:

### Docker Compose (easiest, once Phase 8 exists)

```bash
cd ../hotelapp-server-springboot     # or hotelapp-server-nodejs
docker compose up -d
```

Brings up PostgreSQL, applies migrations, seeds demo data, and starts the API. **Not available until Phase
8** — noted so this section is not mistaken for a working instruction today.

### Natively

1. **PostgreSQL 18.6 running**, with a database for the app. 18.6 specifically: the schema uses `uuidv7()`,
   a PostgreSQL 18 core function, so 17 or earlier will not apply the migrations. See
   [data-model.md](../../shared/data-model.md#target-platform).
2. **Apply migrations with Flyway**, against the canonical SQL in `hotelapp-context/shared/migrations/`.
   Flyway is the only tool that applies DDL — see
   [versioning-strategy.md](../../shared/versioning-strategy.md#database-schema-migrations). The Spring Boot
   backend runs Flyway itself on startup, which makes it the more convenient backend to stand up first.
3. **Seed demo data**, per that backend's own setup guide.
4. **Start the backend** — `:8080` for Spring Boot, `:3000` for Node.
5. **Confirm it is up and which one it is:**

```bash
curl http://localhost:8080/api/v1/health
# {"status":"UP","database":"UP","version":"1.0.0","backend":"springboot"}
```

The `backend` field tells you which implementation answered, which matters when both are running.

### Both at once

Legitimate and useful: both backends can run against the same database, which is how the interchangeability
demo works. Because **browsers scope cookies by host and not by port**, a session established against
`localhost:8080` is honored by `localhost:3000` — see
[AC-SE-05](../../shared/acceptance-criteria.md#ac-se-05--a-session-works-interchangeably-against-both-backends).
Point this client at one, log in, then point it at the other and reload: you are still logged in.

---

## CORS, and the thing that will bite first

The backend must allow this client's origin **with credentials**. Every authenticated request carries the
session cookie, so:

- The backend's `CORS_ALLOWED_ORIGINS` must include `http://localhost:4200` — or whatever port you served
  on.
- `Access-Control-Allow-Credentials: true` must be set, which the backends do per
  [api-contracts.md](../../shared/api-contracts.md#cross-cutting-requirements).
- A wildcard origin will **not** work. The browser refuses a wildcard on a credentialed request, so this
  fails before it is insecure.

**A CORS rejection looks like a network failure in the browser**, not like an HTTP error — the request never
reaches your code. So "We couldn't reach the server" on a backend you can `curl` successfully is almost
always CORS or a wrong base URL.

> **An Angular-specific trap.** The CLI's `proxyConfig` would make the API same-origin in development and
> sidestep CORS entirely. **Do not use it.** It would mean development never exercises the cross-origin
> credentialed-cookie path that a built deployment uses, hiding a CORS misconfiguration until the moment it
> is hardest to debug. Keep the API cross-origin in development, exactly as it will be in a build.

---

## npm scripts

| Script | Does |
|--------|------|
| `npm start` | `ng serve` with HMR |
| `npm run build` | Production build to `dist/` |
| `npm run preview` | Serve the build locally — the only way to test the runtime-config mechanism |
| `npm run lint` | ESLint (`angular-eslint`), zero warnings tolerated |
| `npm run format:check` | Prettier, verify only |
| `npm run format` | Prettier, write |
| `npm run typecheck` | `tsc --noEmit`, with `strictTemplates` |
| `npm test` | Vitest, watch mode |
| `npm run test:run` | Vitest, once — what CI runs |
| `npm run test:coverage` | Coverage report, not gated |

`npm run preview` is worth knowing about: the runtime `config.js` mechanism only exists in a build, so it
cannot be exercised through `npm start`.

---

## Verifying the setup works

Not just "the page loads" — check the things that commonly fail silently:

1. **Property list renders** at `http://localhost:4200/` with seeded hotels. If empty, the database is
   unseeded, not broken.
2. **A search returns results.** Pick dates a week out. Exercises `GET /availability`, the most complex
   query.
3. **Register an account.** Confirms `POST /auth/register`, and that the cookie is being set — check DevTools
   → Application → Cookies for `hotelapp_session` with `HttpOnly` ✓ and `SameSite=Lax`.
4. **Reload the page.** You should still be logged in. This confirms the `GET /auth/me` bootstrap running in
   `provideAppInitializer`; if you are logged out, the cookie is not being sent and the cause is
   `withCredentials` or CORS.
5. **Complete a booking** with test card `4242 4242 4242 4242`. You should reach a confirmation number.
6. **Check `localStorage` and `sessionStorage` are empty.** They must be. Anything there is a violation of
   [security-implementation.md](./security-implementation.md).

Step 6 is the one people skip and the one that catches a real policy breach.

One Angular-specific check worth doing once: if the app hangs on a blank page at startup, the session
initializer is rejecting rather than resolving. It must resolve on `401` — an anonymous visitor is not a
startup failure, and a rejecting initializer is a total outage from a one-line mistake.

---

## Troubleshooting

| Symptom | Cause |
|---------|-------|
| "We couldn't reach the server" but `curl` works | CORS, or a base URL missing `/api/v1`. Check the browser console for the CORS message — the network tab alone will not say |
| Blank page, no error, app never starts | `provideAppInitializer` rejecting instead of resolving on `401` |
| Logged out on every reload | Cookie not sent: `withCredentials: true` missing from the interceptor, or the origin is not in the backend's allow-list |
| `401` on one screen only | That screen's request bypassed the interceptor. `HttpClient` defaults `withCredentials` to `false`, so all HTTP must go through it |
| Config change ignored in dev | The value is compiled in; restart `npm start` |
| Config change ignored in a build | Edit `dist/browser/config.js`, not the environment file |
| Empty property list, no error | Database not seeded |
| Backend won't start: migration errors | Flyway has not run, or PostgreSQL is not 18.x |
| `npm ci` fails | Node version mismatch — `nvm use` |
| `ng` command version mismatch | A global CLI at a different major. Use `npx ng` or the npm scripts |
| Cookie absent in DevTools | Backend never set it. Check the login response for `Set-Cookie` |

---

## What is not part of setup

| Not needed | Why |
|------------|-----|
| A `.env` for secrets | This client has none |
| `proxyConfig` | Deliberately avoided — see the trap above |
| An OpenAPI codegen step | Types are hand-written — [architecture-specification.md](./architecture-specification.md#the-api-client-layer) |
| A Docker build for development | Native dev is the inner loop; Compose is for verification and for other people |
| A global `@angular/cli` install | Use `npx ng` or the npm scripts |
| `@angular/localize` | English only, per [non-functional-requirements.md](../../shared/non-functional-requirements.md) |
