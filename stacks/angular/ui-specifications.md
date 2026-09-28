# UI Specifications — Angular

Screen-by-screen specification for the Angular client, `hotelapp-client-angular`.

> ### This document's screen specification is shared, verbatim, with the other frontend stack
>
> **Sections 1 and 2 below are byte-identical to
> [`stacks/react/ui-specifications.md`](../react/ui-specifications.md).** That is
> deliberate and load-bearing: the two clients must deliver the same screens, states, validation
> messages, and copy, and the cheapest way to guarantee that is for the specification to be one
> text rather than two descriptions of one intent.
>
> **Any diff between the two files' sections 1 and 2 is a defect**, not a stack-appropriate
> variation. Genuine framework differences belong in section 3, which is the only part of this
> file that differs from its counterpart.
>
> This pairs with the OpenAPI diff that guards the two backends
> ([devops-pipeline-overview.md](../../shared/devops-pipeline-overview.md#1-the-openapi-diff)):
> the same check applied to the frontend pair is a CI job that extracts sections 1–2 from both
> files and fails on any difference. See the note at the end of section 3.

**Read first:** [project-overview.md](../../shared/project-overview.md) for what each screen is
for, [api-contracts.md](../../shared/api-contracts.md) for every endpoint these screens call,
and [glossary-of-conventions.md](../../shared/glossary-of-conventions.md#terminology-in-prose-and-ui-copy)
for binding UI wording. Error message text is owned by
[error-handling.md](./error-handling.md); state placement by
[state-management.md](./state-management.md); routing and folder layout by
[architecture-specification.md](./architecture-specification.md).

---

## 1. Conventions for every screen

These apply to all screens below and are not repeated per screen.

**Responsive priority.** Guest-facing surfaces are mobile-first from 360 px. The admin area is
desktop-first at 1280 px and must remain *usable* — not optimized — down to 1024 px. Per
[non-functional-requirements.md](../../shared/non-functional-requirements.md#browser-and-device-support).

**The five states.** Every screen that loads data specifies all of: **loading**, **empty**,
**error**, **success**, and any **role-gated** variant. A screen with no empty state is a screen
whose empty state was forgotten.

- **Loading** — skeleton placeholders matching the eventual layout, never a centered spinner on a
  blank page, which causes layout shift on arrival.
- **Error** — the message comes from the error-handling mapping
  (`error-handling.md`), keyed on the problem `code`. Screens never compose their own
  wording for a known `code`.
- **Empty** — distinguishes "no data exists yet" from "your filters matched nothing", because the
  useful action differs (create something vs. clear filters).

**Money and dates.** Money arrives as a decimal string and is rendered `$1,234.56`; never parsed
into a JavaScript `number`. Calendar dates render as `Sat, Nov 14, 2026` in full and
`Nov 14` in dense tables. A timestamp that represents a real moment — only
`cancellation.deadline` — renders in the **property's** timezone with the zone abbreviation
shown, e.g. `Nov 12, 2026, 12:00 AM EST`.

**Terminology is binding.** All UI copy uses the vocabulary fixed in
[glossary-of-conventions.md](../../shared/glossary-of-conventions.md#terminology-in-prose-and-ui-copy):
"Front Desk" and "Manager" as role labels; **reservation** as the noun and entity, **booking** as
the act ("Complete booking", "booking history"); **property** in code and admin copy, **hotel**
permitted in guest-facing copy; **confirmation number**, never "booking reference". A screen that
invents wording for a concept already named there is a defect in the screen spec.

**Accessibility, every screen.** One `<h1>`; landmark regions; labels tied to inputs by `for`/`id`;
visible focus rings; 4.5:1 text contrast; full keyboard operability. Results counts and
async outcomes announce via `aria-live="polite"`; validation errors via `aria-live="assertive"` and
`aria-describedby` on the offending field. Target is WCAG 2.1 AA.

**Client-side input validation, every field that accepts free text or a number.** This is UX, not
security — the server validates independently and is the real gate — but a field that silently
accepts garbage (`2030323t` in a 4-digit expiry year) or an unbounded length is a defect, not a
missing nice-to-have.

- **A numeric-only field is masked, not merely hinted.** `inputMode="numeric"` alone only changes
  which mobile keyboard appears — it does not stop a pasted or physically-typed letter, and does
  not exist at all for someone on a desktop keyboard. Every numeric-only field (phone, card
  number, card expiry month/year, CVV, and any future one) strips non-digit characters live, as
  typed, and hard-caps at its real maximum length — 10 digits for a US phone number, 16 for a card
  number, 2 for an expiry month, 4 for an expiry year, 3–4 for a CVV.
- **Every text field's maximum length matches its backing database column**, per
  [data-model.md](../../shared/data-model.md), where one exists — not an arbitrary round number.
  Guessing a smaller cap than the column rejects a legitimately long value the server would have
  accepted; guessing a larger one lets a guest type input that only fails after a round trip.
- **A field whose valid range isn't fixed by the database or the contract** (a guest count, a
  price filter) still gets a stated, sensible ceiling chosen by whoever builds the screen — not
  left unbounded because no authority defines one. State the number chosen in a code comment so a
  reviewer isn't left guessing why that value and not another.
- **A field verifying an existing credential — a login password, or "current password" on a
  change-password screen — gets no format or length validation beyond "required."** The client
  cannot know what rule was in effect when that value was set, and a client-side rule that's
  stricter than the one the account was actually created under would reject a genuinely correct
  value. Only a field *setting* a new value enforces shape.
- **Every field validates when the guest leaves it (on blur), not only when the whole form is
  submitted.** Once a field has shown an error, it re-validates live as the guest corrects it,
  rather than waiting for another blur — the standard pairing of "validate on blur, re-validate on
  change." Waiting for submission to surface a problem in the third field of a five-field form is
  a worse experience than saying so as the guest moves past it. Stack-specific mechanics are in
  each stack's own `state-management.md`.

**Pagination.** Every list uses the envelope from
[api-contracts.md](../../shared/api-contracts.md#pagination-sorting-filtering): 1-based `page`,
`pageSize` default 20. Controls show current page, total pages, and total items. Page and all
filters live in the URL query string, so a filtered list is linkable and survives reload — this is
required, not optional, because the admin area's whole workflow is "find this reservation and send
someone the link".

**Authorization is the server's.** Route guards and hidden controls are UX only. Every screen
assumes its guard can be bypassed and relies on the API to refuse.

---

## 2. Screen specifications

### S0 — App shell

Persistent frame around every route. Not a screen, but specified first because every screen sits
inside it.

**Endpoints:** `GET /auth/me` (bootstrap), `POST /auth/logout`.

**Layout.** Header with the HotelApp wordmark (links to the property list), primary nav, and a
user area on the right. Footer is minimal: copyright, a "Demo application — no real bookings"
notice. Guest surfaces get a mobile hamburger below 768 px; the admin area gets a persistent left
sidebar at 1280 px, collapsing to icons at 1024 px.

**Session bootstrap — the app's first action.** On mount, call `GET /auth/me`. This is the *only*
way the client learns whether a session exists, since the cookie is `HttpOnly` and unreadable. Until
it resolves, render the shell with the user area in a loading state and **do not** redirect
anywhere — redirecting on an unresolved session bounces an authenticated user to login on every
refresh.

| Outcome | Result |
|---------|--------|
| `200` | Store the `user` object; render role-appropriate nav |
| `401` | Anonymous. No error shown — not being logged in is not an error |
| Network failure | Treat as anonymous; show a dismissible "Unable to reach the server" banner |

**User area states.**

| Session | Shows |
|---------|-------|
| Resolving | Skeleton chip |
| Anonymous | "Log in" and "Create account" |
| Guest | First name, menu: "My reservations", "Profile", "Log out" |
| Front Desk | First name + "Front Desk" badge + their property name, menu adds "Admin" |
| Manager | First name + "Manager" badge, menu adds "Admin" and a property switcher |

**Nav by role.** Guest-facing nav is always present. `Admin` appears only for Staff and Manager.
Within admin: Reservations, Arrivals, Calendar always; Properties, Rooms, Rate Plans, Reports only
for Manager.

**Logout.** `POST /auth/logout`, clear all cached user and server state, route to the property list
with a "You've been logged out" toast. Treat any response as success — the endpoint is idempotent
and returns `204` even with no session.

**The global 401 rule.** Any authenticated request returning `401` clears user state and routes to
login with `?next=<current path>`, showing "Your session has expired. Please log in again." There
is **no retry and no refresh attempt** — the superseded token design had one; this one does not. See
`state-management.md` for where this interceptor lives in each stack.

---

### S1 — Property list

Landing page. Public.

**Route:** `/` and `/properties`  ·  **Endpoint:** `GET /properties`

**Layout.** Page `<h1>` "Our hotels". A search field ("Search by name or city") and a city filter
above a responsive card grid: 1 column at 360 px, 2 at 768 px, 3 at 1280 px. Each card: photo (16:9,
`loading="lazy"`), name as an `<h2>` link, city and state, truncated description (2 lines), and
"5 room types". Whole card is one link target.

**States.**

| State | Presentation |
|-------|--------------|
| Loading | 6 skeleton cards |
| Success | Card grid + pagination |
| Empty (no properties) | "No hotels are available right now." |
| Empty (filtered) | "No hotels match your search." + "Clear filters" |
| Error | Mapped message + "Try again" |

**Sort:** name (default) or city. Search and city filter are URL query parameters.

**Missing photo:** neutral placeholder block with the property's initials. Never a broken image.

---

### S2 — Property detail

**Route:** `/properties/:propertyIdOrSlug`  ·  **Endpoints:**
`GET /properties/{propertyId}`, `GET /properties/{propertyId}/room-types`,
`GET /room-types/{roomTypeId}`

**Layout.** Hero photo, `<h1>` property name, address, phone. Description below. Then an
`<h2>` "Rooms" section listing each room type as a horizontal card (stacking on mobile): primary
photo, name, category label, bed configuration, "Sleeps 2", amenity icon row, "From $249.00 /
night", and a "Check availability" button that routes to S3 pre-filtered to that room type.

For a Conference Room, "Sleeps N" reads "Capacity N" and "From $X / night" reads "From $X / day" —
"sleeps" and "night" describe an overnight stay, which a full-day meeting space is not, per
[domain-glossary.md](../../shared/domain-glossary.md#room-type)'s note that it follows the same
full-day booking rules as a guest room without being one. Every other element of the card is
unchanged for this category.

An accessible room type carries a visible "Accessible" badge with an accessible-name attribute —
not an icon alone.

**Room-type detail.** Selecting a room-type card opens a detail view (modal on desktop, full route
on mobile, route-addressable either way at `/room-types/:roomTypeId`) using
`GET /room-types/{roomTypeId}`: photo gallery, full description, complete amenity list with names,
bed configuration, max occupancy, accessibility flag.

**Availability search entry.** A date/guest form near the top, which carries its values into S3.

**States.** Loading: hero + two card skeletons. Empty: "This hotel has no rooms listed yet."
Error `NOT_FOUND`: full-page "We couldn't find that hotel." + link back to S1. Other errors: mapped
message.

**Never shown publicly:** room numbers, room counts, or individual room records. Physical inventory
is operational data.

---

### S3 — Search and results

The most complex guest screen.

**Route:** `/properties/:propertyId/search`  ·  **Endpoints:** `GET /availability`,
`GET /amenities`, `GET /rate-categories`

**Search form.** Check-in date, check-out date, guests (stepper, min 1), and an optional special
rate category `<select>` populated from `GET /rate-categories` — labels come from the API response,
never hardcoded, so adding a category needs no frontend change. The category control includes a
"Clear selection" action that returns it to "None"; per
[domain-glossary.md](../../shared/domain-glossary.md#rate-category) this is a UI affordance and
resets the field to `NONE` rather than being a distinct value.

Client-side pre-validation, before any request: check-out must be after check-in; check-in not in
the past; stay at most 30 nights. Messages come from the error-handling mapping so they match what
the server would say.

**Filters** (sidebar at 1280 px, collapsible drawer below 1024 px): room type (multi-select),
amenities (multi-select, from `GET /amenities`), accessible-only toggle, nightly-rate min/max.

**Sort:** nightly rate ascending (default), nightly rate descending, max occupancy, name.

**Result cards.** Photo, name, bed configuration, "Sleeps N", amenity icons, and a pricing block:

```
$224.10 / night        ← nightly rate, after discount
$249.00 struck through ← base rate, ONLY when a discount applied
3 nights · $672.30 total
AAA/CAA rate applied   ← category label, only when not NONE
```

For a Conference Room, "Sleeps N" reads "Capacity N" and the rate line's "/ night" reads "/ day",
same as S2. The "N nights · $total total" line is unchanged — `nights` stays the shared duration
unit across every room type in the pricing model; only the per-unit rate label and the occupancy
label are guest-room-specific wording, not the underlying count.

Scarcity: when `availableRoomCount` is 1, show "Only 1 room left". At 2–3, "Only N rooms left".
Above 3, nothing. Per [api-contracts.md](../../shared/api-contracts.md#get-availability--public)
this is indicative and may be stale — it must never be treated as a hold.

"Select room" routes to S4.

**States.** Loading: form stays interactive, results show 4 skeletons. **Empty is a success, not an
error** — `200` with no results renders "No rooms available for these dates." plus "Try different
dates" and "Clear filters", never an error treatment. Error `VALIDATION_FAILED`: field-level
messages on the offending inputs. Error `NOT_FOUND`: "We couldn't find that hotel."

All search parameters live in the URL, so a result set is shareable and survives reload.

**Announce results** via `aria-live="polite"`: "12 room types available."

---

### S4 — Booking summary

Review step before payment. Requires an authenticated guest.

**Route:** `/properties/:propertyId/book`  ·  **Endpoints:** none — renders state carried from S3

**Layout.** `<h1>` "Review your booking". A summary card: hotel name and address; room type name and
bed configuration; check-in and check-out as full dates with the nights count; guests; rate category
when not None; then a price breakdown:

```
$224.10 × 3 nights      $672.30
─────────────────────────────────
Total                   $672.30
```

Total is `nightlyRate × nights` exactly, per
[data-model.md](../../shared/data-model.md#rate_plans). No taxes or fees — HotelApp models none, and
inventing a line item here would contradict the data model.

Below: the cancellation policy in plain language — "Free cancellation until Nov 12, 2026, 12:00 AM
EST. After that, this reservation is non-refundable." — with the deadline rendered in the property's
timezone. Then "Continue to payment".

**The authentication gate — the one flow requiring care.** Per
[project-overview.md](../../shared/project-overview.md), a guest browses anonymously and is prompted
to log in only at this point.

| Session | Behavior |
|---------|----------|
| Guest | Proceed to S6 |
| Anonymous | Route to S5 with `?next=` carrying the full booking context |
| Staff or Manager | Proceed — admins may hold personal reservations; no special case |

**The booking context must survive the login round-trip.** After authenticating, the guest returns
to this screen with dates, room type, guests, and rate category intact. Losing it here means
re-doing the search, which is the single worst UX failure available in this application. Both stacks
must carry it in the URL rather than in memory, so it survives a full page reload during the
detour — see `state-management.md`.

**Re-validation on arrival.** Availability may have changed while the guest logged in. Re-run the
availability query on mount; if the room type is no longer available, show "Those dates are no
longer available." with "Back to search" and disable "Continue to payment".

---

### S5 — Login and registration

**Routes:** `/login`, `/register`  ·  **Endpoints:** `POST /auth/login`, `POST /auth/register`

Two routes, one shared layout, with a link between them that preserves `?next=`.

**Login.** Email, password, submit "Log in". Below: "Don't have an account? Create one".

**Registration.** First name, last name, email, password, phone (optional, labelled "Optional").
Submit "Create account". Password field shows the rule up front — "At least 12 characters" — and a
show/hide toggle. Per
[security-principles.md](../../shared/security-principles.md#passwords) there are **no character-class
requirements**, and the UI must not imply any; no "must contain a symbol" hint, no strength meter
scolding a long passphrase.

Registration logs the guest straight in and returns the same body as login, so both paths end
identically.

**States and errors.**

| Condition | Presentation |
|-----------|--------------|
| Submitting | Button spinner + disabled; fields stay readable |
| `INVALID_CREDENTIALS` | Form-level: "That email or password is incorrect." **Never** field-level — the server deliberately does not say which, and a field-level error would invent information |
| `ACCOUNT_INACTIVE` | Form-level: "This account has been deactivated." |
| `EMAIL_ALREADY_REGISTERED` | Field-level on email, with a link to log in |
| `VALIDATION_FAILED` | Field-level per `errors[]` entry |
| `RATE_LIMITED` | Form-level: "Too many attempts. Please try again in a few minutes." Disable submit for the `Retry-After` duration |

**On success:** store the `user`, then route to `?next=` if present, else the property list for a
guest, else the admin reservation list for Staff or Manager.

**No token handling of any kind.** The response body contains no token; the session cookie is set by
the server and is invisible to script. Nothing is written to `localStorage` or `sessionStorage`.

Autocomplete: `email`, `current-password` on login, `new-password` on registration. Submit on
Enter.

---

### S6 — Payment form

**Route:** `/properties/:propertyId/book/payment`  ·  **Endpoint:** `POST /reservations`

**A demo payment form. It must say so.** A prominent, non-dismissible banner above the fields:
"This is a demo. No payment is processed and no card details are stored. Do not enter a real card
number." This is the most important copy on the screen — a form that looks like a real payment form
without saying otherwise is a genuine trust problem, not a cosmetic one.

**Fields.** Cardholder name, card number, expiry month and year, CVV. Plus a condensed booking
summary and the total, so the guest can see what they are agreeing to.

**Client-side validation** — shape only, matching what the server checks: Luhn on the card number;
expiry in the future; CVV 3–4 digits; cardholder name present. Card number formats in groups of
four as typed, numbers only, capped at 16 digits entered — every test card in the table below is
16 digits, and this demo does not need to accommodate other card lengths — and shows a brand
indicator derived from the leading digits.

**Test cards, documented on screen** (collapsible "Test card numbers" panel):

| Number | Result |
|--------|--------|
| `4242 4242 4242 4242` | Succeeds (Visa) |
| Any number ending `0000` | `402 PAYMENT_DECLINED` |

Per [api-contracts.md](../../shared/api-contracts.md#post-reservations--guest) the declining case is
deterministic, which makes the failure path demonstrable without a processor.

**Submission.** One `POST /reservations` carrying the booking parameters and the payment block,
with an `Idempotency-Key` header holding a UUID generated once when the screen mounts — **not per
submit attempt**, or a double-click creates two reservations, which is exactly what the header
exists to prevent.

**No price is ever sent.** The request has no price field by contract design; the server resolves
pricing. The frontend must not attempt to send one.

| Condition | Presentation |
|-----------|--------------|
| Submitting | Overlay "Confirming your booking…", form disabled, **navigation blocked** |
| `201` | Route to S7. Replace history so Back does not re-submit |
| `PAYMENT_DECLINED` | Field-level on card number: "This card was declined. Please try another card." Form stays filled |
| `ROOM_UNAVAILABLE` | Form-level, prominent: "Those dates are no longer available." + "Back to search". This is the lost-race case and must read as bad luck, not as user error |
| `VALIDATION_FAILED` | Field-level per `errors[]` |
| `401` | Global rule: session expired, route to login preserving context |
| `NOT_FOUND` | "That room is no longer offered." + back to the property |

**Never logged, never persisted, never put in a URL:** card number, CVV, expiry. They exist only in
form state and are discarded on unmount.

---

### S7 — Confirmation

**Route:** `/reservations/:reservationId/confirmation`  ·  **Endpoint:** renders the `POST` response;
`GET /reservations/{reservationId}` on direct load

**Layout.** Success icon, `<h1>` "Your reservation is confirmed", and the **confirmation number as
the most prominent element on the page** in a large monospace treatment with a copy button —
`HA7K2M9QX4`. It is what a guest quotes at the front desk.

Then full details: hotel name and address, room type, dates with nights, guests, rate category,
price breakdown, total, and the cancellation deadline in plain language. Then: "View my
reservations", "Book another stay", and a "Print" action using a print stylesheet.

A note that a confirmation email "would be sent in a production deployment" — honest about the demo
boundary rather than claiming an email that never sends.

**Direct load / refresh** fetches by id via `GET /reservations/{reservationId}`, so the URL is
shareable by its owner and survives reload. A non-owner gets `404` and the standard not-found
treatment — per
[security-principles.md](../../shared/security-principles.md#authorization) the confirmation number
is not a credential and this screen grants nothing.

---

### S8 — Guest account and booking history

**Routes:** `/account` (profile), `/account/reservations` (list),
`/account/reservations/:id` (detail), `/account/password`
**Endpoints:** `GET /me`, `PATCH /me`, `PUT /me/password`, `GET /reservations`,
`GET /reservations/{reservationId}`, `PATCH /reservations/{reservationId}`,
`POST /reservations/{reservationId}/cancel`

Tabbed (desktop) or stacked (mobile) area with three sections.

**S8a — Profile.** `GET /me` renders first name, last name, email (read-only, with "Email cannot be
changed" as helper text), phone, and the address group. Edit mode via `PATCH /me` with only changed
fields. Success: "Your profile has been updated." An explicit `null` clears a nullable field, so a
cleared input must send `null` rather than `""`.

**S8b — Reservations.** `GET /reservations`, default sort `checkInDate:desc`. Filter tabs
**Upcoming** (`?from=today`), **Past** (`?to=today`), **Cancelled** (`?status=CANCELLED`), **All** —
all four are the same endpoint with different parameters, which is why there is no separate
"history" screen.

Each row/card: hotel name, room type, dates, nights, status badge, total, confirmation number, and a
"View" link. Status badge colors: Confirmed neutral-positive, Checked in active, Checked out muted,
Cancelled muted with strikethrough on the dates.

Empty states differ per tab: Upcoming → "You have no upcoming stays." + "Find a room"; Past → "You
have no past stays."; Cancelled → "You have no cancelled reservations."

**S8c — Reservation detail.** Everything from S7, plus the action area, which is entirely governed
by status and the cancellation deadline:

| Status | `now < deadline` | Actions |
|--------|------------------|---------|
| Confirmed | yes | "Change dates", "Cancel reservation" |
| Confirmed | no | Neither. Show "Changes are no longer available for this reservation." and a "Cancel reservation (non-refundable)" action |
| Checked in | — | None. "You're currently checked in." |
| Checked out | — | None. "This stay is complete." |
| Cancelled | — | None. Show `cancelledAt` and whether it was refundable |

Cancelling inside the window is **allowed** and merely unrefunded — the button is not hidden, it is
relabelled. Hiding it would misrepresent the policy.

**Cancel** opens a confirmation dialog stating the refund outcome explicitly before proceeding:
refundable → "You'll receive a full refund of $672.30."; not → "This cancellation is
non-refundable. You will not receive a refund." Confirm label "Cancel reservation", dismiss label
"Keep reservation" — never "Cancel"/"OK", which invert ambiguously on a cancel-a-thing dialog.

On success, render the outcome including the refund block when present.

**Change dates** re-opens a date/guest form, then `PATCH`. It **re-prices at current rates** and may
move the reservation to a different room, so the confirmation step shows the new total and, when it
differs, says so: "Your new total is $837.00 (was $672.30)." Errors:
`CANCELLATION_WINDOW_CLOSED` → "Changes are no longer available for this reservation.";
`ROOM_UNAVAILABLE` → "Those dates aren't available."; `INVALID_STATUS_TRANSITION` → refresh and
re-render actions.

**S8d — Password.** Current password, new password, confirm new password. `PUT /me/password`.
Success: "Your password has been updated." and a note that other devices have been signed out —
true per the contract, and worth telling the user. `INVALID_CREDENTIALS` → field-level on current
password: "That password is incorrect." **The caller stays logged in**; this screen must not route
to login on success.

---

### S9 — Admin booking list

The front desk's primary screen. Staff and Manager.

**Route:** `/admin/reservations`  ·  **Endpoints:** `GET /admin/reservations`,
`GET /admin/reservations/{reservationId}`, `POST /admin/reservations/{reservationId}/cancel`

**Desktop-first: a dense table**, not cards. Columns: Confirmation, Guest (last, first), Property
(Manager only), Room, Check-in, Check-out, Nights, Status, Total. Sortable on check-in (default
ascending), check-out, booked-at, guest last name, status.

**Filter bar:** free-text guest name, guest email, confirmation number, status multi-select, a
check-in date range, room number, and — **Manager only** — a property selector. Filters and page
live in the URL.

**Role-gated behavior, and it must be built deliberately rather than inherited:**

| Role | Property filter | Result scope |
|------|-----------------|--------------|
| Front Desk | **Not rendered** | Always their own property; the server ignores any `propertyId` they send |
| Manager | Rendered, includes "All properties" | Honored |

Below 1024 px the table collapses to stacked rows with the same data, keeping the admin area usable
on a tablet without pretending to be optimized for it.

**States.** Loading: table skeleton, filter bar interactive. Empty (unfiltered): "No reservations
yet." Empty (filtered): "No reservations match these filters." + "Clear filters". `403
PROPERTY_OUT_OF_SCOPE`: "You don't have access to that property." — this should be unreachable
through the UI, and reaching it means a guard is wrong, so it must be visible rather than swallowed.

**S9b — Admin reservation detail.** Everything in the guest view plus the guest's contact block
(name, email, phone) and the assigned room number. Actions per status: Confirmed → "Check in",
"Cancel reservation"; Checked in → "Check out"; Checked out / Cancelled → none.

Admin cancel adds a **"Waive cancellation fee"** checkbox, shown only when the reservation is past
its deadline, sending `{"waiveFee": true}`. Label the consequence: "Waive the fee and refund this
reservation in full."

---

### S10 — Check-in and check-out

Not a separate route — the arrivals worklist plus the transition actions on S9b.

**Route:** `/admin/arrivals`  ·  **Endpoints:**
`GET /admin/properties/{propertyId}/reports/arrivals`,
`POST /admin/reservations/{reservationId}/check-in`,
`POST /admin/reservations/{reservationId}/check-out`

**Layout.** `<h1>` "Arrivals", a date picker defaulting to today in the **property's** timezone, and
a table ordered by guest last name: Guest, Confirmation, Room, Nights, Guests, Status, and an
action button. Manager sees a property selector.

**Check-in.** Enabled only for `CONFIRMED`. On success the row's status becomes Checked in and the
button becomes "Check out".

**The date warning — a deliberate softness.** Per
[api-contracts.md](../../shared/api-contracts.md#post-adminreservationsreservationidcheck-in--staff)
check-in is **not** blocked on a date other than the check-in date; the response carries
`dateWarning` of `EARLY`, `LATE`, or `null`. When it is not null the UI shows a confirmation prompt
before proceeding — "This guest is arriving early. Check them in anyway?" / "…arriving late…" — with
"Check in" and "Cancel". The action must remain available: early and late arrivals are routine and a
front desk that cannot check a guest in because of the clock is broken.

**Check-out.** Enabled only for `CHECKED_IN`. `INVALID_STATUS_TRANSITION` → "This reservation can't
be checked out from its current status." plus a refresh, since the state is stale.

**States.** Empty: "No arrivals for this date." Each row's action shows an inline spinner while
posting, with only that row disabled — one slow request must not freeze the whole worklist.

---

### S11 — Room and rate calendar

The densest screen in the application. Staff and Manager.

**Route:** `/admin/calendar`  ·  **Endpoint:** `GET /admin/properties/{propertyId}/calendar`

**Layout.** A grid: rooms as rows, dates as columns. Sticky first column (room number, room type,
nightly rate) and sticky header row (dates). Default window 14 days from today; the window is
adjustable and **capped at 60 days**, which the UI enforces before requesting rather than letting
the server reject it. Controls: date range, previous/next, "Today", and a room-type filter. Manager
sees a property selector.

**Cells.** The response carries reservation **segments**, not per-date entries, so the client expands
segments across the dates they cover — per
[api-contracts.md](../../shared/api-contracts.md#get-adminpropertiespropertyidcalendar--staff). A
segment renders as a continuous bar spanning its nights, labelled with the guest's last name and
confirmation number when there is room. Segments may extend beyond the window and are clipped.

| Cell | Presentation |
|------|--------------|
| Free | Empty, subtle background |
| Confirmed | Filled bar, neutral-positive |
| Checked in | Filled bar, active treatment |
| Checked out | Filled bar, muted |
| Out of service | Hatched pattern across the whole row, room label marked "Out of service" |

Colour is never the only channel — each state also differs in pattern or label, so the grid is
readable without colour vision. A legend is always visible.

Clicking a segment opens S9b for that reservation. Hovering shows a tooltip with guest name,
confirmation number, and full date range; the same information is reachable by keyboard focus, since
a hover-only affordance excludes keyboard users from the screen's primary information.

**States.** Loading: grid skeleton with correct row count when known. Empty (no rooms): "This
property has no rooms yet." + a link to room management for Managers. Error: mapped message +
"Try again".

**Below 1024 px** this grid does not work and must not be faked. Show the same data as a
per-room vertical list of segments, with a note that the calendar view needs a wider screen. This is
the clearest case of the admin desktop-first decision, and pretending otherwise would produce a grid
nobody can read.

---

### S12 — Property and room-type management

Manager only.

**Routes:** `/admin/properties`, `/admin/properties/:id`, `/admin/properties/:id/room-types/:rtId`,
`/admin/properties/:id/rooms`
**Endpoints:** `GET /admin/properties`, `POST /admin/properties`,
`PATCH /admin/properties/{propertyId}`, `POST /admin/properties/{propertyId}/room-types`,
`PATCH /admin/room-types/{roomTypeId}`, `PUT /admin/room-types/{roomTypeId}/amenities`,
`GET /admin/room-types/{roomTypeId}/photos`, `POST /admin/room-types/{roomTypeId}/photos`,
`DELETE /admin/room-types/{roomTypeId}/photos/{photoId}`,
`GET /admin/properties/{propertyId}/rooms`, `POST /admin/properties/{propertyId}/rooms`,
`PATCH /admin/rooms/{roomId}`

**S12a — Property list (admin).** Table: Name, City, Room types, Rooms, Active. Includes inactive
properties, which the public list omits. "Add property" button.

**S12b — Property form.** Create and edit share one form: name, slug (helper: "Leave blank to
generate from the name"), description, photo URL, the address group, phone, timezone (a `<select>`
of IANA zones), and — edit only — an Active toggle.

Deactivating warns: "Deactivating this hotel hides it from guests. Existing reservations are not
cancelled and remain visible here." That is exactly the contract's behavior and the manager should
not have to guess it. Errors: `SLUG_IN_USE` → field-level "That URL slug is already in use.";
`VALIDATION_FAILED` → field-level.

**S12c — Room types.** Within a property: list with name, category, base rate, max occupancy,
accessible flag, active. "Add room type". Form: category `<select>`, name, description, base rate
(money input, positive), max occupancy (1–100), bed configuration (optional — and genuinely optional,
since a conference room has none), accessible toggle, and an amenity multi-select.

Changing the base rate warns: "This changes the rate for new bookings only. Existing reservations
keep the rate they were booked at." — the snapshot-pricing behavior from
[data-model.md](../../shared/data-model.md#room_types), surfaced where it matters.

Amenities save via `PUT` as a complete set, not incremental adds.

**S12d — Photos.** Per room type: ordered list with thumbnail, caption, sort order, and a primary
marker. Add by URL — **there is no file upload**, which the UI states plainly rather than hinting at
a drop zone that does not exist. Setting one photo primary clears the others, which the UI reflects
immediately. Deleting the primary leaves the room type with no primary, and the UI must tolerate a
null primary photo everywhere.

**S12e — Rooms.** Per property: table of room number, floor, room type, out-of-service. Sort by
room number (natural sort, so `2` precedes `10`). "Add room". Form: room type `<select>` (scoped to
this property), room number, floor.

Marking a room out of service uses `futureReservationCount` from the response to warn: "This room
has 3 future reservations. Taking it out of service does not cancel them." Errors:
`ROOM_NUMBER_IN_USE` → field-level "That room number already exists at this hotel."

---

### S13 — Rate-plan management

Manager only. The smallest admin screen and the one most easily got wrong.

**Route:** `/admin/properties/:id/rate-plans`  ·  **Endpoints:**
`GET /admin/properties/{propertyId}/rate-plans`,
`PUT /admin/properties/{propertyId}/rate-plans`

**Layout.** One editable table, **always all seven discountable categories**, because the `GET`
returns a complete set with zeros and `isActive: false` for categories that have no stored row — so
the UI never has to special-case absence:

| Rate category | Discount % | Active |
|---------------|-----------|--------|
| AAA/CAA | `12.00` | ☑ |
| AARP | `8.00` | ☑ |
| Government/Per Diem | `0.00` | ☐ |

Category labels come from `GET /rate-categories`. **"None" never appears** — it is the absence of a
discount, and sending it is a `400`.

Discount input: 0–100, two decimals, suffixed `%`. Per
[glossary-of-conventions.md](../../shared/glossary-of-conventions.md#money-dates-and-formatting-in-code)
the value is the percentage itself, so `12.00` means 12% — the input must not accept or display a
fraction.

**Save semantics, stated on screen.** `PUT` replaces the whole set; omitted categories are
deactivated. The UI sends every row, and a helper line says: "Changes apply to new bookings only."
Inactive rows are still sent, with their percentages, so toggling one back on does not lose the
number.

**States.** Loading: table skeleton with seven rows. Success: "Rate plans updated." Dirty-state
guard on navigation. `VALIDATION_FAILED` → field-level on the offending row.

---

### S14 — Admin reports

Staff and Manager. Two small screens, deliberately not a dashboard.

**Route:** `/admin/reports`  ·  **Endpoints:**
`GET /admin/properties/{propertyId}/reports/occupancy`,
`GET /admin/properties/{propertyId}/reports/arrivals`

**S14a — Occupancy.** Date picker defaulting to today in the property's timezone. A summary row of
stat tiles: Total rooms, Sellable rooms, Occupied rooms, and Occupancy rate. Then a per-room-type
table: room type, sellable, occupied, occupancy rate.

`occupancyRate` arrives as a decimal string in `[0, 1]` and renders as a percentage with one
decimal — `74.4%`. The API deliberately does not send a percentage, so the conversion belongs here
and must be done once, in a shared formatter, not per component.

A footnote defines the denominator: "Occupancy is occupied rooms divided by sellable rooms;
out-of-service rooms are excluded." Without it the number is ambiguous, and it is the definition
[api-contracts.md](../../shared/api-contracts.md#get-adminpropertiespropertyidreportsoccupancy--staff)
specifies.

When `sellableRooms` is 0 the API returns `"0.0000"`; render `0.0%` and a note "No sellable rooms at
this property." — never `NaN` and never a division error.

**S14b — Upcoming arrivals.** The same data as S10, presented as a report rather than a worklist: a
paginated table with no action buttons, with a link to S10 for the actionable view.

**Deliberately absent:** ADR, RevPAR, revenue by segment, charts, trend lines, date-range
comparisons. [project-overview.md](../../shared/project-overview.md) lists richer analytics as a
future enhancement, and inventing a dashboard here would be scope the product does not have.

---

### S15 — Not found and error routes

**Routes:** `/404` (and any unmatched path), plus an app-level error boundary.

Unmatched route: "We couldn't find that page." + a link to the property list. A `404` from a
resource fetch renders in-place within the shell rather than replacing it, so the nav stays usable.

An unexpected client-side exception renders "Something went wrong." with a reload action and, when a
`traceId` is available from a failed response, shows it as small print for support correlation.
Never a stack trace.

---

## 3. Angular implementation notes

**This is the only section that differs from the React file.** Nothing here may change what a
screen does, only how this stack builds it. Target: **Angular 22.1**.

### Routing

Standalone components with lazy-loaded routes, mirroring S0's shell:

| Screen | Route |
|--------|-------|
| S1 | `''` and `properties` |
| S2 | `properties/:propertyId` |
| S3 | `properties/:propertyId/search` |
| S4 | `properties/:propertyId/book` |
| S6 | `properties/:propertyId/book/payment` |
| S7 | `reservations/:reservationId/confirmation` |
| S5 | `login`, `register` |
| S8 | `account`, `account/reservations`, `account/reservations/:id`, `account/password` |
| S9–S14 | `admin/...` under a lazy-loaded admin route with a shared layout |

Guards are functional `CanActivateFn` guards (`authGuard`, `staffGuard`, `managerGuard`). Each must
await the S0 bootstrap before deciding — resolve it once in an `APP_INITIALIZER`-equivalent
provider so no guard ever observes an unresolved session, which is the Angular-shaped version of
the same hazard React faces.

### Per-screen notes

| Screen | Note |
|--------|------|
| S0 | Shell is the root component. Session bootstrap runs once during app initialization and exposes the user as a signal, so guards and templates read a resolved value |
| S3 | Search parameters bind to `queryParams` via the router, read as signals through `toSignal(route.queryParamMap)`. Debounce filter input ~300 ms with `debounceTime` before triggering a refetch |
| S4 | Booking context travels in the URL query string so it survives the login detour and a hard reload |
| S6 | `Idempotency-Key` is generated once in the component's field initializer, not in the submit handler — a per-attempt UUID defeats the header's purpose |
| S6 | Block navigation while submitting with a `CanDeactivateFn` plus a `beforeunload` listener |
| S8c | Dialogs are Angular ARIA dialog primitives — stable as of Angular 22 — so focus trapping and `aria-modal` come from the framework rather than hand-rolled |
| S11 | The calendar grid is the one screen where render cost is real. Use `@for` with a stable `track` on room id and date, and compute the segment-to-cell expansion in a `computed()` so it recalculates only when the response or window changes. Do not virtualize — the 60-day cap bounds the grid |
| S11 | `OnPush` is the default for every component; the calendar depends on it |
| S14 | The occupancy-rate formatter is one shared pipe, used by both the tiles and the table |

### Component conventions

Standalone components throughout; no `NgModule` declarations for new code. `ChangeDetectionStrategy.OnPush`
everywhere. Native control flow (`@if`, `@for`, `@switch`), not the legacy structural directives.
Inputs and outputs use the `input()` / `output()` functions rather than decorators. Tailwind
utilities in templates; component styles only where a utility genuinely cannot express it.

Forms use typed reactive forms — **Signal forms are stable in Angular 22** and are the preferred
choice for new forms here, with typed `FormGroup` acceptable where a pattern is already
established; whichever is used, the choice must be consistent within a feature rather than mixed
per component. Field-level server errors from `errors[]` are applied with `setErrors` on the
matching control, which is why the contract's `field` values must match control names exactly.

### The section-diff CI check

A CI step in this repo (or in either client repo) should extract everything from `## 1.` through the
end of section 2 in both `ui-specifications.md` files and fail on any difference. It is a five-line
script and it is the only automated defense this phase has against the two clients' screen
specifications drifting. Specified as a job in
[devops-pipeline.md](./devops-pipeline.md).
