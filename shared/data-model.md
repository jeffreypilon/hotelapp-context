# Data Model

Relational data model for HotelApp. This document is the single source of truth for the
database schema shared by **hotelapp-server-nodejs** (Prisma) and
**hotelapp-server-springboot** (Spring Data JPA / Hibernate). Both backends run against
the *same* physical database, so neither may introduce tables, columns, or constraints
that the other does not implement.

Derived from [project-overview.md](./project-overview.md). Consumed by
[api-contracts.md](./api-contracts.md).

---

## Target platform

| Item | Value |
|------|-------|
| Database | PostgreSQL **18.6** (current stable release, 13 Aug 2026) |
| Encoding / collation | `UTF8`, `en_US.UTF-8` |
| Required extensions | `btree_gist` (needed by the no-overbooking exclusion constraint) |
| Primary keys | `uuid`, generated database-side with PostgreSQL 18's native `uuidv7()` |
| Money | `numeric(10,2)` — never floating point |
| Timestamps | `timestamptz` (UTC storage) |
| Calendar dates | `date` (no time component — see business rules) |

> **Design Decision — PostgreSQL 18.6 over 19.**
> PostgreSQL 19 is in beta (Beta 4, 24 Sep 2026) with GA expected around October 2026.
> A portfolio project should target the newest *stable* release, so 18.6 it is. 18 also
> gives us `uuidv7()` in core, removing the need for an extension or application-side
> UUID generation — time-ordered UUIDs index far better than random v4 under B-tree
> insertion, while keeping IDs non-enumerable in public URLs.

> **Design Decision — native PostgreSQL `enum` types over `varchar` + `CHECK`.**
> Every enumerated domain below is a real PostgreSQL enum. The domains are stable
> (defined by the product spec, not by user data), and both ORMs support them:
> Prisma maps them natively via `enum` blocks, and Hibernate maps them with
> `@JdbcTypeCode(SqlTypes.NAMED_ENUM)`. The trade-off is that adding a value requires
> `ALTER TYPE ... ADD VALUE`; that is acceptable for domains this stable, and it buys
> database-level validation that no application bug can bypass.

---

## Entity overview

```
users ──────────────┐
  │ (guest)         │ (front-desk staff scoped to)
  │                 ▼
  │            properties ──1:N── room_types ──1:N── rooms
  │                 │                 │  │                │
  │                 │                 │  └─1:N── room_type_photos
  │                 │                 │
  │                 │                 └─M:N── amenities  (room_type_amenities)
  │                 │
  │                 └──1:N── rate_plans
  │
  └──1:N── reservations ──1:1── payments
  │             ▲
  │             └── references exactly one room, one room_type, one property
  └──1:N── sessions
```

| Entity | Purpose |
|--------|---------|
| `users` | All authenticated principals: guests, front-desk staff, property managers |
| `sessions` | Server-side login sessions — the authentication credential store, shared by both backends |
| `properties` | Hotel properties |
| `room_types` | A bookable category of room at a property (Single, Double, King, Suite, Conference Room) |
| `room_type_photos` | Ordered photos for a room type |
| `amenities` | Lookup table of amenities |
| `room_type_amenities` | Join table: which amenities a room type offers |
| `rooms` | Individual physical room units — the unit of booking and of overlap prevention |
| `rate_plans` | Per-property discount percentage for each special rate category |
| `reservations` | A booking of one room for a date range, with its status lifecycle |
| `payments` | Dummy payment / confirmation record, one per reservation |

---

## Enumerated types

```sql
CREATE TYPE user_role AS ENUM (
  'GUEST',
  'FRONT_DESK_STAFF',
  'PROPERTY_MANAGER'
);

CREATE TYPE room_type_code AS ENUM (
  'SINGLE',
  'DOUBLE',
  'KING',
  'SUITE',
  'CONFERENCE_ROOM'
);

CREATE TYPE rate_category AS ENUM (
  'NONE',
  'AAA_CAA',
  'AARP',
  'GOVERNMENT_PER_DIEM',
  'MILITARY_VETERAN',
  'SENIOR',
  'CORPORATE_CODE',
  'GROUP_CODE'
);

CREATE TYPE reservation_status AS ENUM (
  'CONFIRMED',
  'CHECKED_IN',
  'CHECKED_OUT',
  'CANCELLED'
);

CREATE TYPE payment_status AS ENUM (
  'SUCCEEDED',
  'REFUNDED',
  'FAILED'
);
```

**Role hierarchy.** `PROPERTY_MANAGER` is a strict superset of `FRONT_DESK_STAFF`.
Authorization is implemented as a rank comparison, not a set-membership test, so a
manager automatically passes every staff-level check.

**`rate_category` and `'NONE'`.** `'NONE'` is a valid value on a reservation (the guest
selected no special rate) but is *never* stored in `rate_plans` — it implies a 0%
discount. The "clear selection" control described in the overview resets the client back
to `'NONE'`; it is a UI affordance, not a stored value.

