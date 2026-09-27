-- =============================================================================
-- V001__initial_schema.sql
--
-- HotelApp canonical initial schema. Transcribed from shared/data-model.md,
-- which is the single source of truth. If this file and that document disagree,
-- the document is right and this file is wrong.
--
-- Target: PostgreSQL 18.6. Requires 18+ for uuidv7().
--
-- Applied by Flyway ONLY. Per shared/versioning-strategy.md, Flyway is the sole
-- DDL executor; Prisma introspects the result via `prisma db pull` and never
-- applies DDL. This file is forward-only and immutable once merged -- Flyway
-- checksums it, and any environment that has applied it will refuse to start if
-- it changes. Corrections go in a new V-numbered file.
--
-- Three deviations from a literal reading of data-model.md, each a redundancy
-- rather than a design change; flagged at the point they occur:
--   1. reservations.confirmation_number -- UNIQUE declared once, at column level
--   2. properties_id_key UNIQUE (id) -- omitted, redundant with the PK
--   3. users.email -- functional unique index only, no plain UNIQUE
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Extensions
-- -----------------------------------------------------------------------------

-- Supplies the GiST operator class for uuid equality, which the no-overbooking
-- exclusion constraint on reservations needs.
CREATE EXTENSION IF NOT EXISTS btree_gist;


-- -----------------------------------------------------------------------------
-- Enumerated types
--
-- Native PostgreSQL enums rather than varchar + CHECK: the domains are fixed by
-- the product spec, and both ORMs map them (Prisma `enum` blocks, Hibernate
-- @JdbcTypeCode(SqlTypes.NAMED_ENUM)). Adding a value later requires
-- ALTER TYPE ... ADD VALUE.
-- -----------------------------------------------------------------------------

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


-- -----------------------------------------------------------------------------
-- properties
--
-- Created before users, because users.home_property_id references it.
-- -----------------------------------------------------------------------------

CREATE TABLE properties (
  id              uuid          PRIMARY KEY DEFAULT uuidv7(),
  name            varchar(160)  NOT NULL,
  slug            varchar(160)  NOT NULL UNIQUE,
  description     text          NOT NULL,
  photo_url       varchar(500),
  address_line1   varchar(200)  NOT NULL,
  address_line2   varchar(200),
  city            varchar(120)  NOT NULL,
  state_province  varchar(120)  NOT NULL,
  postal_code     varchar(20)   NOT NULL,
  country_code    char(2)       NOT NULL DEFAULT 'US',
  phone           varchar(32),
  -- IANA zone. Required to evaluate the 48-hour cancellation cutoff: bookings
  -- carry no times, but "48 hours before check-in" needs a real instant.
  timezone        varchar(64)   NOT NULL DEFAULT 'America/New_York',
  is_active       boolean       NOT NULL DEFAULT true,
  created_at      timestamptz   NOT NULL DEFAULT now(),
  updated_at      timestamptz   NOT NULL DEFAULT now()
);

-- DEVIATION 2: data-model.md adds `properties_id_key UNIQUE (id)`. Omitted --
-- `id` is already the primary key, and nothing references properties as a
-- composite key, so it would create a second index serving nothing. The
-- composite unique keys that the composite FKs do need are on room_types and
-- rooms, below.


-- -----------------------------------------------------------------------------
-- users
--
-- One table for every authenticated principal. Guests and admins differ only
-- by `role`.
-- -----------------------------------------------------------------------------

CREATE TABLE users (
  id                uuid          PRIMARY KEY DEFAULT uuidv7(),
  email             varchar(320)  NOT NULL,
  -- bcrypt ($2b$, cost 12), chosen so Node's bcrypt and Spring Security's
  -- BCryptPasswordEncoder verify each other's hashes.
  password_hash     varchar(255)  NOT NULL,
  first_name        varchar(100)  NOT NULL,
  last_name         varchar(100)  NOT NULL,
  phone             varchar(32),
  address_line1     varchar(200),
  address_line2     varchar(200),
  city              varchar(120),
  state_province    varchar(120),
  postal_code       varchar(20),
  country_code      char(2),
  role              user_role     NOT NULL DEFAULT 'GUEST',
  -- The property a front-desk staff member is scoped to. NULL for guests and
  -- managers; see users_role_property_scope_chk below.
  home_property_id  uuid          REFERENCES properties (id) ON DELETE RESTRICT,
  is_active         boolean       NOT NULL DEFAULT true,
  created_at        timestamptz   NOT NULL DEFAULT now(),
  updated_at        timestamptz   NOT NULL DEFAULT now()
);

