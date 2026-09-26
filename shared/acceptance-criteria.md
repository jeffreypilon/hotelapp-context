# Acceptance Criteria

Testable criteria for the behaviors that most need to be provably correct — the ones where a
bug would be both plausible and embarrassing to discover during a walkthrough.

**These are not exhaustive.** They deliberately cover four areas: no overbooking, the
cancellation boundary, role and scope enforcement, and session behavior. Ordinary CRUD
correctness is left to each repo's own test suite; what is here is the set of behaviors that
(a) involve concurrency, arithmetic, or a boundary condition, and (b) must produce *identical*
results in two backends written in different languages.

**Every criterion below must be implemented as an integration test in both
`hotelapp-server-nodejs` and `hotelapp-server-springboot`**, against a real PostgreSQL
instance — not a mock, not H2, not an in-memory substitute. Several of these criteria are
specifically about PostgreSQL behavior (an exclusion constraint, range overlap semantics,
timezone arithmetic), and a substituted database would make the tests pass while proving
nothing.

Scenario IDs are stable and should be referenced in test names, so a failure in one repo can
be compared against the same scenario in the other.

---

## Conventions used below

- **Given** is database state established by fixtures; **When** is a request through the HTTP
  layer, not a direct service call; **Then** is an observable response plus, where stated,
  resulting database state.
- "Property P" has timezone `America/New_York` unless a scenario says otherwise. Timezone is
  load-bearing in the cancellation scenarios.
- Dates are written relative to a fixed, injectable "now". **Both backends must allow the
  clock to be controlled in tests** — an injected clock in Spring, a mockable time source in
  Node. Several criteria are unverifiable without it, and retrofitting one is painful, so this
  is a design requirement on both implementations, not a testing detail.
- "Room R is the last available room" means: exactly one room of room type T at property P has
  no overlapping non-cancelled reservation for the requested range.

---

## 1. No overbooking

