# Versioning Strategy

How HotelApp versions two things that change independently: the **REST API** that four repos
agree on, and the **database schema** that two backends share. The second is the genuinely
risky one, and most of this document is about it.

Both are already partly decided — path-based `/api/v1` in
[api-contracts.md](./api-contracts.md#conventions), and the migration tooling named in
[data-model.md](./data-model.md#orm-generation-notes). This document turns those into policy.

---

## API versioning

### The scheme

**Path-based, `/api/v1`.** Chosen over header-based negotiation or a query parameter because
it is visible in a log line, a browser address bar, a `curl` command, and a client's
configuration — all places a reviewer will actually look. Content negotiation via
`Accept: application/vnd.hotelapp.v2+json` is more RESTful in the purist sense and
considerably harder to debug.

The version covers the **whole API surface**, not individual resources. There is no
`/properties/v2` alongside `/reservations/v1`; per-resource versioning multiplies the
combinations a client must reason about and there is no scenario in this project where it
would help.

### What counts as a breaking change

The distinction that makes the whole policy usable. A change is **breaking** if a client built
against the previous contract could stop working.

**Breaking — requires a new version:**

| Change | Why it breaks |
|--------|---------------|
| Removing an endpoint | Obvious |
| Removing a response field | A client may render it |
| Renaming anything — field, path segment, parameter, enum value | A rename is a removal plus an addition |
| Changing a field's type | `"224.10"` → `224.10` breaks a client parsing a string |
| Changing a field from optional to required in a request | Existing valid requests start failing |
| Changing a field from nullable to non-nullable in a response, or the reverse | Either direction breaks someone's null handling |
| **Adding a value to an enum returned in a response** | A client with an exhaustive `switch` has no branch for it. See the note below |
| Changing an HTTP status code for an existing outcome | Clients branch on status |
| Changing an error `code` for an existing condition | Clients branch on `code` |
| Tightening validation on an existing field | Previously accepted requests start failing |
| Changing pagination, the error envelope, or the auth mechanism | Cross-cutting, affects every endpoint |
| Changing default sort order | Not a contract violation on paper; breaks any client that depended on it |

**Non-breaking — additive, same version:**

| Change | Why it's safe |
|--------|---------------|
| Adding a new endpoint | Nothing referenced it before |
| Adding an optional response field | Clients ignore unknown fields |
| Adding an optional request parameter or body field | Omitting it preserves old behavior |
| Adding a new **optional** query filter or sort field | |
| Relaxing validation | Previously valid requests stay valid |
| Adding a new error `code` for a genuinely new condition | A client that doesn't recognize it still sees the status |
| Performance, wording of `detail`, internal refactoring | Not contract surface |

> **Enum additions deserve the care.** Adding `PENDING` to `reservation_status` is
> **breaking** for responses, even though it is additive in the database. A client with a
> `switch` over four statuses has no branch for the fifth, and in TypeScript an exhaustive
> switch over a union type is a *compile* error that becomes a runtime gap when the API
> returns something the union does not include.
>
> Two consequences worth stating: adding an enum value accepted only in **requests** is safe
> (an old client simply never sends it); and both frontends should handle an unrecognized
> enum value defensively — render the raw value rather than crash — which reduces an enum
> addition from an outage to a cosmetic issue. That defensive posture is a requirement for
> Phase 3, not merely a suggestion.

**Unknown-field rejection interacts with this.** Because requests reject unknown fields
([api-contracts.md](./api-contracts.md#request-validation)), a *new* client sending a *new*
optional field to an *old* server gets a `400`. That is the accepted cost of strict
validation, and the practical rule is: **the server must be deployed before clients that use a
new field.** In a polyrepo with no coordinated release, this is worth remembering — it is the
one direction in which an additive change can still break something.

### Would a `/v2` ever exist?

**No — and the policy exists anyway.** Stated plainly rather than hedged:

Running `/v1` and `/v2` in parallel means two controller sets, two DTO sets, two sets of
tests, and a translation layer between them, **in both backends** — roughly doubling the
surface of the thing this project is demonstrating, in service of migrating clients that are
both in this developer's own repos and can simply be updated. There is no third-party client,
no published SDK, and no consumer whose upgrade cannot be coordinated by editing two
frontends.

So the concrete policy is:

1. **Within `/v1`, all changes are additive.** This is the only rule that operates in practice.
2. **A breaking change updates the contract and all four implementation repos together**, with
   this repo merging first per
   [glossary-of-conventions.md](./glossary-of-conventions.md#branch-and-repo-conventions).
   There is no deprecation window because there is no client outside the four repos.
3. **`/v2` is defined but unimplemented.** If it ever became necessary, the shape is: mount
   `/api/v2` alongside `/api/v1`, share the service and data layers, differ only in the HTTP
   layer and DTOs, mark `/v1` deprecated with a `Sunset` header
   ([RFC 8594](https://www.rfc-editor.org/rfc/rfc8594)), and remove it once both frontends are
   migrated. Recording that is enough; building it would be speculative work on a problem the
   project does not have.

> **Design Decision — policy without parallel implementation.**
> The reason to write this section at all is that "how would you version this API?" is a
> predictable interview question, and the good answer is not "I built parallel versioning for
> a demo with two first-party clients." It is knowing what breaks, knowing what `/v2` would
> cost, and choosing not to pay it — with the reasoning on record.

### Versioning the contract document itself

[api-contracts.md](./api-contracts.md) is versioned by git history, not by a version number in
the file. The commit that changes it is the change record, and implementation commits reference
it per
[glossary-of-conventions.md](./glossary-of-conventions.md#commit-message-convention). No
`CHANGELOG.md` and no version header — a hand-maintained changelog beside a git history is a
second source of truth that goes stale.

`shared/decision-log.md` (currently a stub) is the intended home for decisions that were
*reversed*, which git history records but does not surface. The Phase 1b session redesign is
its first real entry.

---

## Database schema migrations

This is the real risk in the project's structure: **one physical schema, two independently
developed backends, two different migration tools.** Prisma Migrate and Flyway both want to
own a schema, and each keeps its own history table. Left to themselves they will fight.

### The rule: one owner, one executor, one history

**`hotelapp-context` owns the canonical schema. Exactly one tool applies DDL. The other
consumes.**

```
hotelapp-context/shared/migrations/
    V001__initial_schema.sql
    V002__add_sessions_table.sql
    V003__...
         │
         │  canonical, hand-written, plain SQL
         │  the only authority for what the schema is
         │
    ┌────┴─────────────────────────────┐
    │                                  │
    ▼                                  ▼
Flyway (Spring Boot)            Prisma (Node)
reads and APPLIES these         does NOT apply DDL
files directly                  schema.prisma is generated
                                by introspection
                                (prisma db pull)
ddl-auto = validate             migrate is not used to author
```

Concretely:

1. **Canonical migrations are plain, numbered SQL files** in this repo:
   `V<nnn>__<snake_case_description>.sql`, Flyway's naming convention, zero-padded to three
   digits, never renumbered or edited once merged.
2. **Flyway is the executor.** The Spring Boot backend points Flyway at those files and is the
   only component that applies DDL. Its `flyway_schema_history` table is the single migration
   history.
3. **Prisma never applies DDL.** `schema.prisma` is produced by `prisma db pull` against an
   already-migrated database. `prisma migrate dev` and `prisma migrate deploy` are **not used**
   in this project. `prisma migrate diff` may be used as an *authoring aid* — to generate
   candidate SQL for a schema change — but its output is reviewed by hand and committed as a
   canonical `V<nnn>__*.sql` file, never applied by Prisma.
4. **Hibernate never applies DDL either:** `spring.jpa.hibernate.ddl-auto=validate` in every
   environment, as already required by
   [data-model.md](./data-model.md#orm-generation-notes). Validation failing at startup is the
   desired behavior — it means the entity mapping and the schema disagree, which is exactly
   when you want to find out.

> **Design Decision — Flyway executes, Prisma follows.**
> The alternative arrangements and why they lose:
>
> - **Both tools author migrations.** Two history tables, two opinions about the current
>   version, and a guaranteed conflict the first time both run against one database. This is
>   the failure mode the whole section exists to prevent.
> - **Prisma Migrate is the executor, Flyway is disabled.** Workable, and rejected because
>   Prisma cannot express the things this schema depends on most: the exclusion constraint, the
>   `daterange` generated column, the composite foreign keys, the partial and functional
>   indexes. All of those would live in hand-edited SQL inside Prisma's migration folder
>   anyway, which means writing plain SQL *and* accepting Prisma's ownership model — the worst
>   of both. The limitation is documented in
>   [data-model.md](./data-model.md#no-overbooking).
> - **Neither tool; a hand-run `schema.sql`.** Reproducible only by discipline, with no record
>   of what has been applied.
>
> Flyway wins because plain numbered SQL is the lowest common denominator both stacks can
> consume, it expresses every PostgreSQL feature this schema uses without workarounds, and it
> keeps the canonical schema in the repo whose job is to be canonical. The cost is honest and
> worth naming: **the Node backend cannot migrate a database by itself.** Running the Node
> backend against a fresh database requires Flyway to have run first — from the Spring Boot
> repo, or as a standalone Flyway invocation against the SQL files in this repo. That
> asymmetry between the two backends is a real inconvenience, and it is the price of having
> one authority instead of two.

### Migration authoring rules

- **Forward-only.** No `down` migrations. Reverting means a new forward migration. Down
  migrations are written when the schema is small, rarely tested, and reached for in exactly
  the situation where an untested script is most dangerous. At demo scale the recovery path is
  to reseed.
- **Immutable once merged.** A merged migration file is never edited or renumbered, because
  Flyway checksums them and any environment that already applied it will refuse to start.
  Corrections go in a new file.
- **One logical change per file.** "Add the sessions table" is one migration. "Phase 2
  changes" is not.
- **Idempotent guards where they cost nothing**: `CREATE EXTENSION IF NOT EXISTS btree_gist`.
- **Seed data is not a migration.** Reference data that the schema's correctness depends on —
  the seven `amenities` rows — belongs in a migration, because the enum-like contract in
  [data-model.md](./data-model.md#amenities-and-room_type_amenities) depends on those codes
  existing. Demo data (properties, rooms, guests, reservations) is a separate seeding script,
  re-runnable and not version-tracked.
- **Concurrency caveat, noted for completeness:** `CREATE INDEX CONCURRENTLY` cannot run in a
  transaction, so if one is ever needed it requires a Flyway migration marked non-
  transactional. At this project's data volumes a plain `CREATE INDEX` is instantaneous and
  none of this matters — recorded so the answer exists if the question comes up.

### Keeping the two ORM mappings in step

Since neither ORM owns the schema, both must be re-derived when it changes. The sequence for
any schema change:

1. Write the canonical `V<nnn>__*.sql` in this repo; merge it here first.
2. **Spring Boot repo:** Flyway applies it. Update the JPA entities by hand. `ddl-auto=validate`
   fails the build if they disagree with reality — this is the check working as intended.
3. **Node repo:** run `prisma db pull` against the migrated database to regenerate
   `schema.prisma`, then `prisma generate`. Review the diff, since introspection will render
   some constructs as `Unsupported(...)` — the `daterange` generated column in particular, per
   [data-model.md](./data-model.md#no-overbooking).
4. Update both backends' DTOs and services as the change requires, and the contract document if
   the API surface moved.
5. **CI catches what review missed:** Spring's `validate` fails on entity drift, and the
   OpenAPI diff described in
   [devops-pipeline-overview.md](./devops-pipeline-overview.md) fails on contract drift.

**The failure this prevents**, concretely: someone adds a column via `prisma migrate dev` in
the Node repo, it lands in the database, and the Spring Boot backend starts throwing
validation errors on a schema nobody agreed to change — or worse, the column exists in
production-shaped data and in one `schema.prisma`, but in no committed migration, so a fresh
database cannot be built. The single-executor rule makes both impossible rather than merely
discouraged.

### Schema changes that are breaking

Independent of the API's versioning, since a schema change can break a *running* backend:

| Change | Safe? | Notes |
|--------|-------|-------|
| Adding a nullable column | Yes | Neither backend notices until mapped |
| Adding a table, index, or constraint on new data | Yes | |
| Adding a `NOT NULL` column **with** a default | Yes | PostgreSQL 11+ does not rewrite the table |
| Adding a `NOT NULL` column **without** a default | **No** | Fails against existing rows. Three steps: add nullable, backfill, then set `NOT NULL` |
| Dropping or renaming a column | **No** | Both ORM mappings break. Expand-and-contract: add the new, migrate both backends to it, drop the old in a later migration |
| Changing a column type | **No** | Usually expand-and-contract as well |
| Adding a value to a PostgreSQL enum | Mostly | `ALTER TYPE ... ADD VALUE` is safe for the database; whether it is safe for *clients* is the API question above |
| Removing a value from a PostgreSQL enum | **No** | PostgreSQL has no `DROP VALUE`. Requires creating a new type and swapping — a strong argument against speculative enum values |
| Adding a constraint to existing data | **No** | Fails if existing rows violate it. Backfill first |

**Expand-and-contract is the pattern for every unsafe change**, and it exists here for a
reason particular to this project: two backends are deployed independently, so at some point
both schema versions must be tolerated by whichever backend has not yet been updated.

### Versions of the platform itself

| Component | Pinning | Upgrade posture |
|-----------|---------|-----------------|
| PostgreSQL | **18.6**, per [data-model.md](./data-model.md#target-platform) | Patch releases within 18.x freely. **A major upgrade is a project decision**, since 18-specific features are used — `uuidv7()` most notably. PostgreSQL 19 was in beta when this was written and was deliberately not chosen |
| Node.js | Current LTS, pinned in `.nvmrc` and `package.json` `engines` | |
| Java | An LTS release, pinned in the build file | |
| npm / Maven / Gradle dependencies | Exact versions, lockfiles committed | Per [security-principles.md](./security-principles.md#dependencies) |
| Docker base images | Pinned to a specific tag, never `latest` | `latest` makes a build unreproducible, which defeats the point of committing a Compose file |

The `uuidv7()` dependency is worth flagging: it is a PostgreSQL 18 core function, so the schema
cannot be applied to 17 or earlier without replacing every primary-key default. That is an
acceptable constraint — it is documented, and 18.6 is the current stable release — but it means
"just run it on whatever Postgres you have" is not true of this project, and the requirement
belongs in each repo's setup guide.
