# Non-Functional Requirements

Performance, scale, availability, and compatibility targets for HotelApp.

These are **demo-scale targets, stated as such.** A portfolio project that claims
enterprise numbers it has never measured is less credible than one that names its actual
operating envelope and shows that the design is sound within it. Where a real system would
need something this project does not have, this document says so plainly instead of
implying coverage.

---

## Scale

Illustrative volumes the system is designed and seeded for. These are the numbers to
generate test data at, and the numbers every performance target below assumes.

| Entity | Demo volume | Realistic ceiling for this design |
|--------|-------------|-----------------------------------|
| Properties | 3 | Low hundreds |
| Room types per property | 5–8 | Dozens |
| Rooms per property | 60–120 | Low thousands |
| Rooms, total | ~300 | Low tens of thousands |
| Reservations, total | ~3,000 (18 months of history plus 6 months forward) | Low millions |
| Users | ~200 guests, ~8 admin | Low hundreds of thousands |
| Amenities | 7 (fixed) | Fixed |
| Rate plans | 7 per property | Fixed per property |
| Concurrent users | 1–5 (the developer, an interviewer, a reviewer) | See below |
| Sessions, live at once | Under 20 | Thousands |

The "realistic ceiling" column is the more interesting one: it is where this schema and
these queries would stop performing acceptably **without design changes**. Nothing here is
close to a limit, and the gap is deliberate — the design is not tuned to the demo volume,
it simply is not stressed by it.

