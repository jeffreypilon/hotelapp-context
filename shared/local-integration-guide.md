# Local Integration Guide

How to run one of this project's frontends against one of its backends on a single development
machine, and how to switch which backend a running frontend talks to. This document does not
decide anything about the product or the API — it is a runbook, cross-referencing the documents
that do. Where it repeats a command from a stack's own `environment-setup-guide.md`, that stack
document remains authoritative; this one exists because running the *whole* matrix (which
frontend, against which backend) is a cross-cutting concern none of the four repos owns alone.

> **Status.** Covers `hotelapp-client-react` against both backends, verified by actually running
> it. `hotelapp-client-angular` section is a placeholder — fill it in once that frontend exists,
> alongside its own `stacks/angular/environment-setup-guide.md`.

---

## The matrix

|                | Spring Boot (`:8080`) | Node.js (`:3000`) |
|----------------|-----------------------|--------------------|
| **React** (`:5173`)   | ✅ works, verified | ✅ works, verified |
| **Angular** (`:4200`) | ⬜ not yet built | ⬜ not yet built |

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
  pins (`<java.version>`). **A `mvn` not found on `PATH`, or a JDK version mismatch between
  `JAVA_HOME` and that pin, is a common per-machine gap this guide cannot fix generically** — it
  depends on how Maven and the JDK were installed on this machine, not on anything in this
  project. If either is wrong, see `hotelapp-server-springboot`'s own Copilot instructions for how
  that repo's own environment was actually resolved, rather than guessing.

## Starting a backend

Run each command from inside that repo's own directory (`cd` there first) — none of the commands
below need a `-f`/`--prefix` path argument.

**Spring Boot** (port 8080, applies Flyway migrations on startup), from
`hotelapp-server-springboot`:

```powershell
mvn spring-boot:run
```

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

Not yet applicable — `hotelapp-client-angular` has no code yet. Expect the same shape as React's
(a build-time config value naming the backend's base URL, switched by editing a local env file
and restarting `ng serve`), confirmed against
[stacks/angular/environment-setup-guide.md](../stacks/angular/environment-setup-guide.md) once
that repo exists.

## Troubleshooting

| Symptom | Cause |
|---|---|
| Browser console shows an opaque CORS/network error on every request, not just `401`s | A stray process is already listening on 5173 (or 4200), Vite/Angular CLI silently bumped to the next port, and neither backend's CORS allow-list includes it. Check `Get-NetTCPConnection -LocalPort 5173 -State Listen` and kill the stray process |
| `GET /auth/me` specifically fails as an opaque CORS/network error, but other endpoints work | The known, currently-unfixed Spring Boot defect: its `401`/`403` responses raised before Spring MVC's dispatcher (e.g. an anonymous `GET /auth/me`) are missing CORS headers. Confirmed via `curl -H "Origin: ..."`. Both frontends already tolerate this as a fallback; it is not something to work around by hand |
| Node backend fails at startup with a missing-table error | The database was never migrated. Start Spring Boot once first — Node cannot apply its own schema |
| A session created against one backend doesn't work against the other | Confirm both are pointed at the *same* `DATABASE_URL`/`datasource.url` — this is the most common reason they'd appear to disagree despite the shared-database design |
| `mvn` (or `mvnw`) is not recognized as a command | Maven isn't on this machine's `PATH`, even though it's installed — a per-machine setup gap, not a project defect. Find the real install (e.g. `where.exe mvn` won't find it either; search common install roots) and either add its `bin` directory to `PATH` for the session or reference it by full path. See `hotelapp-server-springboot`'s own Copilot instructions for how this was actually resolved on the machine this project was built on |
| Spring Boot fails to start or build with an "unsupported class file version" / release-version error | `JAVA_HOME` points at a newer JDK than `pom.xml`'s `<java.version>` pins. Set `JAVA_HOME` to a JDK matching that pin for the session before running `mvn` — don't assume the system default JDK is the right one |