-- DEVIATION 3: data-model.md marks email "UNIQUE (case-insensitive)" in the
-- column table and separately specifies this functional index. The functional
-- index is what actually delivers case-insensitivity, so a plain UNIQUE
-- alongside it would be a redundant second index and would not enforce the
-- stated rule. Functional index only.
CREATE UNIQUE INDEX users_email_lower_key ON users (lower(email));

-- A front-desk staff member must be scoped to exactly one property; guests and
-- managers must not be.
ALTER TABLE users ADD CONSTRAINT users_role_property_scope_chk CHECK (
     (role =  'FRONT_DESK_STAFF' AND home_property_id IS NOT NULL)
  OR (role <> 'FRONT_DESK_STAFF' AND home_property_id IS NULL)
);

CREATE INDEX users_role_property_idx ON users (role, home_property_id);


-- -----------------------------------------------------------------------------
-- sessions
--
-- This table IS the authentication mechanism. Both backends read these rows, so
-- a user logged in through one is logged in through the other. Valid only when
-- revoked_at IS NULL AND expires_at > now().
-- -----------------------------------------------------------------------------

CREATE TABLE sessions (
  id           uuid         PRIMARY KEY DEFAULT uuidv7(),
  user_id      uuid         NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  -- SHA-256 hex of the opaque session token. The raw token is never stored, so
  -- a database dump cannot be replayed as a set of live sessions.
  token_hash   char(64)     NOT NULL UNIQUE,
  -- Login time, and the anchor for the 30-day absolute expiry cap.
  issued_at    timestamptz  NOT NULL DEFAULT now(),
  -- Idle deadline: now() + 8 hours at login, pushed forward on activity but
  -- never past issued_at + 30 days, and only written when >5 minutes stale.
  expires_at   timestamptz  NOT NULL,
  revoked_at   timestamptz,
  user_agent   varchar(255),
  ip_address   inet
);

-- Supports "revoke all of this user's other sessions" on password change.
CREATE INDEX sessions_user_idx ON sessions (user_id);
-- Supports the periodic cleanup job that deletes rows past expiry.
CREATE INDEX sessions_expires_at_idx ON sessions (expires_at);


-- -----------------------------------------------------------------------------
-- room_types
--
-- A bookable category at one property. Rates, occupancy, amenities and photos
-- live here; individual units live in rooms.
-- -----------------------------------------------------------------------------

CREATE TABLE room_types (
  id                 uuid            PRIMARY KEY DEFAULT uuidv7(),
  property_id        uuid            NOT NULL REFERENCES properties (id) ON DELETE RESTRICT,
  code               room_type_code  NOT NULL,
  name               varchar(120)    NOT NULL,
  description        text            NOT NULL,
  -- Nightly rate before any special-rate discount.
  base_rate          numeric(10,2)   NOT NULL CHECK (base_rate > 0),
  max_occupancy      smallint        NOT NULL CHECK (max_occupancy BETWEEN 1 AND 100),
  -- Free text. NULL is meaningful for a conference room.
  bed_configuration  varchar(120),
  is_accessible      boolean         NOT NULL DEFAULT false,
  is_active          boolean         NOT NULL DEFAULT true,
  created_at         timestamptz     NOT NULL DEFAULT now(),
  updated_at         timestamptz     NOT NULL DEFAULT now()
);

-- `code` is deliberately NOT unique per property: a property may offer two King
-- room types at different rates ("Standard King", "Deluxe King").
ALTER TABLE room_types ADD CONSTRAINT room_types_property_name_key
  UNIQUE (property_id, name);

-- Referenced by the composite FKs on rooms and reservations.
ALTER TABLE room_types ADD CONSTRAINT room_types_property_id_id_key
  UNIQUE (property_id, id);

CREATE INDEX room_types_property_idx      ON room_types (property_id) WHERE is_active;
CREATE INDEX room_types_property_code_idx ON room_types (property_id, code);


