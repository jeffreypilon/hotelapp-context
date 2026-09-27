# Decision Log

**Reversed decisions only.** This is not a second index of design decisions — those live as
`> **Design Decision — ...**` callouts in the document that owns each one, which is the right
place for them and the place to read about alternatives that were considered and rejected.

What the other documents cannot show on their own is **sequence**: something was decided, built
on, and later undone. An entry belongs here only if all three of "what was decided", "what
caused the reversal", and "what replaced it" can be stated from what was actually written at
the time. If a decision simply beat an alternative that was never adopted, it is an ordinary
design decision and stays where it is.

Entries are chronological, oldest first.

> **A note on git history, before anyone tries to diff these.** Most of this project's
> specification work is not yet reflected in commits: at the time of writing, this repository's
> history contains only the initial scaffold (all documents as three-line stubs) and
> `project-overview.md`. Every other `shared/` document — including both revisions of the
> authentication design — was written in the working tree and has never been committed in its
> superseded form. `git log -p -- shared/api-contracts.md` shows nothing but the stub, and there
> is no stash, reflog entry, or dangling object holding the earlier text. The "before" states
> below are therefore sourced from the surviving contrast passages in the current documents and
> from the change requests that caused each reversal, not from recoverable diffs. **Once these
> documents are committed, that ceases to be true for future reversals** — which is a reason to
> commit them.

---

## 1. Free-tier hosting as a deployment target — dropped

**Decided:** Deploy the finished project to free-tier hosting as a stretch goal — the two
frontends on Vercel or Netlify, the two backends on Render or Railway, with a hosted PostgreSQL
(Neon or Supabase) — so the portfolio piece would have a live URL a reviewer could visit.

This was never specified in any document in this repository. A grep of `shared/` for Vercel,
Netlify, Render, Railway, Neon, Supabase, and "free-tier" returns **zero** matches, confirmed
during the Phase 1b patch and re-confirmed while writing this entry. It existed only in
planning conversation, which is precisely why it needs an entry here: there is no committed
text whose absence would explain itself.

**Reversed:** Two reasons, one specific and one general.

The specific one: a hosted deployment would have put the frontends and backends on **different
registrable domains**, making every API request cross-site. That is incompatible with a
`SameSite=Strict` session cookie and forces `SameSite=None; Secure`, which in turn hands every
state-changing endpoint a CSRF surface that then needs its own defense. The cookie policy was
being driven by the hosting choice rather than by the security requirement.

The general one: keeping four or more free-tier services alive — cold starts, sleeping
instances, services quietly discontinuing free plans, a hosted database expiring — is
continuous operational work that demonstrates nothing about the application. It is upkeep, and
it competes with the thing the project is actually for.