The project's central correctness guarantee, enforced by the exclusion constraint specified in
[data-model.md](./data-model.md#no-overbooking). These criteria test the guarantee, not the
mechanism — an implementation that satisfied them by other means would still be wrong per the
data model, but an implementation that fails them is wrong by any standard.

### AC-OB-01 — Two concurrent bookings for the last room: exactly one wins

```
Given  property P has exactly one room R of room type T with no reservation
       overlapping 2026-11-14 → 2026-11-17
  And  two authenticated guests G1 and G2
When   G1 and G2 both POST /reservations for room type T,
       dates 2026-11-14 → 2026-11-17, simultaneously
Then   exactly one request returns 201 Created
  And  the other returns 409 with code ROOM_UNAVAILABLE
  And  exactly one reservation row exists for room R overlapping that range
  And  exactly one payment row exists
  And  the losing guest has no reservation and no payment row
```

**How to actually test this**, because a naive test passes without proving anything: issue
both requests from two threads or two parallel promises against the same backend process, and
assert on the *pair* of outcomes rather than on either request individually. A test that
awaits the first request before issuing the second is testing sequential booking and will pass
even against an implementation with the race.

The stronger version, worth writing at least once: hold a transaction open with a conflicting
reservation inserted but uncommitted, then issue the booking request and assert it blocks and
then fails — which confirms the constraint rather than a lucky interleaving.

### AC-OB-02 — Adjacent stays do not conflict

```
Given  room R has a CONFIRMED reservation 2026-11-10 → 2026-11-14
When   a guest books room type T at property P for 2026-11-14 → 2026-11-17
  And  R is the only room of type T
Then  the request returns 201 Created
  And the new reservation is assigned to room R
```

The check-out date is exclusive: a departure and an arrival on the same day do not overlap.
This is the off-by-one the `'[)'` range bounds exist to prevent, and it is worth an explicit
test in both directions — a system that rejects this is silently losing a night of inventory
per turnover.

### AC-OB-03 — Every overlap shape is rejected

```
Given  room R has a CONFIRMED reservation 2026-11-10 → 2026-11-20
  And  R is the only room of its type at property P
When   a guest attempts to book that room type for each range below
Then   every attempt returns 409 ROOM_UNAVAILABLE
```

| Case | Requested range | Relationship to existing |
|------|-----------------|--------------------------|
| a | 2026-11-12 → 2026-11-15 | fully inside |
| b | 2026-11-08 → 2026-11-12 | overlaps the start |
| c | 2026-11-18 → 2026-11-22 | overlaps the end |
| d | 2026-11-05 → 2026-11-25 | fully contains |
| e | 2026-11-10 → 2026-11-20 | exactly equal |
| f | 2026-11-19 → 2026-11-21 | overlaps by one night |

Case (f) paired with AC-OB-02 pins the boundary exactly: an arrival on the last *night*
conflicts; an arrival on the departure *date* does not.

### AC-OB-04 — Cancelled reservations free their dates immediately

```
Given  room R is the only room of its type and has a CONFIRMED reservation
       2026-11-14 → 2026-11-17
When   that reservation is cancelled
  And  another guest books the same room type for 2026-11-14 → 2026-11-17
Then   the booking returns 201 Created
  And  both reservations exist on room R with overlapping stay periods
  And  the first has status CANCELLED and the second CONFIRMED
```

This is what the exclusion constraint's partial `WHERE (status <> 'CANCELLED')` clause buys,
and the last assertion is the interesting one: two overlapping rows for one room legitimately
coexist, which would be a constraint violation without the predicate.

### AC-OB-05 — Checked-out reservations do NOT free their dates

```
Given  room R is the only room of its type with a reservation 2026-11-14 → 2026-11-17
       in status CHECKED_IN
When   staff check the guest out on 2026-11-15
  And  another guest attempts to book that room type for 2026-11-16 → 2026-11-17
Then   the second attempt returns 409 ROOM_UNAVAILABLE
```

An early departure does not resell the room, per
[api-contracts.md](./api-contracts.md#post-adminreservationsreservationidcheck-out--staff). This is
the criterion most likely to be "fixed" into a bug by someone who assumes check-out should
release inventory.

### AC-OB-06 — Out-of-service rooms are never allocated

```
Given  property P has exactly two rooms of type T, R1 and R2
  And  R1 is marked is_out_of_service
  And  R2 has a CONFIRMED reservation covering 2026-11-14 → 2026-11-17
When   a guest searches availability for type T, 2026-11-14 → 2026-11-17
Then   type T does not appear in the results
When   the guest nonetheless POSTs a reservation for type T and those dates
Then   the response is 409 ROOM_UNAVAILABLE
```

The second half matters: search filtering and booking-time allocation must apply the same
exclusion, or a client that skips search can book an out-of-service room.

### AC-OB-07 — Allocation order is deterministic

```
Given  property P has rooms 201, 202, and 203 of type T, all free
When   a guest books room type T
Then   the reservation is assigned to room 201
When   a second guest books type T for an overlapping range
Then   that reservation is assigned to room 202
```

Lowest room number by natural sort, per
[api-contracts.md](./api-contracts.md#get-availability--public). Determinism is what makes the two
backends comparable — without it, every allocation test would need to accept any free room and
the two implementations could differ invisibly.

### AC-OB-08 — Availability count is accurate

```
Given  property P has 4 rooms of type T
  And  2 of them have reservations overlapping 2026-11-14 → 2026-11-17
  And  1 of them is out of service
When   a guest searches availability for those dates
Then   type T appears with availableRoomCount = 1
```

---

## 2. Cancellation and refund boundary

The 48-hour rule from [project-overview.md](./project-overview.md), computed against the
property's timezone and stored at booking time per
[data-model.md](./data-model.md#cancellation-policy).

For all scenarios below: property P is `America/New_York`, and a booking with check-in
2026-11-14 therefore has `cancellation_deadline` = **2026-11-12T05:00:00Z** (midnight on the
12th, Eastern Standard Time, minus 48 hours → 2026-11-12 00:00 EST = 05:00 UTC).

### AC-CX-01 — Just before the deadline: refundable

```
Given  a CONFIRMED reservation at property P, check-in 2026-11-14
  And  now is 2026-11-12T04:59:00Z (one minute before the deadline)
When   the guest POSTs /reservations/{id}/cancel
Then   the response is 200 OK
  And  status is CANCELLED
  And  wasRefundable is true
  And  refund is present with amount equal to the reservation total
  And  the payment row's status is REFUNDED
```

### AC-CX-02 — Exactly at the deadline: NOT refundable

```
Given  the same reservation
  And  now is exactly 2026-11-12T05:00:00Z
When   the guest cancels
Then   the response is 200 OK
  And  wasRefundable is false
  And  refund is null
  And  the payment row's status remains SUCCEEDED
```

> The boundary is **exclusive**: refundable requires `now < deadline`, so the deadline instant
> itself is already inside the non-refundable window. Either convention is defensible; what
> matters is that both backends choose the same one, which is why this scenario exists as a
> separate criterion from AC-CX-01 and AC-CX-03 rather than being left to interpretation.

### AC-CX-03 — Just after the deadline: NOT refundable, but still cancellable

```
Given  the same reservation
  And  now is 2026-11-12T05:01:00Z
When   the guest cancels
Then   the response is 200 OK
  And  status is CANCELLED
  And  wasRefundable is false
```

Cancelling late is **allowed** and merely unrefunded. A test asserting `409` here would encode
the most common misreading of the policy.

### AC-CX-04 — Deadline respects the property's timezone, not the server's

```
Given  property P1 with timezone America/New_York and property P2 with
       timezone America/Los_Angeles
  And  a reservation at each, both with check-in 2026-11-14
When   each reservation is created
Then   P1's cancellation_deadline is 2026-11-12T05:00:00Z
  And  P2's cancellation_deadline is 2026-11-12T08:00:00Z
```

Run this test with the backend process in **at least two different system timezones** (e.g.
`TZ=UTC` and `TZ=Asia/Tokyo`) and assert identical results. A system-timezone dependency here
is exactly the divergence the stored-deadline design exists to prevent, and it is invisible
until someone runs the two backends on differently configured machines.

### AC-CX-05 — DST transition does not shift the deadline arithmetic

```
Given  property P (America/New_York) and a reservation with check-in 2026-03-09
       (the day after the 2026 US spring-forward transition on 2026-03-08)
When   the reservation is created
Then   cancellation_deadline is 2026-03-07T04:00:00Z
  And  that instant is 23:00 on 2026-03-06 in the property's local time
```

The derivation, step by step:

| Step | Value |
|------|-------|
| Local midnight on the check-in date | `2026-03-09 00:00 −04:00` — already EDT, since the transition was 02:00 on Sunday the 8th |
| The same moment as an instant | `2026-03-09T04:00:00Z` |
| Minus exactly 48 hours (172,800 s) | **`2026-03-07T04:00:00Z`** |
| That instant back in local time | `2026-03-06 23:00 −05:00` — EST, because the 7th is before the transition |

**The deadline is a fixed 48-hour duration before the check-in instant, not midnight two
calendar days earlier.** Those two readings diverge by exactly one hour across a DST boundary,
and this criterion exists to pin the duration reading — which is what the formula in
[data-model.md](./data-model.md#cancellation-policy) specifies, and what PostgreSQL's
`timestamptz - INTERVAL '48 hours'` actually computes. (An hours-only interval is an exact
duration; only `day` and `month` components get calendar-aware treatment, which is why
`INTERVAL '2 days'` would *not* be equivalent here.)

So the local deadline landing on **23:00 rather than midnight is correct behavior**, not a
rounding artifact. The wrong answer to guard against is `2026-03-07T05:00:00Z`, produced by
subtracting two calendar days from the date and re-localizing midnight — an implementation
that "fixes" the non-round local time will produce exactly that, and give the guest an extra
hour of free cancellation on one weekend a year in each direction.

Both backends must produce the same value. This criterion also catches an implementation that
hardcodes a per-property UTC offset instead of using the IANA zone: a fixed `−05:00` puts the
check-in instant at `2026-03-09T05:00:00Z` and the deadline at `2026-03-07T05:00:00Z` — the
same wrong value the calendar-subtraction bug produces, reached by a different route. Verify
expected values against the zone database rather than trusting the arithmetic in this document.

### AC-CX-06 — Modification is blocked after the deadline

```
Given  a CONFIRMED reservation, check-in 2026-11-14
  And  now is 2026-11-12T05:01:00Z (past the deadline)
When   the guest PATCHes the reservation with new dates
Then   the response is 409 CANCELLATION_WINDOW_CLOSED
  And  the reservation is unchanged
```

### AC-CX-07 — Modification is allowed before the deadline and re-prices

```
Given  a CONFIRMED reservation, check-in 2026-11-14 → 2026-11-17, 3 nights
  And  now is well before the deadline
  And  the room type's base rate has since changed from 249.00 to 279.00
When   the guest PATCHes the dates to 2026-11-15 → 2026-11-19 (4 nights)
Then   the response is 200 OK
  And  the reservation's nights is 4
  And  pricing reflects the CURRENT base rate of 279.00, not the original
  And  cancellation.deadline is recomputed from the new check-in date
```

### AC-CX-08 — Staff fee waiver forces refundability

```
Given  a CONFIRMED reservation past its cancellation deadline
When   front-desk staff at that property POST /admin/reservations/{id}/cancel
       with body { "waiveFee": true }
Then   the response is 200 OK
  And  wasRefundable is true
  And  cancelled_by_user_id is the staff member's user id
```

### AC-CX-09 — Illegal cancellations are rejected

```
Given  reservations in each of these states at property P
When   a cancel is attempted on each
Then   each returns 409 INVALID_STATUS_TRANSITION
```

| State | Why rejected |
|-------|--------------|
| `CANCELLED` | Already cancelled |
| `CHECKED_IN` | Guest is in residence |
| `CHECKED_OUT` | Stay is complete |

### AC-CX-10 — Pricing arithmetic and rounding order

```
Given  room type T with base_rate 249.00
  And  property P has a rate plan for AAA_CAA with discount_percent 10.00
When   a guest books T for 3 nights with rateCategory AAA_CAA
Then   nightlyRate is "224.10"
  And  totalAmount is "672.30"
  And  both are JSON strings, not numbers
```

Round the nightly rate to the cent **first**, then multiply by nights — per
[data-model.md](./data-model.md#rate_plans). Rounding the total instead would give `672.30`
here too, so this case alone does not distinguish the orders; include at least one case where
they differ (e.g. base 100.01 at 33.33% over 3 nights) so the test actually pins the order.
Assert the JSON type as well as the value: a backend emitting `224.1` as a number has broken
the contract in a way a numeric comparison would not catch.

---

## 3. Role and scope enforcement

Tiers and the 403-vs-404 rules are specified in
[api-contracts.md](./api-contracts.md#authorization), with the reasoning in
[security-principles.md](./security-principles.md#authorization).

### AC-AZ-01 — A guest cannot read another guest's reservation

```
Given  guest G1 owns reservation X
  And  guest G2 is authenticated
When   G2 GETs /reservations/{X}
Then   the response is 404 NOT_FOUND
  And  the response body contains no detail about reservation X
```

**`404`, not `403`** — a `403` confirms the reservation exists. Assert the status code
explicitly; this is the criterion most likely to be "corrected" to `403` by someone applying a
general convention without reading the reasoning.

### AC-AZ-02 — A guest's list contains only their own reservations

```
Given  guest G1 has 3 reservations and guest G2 has 2
When   G1 GETs /reservations
Then   exactly 3 reservations are returned, all G1's
  And  pagination.totalItems is 3
```

Also assert that no query parameter widens the scope: a request with a `guestUserId` or
`userId` parameter must either reject it as an unknown parameter or ignore it, never honor it.

### AC-AZ-03 — A guest cannot cancel another guest's reservation

```
Given  guest G1 owns a CONFIRMED reservation X
When   guest G2 POSTs /reservations/{X}/cancel
Then   the response is 404 NOT_FOUND
  And  reservation X is still CONFIRMED
```

The state assertion matters as much as the status code: a handler that checks ownership after
performing the mutation would return `404` and still have cancelled the booking.

### AC-AZ-04 — A guest cannot reach any admin endpoint

```
Given  an authenticated guest
When   the guest requests each admin endpoint below
Then   each returns 403 INSUFFICIENT_ROLE
```

| Endpoint |
|----------|
| `GET /admin/reservations` |
| `POST /admin/reservations/{id}/check-in` |
| `POST /admin/properties` |
| `PUT /admin/properties/{id}/rate-plans` |
| `GET /admin/properties/{id}/calendar` |
| `GET /admin/properties/{id}/reports/occupancy` |

This should be table-driven over the full `/admin/*` route list rather than a hand-picked
subset, so a newly added admin route is covered by default. The failure mode being guarded
against is a route added without its tier annotation, which
[security-principles.md](./security-principles.md#authorization) requires to fail closed.

### AC-AZ-05 — Front-desk staff cannot reach another property

```
Given  staff S with home_property_id = P1
  And  reservation Y at property P2
When   S GETs /admin/reservations/{Y}
Then   the response is 403 PROPERTY_OUT_OF_SCOPE
When   S GETs /admin/reservations?propertyId=P2
Then   the results contain only P1 reservations
  And  the propertyId parameter is ignored, not honored
```

**`403` here, `404` in AC-AZ-01** — the asymmetry is deliberate and both must be asserted, or
a later "consistency" refactor will collapse them and silently create an enumeration oracle
on the guest side.

### AC-AZ-06 — Front-desk staff cannot perform manager-only actions

```
Given  staff S with home_property_id = P1
When   S attempts each of the following at their OWN property P1
Then   each returns 403 INSUFFICIENT_ROLE
```

| Action |
|--------|
| `POST /admin/properties` |
| `PATCH /admin/properties/{P1}` |
| `POST /admin/properties/{P1}/room-types` |
| `PATCH /admin/room-types/{id}` |
| `PUT /admin/properties/{P1}/rate-plans` |
| `POST /admin/properties/{P1}/rooms` |
| `PATCH /admin/rooms/{id}` |

Scope and tier are independent: being at the right property does not grant the higher tier.

### AC-AZ-07 — A manager reaches every property

```
Given  manager M and properties P1 and P2
When   M GETs /admin/reservations with no propertyId
Then   reservations from both P1 and P2 are returned
When   M GETs /admin/reservations?propertyId=P2
Then   only P2 reservations are returned
  And  the parameter IS honored (unlike AC-AZ-05)
```

### AC-AZ-08 — A manager passes every staff-level check

```
Given  manager M
When   M POSTs /admin/reservations/{id}/check-in for a CONFIRMED reservation
       at any property
Then   the response is 200 OK and the reservation is CHECKED_IN
```

The rank-based rule, tested directly: a manager is never enumerated in a staff-level check
yet must always pass it.

### AC-AZ-09 — Registration cannot escalate

```
When   POST /auth/register is sent with an extra field
       "role": "PROPERTY_MANAGER"
Then   the response is 400 VALIDATION_FAILED (unknown field rejected)
  And  no user is created
When   the same request is sent without the role field
Then   201 Created and the new user's role is GUEST
```

The mass-assignment defense from
[security-principles.md](./security-principles.md#input-validation). Repeat the same shape
against `PATCH /me` with `role` and `isActive`.

### AC-AZ-10 — Public endpoints require nothing and leak nothing

```
Given  no session cookie
When   GET /properties, GET /properties/{id}/room-types, and
       GET /availability?... are requested
Then   each returns 200 OK
  And  no room numbers, room ids, or roomCount appear in any response
```

Physical inventory is operational data — see
[api-contracts.md](./api-contracts.md#get-propertiespropertyidroom-types--public).

### AC-AZ-11 — Inactive accounts cannot authenticate

```
Given  a user with is_active = false and a correct password
When   POST /auth/login with valid credentials
Then   the response is 403 ACCOUNT_INACTIVE
Given  a user with a live session who is then deactivated
When   the user makes any authenticated request
Then   the response is 403 ACCOUNT_INACTIVE
```

The second half is the one that matters and the one a token-based design could not satisfy:
deactivation takes effect on the **next request**, because role and status are read from the
joined user row rather than from a cached claim.

---

## 4. Session behavior

The session design is in [api-contracts.md](./api-contracts.md#authentication); the schema in
[data-model.md](./data-model.md#sessions). **AC-SE-05 is the concrete proof that the
shared-session design works**, and is the single most demonstrable criterion in this document.

### AC-SE-01 — Login establishes a session

```
When   POST /auth/login with valid credentials
Then   the response is 200 OK
  And  a Set-Cookie header sets hotelapp_session
  And  that cookie carries HttpOnly, Secure, SameSite=Lax, and Path=/api/v1
  And  the response body contains the user object
  And  the body contains NO accessToken, token, or expiresIn field
  And  exactly one new sessions row exists with revoked_at IS NULL
  And  that row's token_hash is the SHA-256 of the cookie value
  And  the raw token does not appear anywhere in the database
```

Asserting the *absence* of token fields guards against a later well-meaning reintroduction.
Asserting the hash relationship proves the token is stored hashed rather than in plaintext.

### AC-SE-02 — A fresh login creates a new session rather than reusing one

```
Given  a user with an existing valid session
When   the user logs in again
Then   a second sessions row is created with a different token_hash
  And  the first session remains valid
  And  the server does not adopt any client-supplied token
```

Session-fixation resistance, plus the multi-device property AC-SE-07 depends on.

### AC-SE-03 — Logout revokes immediately

```
Given  an authenticated session
When   POST /auth/logout
Then   the response is 204 No Content
  And  Set-Cookie clears hotelapp_session with Max-Age=0
  And  the sessions row has revoked_at set
When   the SAME cookie value is replayed on GET /auth/me
Then   the response is 401 AUTHENTICATION_REQUIRED
```

The replay step is the real assertion. "Immediately" means on the very next request, with no
TTL lag — the property the session design was chosen for.

### AC-SE-04 — Logout is idempotent and scoped to one session

```
When   POST /auth/logout is called twice with the same cookie
Then   both return 204 No Content
When   POST /auth/logout is called with no cookie at all
Then   the response is 204 No Content
Given  a user with sessions on two devices
When   one session logs out
Then   the other session remains valid
```

### AC-SE-05 — A session works interchangeably against BOTH backends

```
Given  hotelapp-server-nodejs on localhost:3000
  And  hotelapp-server-springboot on localhost:8080
  And  both connected to the same PostgreSQL database
When   POST http://localhost:3000/api/v1/auth/login succeeds
  And  the returned cookie is sent to GET http://localhost:8080/api/v1/auth/me
Then   the response is 200 OK with the same user object
When   POST http://localhost:8080/api/v1/auth/logout is called with that cookie
  And  GET http://localhost:3000/api/v1/auth/me is called with the same cookie
Then   the response is 401 AUTHENTICATION_REQUIRED
```

**This is the demoable proof of the whole architecture** — log in against Node, act against
Spring Boot, log out from Spring Boot, and find yourself logged out of Node. It works because
sessions are rows in a shared database rather than state in either process, and because
browsers scope cookies by host and **not** by port, so `localhost:3000` and `localhost:8080`
share one cookie jar.

Practical notes, since this criterion is unlike the others:

- It cannot live in either backend's unit or integration suite alone, because it requires both
  processes running. It belongs in the **Docker Compose smoke test** — see
  [devops-pipeline-overview.md](./devops-pipeline-overview.md).
- Each backend should still hold a single-process approximation: seed a session row directly,
  then assert the backend honors it. That proves neither backend depends on having created the
  session itself, which is the property the cross-backend test exercises for real.
- Run it manually before any interview walkthrough. It takes thirty seconds and is the most
  convincing thing in the project.

### AC-SE-06 — Expired and unknown sessions are indistinguishable

```
Given  a sessions row with expires_at in the past
When   its cookie is used on any authenticated endpoint
Then   the response is 401 AUTHENTICATION_REQUIRED
Given  a revoked session
When   its cookie is used
Then   the response is 401 AUTHENTICATION_REQUIRED
Given  a syntactically valid but wholly fabricated token
When   it is used
Then   the response is 401 AUTHENTICATION_REQUIRED
  And  all three responses are byte-identical apart from traceId
```

One code for all four failure modes, per
[api-contracts.md](./api-contracts.md#error-responses). Distinguishing them would reveal
whether a guessed token ever existed.

### AC-SE-07 — Password change revokes other sessions but not the caller's

```
Given  a user with three valid sessions S1, S2, S3
When   the user PUTs /me/password from S1 with the correct current password
Then   the response is 204 No Content
  And  S1 remains valid
  And  S2 and S3 have revoked_at set
When   S2's cookie is replayed
Then   the response is 401 AUTHENTICATION_REQUIRED
```

### AC-SE-08 — The idle window slides, subject to the write-throttle

```
Given  a session whose expires_at is 7 hours away and was last written
       10 minutes ago
When   any authenticated request is made
Then   expires_at is extended to approximately now + 8 hours

Given  a session whose expires_at was written 1 minute ago
When   any authenticated request is made
Then   expires_at is NOT modified

Given  a session issued 30 days ago that has been continuously active
When   an authenticated request is made
Then   the response is 401 AUTHENTICATION_REQUIRED
  And  expires_at is never extended beyond issued_at + 30 days
```

All three parts must hold identically in both backends, since the numbers are the ones most
easily implemented slightly differently — the 5-minute throttle in particular is invisible in
manual testing and would make one backend appear to expire sessions sooner than the other.

### AC-SE-09 — Login rate limiting

```
Given  a clean rate-limit window
When   11 failed login attempts are made for the same email within 15 minutes
Then   the first 10 return 401 INVALID_CREDENTIALS
  And  the 11th returns 429 RATE_LIMITED with a Retry-After header
When   a CORRECT password is then submitted for that email inside the window
Then   the response is still 429 RATE_LIMITED
  And  no session is created
```

The last part is what makes the limit meaningful; a limiter that lets a correct password
through mid-window does not slow credential stuffing.

### AC-SE-10 — Credential errors do not reveal whether an account exists

```
When   POST /auth/login with an unregistered email and any password
  And  POST /auth/login with a registered email and a wrong password
Then   both return 401 INVALID_CREDENTIALS
  And  both response bodies are identical apart from traceId and instance
  And  the two response times are within the same order of magnitude
```

The timing assertion should be a loose statistical check over repeated runs, not a strict
comparison — a flaky timing test is worse than none. Its purpose is to catch the obvious
failure where the unknown-email path skips bcrypt entirely and returns in 2 ms while the
wrong-password path takes 200 ms.

---

## Cross-cutting criteria

Small but worth pinning, because each is a place the two backends could differ invisibly.

### AC-CC-01 — Error responses conform to RFC 9457

```
When   any error occurs
Then   Content-Type is application/problem+json
  And  the body contains type, title, status, detail, instance, code, traceId
  And  status equals the HTTP status
  And  validation errors additionally contain an errors array with field,
       code, and message per entry
```

### AC-CC-02 — Unknown request fields are rejected

```
When   any POST or PATCH body includes a field not in that endpoint's contract
Then   the response is 400 VALIDATION_FAILED
  And  the errors array identifies the offending field by name
```

### AC-CC-03 — Pagination is consistent everywhere

```
When   any collection endpoint is requested
Then   the response has data and pagination
  And  pagination contains page, pageSize, totalItems, totalPages,
       hasPreviousPage, hasNextPage
  And  page defaults to 1 and pageSize to 20
When   pageSize=101 or page=0 is requested
Then   the response is 400 VALIDATION_FAILED, not a clamped result
When   the same page is requested twice with the same sort
Then   the results are identical and in the same order
```

The last part tests the stable-sort tiebreak on `id`; without it, two rows with equal sort
keys can swap between pages and a row can be seen twice or missed.

### AC-CC-04 — The two backends publish equivalent OpenAPI documents

```
When   GET /api/v1/openapi.json is fetched from both backends
Then   both return a valid OpenAPI 3.1 document
  And  the set of paths is identical
  And  for each path, the set of methods is identical
  And  for each operation, request and response schemas are semantically
       equivalent
```

The automated form of this is the CI diff specified in
[api-contracts.md](./api-contracts.md#cross-cutting-requirements) and described in
[devops-pipeline-overview.md](./devops-pipeline-overview.md). It is the cheapest broad check
that the contract is being honored, and the only one that scales to every endpoint without a
hand-written test each.

### AC-CC-05 — Health check reflects real database state

```
When   GET /health is requested with the database reachable
Then   200 OK with status UP, database UP, and a backend field
       identifying which implementation answered
When   the database is unreachable
Then   503 with status DOWN
```

The `backend` field is how a tester confirms which implementation a frontend is actually
talking to, which matters during the AC-SE-05 walkthrough.

---

## What is not covered here

So the boundary is explicit rather than assumed:

- Ordinary CRUD happy paths for properties, room types, rooms, photos, and amenities — each
  repo's own test suite.
- Frontend behavior of any kind: component rendering, route guards, form validation, the
  booking wizard. Those belong in `stacks/react/testing-standards.md` and
  `stacks/angular/testing-standards.md` (Phase 3).
- Search filtering and sorting permutations beyond AC-OB-06 and AC-OB-08.
- Report arithmetic beyond the occupancy denominator already specified in
  [api-contracts.md](./api-contracts.md#get-adminpropertiespropertyidreportsoccupancy--staff).
- Load, stress, and soak testing — deliberately absent, per
  [non-functional-requirements.md](./non-functional-requirements.md#throughput-and-concurrency).
  AC-OB-01 tests correctness under concurrency, which is a different claim from performance
  under load, and this project makes only the former.