-- -----------------------------------------------------------------------------
-- room_type_photos
--
-- `url` holds an externally hosted or statically served path. Binary upload is
-- out of scope; admin endpoints accept URLs.
-- -----------------------------------------------------------------------------

CREATE TABLE room_type_photos (
  id            uuid          PRIMARY KEY DEFAULT uuidv7(),
  room_type_id  uuid          NOT NULL REFERENCES room_types (id) ON DELETE CASCADE,
  url           varchar(500)  NOT NULL,
  caption       varchar(200),
  sort_order    smallint      NOT NULL DEFAULT 0,
  is_primary    boolean       NOT NULL DEFAULT false
);

CREATE INDEX room_type_photos_room_type_idx
  ON room_type_photos (room_type_id, sort_order);

-- At most one primary photo per room type.
CREATE UNIQUE INDEX room_type_photos_one_primary_idx
  ON room_type_photos (room_type_id) WHERE is_primary;


-- -----------------------------------------------------------------------------
-- amenities
--
-- A seeded lookup table, not user-managed content. Rows are inserted at the end
-- of this file: the codes are a contract other documents depend on, so the
-- schema is incomplete without them.
-- -----------------------------------------------------------------------------

CREATE TABLE amenities (
  id          uuid         PRIMARY KEY DEFAULT uuidv7(),
  code        varchar(40)  NOT NULL UNIQUE,
  name        varchar(80)  NOT NULL,
  sort_order  smallint     NOT NULL DEFAULT 0
);


-- -----------------------------------------------------------------------------
-- room_type_amenities
--
-- Many-to-many between room_types and amenities.
-- -----------------------------------------------------------------------------

CREATE TABLE room_type_amenities (
  room_type_id  uuid  NOT NULL REFERENCES room_types (id) ON DELETE CASCADE,
  amenity_id    uuid  NOT NULL REFERENCES amenities (id)  ON DELETE RESTRICT,
  PRIMARY KEY (room_type_id, amenity_id)
);

-- Supports filtering search results by amenity.
CREATE INDEX room_type_amenities_amenity_idx ON room_type_amenities (amenity_id);


-- -----------------------------------------------------------------------------
-- rooms
--
-- Individual physical units. THIS IS THE UNIT OF BOOKING AND OF OVERLAP
-- PREVENTION. Real units rather than a per-type count, so the no-overbooking
-- rule can be a single database constraint instead of application locking.
-- -----------------------------------------------------------------------------

CREATE TABLE rooms (
  id                 uuid         PRIMARY KEY DEFAULT uuidv7(),
  -- Denormalized from room_types; kept consistent by the composite FK below.
  property_id        uuid         NOT NULL,
  room_type_id       uuid         NOT NULL,
  room_number        varchar(20)  NOT NULL,
  floor              smallint,
  -- Excluded from availability while true. Does not cancel existing bookings.
  is_out_of_service  boolean      NOT NULL DEFAULT false,
  created_at         timestamptz  NOT NULL DEFAULT now(),
  updated_at         timestamptz  NOT NULL DEFAULT now()
);

-- A room's property and room type cannot disagree: one composite FK, not two
-- simple ones. This is what makes the denormalization free.
ALTER TABLE rooms ADD CONSTRAINT rooms_property_room_type_fk
  FOREIGN KEY (property_id, room_type_id)
  REFERENCES room_types (property_id, id) ON DELETE RESTRICT;

ALTER TABLE rooms ADD CONSTRAINT rooms_property_number_key
  UNIQUE (property_id, room_number);

-- Referenced by the composite FK on reservations.
ALTER TABLE rooms ADD CONSTRAINT rooms_property_id_id_key
  UNIQUE (property_id, id);

CREATE INDEX rooms_room_type_idx ON rooms (room_type_id) WHERE NOT is_out_of_service;


-- -----------------------------------------------------------------------------
-- rate_plans
--
-- Per-property discount percentage for each special rate category. 'NONE' is
-- never stored here -- it implies a 0% discount.
-- -----------------------------------------------------------------------------

