# Domain Glossary

Plain-language definitions of every HotelApp domain term, with a pointer to where each one
is specified in full. This document decides nothing — it is the index you read when a term
in another document is unfamiliar, and the reference that keeps two frontends and two
backends using one vocabulary.

Definitions are drawn from [project-overview.md](./project-overview.md) (what the product
does) and [data-model.md](./data-model.md) (how it is represented). For how these terms
should be *written* in prose and UI copy, see
[glossary-of-conventions.md](./glossary-of-conventions.md#terminology-in-prose-and-ui-copy).

---

## Quick reference

| Term | One-line definition | Specified in |
|------|--------------------|--------------|
| [Property](#property) | One hotel | [data-model.md](./data-model.md#properties) |
| [Room type](#room-type) | A category of room at a property, with its rate and amenities | [data-model.md](./data-model.md#room_types) |
| [Room](#room) | One physical room unit — what actually gets booked | [data-model.md](./data-model.md#rooms) |
| [Amenity](#amenity) | A feature a room type offers | [data-model.md](./data-model.md#amenities-and-room_type_amenities) |
| [Rate category](#rate-category) | The discount *bucket* a guest selects | [data-model.md](./data-model.md#enumerated-types) |
| [Rate plan](#rate-plan) | The stored discount *percentage* for one category at one property | [data-model.md](./data-model.md#rate_plans) |
| [Base rate](#base-rate) | A room type's undiscounted nightly price | [data-model.md](./data-model.md#room_types) |
| [Nightly rate](#nightly-rate) | The per-night price after discount | [data-model.md](./data-model.md#rate_plans) |
| [Reservation](#reservation) | A booking of one room for a date range | [data-model.md](./data-model.md#reservations) |
| [Reservation status](#reservation-status) | Where a reservation sits in its lifecycle | [data-model.md](./data-model.md#enumerated-types) |
| [Confirmation number](#confirmation-number) | The human-readable identifier a guest is given | [data-model.md](./data-model.md#indexes) |
| [Stay period](#stay-period) | The reservation's date range as a single comparable value | [data-model.md](./data-model.md#no-overbooking) |
| [Cancellation deadline](#cancellation-deadline) | The moment free cancellation ends | [data-model.md](./data-model.md#cancellation-policy) |
| [Payment](#payment) | The dummy charge record attached to a reservation | [data-model.md](./data-model.md#payments) |
| [Session](#session) | A logged-in state, stored server-side | [data-model.md](./data-model.md#sessions) |
| [Guest](#guest) | Someone who books and manages their own reservations | [project-overview.md](./project-overview.md) |
| [Front-desk staff](#front-desk-staff) | Admin tier that views bookings and checks guests in and out | [project-overview.md](./project-overview.md) |
| [Property manager](#property-manager) | Admin tier that also manages inventory, rates, and properties | [project-overview.md](./project-overview.md) |

---

## Places and inventory

### Property

One hotel. It has a name, a description, one photo, a postal address, and a timezone.
HotelApp supports several properties at once, and every room, room type, rate plan, and
reservation belongs to exactly one.

The **timezone** is worth knowing about: bookings carry no times, but the cancellation
deadline needs a real moment, so each property records its IANA timezone to anchor that
calculation. See
[data-model.md](./data-model.md#properties) for why this exists in a dates-only model.

In guest-facing UI copy a property may be called a "hotel". In code, API paths, and these
documents it is always a property.

### Room type

A category of room offered at one property — its description, photos, amenities, bed
configuration, maximum occupancy, accessibility flag, and **base rate**. Guests shop at
this level: search results are room types, because that is what carries the photos and
features someone chooses between.

Five categories exist, fixed by the product: Single, Double, King, Suite, and **Conference
Room**. A conference room is a bookable meeting space that follows exactly the same
full-day booking rules as a guest room — it is a room type, not a special case, and no code
should treat it as one.

A property may offer more than one room type in the same category ("Standard King" and
"Deluxe King") at different rates.

### Room

One physical room unit, with a room number and an optional floor. **This is what actually
gets booked** and what the no-overbooking rule protects: a room cannot hold two overlapping
reservations.

Guests never choose a room and never see room numbers. They pick a room type, and the
backend assigns a specific free room when the booking is created. Staff see room numbers
throughout the admin area.

A room can be marked **out of service**, which removes it from future availability without
affecting reservations already on it.

### Amenity

A feature a room type offers, from a fixed list of seven: Wi-Fi, air conditioning,
refrigerator, television, microwave, wet bar, and a safe. Amenities attach to room types,
not to individual rooms, and a guest can filter search results by them.

---

## Money

### Base rate

A room type's nightly price before any discount. Set by a property manager, and the same
for every date — there is no seasonal or demand-based pricing in HotelApp.

### Rate category

The discount **bucket** a guest optionally selects when searching or booking: None,
AAA/CAA, AARP, Government/Per Diem, Military/Veteran, Senior, Corporate Code, or Group
Code.

It is a single-select choice, **not** a code someone types in and not a real eligibility
system. Nothing is verified — selecting "Military/Veteran" simply applies whatever discount
the property has configured for that category. The "clear selection" control in the UI
returns the field to None; None is the absence of a discount, not a category with its own
row.

### Rate plan

The stored record that turns a rate category into an actual number: one **discount
percentage** per (property, rate category) pair, editable by a property manager. This is
what "manage special rate discounts" means in the product description.

> **Rate category vs. rate plan** is the pair most easily confused. The *category* is what
> the guest picks (`AAA_CAA`). The *plan* is what the property charges for it (12% off at
> Harborview, 8% at Lakeside). One category, many plans — one per property.

### Nightly rate

The per-night price a guest actually pays: base rate reduced by the rate plan's discount
percentage, rounded to the cent **before** being multiplied by the number of nights, so the
displayed nightly rate always multiplies out to the displayed total. The exact formula and
rounding order are in [data-model.md](./data-model.md#rate_plans) and are binding on both
backends.

Every reservation **snapshots** its base rate, discount percentage, nightly rate, and
total. Editing a room type's base rate later never re-prices an existing booking.

---

## Bookings

### Reservation

A booking of one specific room, at one property, for a date range, by one guest. It records
who booked it, the dates, the guest count, the rate category, the snapshotted pricing, its
status, and its cancellation deadline.

Check-out date is **exclusive**: a reservation from the 14th to the 17th occupies three
nights and releases the room on the 17th, so another guest can arrive that day.

In UI copy, the act of creating one is "booking"; the thing itself is a "reservation".

### Reservation status

Where a reservation sits in its lifecycle. Four values, and the only legal transitions:

```
CONFIRMED ──→ CHECKED_IN ──→ CHECKED_OUT
    │
    └──→ CANCELLED
```

- **Confirmed** — booked and paid (with the dummy payment). The state every reservation
  starts in; there is no pending or held state.
- **Checked in** — the guest has arrived. Set by front-desk staff.
- **Checked out** — the guest has departed. Set by front-desk staff, and only from checked
  in.
- **Cancelled** — called off, by the guest or by staff. The only status that releases the
  room's dates for rebooking.

A checked-out reservation keeps its dates reserved; an early departure does not resell the
room.

### Confirmation number

The short, human-readable identifier a guest is given and quotes at the front desk: ten
characters, `HA` plus eight unambiguous base32 characters, e.g. `HA7K2M9QX4`.

It is a **display identifier only, never a credential.** Knowing a confirmation number does
not authorize anything — every endpoint still checks who is asking.

### Stay period

The reservation's date range expressed as one PostgreSQL `daterange` value, so the database
can compare two reservations for overlap directly. It is derived automatically from the
check-in and check-out dates and is not something anyone sets. It exists because it is what
the no-overbooking constraint operates on — see
[data-model.md](./data-model.md#no-overbooking).

### Cancellation deadline

The moment at which free cancellation ends: **48 hours before check-in**, measured from
midnight on the check-in date in the property's own timezone. Computed once when the booking
is made and stored, so both backends always agree.

Cancelling *before* the deadline is free and refundable. Cancelling *after* it is still
allowed — the guest simply gets no refund. The deadline also governs **modification**: dates
and guest count can only be changed while the booking is still inside its free window.

### Payment

The record that a reservation was paid for. HotelApp processes nothing: the payment form
collects and validates card-shaped input, and the backend keeps only the card brand and last
four digits for display. No card number, CVV, or expiry is ever stored.

`REFUNDED` status records the outcome of a refundable cancellation. No money moves in either
direction; the row is the demo's audit trail.

---

## People and access

### Session

A logged-in state. HotelApp uses **server-side sessions**: a row in the database, keyed by a
random token the browser holds in a cookie it cannot read. Both backends read the same
table, so a guest who logs in through one is logged in through the other.

A session expires after 8 hours of inactivity (extended by use, capped at 30 days from
login) and is revoked immediately on logout or password change. Full design in
[api-contracts.md](./api-contracts.md#authentication).

### Public

Not logged in. Anyone can browse properties, view room types and photos, and search
availability. An account is only needed to actually book.

### Guest

An authenticated user who books rooms and manages **their own** reservations: profile and
contact details, booking history, and cancelling or modifying their bookings. A guest can
never see anyone else's reservation — attempting to returns "not found" rather than
"forbidden", so the existence of other bookings is not disclosed.

### Front-desk staff

The first admin tier. Views **all** bookings at their own property, with search and
filtering, and checks guests in and out. Scoped to exactly one property: a front-desk staff
member assigned to Harborview cannot see Lakeside's bookings.

Cannot change inventory, rates, or properties.

### Property manager

The second admin tier, and a strict **superset** of front-desk staff — everything staff can
do, plus: add and edit properties, manage room types and rooms, manage rate plans, view the
room/rate calendar, and see occupancy and arrivals reporting. Not scoped to one property;
managers reach all of them.

Called "Property Manager / Owner" in [project-overview.md](./project-overview.md). "Owner"
is not a separate tier.

### Admin

Both admin tiers together — what "the admin area" and the `/admin/*` routes mean. Never a
synonym for property manager specifically.

---

## Terms deliberately absent

These come up when discussing hotel software and are **not** part of HotelApp. Their absence
is a scope decision, recorded in [project-overview.md](./project-overview.md):

| Term | Why absent |
|------|------------|
| Overbooking | Explicitly forbidden — a room is never double-booked |
| Hold, cart, pending booking | Booking is one atomic step; no reservation is ever provisional |
| Rate calendar, seasonal rate, dynamic pricing, ADR, RevPAR | One flat base rate per room type; revenue management is out of scope |
| Discount code, promo code, coupon | Rate categories are a selection, not a code lookup |
| Loyalty, rewards, points | Out of scope |
| Review, rating | Out of scope |
| Housekeeping, turndown, maintenance ticket | Out of scope; `is_out_of_service` is the only inventory flag |
| Folio, incidentals, room charge | Nothing beyond the room total is billed |
| OTA, channel manager, GDS, PNR | No third-party distribution |
| Walk-in | All reservations are created through the booking flow |
| Room assignment (as a separate step) | A room is assigned automatically at booking, not at check-in |