---

## `users`

One table for every authenticated principal. Guests and admins differ only by `role`.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | `uuid` | PK, `DEFAULT uuidv7()` | |
| `email` | `varchar(320)` | NOT NULL, UNIQUE (case-insensitive) | Login identifier; stored lowercased |
| `password_hash` | `varchar(255)` | NOT NULL | Argon2id preferred; bcrypt (cost ≥ 12) acceptable. Both backends must agree — see note below |
| `first_name` | `varchar(100)` | NOT NULL | |
| `last_name` | `varchar(100)` | NOT NULL | |
| `phone` | `varchar(32)` | NULL | |
| `address_line1` | `varchar(200)` | NULL | Guest profile contact details |
| `address_line2` | `varchar(200)` | NULL | |
| `city` | `varchar(120)` | NULL | |
| `state_province` | `varchar(120)` | NULL | |
| `postal_code` | `varchar(20)` | NULL | |
| `country_code` | `char(2)` | NULL | ISO 3166-1 alpha-2 |
| `role` | `user_role` | NOT NULL, `DEFAULT 'GUEST'` | |
| `home_property_id` | `uuid` | NULL, FK → `properties(id)` ON DELETE RESTRICT | The property a front-desk staff member is scoped to |
| `is_active` | `boolean` | NOT NULL, `DEFAULT true` | Soft deactivation; inactive users cannot authenticate |
| `created_at` | `timestamptz` | NOT NULL, `DEFAULT now()` | |
| `updated_at` | `timestamptz` | NOT NULL, `DEFAULT now()` | |

**Case-insensitive email.** Enforced with a unique index on `lower(email)` rather than
the `citext` extension — a functional index needs no extension and behaves identically
in both ORMs (both simply lowercase before querying).

```sql
CREATE UNIQUE INDEX users_email_lower_key ON users (lower(email));
```

**Role / scope consistency.** A front-desk staff member must be scoped to exactly one
property; guests and managers must not be:

```sql
ALTER TABLE users ADD CONSTRAINT users_role_property_scope_chk CHECK (
  (role = 'FRONT_DESK_STAFF' AND home_property_id IS NOT NULL)
  OR (role <> 'FRONT_DESK_STAFF' AND home_property_id IS NULL)
);
```

> **Assumption (not stated in the overview).** The overview says front-desk staff view
> bookings "across the property/properties" without resolving whether staff are
> property-scoped. This model scopes **front-desk staff to one property** and gives
> **property managers/owners access to all properties**. That makes the two admin tiers
> differ in *data reach* as well as permission, which is how real multi-property
> operations work. If a single-property deployment is ever wanted, seed one property and
> the model degenerates correctly with no schema change.

> **Assumption.** Admin accounts are created by seed/migration or by another manager, not
> through public self-registration. `POST /auth/register` always produces a `GUEST`.

**Password hashing across two backends.** Both backends read the same `password_hash`
column, so they must use a mutually verifiable algorithm and encoding. Use **bcrypt**
(`$2b$`, cost 12): `bcrypt` in Node and `BCryptPasswordEncoder` in Spring Security
produce and verify byte-identical modular-crypt strings. Argon2id is cryptographically
preferable but the Node and Java implementations must be configured with matching
parameters to interoperate; bcrypt is chosen here specifically because cross-stack
interoperability is a hard requirement of this project.

---

## `sessions`

Server-side login sessions. This table **is** the authentication mechanism: the cookie a
client holds is a lookup key into it, and both backends read the same rows, so a user
logged in through one backend is logged in through the other. See
[api-contracts.md](./api-contracts.md) for the protocol.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | `uuid` | PK, `DEFAULT uuidv7()` | |
| `user_id` | `uuid` | NOT NULL, FK → `users(id)` ON DELETE CASCADE | |
| `token_hash` | `char(64)` | NOT NULL, UNIQUE | SHA-256 hex of the opaque session token. The raw token is never stored |
| `issued_at` | `timestamptz` | NOT NULL, `DEFAULT now()` | Login time. Also the anchor for the absolute expiry cap |
| `expires_at` | `timestamptz` | NOT NULL | Idle deadline; extended on activity — see TTL below |
| `revoked_at` | `timestamptz` | NULL | Set on logout or password change |
| `user_agent` | `varchar(255)` | NULL | Captured for the audit trail |
| `ip_address` | `inet` | NULL | |

```sql
CREATE INDEX sessions_user_idx ON sessions (user_id);
CREATE INDEX sessions_expires_at_idx ON sessions (expires_at);
```

`(user_id)` supports "revoke all of this user's other sessions" on password change;
`(expires_at)` supports the periodic cleanup job that deletes rows past expiry.

A session is valid only when `revoked_at IS NULL AND expires_at > now()`. Any request
presenting a token that is unknown, revoked, or expired is unauthenticated — there is no
recovery path short of logging in again.