CREATE TABLE rate_plans (
  id                uuid           PRIMARY KEY DEFAULT uuidv7(),
  property_id       uuid           NOT NULL REFERENCES properties (id) ON DELETE CASCADE,
  rate_category     rate_category  NOT NULL CHECK (rate_category <> 'NONE'),
  discount_percent  numeric(5,2)   NOT NULL CHECK (discount_percent BETWEEN 0 AND 100),
  is_active         boolean        NOT NULL DEFAULT true,
  created_at        timestamptz    NOT NULL DEFAULT now(),
  updated_at        timestamptz    NOT NULL DEFAULT now()
);

ALTER TABLE rate_plans ADD CONSTRAINT rate_plans_property_category_key
  UNIQUE (property_id, rate_category);


-- -----------------------------------------------------------------------------
-- reservations
--
-- The core booking entity. Pricing is snapshotted at sale time, so later rate
-- edits never rewrite booking history.
-- -----------------------------------------------------------------------------

CREATE TABLE reservations (
  id                        uuid                PRIMARY KEY DEFAULT uuidv7(),
  -- DEVIATION 1: declared UNIQUE here and NOT repeated as a separate
  -- CREATE UNIQUE INDEX. A column-level UNIQUE already creates an index named
  -- reservations_confirmation_number_key -- the name error-handling.md expects
  -- -- so doing both would fail with "relation already exists".
  -- Format: 'HA' + 8 Crockford base32 chars. A display identifier only, never
  -- an authorization token.
  confirmation_number       varchar(12)         NOT NULL UNIQUE,
  guest_user_id             uuid                NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
  property_id               uuid                NOT NULL,
  -- The specific unit held by this reservation.
  room_id                   uuid                NOT NULL,
  -- What the guest booked and paid for. Deliberately NOT constrained to equal
  -- rooms.room_type_id; the composite FKs below guarantee both belong to the
  -- same property, which is the invariant that matters.
  room_type_id              uuid                NOT NULL,
  check_in_date             date                NOT NULL,
  -- Exclusive: a departure on the 10th and an arrival on the 10th do not
  -- overlap.
  check_out_date            date                NOT NULL,
  -- Generated, never written. Drives the exclusion constraint below. '[)'
  -- bounds are what make same-day turnover work.
  stay_period               daterange           GENERATED ALWAYS AS
                              (daterange(check_in_date, check_out_date, '[)')) STORED,
  -- Must also be <= the room type's max_occupancy. A CHECK cannot reference
  -- another table, so that half is enforced in application code and tested in
  -- both backends.
  num_guests                smallint            NOT NULL CHECK (num_guests >= 1),
  rate_category             rate_category       NOT NULL DEFAULT 'NONE',
  -- Snapshot of room_types.base_rate at sale time.
  base_rate_amount          numeric(10,2)       NOT NULL CHECK (base_rate_amount > 0),
  -- Snapshot of the rate plan's discount.
  discount_percent_applied  numeric(5,2)        NOT NULL DEFAULT 0
                              CHECK (discount_percent_applied BETWEEN 0 AND 100),
  -- round(base_rate * (1 - discount/100), 2) -- rounded BEFORE multiplying by
  -- nights, so the displayed nightly rate multiplies out to the total.
  nightly_rate_amount       numeric(10,2)       NOT NULL CHECK (nightly_rate_amount >= 0),
  total_amount              numeric(10,2)       NOT NULL CHECK (total_amount >= 0),
  currency                  char(3)             NOT NULL DEFAULT 'USD',
  status                    reservation_status  NOT NULL DEFAULT 'CONFIRMED',
  booked_at                 timestamptz         NOT NULL DEFAULT now(),
  -- Materialized 48-hour cutoff: check-in midnight in the property's timezone,
  -- minus exactly 172,800 seconds. A fixed duration, not a calendar operation,
  -- so across a DST boundary the local wall-clock time will not be midnight.
  cancellation_deadline     timestamptz         NOT NULL,
  checked_in_at             timestamptz,
  checked_out_at            timestamptz,
  cancelled_at              timestamptz,
  cancelled_by_user_id      uuid                REFERENCES users (id) ON DELETE SET NULL,
  -- Evaluated at cancellation time and frozen.
  was_refundable            boolean,
  created_at                timestamptz         NOT NULL DEFAULT now(),
  updated_at                timestamptz         NOT NULL DEFAULT now(),

  -- Named explicitly: an anonymous table-level CHECK is auto-named
  -- "reservations_check", which is opaque in an error message.
  CONSTRAINT reservations_dates_chk CHECK (check_out_date > check_in_date)
);

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
     (status = 'CONFIRMED'   AND checked_in_at IS NULL     AND checked_out_at IS NULL     AND cancelled_at IS NULL)
  OR (status = 'CHECKED_IN'  AND checked_in_at IS NOT NULL AND checked_out_at IS NULL     AND cancelled_at IS NULL)
  OR (status = 'CHECKED_OUT' AND checked_in_at IS NOT NULL AND checked_out_at IS NOT NULL AND cancelled_at IS NULL)
  OR (status = 'CANCELLED'   AND cancelled_at IS NOT NULL)
);

