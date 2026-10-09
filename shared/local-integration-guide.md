# Local Integration Guide

How to run one of this project's frontends against one of its backends on a single development
machine, and how to switch which backend a running frontend talks to. This document does not
decide anything about the product or the API — it is a runbook, cross-referencing the documents
that do. Where it repeats a command from a stack's own `environment-setup-guide.md`, that stack
document remains authoritative; this one exists because running the *whole* matrix (which
frontend, against which backend) is a cross-cutting concern none of the four repos owns alone.

> **Status.** Covers `hotelapp-client-react` and `hotelapp-client-angular` against both backends,
> both verified by actually running them. Angular's entire guest-facing scope (items 1-6) finished
> 2026-09-29 (`hotelapp-client-angular@a8c59f4`), with an outcome note for all seven steps in
> `phased-implementation-plan.md` — Steps 6 and 7's notes landed after this guide's first Angular
> pass was drafted and were folded in immediately once found, rather than left stale. Every step's
> outcome records a live click-through against a running backend, including Step 4's cross-backend
> `public/config.js`-switch walkthrough this document's "Pointing Angular at a backend" section
> describes below.
>
> **2026-10-09**: added the AI service (hybrid native-plus-Docker startup, since `pgvector` has no
> stock Windows-native path), a start-to-finish demo sequence, and a shutdown sequence — written up
> after a real ~20-minute struggle getting all services running for a demo, so the actual root
> causes (Docker Desktop not yet running, a non-obvious Compose invocation, two databases with two
> different passwords) are captured here rather than left to be rediscovered the same way again.
> That manual sequence is now also automated as `scripts/services.ps1` — start, stop, or check the
> status of any combination of services in one command, verified by actually running every path
> (including a real Start-Process argument-quoting bug on Windows PowerShell 5.1, caught and fixed
> rather than shipped).

---

## The matrix

|                | Spring Boot (`:8080`) | Node.js (`:3000`) |
|----------------|-----------------------|--------------------|
| **React** (`:5173`)   | ✅ works, verified | ✅ works, verified |
| **Angular** (`:4200`) | ✅ works, verified (session portability confirmed live, Step 4) | ✅ works, verified (all 7 steps click-through-tested live) |

Both backends share **one** PostgreSQL database (`hotelapp`) —
[versioning-strategy.md](./versioning-strategy.md) is the reason only Spring Boot may migrate it.
Because browsers scope session cookies by host, not by port, a session established against one
backend is honored by the other; switching backends mid-session does not require logging in
again, as long as both are running against the same database. Sessions are still separate
*rows* — created through whichever backend you signed in against.

## Prerequisites, once per machine

- PostgreSQL 18.6 running and migrated. Start Spring Boot once against a fresh database before
  ever starting Node — Node's own [environment-setup-guide.md](../stacks/nodejs/environment-setup-guide.md)
  covers why (Flyway ownership).
- Each repo's own quick start has been run at least once (`mvn`/`./mvnw` resolved, `npm ci` run,
  `.env`/`.env.local` copied from its `.example`). See each stack's own
  `environment-setup-guide.md` for the one-time setup; this document only covers day-to-day
  running and switching.
- `mvn -v` resolves at all, and reports the Java version `hotelapp-server-springboot/pom.xml`
  pins (`<java.version>`). On a machine where either is wrong — a common, purely local setup gap,
  not a project defect — see the override in "Starting a backend" below.

## Starting a backend

Run each command from inside that repo's own directory (`cd` there first) — none of the commands
below need a `-f`/`--prefix` path argument.

**Spring Boot** (port 8080, applies Flyway migrations on startup), from
`hotelapp-server-springboot`:

```powershell
mvn spring-boot:run
```

**On this machine, that alone is not enough** — `mvn` is not on `PATH`, and the default
`JAVA_HOME` (JDK 23) is newer than this project's pinned `<java.version>21</java.version>`. Both
must be set in the same terminal session first, as one three-line unit, not the last line alone in
a fresh terminal:

```powershell
$env:JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-21.0.12.101-hotspot"
$env:PATH = "$env:JAVA_HOME\bin;C:\Users\Jeff\tools\apache-maven-3.9.16\bin;$env:PATH"
mvn spring-boot:run
```

This is confirmed working on this machine specifically — a different machine may already have
`mvn` on `PATH` and the right `JAVA_HOME`, in which case the plain `mvn spring-boot:run` above is
enough and this override isn't needed. Only needs retyping once per new terminal window/tab, not
before every `mvn` command in one already-configured session. Same detail lives in
`hotelapp-server-springboot`'s own Copilot instructions; kept here too since this is where Jeff
actually looks first when starting a backend.