**Why hash the token.** Storing only the SHA-256 digest means a leaked database dump cannot
be replayed as a set of live sessions. A single unsalted SHA-256 is sufficient here
precisely because the token is 256 bits of CSPRNG output: there is no low-entropy input for
a rainbow table to attack, so the deliberately slow hashing that `users.password_hash`
requires would be wasted cost on a lookup that runs once per request.

> **Design Decision — sliding idle window with an absolute cap, not a fixed expiry.**
> `expires_at` is set to `now() + 8 hours` at login and pushed forward on authenticated
> activity, but never past `issued_at + 30 days`. Two columns carry both bounds, so no
> extra column is needed for the cap.
>
> A fixed absolute expiry is simpler — one write at login, never touched again — but it
> logs people out mid-task, and the two user populations here make that concretely bad: a
> front-desk shift runs 8+ hours on one terminal, and a guest comparing rooms across a
> lunch break should not lose their session. The 8-hour idle window covers both. The
> 30-day cap ensures an abandoned session on a shared machine dies on its own.
>
> **The write-throttle matters.** Because every authenticated request already reads this
> row, a naive sliding window would also *write* it on every request, turning a read-only
> hot path into a write-amplified one. So `expires_at` is only bumped when it is more than
> 5 minutes stale — under continuous use that is one write per 5 minutes instead of one per
> request, and the user-visible behavior is indistinguishable. Both backends must implement
> the same threshold, or one will appear to log users out sooner than the other.

---

## `properties`

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | `uuid` | PK, `DEFAULT uuidv7()` | |
| `name` | `varchar(160)` | NOT NULL | |
| `slug` | `varchar(160)` | NOT NULL, UNIQUE | URL-friendly identifier |
| `description` | `text` | NOT NULL | |
| `photo_url` | `varchar(500)` | NULL | Single hero photo, per the overview |
| `address_line1` | `varchar(200)` | NOT NULL | |
| `address_line2` | `varchar(200)` | NULL | |
| `city` | `varchar(120)` | NOT NULL | |
| `state_province` | `varchar(120)` | NOT NULL | |
| `postal_code` | `varchar(20)` | NOT NULL | |
| `country_code` | `char(2)` | NOT NULL, `DEFAULT 'US'` | ISO 3166-1 alpha-2 |
| `phone` | `varchar(32)` | NULL | |
| `timezone` | `varchar(64)` | NOT NULL, `DEFAULT 'America/New_York'` | IANA zone — required to evaluate the 48-hour cancellation cutoff |
| `is_active` | `boolean` | NOT NULL, `DEFAULT true` | Inactive properties are hidden from public browsing |
| `created_at` | `timestamptz` | NOT NULL, `DEFAULT now()` | |
| `updated_at` | `timestamptz` | NOT NULL, `DEFAULT now()` | |

Additional unique key needed for composite foreign keys further down:

```sql
ALTER TABLE properties ADD CONSTRAINT properties_id_key UNIQUE (id);
```

