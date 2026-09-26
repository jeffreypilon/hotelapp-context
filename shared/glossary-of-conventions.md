# Glossary of Conventions

Naming and formatting rules that apply across all four implementation repos. The point is
that a reviewer reading the React client and then the Spring Boot backend should recognize
the same vocabulary and the same shapes, not two projects that happen to share a database.

Stack-specific file layout is deferred to `stacks/<tech>/coding-standards.md`
(Phases 3 and 4). This document holds only the rules that must be the *same* in all four
repos — anything a stack document could contradict does not belong here.

---

## The identifier-casing rule

One canonical name per concept, rendered in each layer's native casing. The concept is the
thing that stays constant; the casing is a rendering detail.

| Layer | Casing | Example |
|-------|--------|---------|
| SQL tables, columns, indexes | `snake_case` | `check_in_date`, `room_types` |
| PostgreSQL enum *values* | `SCREAMING_SNAKE_CASE` | `FRONT_DESK_STAFF`, `CONFERENCE_ROOM` |
| JSON request and response fields | `camelCase` | `checkInDate` |
| URL path segments | `kebab-case` | `/room-types`, `/check-in` |
| Query parameters | `camelCase` | `?checkInDate=&roomTypeCode=` |
| TypeScript / JavaScript identifiers | `camelCase`, types `PascalCase` | `checkInDate`, `type Reservation` |
| Java identifiers | `camelCase`, classes `PascalCase` | `checkInDate`, `class Reservation` |
| Environment variables | `SCREAMING_SNAKE_CASE` | `DATABASE_URL`, `BCRYPT_COST` |

