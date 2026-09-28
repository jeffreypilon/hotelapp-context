# Phase 7 Step 6 — reservation history, modify, cancel (S8b/S8c)

In progress as of 2026-09-27 — not yet run through Copilot. Scoped to S8b/S8c only, mirroring the
backend's own split of this item into two steps (Step 5: reservation management; Step 6:
profile/password) rather than bundling all four S8 sub-screens into one prompt. S8a (profile) and
S8d (password) are a separate, lighter step to follow.

```
HotelApp — React Phase 7, Step 6: guest reservation history, modify, cancel (S8b/S8c)

Read first: shared/api-contracts.md (GET /reservations, GET /reservations/{id} — already used
since Step 5, PATCH /reservations/{id}, POST /reservations/{id}/cancel), stacks/react/
ui-specifications.md's S8b/S8c entries (S8a/S8d are a separate step, not this one),
stacks/react/state-management.md's mutation-invalidation table, stacks/react/error-handling.md's
409 table (CANCELLATION_WINDOW_CLOSED, INVALID_STATUS_TRANSITION, ROOM_UNAVAILABLE). Stay in
stacks/react/ only.

CURRENT STATE (confirmed by reading the actual repo — Phase 7 Step 5 is commit f746c07):
`api/endpoints/reservations.ts` has `createReservation`/`getReservation` only.
`api/types.ts`'s `Reservation` type already matches both `POST /reservations` and
`GET /reservations/{id}`'s full shape — reuse it for this screen's detail view and the `PATCH`
response, which is the same shape. `qk.reservation(id)` already exists; there is no
`qk.reservations(params)` list key yet. `RequireAuth` already wraps the booking-flow routes; this
step's routes join that same group. No `/account` routes exist.

SCOPE — S8b (reservation list) and S8c (detail, modify, cancel) only. Do NOT build S8a (profile)
or S8d (password) — that's the next step. Do NOT touch admin.

1. api/types.ts: `ReservationSummary` — **a narrower shape than `Reservation`**, per
   `GET /reservations`'s own contract text: `id`, `confirmationNumber`, `status`,
   `property: {id, name}`, `roomType: {code, name}`, `checkInDate`, `checkOutDate`, `nights`,
   `totalAmount`, `currency`, `cancellation`. This is the third time this exact pattern has shown
   up (`PropertyRoomTypeSummary` vs `RoomType` in Step 2, `ReservationPricing` vs `Pricing` in
   Step 5) — a list/summary endpoint and its corresponding detail endpoint are never the same
   shape in this API. Don't reuse `Reservation` here and assume the extra fields will just be
   `undefined`; type it from the contract text directly.
   Also add `CancelReservationResponse` (`id`, `confirmationNumber`, `status`, `cancelledAt`,
   `wasRefundable`, `refund: {status, amount, currency} | null`) — distinct from `Reservation`
   again, since cancel's response is deliberately smaller.
   `PatchReservationRequest` (`checkInDate?`, `checkOutDate?`, `numGuests?`, `rateCategory?`).

2. api/endpoints/reservations.ts: add `listReservations(params)` (`status?: string[]`, `from?`,
   `to?`, `page?`, `pageSize?`, `sort?`), `patchReservation(id, body)`, `cancelReservation(id,
   reason?)`.
   api/queryKeys.ts: add `reservations(params)`.

3. features/account/ (new — per architecture-specification.md's folder layout, `account/` holds
   S8a–S8d; this step only populates the b/c parts of it).
   ReservationListScreen.tsx at `/account/reservations`. Four tabs, all the same
   `GET /reservations` call with different params, URL-driven like every prior list in this app:
   **Upcoming** (`?from=<today>`), **Past** (`?to=<today>`), **Cancelled**
   (`?status=CANCELLED`), **All** (no filter). Default sort `checkInDate:desc`. "Today" here is
   the browser's local calendar date — there's no single property timezone to anchor it to, since
   a guest's reservations can span properties. Row: hotel name, room type, dates (via
   `formatDate(..., "dense")`), nights, status badge (color per ui-specifications.md's table:
   neutral-positive Confirmed, active Checked in, muted Checked out, muted+strikethrough
   Cancelled), total (`formatMoney`), confirmation number, "View" link to S8c. Distinct empty
   copy per tab, exactly as specified — this is not one generic "no reservations" string reused
   four times.

4. features/account/ReservationDetailScreen.tsx at `/account/reservations/:reservationId`.
   Reuses `getReservation`/`qk.reservation(id)` — already built for S7, same data, richer actions.
   Everything S7 already renders, plus the action area **gated on `status` and
   `cancellation.isRefundableNow`** — use that field directly rather than recomputing "now <
   deadline" client-side; the server already evaluated it at request time and is authoritative,
   avoiding any client-clock-skew question. Exactly per the status/action table in
   ui-specifications.md: Confirmed+refundable → "Change dates"/"Cancel reservation"; Confirmed,
   not refundable → no actions, a note, plus "Cancel reservation (non-refundable)"; Checked
   in/out/Cancelled → no actions, a status-appropriate note.

   **Cancel dialog**: use the native `<dialog>` element rather than hand-rolling focus trapping —
   it gives you the modal semantics ui-specifications.md's implementation note asks for
   ("controlled... with focus trapping; return focus to the invoking button on close") without a
   dependency, consistent with this repo's "no component library, platform primitives" preference.
   States the refund outcome explicitly before the guest confirms — "You'll receive a full refund
   of {total}." or "This cancellation is non-refundable. You will not receive a refund." — using
   `wasRefundable`'s pre-cancel equivalent (`cancellation.isRefundableNow`) to pick the wording.
   Confirm label "Cancel reservation", dismiss label "Keep reservation" — never "Cancel"/"OK".

   **Change-dates dialog**: same native-`<dialog>` approach, a small date/guest (and rate-category)
   form, `PATCH /reservations/{id}`. On success, compare the new `totalAmount` to the one already
   on screen — if it differs, say so: "Your new total is {new} (was {old})." If not, just show
   the confirmation without the comparison line.

   Errors: `CANCELLATION_WINDOW_CLOSED` → "Changes are no longer available for this reservation.";
   `ROOM_UNAVAILABLE` → "Those dates aren't available."; `INVALID_STATUS_TRANSITION` →
   **invalidate/refetch `qk.reservation(id)` and re-render the actions from the fresh data** —
   this is explicitly what ui-specifications.md asks for here (the client's view of state is
   stale), not just showing an error message and leaving the stale actions on screen.

   Mutation invalidation per state-management.md's table: both `PATCH` and `cancel` invalidate
   the specific `qk.reservation(id)`, the `["reservations"]` subtree, and `["availability"]`. The
   admin-reservations and calendar targets that table also lists don't exist yet — nothing to do
   there.

5. routes.tsx: add both routes inside the existing `<RequireAuth>` group alongside the
   booking-flow routes.

NOT in scope: S8a, S8d, admin. Don't scaffold those folders speculatively.

Per the standing rule already in this repo's Copilot instructions: any new pure logic (the
tab-to-query-param mapping, the totalAmount-comparison formatter, if you factor either out) ships
with a unit test in this same commit — this is not optional. Commit and push once verification
passes, per the other standing rule, regardless of whether this paragraph existed.

VERIFICATION: npm run lint / typecheck / test:run / build all green. Manually, using the guest
account and reservation created during Step 5's verification: the reservation appears under
Upcoming with the right status badge and total; Cancelled/Past tabs show their distinct empty
copy for an account with only one upcoming booking; open the detail view and change the dates to
a range with a different rate — confirm the new-total comparison line appears; cancel the
(still-refundable) reservation and confirm the dialog states the refund amount before you
confirm, and that after cancelling the list's Cancelled tab now shows it with strikethrough
dates. Flag judgment calls in code and summarize them at the end, same discipline as every prior
step.
```