Use `./mvnw` instead of a system `mvn` once the wrapper exists in that repo (not committed as of
this writing — see that repo's own Copilot instructions). Confirm it is up:

```powershell
curl http://localhost:8080/api/v1/health
```

**Node.js** (port 3000, never migrates — the database must already have been migrated by Spring
Boot at least once), from `hotelapp-server-nodejs`:

```powershell
npm run dev
```

Confirm it is up:

```powershell
curl http://localhost:3000/api/v1/health
```

Only one backend needs to be running at a time to develop against; both may run simultaneously
(different ports, same database) if you want to compare behavior directly — this is exactly the
manual check [devops-pipeline-overview.md](./devops-pipeline-overview.md)'s Compose smoke test
automates in CI.

## Pointing React at a backend

React reads its backend URL from `VITE_API_BASE_URL`, a **build-time** env var — see
[stacks/react/environment-setup-guide.md](../stacks/react/environment-setup-guide.md#pointing-at-either-backend)
for the full mechanism (including the built-bundle `public/config.js` path, which does not apply
in dev).

1. Edit `.env.local` in `hotelapp-client-react`:
   ```dotenv
   VITE_API_BASE_URL=http://localhost:8080/api/v1   # Spring Boot
   # or
   VITE_API_BASE_URL=http://localhost:3000/api/v1   # Node
   ```
2. **Restart** the dev server — Vite inlines `VITE_*` values at startup; editing `.env.local`
   while `npm run dev` is already running has no effect until it is stopped and started again.
   From inside `hotelapp-client-react`:
   ```powershell
   npm run dev
   ```

To switch backends mid-session: stop the old backend, start the new one, edit `.env.local`, and
restart the React dev server. The three steps do not need to happen in that exact order, but the
dev server restart must be the *last* one, since it is the only step that actually re-reads the
file.

## Pointing Angular at a backend

Angular's mechanism is a genuine improvement on React's, not just a different flavor of the same
thing: the backend URL is read from `window.__HOTELAPP_CONFIG__.apiBaseUrl` at runtime, set by
`public/config.js` and loaded via a `<script>` tag in `index.html` **before** the app bootstraps —
see [stacks/angular/architecture-specification.md](../stacks/angular/architecture-specification.md#configuration)
for the full mechanism. `public/config.js` is a static asset, served as-is by both `ng serve` and a
built bundle, so switching backends needs **no dev-server restart and no rebuild** — edit the file
and reload the browser tab. Start the dev server first, from inside `hotelapp-client-angular`:

```powershell
npm start
```

Confirm it is up (Angular CLI's default dev-server port, `4200`, is not overridden anywhere in this
repo):

```powershell
curl http://localhost:4200/
```

Then edit `public/config.js`:

```js
window.__HOTELAPP_CONFIG__ = { apiBaseUrl: 'http://localhost:8080/api/v1' };   // Spring Boot
// or
window.__HOTELAPP_CONFIG__ = { apiBaseUrl: 'http://localhost:3000/api/v1' };   // Node
```

Reload the browser tab — that's the whole switch. **Confirmed live, not just designed this way**:
Angular's own Step 4 outcome note in `phased-implementation-plan.md` records registering a guest
against Node, then editing `public/config.js` to point at Spring Boot on `:8080` and reloading with
no fresh login — the header still showed the same logged-in guest, the same cross-backend session
portability [AC-SE-05](./acceptance-criteria.md#ac-se-05--a-session-works-interchangeably-against-both-backends)
proves for React. Both backends' CORS allow-lists already include `http://localhost:4200` by
default (`hotelapp-server-springboot`'s `application.properties` and
`hotelapp-server-nodejs`'s `CORS_ALLOWED_ORIGINS` default both list it alongside `:5173`) — checked
directly in each repo's source, not assumed from the port number alone.

If `public/config.js` is ever missing or emptied, Angular falls back to the compiled
`src/environments/environment.development.ts` value in a dev build (a genuinely missing config
throws, rather than silently calling nowhere) — but that file needs a dev-server restart to take
effect, the same restart React's `.env.local` needs. **`public/config.js` is the file to edit for a
quick backend switch; `environment.development.ts` is only the fallback default.**

## Starting the AI service

Optional — only needed when a demo uses the AI policy assistant, not for the base booking flow.
From `hotelapp-ai-service`.

**Hard dependency: the `vector` extension.** The AI schema needs PostgreSQL's `pgvector`
extension, which the stock Windows PostgreSQL 18 install does not ship and which is impractical
to compile natively on Windows (needs MSVC) — see §1 of
[stacks/ai-service/environment-setup-guide.md](../stacks/ai-service/environment-setup-guide.md).
The practical answer is **not** to containerize the whole AI service — only its database and
migrations, from `hotelapp-context/docker`:

```powershell
cd <path to>\hotelapp-context\docker
docker compose --profile ai up -d db flyway flyway-ai
```

This is a **different** invocation from the five fully-containerized combinations documented at
the top of `docker-compose.yml` (`--profile react --profile spring --profile ai`, etc.) — naming
the three infrastructure services directly brings up only a pgvector-enabled Postgres on `:5433`
and applies both the business schema and the AI schema to it, while Spring Boot, the frontend, and
the AI service itself all keep running natively. The command blocks until `db` is healthy and both
Flyway runs have exited `0`, so by the time it returns the database is actually ready — no
separate wait needed. This recipe wasn't written down anywhere before 2026-10-09; it had to be
rediscovered by trial, which is why it's here now.

**Docker Desktop must already be running** before this command — if it isn't,
`docker compose` fails with
`failed to connect to the docker API at npipe:////./pipe/dockerDesktopLinuxEngine`. Docker Desktop
itself can take several minutes to fully start after being launched; start it *before* you need
it, not as the first step of a time-boxed demo.

Then, from `hotelapp-ai-service`:

```powershell
uv run hotelapp-ai serve
```

`:8000`. Confirm it's actually healthy, including its view of the backend:

```powershell
curl http://localhost:8000/api/v1/assistant/health
```

**Start the AI service last, after confirming the real backend already answers
`GET /properties`.** Its health check reports `backend` separately from its own status — a
`"backend":"DOWN"` result means the Spring Boot/Node backend isn't actually reachable; go back and
fix *that*, not the AI service.

The native database (`:5432`, password `password`) and the Docker one (`:5433`, password
`postgres`) are genuinely different credentials on purpose — see §1 of
[stacks/ai-service/environment-setup-guide.md](../stacks/ai-service/environment-setup-guide.md)
before assuming a connection failure means something is broken.

## Running everything for a demo, start to finish

**As of 2026-10-09, this is automated: `scripts/services.ps1` in this repo.** It encodes
everything below — the order, the health-check waiting, the JAVA_HOME/Maven override, the Docker
Desktop wait, the AI-service backend-readiness check — so starting, stopping, or checking any
combination of services is one command instead of re-deriving the steps each time:

```powershell
cd hotelapp-context\scripts
.\services.ps1 start -All                                    # postgres + Spring Boot + React + AI
.\services.ps1 start -Services react,angular,springboot      # both frontends side by side, one backend
.\services.ps1 status                                        # what's actually running, with live health checks
.\services.ps1 stop -All                                     # stops everything it's safe to stop (see below)
```

Pass `-Visible` to `start` to open each service in its own labeled, visible terminal window you
can tile on screen — useful for actually showing backend request/response logs live during a
demo, which hidden (the default) background processes can't do. `services.ps1 start -?` (or just
reading the script's own comment header) lists every option and example, including picking the
other backend/frontend (`-Backend nodejs -Frontend angular`).

The manual sequence below is what the script *does* — read it if something needs debugging, or if
you're on a machine without this script. In this order; confirm each step is actually up (via its
own health check) before starting the next — starting steps out of order, or not waiting for one
to finish, is the most common cause of a slow, confusing startup.

1. **PostgreSQL** (native service) — already running as a Windows service; confirm with
   `Get-Service postgresql-x64-18`.
2. **If the AI service is part of the demo**: Docker Desktop, then
   `docker compose --profile ai up -d db flyway flyway-ai` (see "Starting the AI service" above).
   Skip this step entirely if the demo doesn't need the AI assistant.
3. **One backend** — Spring Boot or Node.js (see "Starting a backend" above). Confirm with its
   `/health` endpoint before moving on.
4. **One frontend** — React or Angular (see "Pointing React/Angular at a backend" above). No
   ordering dependency on the backend being up first, but there's nothing to demo yet without it.
5. **The AI service**, last, only if needed (see above) — its own health check is the first place
   that will reveal whether an earlier step didn't actually finish.

Budget real time for step 2 specifically if it's needed and Docker Desktop wasn't already
running — that single step, including Docker Desktop's own startup time, is the most likely
source of an unexpectedly long wait before a demo.

## Stopping everything, cleanly

**`.\services.ps1 stop -All`** does this: stops every app process it's safe to stop, leaves
native PostgreSQL running (shared system service), and leaves the AI service's Docker containers
up (`aidb` — so the next `start` doesn't re-migrate from scratch). Tear those down explicitly,
only when actually done with the AI service for a while, with `.\services.ps1 stop -Services aidb`.

The manual sequence, roughly the reverse of startup order, so nothing is left holding a port the
next session needs:

1. **AI service** — `Ctrl+C` in its terminal.
2. **Frontend(s)** — `Ctrl+C` in their terminal(s).
3. **Backend(s)** — `Ctrl+C` in their terminal(s).
4. **Only if step 2 of "Running everything for a demo" was used** — the AI-only Docker containers:
   ```powershell
   cd <path to>\hotelapp-context\docker
   docker compose --profile ai down
   ```
   `down` (no `-v`) stops and removes the `db`/`flyway`/`flyway-ai` containers but **keeps** the
   named `pgdata` volume, so the next startup reuses the same data rather than re-migrating from
   scratch. Only add `-v` if you deliberately want to wipe it.

**Native PostgreSQL is not part of this shutdown** — it's a persistent Windows service, not a
per-demo process; leave it running.

> **If an AI coding assistant is driving your terminals for you** (rather than you running each
> command in your own terminal windows), one more failure mode is worth knowing: some assistants
> share a small pool of background shells and silently evict the oldest one when a new one is
> opened, which can kill an already-running dev server with no application-level error at all —
> the only symptom is the port suddenly refusing connections. This is not a HotelApp defect and
> won't happen if you're running the processes yourself in ordinary terminals; it only matters when
> something else is orchestrating three or more long-running processes through one shared shell
> pool.

## Troubleshooting

| Symptom | Cause |
|---|---|
| Browser console shows an opaque CORS/network error on every request, not just `401`s | A stray process is already listening on 5173 (or 4200), Vite/Angular CLI silently bumped to the next port, and neither backend's CORS allow-list includes it. Check `Get-NetTCPConnection -LocalPort 5173 -State Listen` and kill the stray process |
| `GET /auth/me` specifically fails as an opaque CORS/network error, but other endpoints work | **This was a real Spring Boot defect (401/403 responses raised before Spring MVC's dispatcher were missing CORS headers), fixed 2026-09-28 (`hotelapp-server-springboot@3a3f864`) — this row is now stale as a live symptom, kept only as a historical note.** If it recurs, the fix has three parts that must all be present: `WebConfig`'s `CorsConfigurationSource` bean, `SecurityConfig` wiring it into `.cors(...)` rather than a no-op, and `ProblemResponseWriter` **not** calling `response.reset()` before writing the error body (that call silently wipes the CORS headers the first two parts just added). Confirmed by reading all three files directly -- Spring Boot wasn't running this session to `curl` it live -- not assumed fixed from the commit message alone |
| Node backend fails at startup with a missing-table error | The database was never migrated. Start Spring Boot once first — Node cannot apply its own schema |
| A session created against one backend doesn't work against the other | Confirm both are pointed at the *same* `DATABASE_URL`/`datasource.url` — this is the most common reason they'd appear to disagree despite the shared-database design |
| `mvn` (or `mvnw`) is not recognized as a command | Maven isn't on this machine's `PATH`, even though it's installed — a per-machine setup gap, not a project defect. Find the real install (e.g. `where.exe mvn` won't find it either; search common install roots) and either add its `bin` directory to `PATH` for the session or reference it by full path. See `hotelapp-server-springboot`'s own Copilot instructions for how this was actually resolved on the machine this project was built on |
| Spring Boot fails to start or build with an "unsupported class file version" / release-version error | `JAVA_HOME` points at a newer JDK than `pom.xml`'s `<java.version>` pins. Set `JAVA_HOME` to a JDK matching that pin for the session before running `mvn` — don't assume the system default JDK is the right one |
| Edited `public/config.js` in `hotelapp-client-angular` but the app still calls the old backend | Either the browser tab wasn't reloaded (no dev-server restart is needed, but a reload is), or `src/environments/environment.development.ts` was edited instead — that file is only the fallback used when `public/config.js` is missing/empty, and it *does* need a dev-server restart to take effect, the same restart React's `.env.local` needs. `public/config.js` is the one to edit for a quick switch |
| Angular's `ng serve` fails to start because port `4200` is already in use | A previous `ng serve` (or another Angular project) is still holding the port. `Get-NetTCPConnection -LocalPort 4200 -State Listen` to find it, same check as the stray-Vite-process symptom above |
| `docker compose` fails with `failed to connect to the docker API at npipe:////./pipe/dockerDesktopLinuxEngine` | Docker Desktop isn't running. Launch it and wait — it can take several minutes to fully start, which is easy to mistake for the command itself hanging |
| The AI service's health check reports `"backend":"DOWN"` | The real backend (Spring Boot or Node) isn't actually reachable. Re-check that backend, not the AI service — this is a downstream symptom, not the root cause |
| A connection to either database fails with a password error | `:5432` (native) and `:5433` (Docker) use **different** passwords on purpose — see §1 of [stacks/ai-service/environment-setup-guide.md](../stacks/ai-service/environment-setup-guide.md). A failure against one almost always means the other's credentials were used by mistake |
| The fully-containerized demo stack (`docker compose --profile <frontend> --profile <backend> up`) fails to bind `:8080` | A stray exited container from an earlier run may still hold the name. `docker ps -a` to find it, `docker rm` it before retrying — one such container (`hotelapp-api-spring-1`) was found sitting unused on this machine on 2026-10-09 |