> **Design Decision — why `timezone` exists in a "dates only" model.**
> Bookings carry no times, but the cancellation rule ("free up to 48 hours before
> check-in") compares *now* against a moment, and a bare `date` is not a moment. Storing
> the property's IANA timezone lets every backend compute the same cutoff:
> `check_in_date` at `00:00` in the property's zone, minus 48 hours. Without it, two
> backends in different deployment regions would disagree about whether a cancellation is
> refundable — exactly the kind of divergence this project forbids.

---

## `room_types`

A bookable category at one property. Rates, occupancy, amenities, and photos live here;
individual units live in `rooms`.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | `uuid` | PK, `DEFAULT uuidv7()` | |
| `property_id` | `uuid` | NOT NULL, FK → `properties(id)` ON DELETE RESTRICT | |
| `code` | `room_type_code` | NOT NULL | Category from the overview's fixed list |
| `name` | `varchar(120)` | NOT NULL | Display name, e.g. "Deluxe King, City View" |
| `description` | `text` | NOT NULL | |
| `base_rate` | `numeric(10,2)` | NOT NULL, CHECK `> 0` | Nightly rate before any special-rate discount |
| `max_occupancy` | `smallint` | NOT NULL, CHECK `BETWEEN 1 AND 100` | Used by availability search |
| `bed_configuration` | `varchar(120)` | NULL | Free text, e.g. "one king bed". NULL is meaningful for Conference Room |
| `is_accessible` | `boolean` | NOT NULL, `DEFAULT false` | ADA-compliant flag |
| `is_active` | `boolean` | NOT NULL, `DEFAULT true` | |
| `created_at` | `timestamptz` | NOT NULL, `DEFAULT now()` | |
| `updated_at` | `timestamptz` | NOT NULL, `DEFAULT now()` | |

Constraints and indexes:

```sql
ALTER TABLE room_types ADD CONSTRAINT room_types_property_name_key
  UNIQUE (property_id, name);

-- Referenced by the composite FKs on rooms and reservations.
ALTER TABLE room_types ADD CONSTRAINT room_types_property_id_id_key
  UNIQUE (property_id, id);

CREATE INDEX room_types_property_idx ON room_types (property_id) WHERE is_active;
CREATE INDEX room_types_property_code_idx ON room_types (property_id, code);
```

`(property_id, name)` is unique, but `code` is **not**: a property may offer two King
room types at different rates ("Standard King", "Deluxe King"). Nothing in the overview
forbids that, and the alternative — one row per category per property — would make
`base_rate` unable to vary within a category.

> **Assumption.** `is_accessible` sits on `room_types`, not `rooms`, because the overview
> lists it among the room *type* attributes. Real properties flag individual rooms; if
> that is ever needed, the column moves to `rooms` without touching anything else.

> **Design Decision — no seasonal rate calendar.** A single `base_rate` per room type,
> with the special-rate discount applied on top. The overview lists "base rate" as a
> room-type field and puts revenue-management-style dynamic pricing explicitly out of
> scope. Reservations snapshot their resolved rate (below), so later rate edits never
> rewrite booking history — which is the actual correctness requirement a rate calendar
> would otherwise be solving.

---

## `room_type_photos`

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | `uuid` | PK, `DEFAULT uuidv7()` | |
| `room_type_id` | `uuid` | NOT NULL, FK → `room_types(id)` ON DELETE CASCADE | |
| `url` | `varchar(500)` | NOT NULL | |
| `caption` | `varchar(200)` | NULL | |
| `sort_order` | `smallint` | NOT NULL, `DEFAULT 0` | Ascending display order |
| `is_primary` | `boolean` | NOT NULL, `DEFAULT false` | Thumbnail used in search results |

```sql
CREATE INDEX room_type_photos_room_type_idx
  ON room_type_photos (room_type_id, sort_order);

-- At most one primary photo per room type.
CREATE UNIQUE INDEX room_type_photos_one_primary_idx
  ON room_type_photos (room_type_id) WHERE is_primary;
```

> **Assumption.** `url` holds an externally hosted or statically served image path. Binary
> upload and image processing are not mentioned in the overview and are treated as out of
> scope; admin endpoints accept URLs.

---

## `amenities` and `room_type_amenities`

`amenities` is a seeded lookup table, not user-managed content.

| Column | Type | Constraints |
|--------|------|-------------|
| `id` | `uuid` | PK, `DEFAULT uuidv7()` |
| `code` | `varchar(40)` | NOT NULL, UNIQUE |
| `name` | `varchar(80)` | NOT NULL |
| `sort_order` | `smallint` | NOT NULL, `DEFAULT 0` |

Seed rows, exactly the overview's list:

| `code` | `name` |
|--------|--------|
| `WIFI` | Wi-Fi |
| `AIR_CONDITIONING` | Air conditioning / climate control |
| `REFRIGERATOR` | Refrigerator |
| `TELEVISION` | Television |
| `MICROWAVE` | Microwave |
| `WET_BAR` | Wet bar |
| `SAFE` | Safe for valuables |

`room_type_amenities` — many-to-many between `room_types` and `amenities`:

| Column | Type | Constraints |
|--------|------|-------------|
| `room_type_id` | `uuid` | NOT NULL, FK → `room_types(id)` ON DELETE CASCADE |
| `amenity_id` | `uuid` | NOT NULL, FK → `amenities(id)` ON DELETE RESTRICT |

PK is `(room_type_id, amenity_id)`. Add `CREATE INDEX ON room_type_amenities (amenity_id)`
to support filtering search results by amenity.

> **Design Decision — lookup table rather than an enum or a text array.** Amenities are the
> one enumerated domain that is plausibly extended by a person rather than a developer, and
> a join table is what lets the search endpoint filter by amenity with an index. Prisma
> models it as an explicit join model; JPA as `@ManyToMany` with `@JoinTable`.

---

## `rooms`

Individual physical units. **This is the unit of booking and of overlap prevention.**

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | `uuid` | PK, `DEFAULT uuidv7()` | |
| `property_id` | `uuid` | NOT NULL | Denormalized from `room_types`; kept consistent by the composite FK below |
| `room_type_id` | `uuid` | NOT NULL | |
| `room_number` | `varchar(20)` | NOT NULL | e.g. "214", "CONF-A" |
| `floor` | `smallint` | NULL | |
| `is_out_of_service` | `boolean` | NOT NULL, `DEFAULT false` | Excluded from availability while true |
| `created_at` | `timestamptz` | NOT NULL, `DEFAULT now()` | |
| `updated_at` | `timestamptz` | NOT NULL, `DEFAULT now()` | |

```sql
-- A room's property and room type cannot disagree: one composite FK, not two simple ones.
ALTER TABLE rooms ADD CONSTRAINT rooms_property_room_type_fk
  FOREIGN KEY (property_id, room_type_id)
  REFERENCES room_types (property_id, id) ON DELETE RESTRICT;

ALTER TABLE rooms ADD CONSTRAINT rooms_property_number_key
  UNIQUE (property_id, room_number);

-- Referenced by the composite FK on reservations.
ALTER TABLE rooms ADD CONSTRAINT rooms_property_id_id_key UNIQUE (property_id, id);

CREATE INDEX rooms_room_type_idx ON rooms (room_type_id) WHERE NOT is_out_of_service;
```

> **Design Decision — real room units, not a per-type unit count.**
> The overview's no-overbooking rule says a *room* may not be booked for overlapping
> dates, and the admin calendar shows "rooms across dates". Modeling real units lets that
> rule be enforced by a single database constraint (below) rather than by an application
> reading an aggregate count and racing another request. A `total_units` integer on
> `room_types` would make correctness depend on application code getting its locking
> right; this makes it impossible to get wrong.

> **Design Decision — composite FK instead of a trigger.**
> `rooms.property_id` is redundant with `room_types.property_id`, and redundancy usually
> invites drift. The composite foreign key `(property_id, room_type_id) → room_types
> (property_id, id)` makes drift unrepresentable, so the denormalization is free. It pays
> off in every availability and calendar query, which filter by property. Both ORMs support
> it: Prisma via `@@index` plus a raw-SQL migration for the composite FK, JPA via
> `@JoinColumnsOrFormulas`/`insertable=false` mappings or simply by mapping the scalar
> columns and declaring the FK in the migration.

> **Assumption.** `is_out_of_service` is a minimal inventory flag so a manager can pull a
> room from sale. Housekeeping and maintenance workflows are explicitly out of scope, so
> there is no status history, no reason code, and no date-ranged closure.

---

## `rate_plans`

Per-property discount for each special rate category.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | `uuid` | PK, `DEFAULT uuidv7()` | |
| `property_id` | `uuid` | NOT NULL, FK → `properties(id)` ON DELETE CASCADE | |
| `rate_category` | `rate_category` | NOT NULL, CHECK `<> 'NONE'` | |
| `discount_percent` | `numeric(5,2)` | NOT NULL, CHECK `BETWEEN 0 AND 100` | Percentage off `base_rate` |
| `is_active` | `boolean` | NOT NULL, `DEFAULT true` | Inactive categories are not offered |
| `created_at` | `timestamptz` | NOT NULL, `DEFAULT now()` | |
| `updated_at` | `timestamptz` | NOT NULL, `DEFAULT now()` | |

```sql
ALTER TABLE rate_plans ADD CONSTRAINT rate_plans_property_category_key
  UNIQUE (property_id, rate_category);
```

> **Design Decision — a percentage per (property, category), not a discount-code system.**
> The overview is explicit that special rates are a single-select category, not a code
> lookup, and that managers "manage special rate discounts". One editable percentage per
> category per property satisfies both without building eligibility rules, validity
> windows, or stacking logic — none of which the overview asks for. Per-room-type
> discounts were considered and rejected as more granular than the product describes.

**Pricing formula.** For a stay of *N* nights:

```
nightly_rate = round(base_rate * (1 - discount_percent / 100), 2)
total_amount = nightly_rate * N
```

Rounding is half-up at two decimal places, applied to the nightly rate *before*
multiplying by nights, so the rate shown per night always multiplies out to the total.
Both backends must implement it in this order.

---

## `reservations`

The core booking entity.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | `uuid` | PK, `DEFAULT uuidv7()` | |
| `confirmation_number` | `varchar(12)` | NOT NULL, UNIQUE | Human-readable, e.g. `HA7K2M9QX4` |
| `guest_user_id` | `uuid` | NOT NULL, FK → `users(id)` ON DELETE RESTRICT | |
| `property_id` | `uuid` | NOT NULL | |
| `room_id` | `uuid` | NOT NULL | The specific unit held by this reservation |
| `room_type_id` | `uuid` | NOT NULL | Denormalized for query convenience; constrained below |
| `check_in_date` | `date` | NOT NULL | |
| `check_out_date` | `date` | NOT NULL, CHECK `> check_in_date` | Exclusive — departure day is bookable by the next guest |
| `stay_period` | `daterange` | `GENERATED ALWAYS AS (daterange(check_in_date, check_out_date, '[)')) STORED` | Drives the exclusion constraint |
| `num_guests` | `smallint` | NOT NULL, CHECK `>= 1` | Must also be ≤ the room type's `max_occupancy` |
| `rate_category` | `rate_category` | NOT NULL, `DEFAULT 'NONE'` | Category selected at booking |
| `base_rate_amount` | `numeric(10,2)` | NOT NULL, CHECK `> 0` | Snapshot of `room_types.base_rate` |
| `discount_percent_applied` | `numeric(5,2)` | NOT NULL, `DEFAULT 0`, CHECK `BETWEEN 0 AND 100` | Snapshot of the rate plan |
| `nightly_rate_amount` | `numeric(10,2)` | NOT NULL, CHECK `>= 0` | Resolved per-night price |
| `total_amount` | `numeric(10,2)` | NOT NULL, CHECK `>= 0` | `nightly_rate_amount × nights` |
| `currency` | `char(3)` | NOT NULL, `DEFAULT 'USD'` | ISO 4217 |
| `status` | `reservation_status` | NOT NULL, `DEFAULT 'CONFIRMED'` | |
| `booked_at` | `timestamptz` | NOT NULL, `DEFAULT now()` | Booking creation time |
| `cancellation_deadline` | `timestamptz` | NOT NULL | Materialized 48-hour cutoff — see below |
| `checked_in_at` | `timestamptz` | NULL | Set when status → `CHECKED_IN` |
| `checked_out_at` | `timestamptz` | NULL | Set when status → `CHECKED_OUT` |
| `cancelled_at` | `timestamptz` | NULL | Set when status → `CANCELLED` |
| `cancelled_by_user_id` | `uuid` | NULL, FK → `users(id)` ON DELETE SET NULL | Guest or the admin who cancelled |
| `was_refundable` | `boolean` | NULL | Evaluated at cancellation time and frozen |
| `created_at` | `timestamptz` | NOT NULL, `DEFAULT now()` | |
| `updated_at` | `timestamptz` | NOT NULL, `DEFAULT now()` | |

### Referential and state constraints

```sql
-- Room must belong to the stated property.
ALTER TABLE reservations ADD CONSTRAINT reservations_property_room_fk
  FOREIGN KEY (property_id, room_id)
  REFERENCES rooms (property_id, id) ON DELETE RESTRICT;

-- Room type must belong to the same property.
ALTER TABLE reservations ADD CONSTRAINT reservations_property_room_type_fk
  FOREIGN KEY (property_id, room_type_id)
  REFERENCES room_types (property_id, id) ON DELETE RESTRICT;

-- Status and its timestamps cannot contradict each other.
ALTER TABLE reservations ADD CONSTRAINT reservations_status_timestamps_chk CHECK (
      (status = 'CONFIRMED'   AND checked_in_at IS NULL AND checked_out_at IS NULL AND cancelled_at IS NULL)
   OR (status = 'CHECKED_IN'  AND checked_in_at IS NOT NULL AND checked_out_at IS NULL AND cancelled_at IS NULL)
   OR (status = 'CHECKED_OUT' AND checked_in_at IS NOT NULL AND checked_out_at IS NOT NULL AND cancelled_at IS NULL)
   OR (status = 'CANCELLED'   AND cancelled_at IS NOT NULL)
);
```

`reservations.room_type_id` is redundant with `rooms.room_type_id`, but deliberately not
constrained to equal it: the room type recorded on the reservation is what the guest
booked and paid for. The two composite FKs above guarantee both belong to the same
property, which is the invariant that matters.

**`num_guests` vs `max_occupancy`.** A `CHECK` cannot reference another table, so this is
enforced in application code on create and modify, and is a required integration test in
both backends. A `BEFORE INSERT OR UPDATE` trigger is the optional belt-and-braces
version; it is not required, because unlike double-booking this invariant has no race
condition — `max_occupancy` is read in the same transaction that writes the reservation.

### No overbooking

This is the schema's central correctness guarantee. It is enforced by a **partial
exclusion constraint**, not by application logic:

```sql
CREATE EXTENSION IF NOT EXISTS btree_gist;

ALTER TABLE reservations ADD CONSTRAINT reservations_no_overlap_excl
  EXCLUDE USING gist (
    room_id      WITH =,
    stay_period  WITH &&
  ) WHERE (status <> 'CANCELLED');
```

Two non-cancelled reservations for the same room can never hold overlapping date ranges.
`btree_gist` supplies the GiST operator class for `uuid` equality; the `WHERE` clause lets
a cancelled booking's dates be reused immediately. Because `stay_period` uses `'[)')`
bounds, a departure on the 10th and an arrival on the 10th do not overlap — which is the
correct hotel semantic and a common off-by-one bug this makes impossible.

The constraint's backing GiST index is also the index that makes availability search fast;
no separate index is needed for it.

**Why this and not application checking.** A "SELECT then INSERT" availability check is a
textbook race: two concurrent bookings both see the room free and both insert. Serializing
that in application code requires advisory locks or `SERIALIZABLE` retries in *both*
backends, implemented identically. The exclusion constraint moves the guarantee into the
one component both backends share.

The DDL is not either backend's to author. The constraint, the `daterange` generated column,
the composite foreign keys, and the partial and functional indexes all live in the canonical
numbered SQL under `shared/migrations/` in this repository, applied by Flyway as the single
executor — see
[versioning-strategy.md](./versioning-strategy.md#database-schema-migrations) for the full
policy. What each backend owns is reading that schema correctly and translating a violation
into `409 Conflict`:

- **Prisma** — `schema.prisma` is generated by `prisma db pull` against the already-migrated
  database, never hand-edited to match it. Prisma Schema Language cannot express exclusion
  constraints or the `daterange` generated column and introspects them imperfectly, so expect
  `stay_period` to come back as `Unsupported("daterange")` — or omit it from the model
  entirely, since it is generated and never written. At runtime, catch
  `PrismaClientKnownRequestError` / raw SQLSTATE `23P01`.
- **Hibernate / JPA** — Flyway applies the same canonical SQL, and
  `spring.jpa.hibernate.ddl-auto=validate` is how this side confirms its entity mappings agree
  with what Flyway already applied; a startup failure there means the mapping drifted, not that
  the schema needs generating. Map `stayPeriod` as
  `@Generated @Column(insertable=false, updatable=false)` or leave it unmapped. Catch
  `ConstraintViolationException` and inspect SQLSTATE `23P01`.

**Availability query shape.** Both backends must implement this logic identically:

```sql
SELECT rt.*, count(r.id) AS available_room_count
FROM   room_types rt
JOIN   rooms r ON r.room_type_id = rt.id AND NOT r.is_out_of_service
WHERE  rt.property_id = $1
  AND  rt.is_active
  AND  rt.max_occupancy >= $4          -- requested guests
  AND  NOT EXISTS (
         SELECT 1 FROM reservations res
         WHERE  res.room_id = r.id
           AND  res.status <> 'CANCELLED'
           AND  res.stay_period && daterange($2, $3, '[)')   -- requested dates
       )
GROUP BY rt.id
HAVING count(r.id) > 0;
```

### Cancellation policy

`cancellation_deadline` is computed **once, at booking time**, and stored:

```
cancellation_deadline = (check_in_date AT TIME ZONE property.timezone) - INTERVAL '48 hours'
```

A cancellation is refundable when `now() < cancellation_deadline`. The result is frozen
into `was_refundable` when the cancellation actually happens.

**The subtraction is a fixed 48-hour duration, not a calendar operation.** In each backend the
steps are: resolve check-in midnight in the property's timezone to a UTC instant, then subtract
exactly 172,800 seconds. It is *not* "subtract two days from the date, then re-localize
midnight" — PostgreSQL applies calendar-aware handling only to `day` and `month` interval
components, so `INTERVAL '48 hours'` above is an exact duration and `INTERVAL '2 days'` would
not be equivalent. Consequently, when a DST transition falls inside the 48-hour window the
deadline's local wall-clock time will not be midnight; that is intended, and
[AC-CX-05](./acceptance-criteria.md#ac-cx-05--dst-transition-does-not-shift-the-deadline-arithmetic)
is the criterion that verifies it.

> **Design Decision — materialize the deadline instead of recomputing it.**
> `booked_at` plus `check_in_date` is enough to *derive* the answer, as the brief notes.
> Storing the deadline anyway costs one column and buys three things: both backends
> compute the timezone arithmetic exactly once, in the same place; the value can be
> returned to clients so the UI can display the real deadline; and it stays correct if a
> property's timezone is later corrected, because the booking's deadline was fixed at sale
> time. This is deliberately *not* a policy engine — there is one rule, one column, no
> policy table.

**Modification.** The overview allows a guest to "modify (where cancellation policy
allows)". A date or guest-count change is therefore permitted only while
`now() < cancellation_deadline` and `status = 'CONFIRMED'`. Changing dates re-runs
allocation and re-prices the stay; the exclusion constraint protects the new range just as
it did the original.

### Indexes

```sql
CREATE UNIQUE INDEX reservations_confirmation_number_key
  ON reservations (confirmation_number);

-- Guest booking history, newest stays first.
CREATE INDEX reservations_guest_idx
  ON reservations (guest_user_id, check_in_date DESC);

-- Admin booking list, filtered by property and status.
CREATE INDEX reservations_property_status_checkin_idx
  ON reservations (property_id, status, check_in_date);

-- Upcoming-arrivals report and the check-in queue.
CREATE INDEX reservations_arrivals_idx
  ON reservations (property_id, check_in_date)
  WHERE status = 'CONFIRMED';

-- Admin room/rate calendar: rooms × dates for one property.
CREATE INDEX reservations_calendar_idx
  ON reservations (property_id, room_id, check_in_date)
  WHERE status <> 'CANCELLED';
```

Admin search by guest name joins `users`; if that search becomes slow, the scale-up path
is a trigram index (`pg_trgm`) on `users.last_name` — noted, not built.

**Confirmation number format.** 10 characters: the literal `HA` followed by 8 characters
drawn from Crockford base32 (no `I`, `L`, `O`, `U`), generated from a CSPRNG and retried on
unique-violation. It is a *display* identifier only — never an authorization token. Every
endpoint still checks ownership or role.

---

## `payments`

Dummy payment record, one per reservation.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | `uuid` | PK, `DEFAULT uuidv7()` | |
| `reservation_id` | `uuid` | NOT NULL, UNIQUE, FK → `reservations(id)` ON DELETE CASCADE | One-to-one |
| `amount` | `numeric(10,2)` | NOT NULL, CHECK `>= 0` | Mirrors `reservations.total_amount` at sale time |
| `currency` | `char(3)` | NOT NULL, `DEFAULT 'USD'` | |
| `status` | `payment_status` | NOT NULL | |
| `method` | `varchar(20)` | NOT NULL, `DEFAULT 'DUMMY_CARD'` | |
| `card_brand` | `varchar(20)` | NULL | Derived from the input pattern: `VISA`, `MASTERCARD`, `AMEX`, `DISCOVER` |
| `card_last_four` | `char(4)` | NULL | Display only |
| `cardholder_name` | `varchar(160)` | NULL | |
| `processed_at` | `timestamptz` | NOT NULL, `DEFAULT now()` | |
| `created_at` | `timestamptz` | NOT NULL, `DEFAULT now()` | |

> **Design Decision — what is deliberately absent.**
> No full card number, no CVV, no expiry date, no billing address, no tokenized
> instrument, no processor transaction id, no gateway response payload. The overview
> specifies a dummy form that validates card-shaped input but never charges anything.
> `card_brand` and `card_last_four` exist only so a confirmation page can say
> "Visa ending 4242"; both are nullable, and a compliant implementation could leave them
> null. The column list is itself the documentation that this system is out of PCI scope —
> there is no field here that a breach could turn into a card.

`REFUNDED` exists to record the outcome of a cancellation inside the free window. Nothing
is actually refunded; the row's status is the demo's audit trail.

---

## ORM generation notes

The schema above is complete enough to generate both data layers directly.

**Prisma (`hotelapp-server-nodejs`)**
- `provider = "postgresql"`; `previewFeatures` are not required for anything here.
- Native enums map one-to-one to Prisma `enum` blocks.
- `@db.Uuid`, `@db.Decimal(10, 2)`, `@db.Date`, `@db.Timestamptz(6)`, `@db.Char(3)`.
- `@default(dbgenerated("uuidv7()"))` on every id.
- The `btree_gist` extension, the `stay_period` generated column, the exclusion constraint,
  the composite foreign keys, and the partial and functional indexes all arrive from the
  canonical `shared/migrations/` SQL applied by Flyway; Prisma authors none of it and picks
  it up via `prisma db pull`.
- Run every write that must respect a cross-row invariant inside
  `prisma.$transaction(...)`.

**Spring Data JPA / Hibernate (`hotelapp-server-springboot`)**
- Flyway is the sole executor; `ddl-auto=validate` in every environment confirms the entity
  mappings agree with what Flyway already applied.
- `@JdbcTypeCode(SqlTypes.NAMED_ENUM)` for the PostgreSQL enum columns.
- `BigDecimal` for money, `LocalDate` for dates, `OffsetDateTime` (or `Instant`) for
  `timestamptz`.
- Generated columns: `@org.hibernate.annotations.Generated` with
  `insertable = false, updatable = false`.
- Prefer `FetchType.LAZY` on every association and fetch join explicitly; the photo and
  amenity collections are the obvious N+1 hazards in property and search responses.

**Shared obligations.** Both backends must produce identical results for: the pricing
formula and its rounding order, the cancellation-deadline computation, the availability
query, confirmation-number format, bcrypt parameters, session validity rules (TTL, sliding
window, and the 5-minute write-throttle), and the mapping of SQLSTATE `23P01` to
`409 Conflict`. These are the seams where two implementations of one contract most easily
drift apart, so each deserves a test in both repositories.

---

## Open items for later documents

Deferred deliberately — not gaps in this model:

- Seed/fixture data volumes and content → `stacks/*/environment-setup-guide.md`
- Migration tooling conventions and naming → `stacks/*/architecture-specification.md`
- Password policy, rate limiting, session TTLs as configuration → `shared/security-principles.md`
- Acceptance tests for no-overbooking and cancellation → `shared/acceptance-criteria.md`

Sources for the version and constraint facts cited above:
[PostgreSQL 18.6 release announcement](https://www.postgresql.org/about/news/postgresql-186-1711-1615-1519-1424-and-19-beta-3-released-3365/),
[PostgreSQL 19 Beta 4](https://www.postgresql.org/about/news/postgresql-19-beta-4-released-3386/),
[Prisma issue #17514 — exclusion constraints](https://github.com/prisma/prisma/issues/17514),
[Prisma issue #18337 — `daterange` support](https://github.com/prisma/prisma/issues/18337).
