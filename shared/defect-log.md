# Defect Log

**Real defects found in the four implementation repos** — `hotelapp-client-react`,
`hotelapp-client-angular`, `hotelapp-server-nodejs`, `hotelapp-server-springboot`. Not a second
[decision-log.md](./decision-log.md): that tracks *specification* decisions later reversed; this
tracks *code* that didn't do what the specification already correctly said. A defect found and
fixed in the same session still gets an entry — the point is a visible record that the project is
tested and maintained, not just built once.

**Out of scope for this log**: a stale claim inside a document itself (a wrong test count, a
missing status update) is a documentation-accuracy issue, corrected in place where it was found,
not logged here. This log is for the four *code* repos only.

Newest first within each section.

---

## Open

| # | Repo | Summary | Priority | Found |
|---|------|---------|----------|-------|
| 1 | `hotelapp-client-react` | `npm run format:check` fails on 79 files — pre-existing Prettier style drift, not caused by any single change (confirmed via `git stash`). Purely cosmetic: does not affect `build`, `typecheck`, `lint`, `test:run`, or anything a user or reviewer running the app would see. No CI workflow exists in this repo yet to gate on it either. Deferred at Jeff's instruction (2026-09-29) — low priority, fix in a dedicated cleanup pass rather than folded into an unrelated commit | Low | 2026-09-29 |

## Fixed

| # | Repo | Summary | Priority | Found | Fixed |
|---|------|---------|----------|-------|-------|
| — | *(none backfilled yet — this log was created 2026-09-29. Earlier defects found and fixed this session, e.g. `hotelapp-server-nodejs`'s own smaller `format:check` gap and the session-logout header bug in `hotelapp-client-react`, are recorded in their fix commits and in `claude-memory/hotelapp.md`, not retroactively added here unless asked.)* | | | | |

---

## Using this log

Add an entry when real application code in one of the four implementation repos does not do what
its own specification already correctly describes — found by running something (a test, a manual
click-through, a command), not by inspection alone. Log it whether or not it gets fixed in the same
session: an entry moves from **Open** to **Fixed** with a commit reference once resolved, it is
never deleted. Priority is a judgment call (`Low`/`Medium`/`High`/`Critical`) — weigh user-visible
impact and whether the project's own acceptance criteria or CI would ever have caught it
unassisted.