-- =============================================================================
-- NO OVERBOOKING -- the schema's central correctness guarantee.
--
-- Two non-cancelled reservations for the same room can never hold overlapping
-- date ranges. Enforced here rather than in application code because a
-- "SELECT then INSERT" check is a textbook race: two concurrent bookings both
-- see the room free and both insert. This moves the guarantee into the one
-- component both backends share.
--
-- The WHERE clause lets a cancelled booking's dates be reused immediately.
-- btree_gist supplies the operator class for uuid equality.
--
-- A violation raises SQLSTATE 23P01, which both backends translate to
-- 409 ROOM_UNAVAILABLE. The backing GiST index is also what makes availability
-- search fast; no separate index is needed for it.
-- =============================================================================

ALTER TABLE reservations ADD CONSTRAINT reservations_no_overlap_excl
  EXCLUDE USING gist (
    room_id     WITH =,
    stay_period WITH &&
  ) WHERE (status <> 'CANCELLED');

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

-- Admin room/rate calendar: rooms x dates for one property.
CREATE INDEX reservations_calendar_idx
  ON reservations (property_id, room_id, check_in_date)
  WHERE status <> 'CANCELLED';


-- -----------------------------------------------------------------------------
-- payments
--
-- Dummy payment record, one per reservation. No PAN, no CVV, no expiry, no
-- billing address, no processor reference. The column list is itself the
-- documentation that this system is out of PCI scope.
-- -----------------------------------------------------------------------------

CREATE TABLE payments (
  id               uuid            PRIMARY KEY DEFAULT uuidv7(),
  reservation_id   uuid            NOT NULL UNIQUE
                                     REFERENCES reservations (id) ON DELETE CASCADE,
  -- Mirrors reservations.total_amount at sale time.
  amount           numeric(10,2)   NOT NULL CHECK (amount >= 0),
  currency         char(3)         NOT NULL DEFAULT 'USD',
  status           payment_status  NOT NULL,
  method           varchar(20)     NOT NULL DEFAULT 'DUMMY_CARD',
  -- Derived from the leading digits: VISA, MASTERCARD, AMEX, DISCOVER.
  card_brand       varchar(20),
  -- Display only.
  card_last_four   char(4),
  cardholder_name  varchar(160),
  processed_at     timestamptz     NOT NULL DEFAULT now(),
  created_at       timestamptz     NOT NULL DEFAULT now()
);


-- -----------------------------------------------------------------------------
-- Reference data: amenities
--
-- Exactly the seven amenities from project-overview.md. These belong in a
-- migration rather than a seed script because their codes are a contract that
-- api-contracts.md and both frontends depend on -- the schema is incomplete
-- without them. Demo data (properties, rooms, guests, reservations) is a
-- separate re-runnable seed script and is NOT version-tracked here.
-- -----------------------------------------------------------------------------

INSERT INTO amenities (code, name, sort_order) VALUES
  ('WIFI',             'Wi-Fi',                              10),
  ('AIR_CONDITIONING', 'Air conditioning / climate control',  20),
  ('REFRIGERATOR',     'Refrigerator',                        30),
  ('TELEVISION',       'Television',                          40),
  ('MICROWAVE',        'Microwave',                           50),
  ('WET_BAR',          'Wet bar',                             60),
  ('SAFE',             'Safe for valuables',                  70);