The base rule is stated in [api-contracts.md](./api-contracts.md#conventions); the
elaborations below are what it means in cases that document does not spell out.

### How the mapping extends to nested structures

**Nested objects** map key-by-key, recursively. Nesting exists to group related fields for
the client's benefit and never implies a nested table:

```json
{ "address": { "line1": "18 Wharf Street", "stateProvince": "ME", "countryCode": "US" } }
```

maps to flat columns `address_line1`, `state_province`, `country_code` on `properties`.
Note that the JSON key is `line1`, not `addressLine1` — the object name already supplies
the prefix, and repeating it would read as `address.addressLine1`. **Rule: strip the
grouping prefix from keys inside a grouping object.** The affected groups are `address` on
properties and users, and `pricing` and `cancellation` on reservations.

**Arrays** are named by the plural of what they contain, and the elements are objects, not
bare scalars, wherever an element might ever need a second field:

```json
{ "amenities": [ { "code": "WIFI", "name": "Wi-Fi" } ] }
```

`{"amenities": ["WIFI"]}` would be smaller and is deliberately not used in responses — the
client needs the display name too, and widening a scalar array into an object array later
is a breaking change. Request bodies may use scalar arrays where only the identifier is
meaningful, which is why the write side is `amenityCodes: ["WIFI"]` while the read side is
`amenities: [{...}]`. The asymmetry is intentional and is the one place the naming differs
between a request and its response.

**Enum values cross layers unchanged.** `FRONT_DESK_STAFF` is spelled exactly that way in
PostgreSQL, in JSON, in TypeScript, and in Java. They are not converted to `camelCase` in
JSON, even though every other field is. Converting them would mean four independent
mapping tables to keep correct, and a mismatch would fail at runtime rather than at compile
time. The full enum lists live in
[data-model.md](./data-model.md#enumerated-types).

**Booleans** are named with an `is`/`has` prefix in every layer: `is_accessible` /
`isAccessible`, `is_out_of_service` / `isOutOfService`. Never bare adjectives
(`accessible`), and never negated names (`isNotActive`), which produce double negatives at
the call site.

**Dates and timestamps** carry their type in the name. A `date` column ends in `_date`
(`check_in_date`); a `timestamptz` column ends in `_at` (`booked_at`, `cancelled_at`). This
is load-bearing in this project, because the "dates only, no times" rule from
[project-overview.md](./project-overview.md) means confusing the two is a business-logic
bug, not just a type error. The one deliberate exception is
`reservations.cancellation_deadline`, which is a `timestamptz` without an `_at` suffix
because `cancellation_deadline_at` reads worse than the clarity is worth; it is called out
here so it is not mistaken for an oversight.

### ID naming

- A primary key is always `id`, never `reservation_id` on the `reservations` table.
- A foreign key is `<referenced_singular>_id`: `property_id`, `room_type_id`,
  `guest_user_id`.
- `guest_user_id` rather than `user_id` on `reservations` is deliberate: it names the
  *role* the user plays in that relationship, which matters because
  `cancelled_by_user_id` on the same table points at the same table for a different reason.
- In JSON, a bare id is `propertyId`; an expanded object is `property`. A response never
  contains both for the same relationship — either the id or the object, decided per
  endpoint in [api-contracts.md](./api-contracts.md).

---

## HTTP and REST conventions

Established in [api-contracts.md](./api-contracts.md); collected here as rules rather than
as a specification.

- **Collections are plural nouns**: `/properties`, `/reservations`. Never `/property/list`.
- **Verbs appear only for state transitions that are not CRUD**: `/check-in`,
  `/check-out`, `/cancel`, as a `POST` to a sub-path of the resource. A reservation's
  status is not editable via `PATCH`, because "cancel" and "set status to cancelled" have
  different authorization and different side effects.
- **`PUT` replaces a whole collection, `PATCH` merges fields.** Where a request body is the
  complete desired state (`/rate-plans`, `/amenities`), it is a `PUT` and therefore
  idempotent. Partial updates are `PATCH`.
- **Admin routes are prefixed `/admin`**, so the authorization tier is legible from the
  route alone without consulting this repo.
- **Sub-resources nest one level at most**: `/properties/{id}/rooms` is fine;
  `/properties/{id}/room-types/{id}/photos` is not — it becomes
  `/room-types/{id}/photos`, because a room-type id is already globally unique and the
  extra segment adds a redundant consistency check on every request.

---

## Terminology in prose and UI copy

Both frontends will be read side by side by the same reviewer. Divergent wording for the
same concept is the most visible possible inconsistency, and the cheapest to prevent.

### The two admin tiers

| Context | Front-desk tier | Manager tier |
|---------|-----------------|--------------|
| Code, enum value, JSON | `FRONT_DESK_STAFF` | `PROPERTY_MANAGER` |
| Documentation prose | front-desk staff | property manager |
| UI copy, labels, headings | Front Desk | Manager |
| Collective term for both | staff, or admin users | — |

Rules:

- **In prose, lowercase**: "front-desk staff can check guests in". These are job functions,
  not proper nouns. Hyphenate "front-desk" when it modifies a noun ("front-desk staff"),
  leave it open as a standalone noun ("at the front desk").
- **In UI copy, "Front Desk" and "Manager"** — short enough for a badge, a nav item, or a
  role column, and both frontends must use these exact strings.
- **"Property Manager / Owner" appears only in [project-overview.md](./project-overview.md)**,
  which is the product document. Everywhere else the tier is "property manager" or
  "Manager". "Owner" is not a separate tier and must not appear in UI copy as though it
  were.
- **Never "admin" for the manager tier specifically.** "Admin" covers both tiers
  collectively — it is what `/admin/*` routes and "the admin area" mean. Using it for the
  higher tier alone makes every sentence about permissions ambiguous.
- **Never "employee", "agent", "clerk", "receptionist", or "superuser"** as synonyms.

### Other terms that must not drift

| Use | Not |
|-----|-----|
| guest | customer, client, user (in guest-facing copy) |
| reservation | booking, in API paths, entity names, and docs |
| booking | acceptable in UI copy and prose for the *act* of reserving ("complete your booking") |
| room type | roomtype, category, class |
| rate category | rate type, discount code, promo code |
| rate plan | the stored discount record — distinct from rate category, see [domain-glossary.md](./domain-glossary.md) |
| confirmation number | booking reference, booking number, PNR |
| check-in / check-out | checkin, check in (as a noun), arrival/departure (in UI labels) |
| property | hotel, location, site (in code and API); "hotel" is fine in guest-facing UI copy |

The `reservation` / `booking` split is the one that needs care: **`reservation` is the
noun, the entity, and the URL segment; `booking` is the verb-ish act.** So `/reservations`
and `reservations` table, but "Complete booking" on the confirm button and "booking
history" in the account area, because that is what a guest expects to read. Full
definitions in [domain-glossary.md](./domain-glossary.md).

---

## Money, dates, and formatting in code

All three already fixed in [api-contracts.md](./api-contracts.md#conventions); the
conventions that follow from them:

- **Never a floating-point type for money**, at any layer: `numeric(10,2)` in PostgreSQL,
  `Prisma.Decimal` in TypeScript, `BigDecimal` in Java, a decimal **string** in JSON.
  A `number` in a TypeScript interface for a money field is a bug, not a simplification.
- **Amount fields are named for what they are**, with no currency in the name:
  `totalAmount`, not `totalUsd`. Currency travels in a sibling `currency` field.
- **Percentages are stored and transmitted as the percentage**, not the fraction:
  `discountPercent: "10.00"` means 10%, not 1000%. The one exception is
  `occupancyRate`, which is a fraction in `[0, 1]` — named `rate` rather than `percent`
  precisely to mark the difference.
- **Dates in code use each stack's date-only type**: `LocalDate` in Java, and a plain
  `YYYY-MM-DD` string or `Date`-at-UTC-midnight in TypeScript. Never a JavaScript `Date`
  constructed from a local-time string, which shifts the day for half the world's
  timezones.

---

## Commit message convention

**Recommended: [Conventional Commits](https://www.conventionalcommits.org/) 1.0.0**, in all
five repos.

```
<type>(<optional scope>): <subject>

<optional body>
```

Types used here: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `build`, `ci`.

```
feat(reservations): enforce no-overbooking via exclusion constraint
docs(shared): add security-principles and NFR documents
fix(auth): revoke sibling sessions on password change
```

Rationale, since this is a recommendation rather than an inherited constraint: a polyrepo
with two parallel implementations of one contract benefits from commit messages that say
*which layer* changed in a scannable way, and a reviewer comparing the two backend repos'
histories can line them up feature by feature. It is also a recognizable industry
convention, which is worth something in a portfolio. The cost is near zero and it needs no
tooling — though `commitlint` is the obvious enforcement point if this ever warrants one.

Subject line: imperative mood ("add", not "added" or "adds"), no trailing period, under 72
characters. Scope is the module or area, lowercase.

**Cross-repo changes.** A change to this repo that obliges a change in an implementation
repo should reference the contract commit in the implementation commit body:

```
feat(auth): replace JWT middleware with session lookup

Implements hotelapp-context@<sha> (Phase 1b: server-side sessions).
```

There is no submodule or automated link between the repos, so this reference is the only
trail from an implementation change back to the decision that caused it. Phase 4 should
treat it as required rather than optional.

---

## Branch and repo conventions

- **Default branch: `main`** in all five repos.
- **Branch names: `<type>/<short-description>`**, using the commit types above:
  `feat/availability-search`, `docs/phase-2-shared`, `fix/cancellation-boundary`.
- **No cross-repo branch coordination.** Each repo's `main` must be independently
  buildable at all times. Where a contract change spans repos, this repo merges first —
  the contract is the thing the implementations conform to, so it cannot trail them.

---

## Documentation conventions in this repo

- One topic per file; the filename is the topic, `kebab-case.md`.
- Every document opens with an H1 matching its subject and a short statement of what it is
  for and who reads it.
- **Cross-reference, never copy.** A decision lives in exactly one document. Other
  documents link to it with a one-line summary of what they would otherwise restate. This
  is the rule that keeps thirteen documents from drifting apart, and it is worth being
  pedantic about.
- Prose wraps at 90 columns. Tables and fenced code may exceed it.
- Where a document records a judgment call rather than an inherited requirement, it says so
  in a `> **Design Decision — ...**` or `> **Assumption ...**` callout, so a reviewer can
  find every place the project chose something and see why.
