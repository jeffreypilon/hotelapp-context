# Copilot instructions — hotelapp-context

## What this repository is

The **specification repository** for HotelApp, a hotel booking and guest-management demo built as a
portfolio piece. **It contains no application code** — 61 files, almost all Markdown, plus one SQL
migration.

It is the normative source for four sibling implementation repositories:
`hotelapp-client-react`, `hotelapp-client-angular`, `hotelapp-server-nodejs`,
`hotelapp-server-springboot`. Where an implementation and a document here disagree, **the
implementation is wrong.**

## Layout

```
context-map.md                    The index — read this first. Says which document decides what
shared/                           14 documents binding all four implementation repos
shared/migrations/                Canonical SQL. Flyway is the sole executor
  V001__initial_schema.sql        11 tables, 5 enums, 36 indexes, the exclusion constraint
stacks/react/      (12 docs)      Per-stack specifications
stacks/angular/    (12 docs)
stacks/nodejs/     (10 docs)
stacks/springboot/ (10 docs)
```

## Rules for editing documents here

- **A decision lives in exactly one document.** Others cross-reference it with a link and a one-line
  summary. **Never duplicate reasoning** — duplication is how thirteen documents drift apart.
- **`api-contracts.md` and `data-model.md` are normative.** Changing either has consequences in four
  repositories; check `decision-log.md` before proposing a change, in case it was already reversed.
- **Mark judgment calls** with a `> **Design Decision — …**` callout, and gaps in the source
  material with `> **Assumption …**`. Both are searchable on purpose.
- **Prose wraps at 90 columns.** Tables and fenced code may exceed it.
- Every document opens with an H1 and a statement of what it is for.

## Four document pairs are BYTE-IDENTICAL over their shared sections

Generated from one shared body by a script, then verified equal — not written twice and hoped to
match. **Editing one without the other is a defect.**

| Pair | Identical span |
|------|---------------|
| `stacks/react` / `stacks/angular` `ui-specifications.md` | §1–2 |
| `stacks/react` / `stacks/angular` `error-handling.md` | §1–4 |
| `stacks/nodejs` / `stacks/springboot` `error-handling.md` | §1–5 |
| `stacks/nodejs` / `stacks/springboot` `testing-standards.md` | §1–5 |

To change one of these spans: edit a shared body, regenerate both files, and verify with `md5sum` on
the extracted span. A CI job to enforce this is specified but **not yet written**.

## Validation you can and should run

There is no build and no test suite. Two checks matter:

**1. Cross-document links and anchors.** 536 internal links, 315 carrying an `#anchor`. **GitHub's
slugger does not collapse consecutive spaces**, so a heading `### AC-OB-01 — Two concurrent…` slugs
to `ac-ob-01--two-concurrent…` with a **double** hyphen, and `## 4. \`traceId\` and logging` becomes
`#4-traceid-and-logging`. Six broken anchors were found by hand during Phases 3 and 4. **Always
verify an anchor against the target's actual headings rather than guessing.**

**2. The migration applies.** `shared/migrations/V001__initial_schema.sql` has been validated by
applying it to a throwaway PostgreSQL 18.6 database with `ON_ERROR_STOP=1`, running 16 behavioural
tests, and dropping the database. **Migrations are immutable once merged** — Flyway checksums them.
Corrections go in a new `V002__*.sql`, never by editing `V001`.

```bash
# verification pattern that was used, and should be reused
createdb hotelapp_v001_test
psql -d hotelapp_v001_test -v ON_ERROR_STOP=1 -f shared/migrations/V001__initial_schema.sql
# ... assertions ...
dropdb hotelapp_v001_test
```

## Project state

Phases 1–5 complete: all 14 `shared/` and all 44 `stacks/` documents, `V001`, and Copilot
instructions in all five repositories. **Phase 6 Step 0 is done** — a walking skeleton reaching a
browser, Spring Boot 4.1.1 plus a React screen rendering seeded properties.

**Step 0 found a real contract defect** (nullable fields being omitted rather than sent as `null`,
which would have made the two backends disagree on the wire) and it has been fixed here. It also
established that **money and date serialization remain unvalidated**, because `GET /properties`
carries neither — see the Step 0 outcome section in `shared/phased-implementation-plan.md` before
assuming either is proven.

**Phase 6 Step 1 onward is implementation**, in the four sibling repositories, not here. Changes to
this repository from now on are usually *corrections driven by implementation* — which is the
intended direction.

## Trust these instructions

**Trust this file first.** Search only when the information here is incomplete or found to be in
error — and if you find an error, say so rather than quietly working around it.