**Where the ceilings come from.** Reservations are the table that grows without bound, and
the query that touches the most of it is the availability search, which is bounded by a GiST
index lookup over one property's rooms for one date range — its cost tracks the number of
*overlapping* reservations, not the table size. Offset pagination is the first thing that
degrades, at deep page numbers over large result sets, which is documented as a known
trade-off in [api-contracts.md](./api-contracts.md#pagination-sorting-filtering).

**Seed data should reach the demo volumes, not the minimum.** A booking flow tested against
three reservations proves nothing about the availability query or the admin calendar. Seeding
detail belongs in `stacks/<tech>/environment-setup-guide.md` (Phases 3 and 4); the volumes
above are the target.

---

## Response time targets

Measured server-side, backend process only, excluding network and browser render, against a
warm database at the seeded volumes above, on developer-grade hardware.

| Endpoint class | Target (p95) | Notes |
|----------------|--------------|-------|
| `GET /availability` | **< 150 ms** | The most complex read. See below |
| `GET /admin/properties/{id}/calendar` | **< 300 ms** | The largest response |
| `POST /reservations` | **< 200 ms** | Includes bcrypt-free write path, allocation, two inserts, one transaction |
| `POST /auth/login` | **< 400 ms** | Dominated by bcrypt at cost 12, deliberately — ~150–250 ms of that is the hash, and that is the feature |
| Authenticated simple reads (`/auth/me`, `GET /reservations/{id}`) | **< 50 ms** | Session lookup plus one indexed query |
| Public catalogue reads (`/properties`, `/room-types`) | **< 50 ms** | Small result sets, no joins of consequence |
| Paginated list reads | **< 100 ms** | Includes the count query |
| Admin reports (occupancy, arrivals) | **< 200 ms** | Aggregates over one property, one date |

**The two query-heavy endpoints, specifically:**

**Availability search** is the one query whose plan is worth checking rather than assuming.
It joins room types to rooms and applies a `NOT EXISTS` anti-join against reservations using
the `&&` range operator, which is served by the GiST index backing the no-overbooking
exclusion constraint — the constraint and the search share one index, noted in
[data-model.md](./data-model.md#no-overbooking). At ~120 rooms per property and a two-week
window, the anti-join touches tens of rows. 150 ms is a generous target; the interesting
requirement is that **the query plan uses the GiST index rather than a sequential scan**, and
that is what an `EXPLAIN` in each backend's test suite should assert. A plan regression is the
realistic failure mode here, not a latency regression.

**The admin calendar** is bounded by design rather than by query cost: the 60-day window cap
in [api-contracts.md](./api-contracts.md#get-adminpropertiespropertyidcalendar--staff) exists to keep
the response finite, and the segment-based response shape (reservation ranges, not one entry
per room per date) keeps a 60-day × 120-room view in the low hundreds of objects rather than
7,200 cells. The cost is in serialization, not in SQL.

**Session lookup runs on every authenticated request** and is the one piece of added
per-request work the session design accepted. It is a single-row lookup on a unique index over
`sessions.token_hash`, joined to the user row: sub-millisecond, and inside the connection the
request needs anyway. If it ever measured above a few milliseconds, something is wrong with
the index rather than with the approach — see
[api-contracts.md](./api-contracts.md#authentication) for the trade as originally argued.

**Frontend targets**, for both clients equally, on a broadband connection:

| Metric | Target |
|--------|--------|
| First Contentful Paint | < 1.5 s |
| Time to Interactive | < 3 s |
| Initial JS bundle, gzipped | < 300 KB |
| Search results render after response | < 100 ms |

Bundle parity between the React and Angular clients is **not** a target. They will differ,
Angular's baseline is larger, and pretending otherwise would be the wrong kind of
symmetry.

---

## Throughput and concurrency

**Expected concurrent load: single digits.** This is a demo walked through by one person at
a time. There is no load target, no requests-per-second figure, and no capacity plan, because
inventing one would be fiction.

What does need to hold under concurrency is **correctness**, and exactly one scenario
matters: two simultaneous booking attempts for the last available room. That is guaranteed by
the database exclusion constraint rather than by application locking, and it is a required
test in both backends —
[acceptance-criteria.md](./acceptance-criteria.md#1-no-overbooking) specifies it.

> **Design Decision — correctness under concurrency, without a throughput target.**
> These are separate concerns and the project takes them separately. The no-overbooking
> guarantee must hold at any level of concurrency, and it does, because it is enforced by a
> constraint rather than by a check-then-write. Whether the system can *sustain* high
> concurrency is untested and unclaimed. A reviewer asking "what happens when two people book
> the last room at once" gets a demonstrable answer; one asking "how many bookings per second"
> gets an honest "not measured, and here is the design that would need to change first."

Connection pooling: modest pools (10–20 connections) in both backends. Default PostgreSQL
`max_connections` is 100, and two backends running at once must not between them exhaust it —
a small point, but the kind that produces a confusing failure the first time both run
together.

---

## Availability

**This system is not highly available, and nothing in it pretends to be.**

| Component | Redundancy | Consequence |
|-----------|-----------|-------------|
| PostgreSQL | **None.** One instance | The database is a single point of failure. If it stops, the application is fully down |
| Backend | **None.** One process | No clustering, no rolling restart, no health-check-driven replacement |
| Frontend | Static assets | The only piece that would trivially survive, since it has no runtime |

Specifically absent, each a normal production requirement:

- **No read replicas.** Every query goes to the primary. Nothing in the design would prevent
  adding one for reporting later, and nothing depends on it.
- **No failover, no standby, no replication.** A failed database is restored from backup by
  hand, or the demo data is reseeded.
- **No automated backups.** Development data is reproducible from seed scripts, which is the
  actual recovery mechanism and is more appropriate here than a backup schedule.
- **No load balancing.** One backend process, addressed directly.
- **No zero-downtime deployment.** Deployment is stopping a process and starting it again.
- **No uptime target.** There is nothing to be up. No SLA, no SLO, no error budget, and no
  monitoring to measure them against.
- **No graceful-degradation story.** If the database is unreachable, requests fail with
  `503` from `GET /health` and `500` elsewhere. There is no cache to serve stale reads from,
  by design — see
  [architecture-overview.md](./architecture-overview.md#what-is-deliberately-not-in-this-architecture).

**Recovery expectations, stated concretely:** RPO and RTO are both "reseed the database",
which takes under a minute. That is an acceptable answer for a demo and would be an
unacceptable one for a hotel, and the difference is worth naming rather than blurring.

**What the design does get right for availability, given one instance:** both backends are
stateless, so restarting one loses nothing but in-flight requests. All state — including
sessions — is in PostgreSQL, which means a restart does not log anyone out. That is a real
property, not a consolation, and it is the one thing that would make horizontal scaling
straightforward if it were ever wanted.

---

## Data integrity and durability

Where the project *does* hold itself to a high standard, because this is what the schema
design is for:

- **No overbooking is absolute.** Enforced by a database constraint, not by application
  logic, so it holds under any concurrency and against both backends equally.
- **Pricing history is immutable.** Reservations snapshot base rate, discount, nightly rate,
  and total. Editing a room type's rate never re-prices a past booking.
- **Money is exact.** `numeric(10,2)` end to end, decimal strings in JSON, no
  floating-point arithmetic at any layer.
- **Status transitions cannot produce contradictory rows.** A `CHECK` constraint ties each
  status to its required timestamps.
- **Referential integrity is enforced in the database**, including the composite foreign keys
  that make a room's property and room type unable to disagree.
- **Writes that span tables are transactional.** Booking a room and recording its payment
  either both happen or neither does.

PostgreSQL defaults apply for durability: WAL, `synchronous_commit = on`, full fsync. Not
tuned, not relaxed for demo speed.

---

## Browser and device support

**Both frontends target the same matrix.** Divergence between the React and Angular clients
in what they support would undermine the point of building both.

| Browser | Support |
|---------|---------|
| Chrome / Edge (Chromium) | Last 2 major versions |
| Firefox | Last 2 major versions |
| Safari (macOS) | Last 2 major versions |
| Safari (iOS) | Last 2 major versions |
| Internet Explorer | **Not supported.** Any version |

Practically: **evergreen browsers with baseline-2023-or-later support.** Both clients may use
modern JavaScript, CSS Grid, Flexbox, container queries, and `SameSite` cookie semantics
without polyfills or transpilation targets below ES2020.

Two specific browser behaviors this project depends on, worth listing because a target matrix
usually hides its real dependencies:

- **`SameSite=Lax` cookie semantics** — the CSRF posture in
  [security-principles.md](./security-principles.md#sessions) rests on the browser
  withholding the cookie from cross-site state-changing requests. Every browser above does
  this; IE does not, which is part of why it is excluded outright rather than degraded.
- **`Secure` cookies on `http://localhost`** — treated as a secure context by every browser
  above, which is what lets the development configuration match the deployed one.

**Responsive layout, with different priorities per surface:**

| Surface | Priority | Target widths |
|---------|----------|---------------|
| Public browsing and search | Mobile-first | 360 px and up |
| Guest booking and account | Mobile-first | 360 px and up |
| Admin area | **Desktop-first** | 1280 px and up; usable, not optimized, below 1024 px |

> **Assumption — the admin area is desktop-first.**
> [project-overview.md](./project-overview.md) does not state a device target. Front-desk and
> manager work happens at a desk on a wide screen, and the room/rate calendar is a dense grid
> that cannot be made genuinely good on a phone. Rather than compromise the calendar to a
> mobile layout it will never be used in, the admin area targets desktop and remains merely
> usable when narrow. The guest-facing side is the reverse, since guests book on phones.

**Accessibility.** WCAG 2.1 Level AA as the target for both clients: keyboard navigation
throughout, visible focus states, semantic landmarks, form labels tied to inputs, 4.5:1 text
contrast, and `aria-live` announcements for search results and booking confirmation. This is
a target rather than a verified claim — no audit has been run. It is called out here partly
because the domain includes an accessibility feature in the data itself: room types carry an
ADA flag, and an application that models accessible rooms while being unusable with a keyboard
would be a poor look.

**Localization is out of scope.** English only, `en-US` formatting, USD only, a single
currency field carried through the API for future-proofing rather than for present use. Dates
are rendered in the property's timezone where a moment is shown, and as plain calendar dates
where the model has no time.