**Replaced with:** Local native development now, Docker Compose later, and no hosted
environment at all. Specified in
[devops-pipeline-overview.md](./devops-pipeline-overview.md) and
[architecture-overview.md](./architecture-overview.md#deployment-shape); the consequences for
availability are stated plainly in
[non-functional-requirements.md](./non-functional-requirements.md#availability).

**What changed as a result:**

- **It removed the cross-origin constraint entirely**, which is what made entry 2 possible. This
  is the originating reversal; the authentication change is downstream of it.
- Docker Compose became the answer to "how does someone else run this", which is the job the
  live URL was meant to do — see
  [devops-pipeline-overview.md](./devops-pipeline-overview.md#2-the-docker-compose-smoke-test).
- Several sections that would otherwise have covered deployment instead state its absence as a
  deliberate scope line: no CI deployment step, no staging ladder, no uptime target, no
  monitoring.
- `shared/` needed no edits when the goal was dropped, because nothing had been written about
  it yet — an accidental benefit of specifying the data model and contract before the
  deployment story.

---

## 2. Authentication: JWT access tokens plus rotating refresh tokens → server-side sessions

The project's clearest reversal, and the one with the most downstream effect.

**Decided:** In Phase 1a, `api-contracts.md` specified a hybrid token scheme, chosen over
server-side sessions after explicit comparison:

- A stateless **JWT access token**, `HS256`, 15-minute TTL, held in client memory and sent as
  `Authorization: Bearer`, carrying `sub`, `email`, `role`, and `propertyId` claims.
- An opaque **refresh token**, 30-day TTL, stored server-side as a SHA-256 hash, delivered in
  an `HttpOnly; SameSite=Strict` cookie path-scoped to `/api/v1/auth/refresh`, **rotated on
  every use with reuse detection** — replaying a rotated token revoked its entire token family.
- A `refresh_tokens` table in `data-model.md` carrying `family_id`, `previous_token_id`,
  `revoked_at`, and `revoked_reason` (`ROTATED`, `LOGOUT`, `REUSE_DETECTED`,
  `PASSWORD_CHANGED`) to support rotation and family revocation.
- A `POST /auth/refresh` endpoint, `TOKEN_EXPIRED` and `REFRESH_TOKEN_INVALID` problem codes,
  and `accessToken` / `tokenType` / `expiresIn` in the login and registration response bodies.
- Client obligations in both frontends: keep the access token in memory only, attach it as a
  bearer header, retry once on `401` after refreshing, and serialize concurrent refreshes so
  two parallel refreshes would not trip reuse detection.

The stated reasoning at the time was explicitly shaped by the deployment topology in entry 1:
server-side sessions were acknowledged as the better default for a single first-party web
application, and rejected here because **two SPA origins talking to two interchangeable
backends** would require a session cookie sent cross-origin on every request, meaning
`SameSite=None; Secure`.

**Reversed:** Entry 1 removed the cross-origin topology, and with it the premise the token
design rested on. What remained was a plainer requirement — *two backends must agree on who is
logged in* — and both backends already share one PostgreSQL database, which is the thing a
session lookup consults. The token scheme was solving a problem the project no longer had, at
the cost of two mechanisms instead of one and roughly a hundred lines of client-side machinery
per frontend.

Notably, this was **not** a correction of an error. The Phase 1a design was sound for the
topology it was written against; it became the wrong answer when the topology changed.

**Replaced with:** A single opaque session token in an `HttpOnly; Secure; SameSite=Lax` cookie
scoped to `/api/v1`, backed by a `sessions` row, with an 8-hour sliding idle window, a 30-day
absolute cap, and a 5-minute write-throttle on the sliding update. Specified in
[api-contracts.md](./api-contracts.md#authentication) and
[data-model.md](./data-model.md#sessions).

**What changed as a result:**

- `refresh_tokens` was **removed** from the schema and replaced by `sessions`, dropping
  `family_id`, `previous_token_id`, and `revoked_reason` along with the concepts they existed
  for.
- `POST /auth/refresh` was removed. `TOKEN_EXPIRED` and `REFRESH_TOKEN_INVALID` collapsed into
  a single `AUTHENTICATION_REQUIRED`, which also closed a small oracle: the four failure modes
  are now indistinguishable, so a response cannot reveal whether a guessed token ever existed.
- Login and registration responses lost `accessToken`, `tokenType`, and `expiresIn`. The cookie
  is the entire credential.
- The cookie moved from `SameSite=Strict` to `SameSite=Lax`, and the reasoning inverted:
  `Strict` had been free under the old design because the refresh cookie went to exactly one
  endpoint. With one cookie serving the whole API, `Lax` became the better fit — it still
  blocks every cross-site state-changing method, while permitting the top-level GET navigations
  an admin deep link needs. This rests on **no `GET` endpoint mutating state**, which is now a
  security invariant rather than merely a REST convention; see
  [security-principles.md](./security-principles.md#sessions).
- The CORS allowed-headers list lost `Authorization`, and the logging rules switched from
  masking `Authorization` to masking `Cookie` and `Set-Cookie`.
- **Both frontends lost a whole subsystem before it was ever written**: no in-memory token
  store, no bearer-header interceptor, no `401`-refresh-retry logic, no serialized
  concurrent-refresh handling. Client obligations shrank to "send `credentials: "include"`".
- **A database read was added to every authenticated request** — the one thing the reversal gave
  up, and argued on the record rather than glossed: it is a single-row lookup on a unique index,
  on a connection the request needs anyway, and it *replaces* work the token design also did,
  since that design denormalized `role` and `propertyId` into claims and still re-verified
  property scope against the database on every scoped route.
- Two behaviors improved as a side effect: revocation became effective on the very next request
  rather than lagging by up to the access-token TTL, and a role change or account deactivation
  now takes effect immediately. The latter is directly testable —
  [AC-AZ-11](./acceptance-criteria.md#ac-az-11--inactive-accounts-cannot-authenticate) asserts
  a deactivated user's live session fails on its next request, which the token design could not
  have satisfied.
- It produced the project's most demonstrable property: because sessions are rows in a shared
  database, a login against one backend is honored by the other. That is
  [AC-SE-05](./acceptance-criteria.md#ac-se-05--a-session-works-interchangeably-against-both-backends),
  the clearest thirty-second proof that the two backends implement one API.

Where the superseded design is still visible, deliberately: the design-decision writeup in
[api-contracts.md](./api-contracts.md#authentication) contrasts the two approaches and names
what the current one gives up, and the `SameSite=Lax` callout explains why `Strict` no longer
applies. Those passages are the only in-repo record of the earlier design and should not be
trimmed as redundant.

---

## 3. Schema migrations: each backend migrating independently → one canonical schema, one executor

**Decided:** In Phase 1a, `data-model.md` assumed **each backend would carry its own
migrations in its own tool**. Its ORM notes told the Node backend that hand-written migration
SQL was required for the exclusion constraint, the generated column, the composite foreign
keys, and the partial indexes — placing that SQL at `prisma/migrations/.../migration.sql`, the
path Prisma Migrate owns — and told the Spring Boot backend that "the same DDL belongs in the
Flyway or Liquibase migration."

That wording is still present in
[data-model.md](./data-model.md#no-overbooking), and it commits the project to keeping one
schema's DDL in **two** migration tools, each with its own history table.

**Reversed:** Writing [versioning-strategy.md](./versioning-strategy.md) in Phase 2 forced the
question directly, and the arrangement did not survive it. Two tools authoring one schema means
two histories and two opinions about the current version, and they collide the first time both
run against the same database. Worse, the duplication has no single source of truth: a change
applied through one tool and forgotten in the other leaves a database that no committed
migration can reproduce.

This reversal was not prompted by an external change, unlike entries 1 and 2. It surfaced
because a later document's job was to state a policy the earlier document had only implied.

**Replaced with:** One owner, one executor. Canonical numbered SQL lives in **this** repository
(`shared/migrations/V<nnn>__*.sql`), **Flyway is the only tool that ever applies DDL**, and
Prisma consumes the schema by introspection — `prisma db pull`, with `prisma migrate dev` and
`prisma migrate deploy` not used at all. Hibernate stays at `ddl-auto=validate`. Specified in
[versioning-strategy.md](./versioning-strategy.md#database-schema-migrations).

**What changed as a result:**

- The canonical schema moved **out of both backend repos** and into this one, making
  `shared/migrations/` the first code-shaped artifact this repository holds. Delivered as
  `V001__initial_schema.sql` (`281365f`), the Phase 4 deliverable this decision required.
- **The two backends stopped being peers.** The Node backend can no longer migrate a database
  unaided — it needs Flyway to have run first, from the Spring Boot repo or as a standalone
  Flyway invocation. This is the only asymmetry between the two implementations anywhere in the
  project, and it is recorded as a cost rather than presented as free.
- CI gained a cross-repo dependency: the Node repo's pipeline checks out this repository as a
  second checkout and runs the Flyway CLI against the canonical SQL, so a Node build can go red
  because of a commit in a different repo. Described in
  [devops-pipeline-overview.md](./devops-pipeline-overview.md#backend-repos-hotelapp-server-nodejs-hotelapp-server-springboot).
- It set the build order: [phased-implementation-plan.md](./phased-implementation-plan.md)
  recommends **Spring Boot before Node** in Phase 6, because the Flyway-owning backend must
  make the schema real before Prisma has anything to introspect.
- `schema.prisma` became a **generated** artifact rather than an authored one, which changes
  what a reviewer should expect to see in the Node repo and is a required note for Phase 4.

> **Inconsistency corrected.** The Phase 1a wording in
> [data-model.md](./data-model.md#no-overbooking) used to point the Node backend at
> `prisma/migrations/.../migration.sql` and to say the same DDL belonged in "the Flyway or
> Liquibase migration", describing two independent executors. That passage has since been
> rewritten: the DDL is stated to live in the canonical `shared/migrations/` SQL applied by
> Flyway alone, Prisma is described as generating `schema.prisma` by `prisma db pull` against the
> already-migrated database, `ddl-auto=validate` is reframed as mapping confirmation rather than
> schema generation, and the section now cross-references
> [versioning-strategy.md](./versioning-strategy.md#database-schema-migrations) instead of
> implying its own policy. The same document's **ORM generation notes** checklist was corrected
> to match in a follow-up pass, dropping the last two phrases that still read as Prisma
> authoring migration SQL and as Flyway and Liquibase being alternatives.

---

## 4. Both backends' package layout: the exception hierarchy inside `domain/` → its own package

**Decided:** In Phase 4, `stacks/nodejs/` and `stacks/springboot/` were written together, and both
architecture-specification.md documents listed their exception hierarchy as part of `domain/`,
alongside the pure rule functions — `AppException.java` (Spring) and `errors.ts` (Node) sat next
to `Pricing`/`Cancellation`/`Allocation`/status-transition logic in both. Built on directly on the
Spring side: by the end of Phase 6 Step 4, sixteen files sat in `domain/` in
`hotelapp-server-springboot`, twelve of them exception types (`AppException`, `ProblemCode`, and
ten subclasses) and four the actual pure functions. Node had not started, so nothing was built on
it there yet.

**Reversed:** Caught the way most of this project's review has worked — by inspection of the
actual Spring Boot repository, not a re-read of the spec in isolation — and then checked against
the Node spec, which turned out to share the identical mistake. The stated rationale for `domain/`
(pure computation, no framework/HTTP dependency, unit-testable without a context) genuinely holds
for the rule functions. It does not hold for the exception hierarchy: `AppException`/`AppError`
exist specifically to carry an HTTP status and title for a central handler to translate into a
response. That is API-error-translation, not business computation, regardless of whether a
subclass's name describes a domain condition (`RoomUnavailableException`) or nothing
domain-specific at all (`ValidationException`, `RateLimitedException` — neither expresses anything
about hotels). "Imports no framework class" and "computes a business rule" are different tests,
and the layout had been satisfying only the first, in both stacks.

**Replaced with:** A dedicated package per stack — `exception/` (Spring Boot), `errors/` (Node,
matching that ecosystem's naming, not forced to match Java's) — holding the whole error hierarchy,
entirely separate from `domain/`. Specified in each stack's own architecture-specification.md
under "Exception handling architecture" / "Error handling architecture", including the hierarchy
shape and why the split matters, not just the new location.

**What changed as a result:**

- `domain/` in both stacks' package listings and `module-registry.md` tables now names only pure
  functions: `Pricing`/`pricing.ts`, `Cancellation`/`cancellation.ts`, `Allocation`/`allocation.ts`,
  `ReservationStatusRules`/`status.ts`, plus Spring's `PaymentValidation` (Node has no equivalent
  file yet — Step 4 hasn't been built there).
- The actual code in `hotelapp-server-springboot` needed a mechanical refactor — moving twelve
  files and updating every import that referenced them (`web/`, `service/`, and the moved files'
  own package declarations) — since four backend steps had already been built on the old layout.
  Unlike the migration-ownership reversal (entry 3), this one was caught after code existed, not
  before, so the correction cost a refactor rather than an edit.
- **The Node side cost nothing but the spec edit** — no code exists there yet, so this is the
  cheaper of the two corrections and a reminder of why catching a layout mistake before Phase 6
  reaches a stack matters.
- This reversal touches only the two backend stacks' documents — the two frontends have no
  equivalent `domain/`-shaped layer.

---

## 5. Spring Boot package layout: a single `web/` package → `controller/` + `security/`

**Decided:** `stacks/springboot/architecture-specification.md`'s package layout put every
HTTP-adjacent class in one `web/` package: the controllers, the two servlet filters
(`TraceIdFilter`, `SessionAuthFilter`), the two Spring Security hooks
(`CustomAuthenticationEntryPoint`, `CustomAccessDeniedHandler`), an auth-principal type and a
cookie helper, and the exception-to-response translation classes
(`ProblemDetailExceptionHandler`, `ProblemResponseWriter`). Built on directly: by Phase 6 Step 4,
`hotelapp-server-springboot`'s `web/` package held eight controllers plus eight non-controller
classes doing four distinct jobs.

**Reversed:** Found by inspecting the built repository against what the sibling Node backend's
own spec already does. `stacks/nodejs/architecture-specification.md` has always kept `middleware/`
(request-pipeline infrastructure) and `routes/` (endpoint definitions) as separate top-level
folders — Express's own request-handling model forces the distinction, so Phase 4 never had the
chance to make this mistake on the Node side the way it did on the Spring Boot side, where nothing
in the framework forces controllers and filters apart. Unlike entry 4, this was **not** a mistake
shared by both stacks — Node was already right, which is itself evidence the split is a reasonable
architecture and not just a stylistic preference.

**Replaced with:** `controller/` (the endpoint classes, unchanged internally) and `security/` (the
filters, the Spring Security hooks, the auth principal and cookie helper, and the exception
handler/writer), both top-level, no `web/` umbrella — matching Node's sibling-folder shape so the
two backends compare directly, which is this project's standing reason for keeping structure
aligned across stacks. `ProblemDetailExceptionHandler` went to `security/`, not `exception/`
(entry 4's new package), on the same reasoning as Node's `errorHandler.ts` living in `middleware/`
rather than beside `AppError`: it is pipeline infrastructure that consumes the exception
vocabulary, not part of the vocabulary itself. Specified in
[architecture-specification.md](../stacks/springboot/architecture-specification.md#package-layout).

**What changed as a result:**

- `stacks/springboot/module-registry.md`, `error-handling.md`, `logging-observability.md`, and
  `security-implementation.md` all had stale `web/ClassName` references corrected to
  `security/ClassName`.
- The actual code in `hotelapp-server-springboot` needs the same kind of mechanical refactor as
  entry 4 — moving files and updating imports across `service/` and the moved files themselves —
  since four backend steps were built on the old layout.
- Node needed no spec change here, unlike entry 4 — its layout was already correct.

---

## Considered and excluded

Recorded so they are not re-added: each was assessed against the "decided, then reversed" test
and failed it.

| Candidate | Why it is not a reversal |
|-----------|--------------------------|
| **Room inventory: per-type unit count → real room rows** | The per-type-count model was never adopted. It was one of three options weighed *before* `data-model.md` was written, and real room units were chosen at that point; nothing was ever specified or built on the alternative. It remains correctly documented as a [design decision](./data-model.md#rooms) naming the alternative it beat |
| **Rate discounts: global vs. per-property vs. per-room-type** | Same shape — decided once, up front, from three options. Never reversed. See [rate_plans](./data-model.md#rate_plans) |
| **Admin property scoping; flat vs. seasonal rates** | Both settled before the schema was written, both first-time decisions |
| **AC-CX-05's DST arithmetic (`05:00Z` → `04:00Z`)** | A **bug fix**, not a reversal. The criterion contradicted the formula it was testing from the moment both were written — the same paragraph derived `04:00Z` and then asserted `05:00Z` — and it was caught in the first review pass over an uncommitted draft. The `05:00Z` value was never a settled position anyone built on. The fix is in [AC-CX-05](./acceptance-criteria.md#ac-cx-05--dst-transition-does-not-shift-the-deadline-arithmetic), with the derivation shown so it can be re-checked |
| **PostgreSQL 19 → 18.6** | Never a reversal; 18.6 was chosen on first consideration because 19 was in beta. The reasoning is a [design decision](./data-model.md#target-platform) |
| **bcrypt over Argon2id** | A first-time decision, made for Node/Java hash interoperability, not a reversal of a prior choice |

---

## Using this log

Add an entry when a decision recorded in a `shared/` document is undone — not when one is made,
and not when a draft is corrected before anyone relied on it. A reversal is worth logging
because the *reason* a project moved away from something is the part that vanishes fastest:
git shows that text changed, and the current document shows the state that won, but neither
shows what pressure caused the change.

The tell is that a later document has to explain why an earlier one no longer applies. When
that happens, the earlier document usually also needs correcting — see the live inconsistency
noted in entry 3 — and this log is the right place to record both the reversal and the cleanup
it implies.
