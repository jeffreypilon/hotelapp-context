# Phase 7 Step 5 — booking flow (summary, payment, confirmation)

Produced `hotelapp-client-react@9acb688`, `f746c07`.

```
HotelApp — React Phase 7, Step 5: booking flow (summary, payment, confirmation)

Read first: shared/api-contracts.md (POST /reservations — the full request/response shape,
Idempotency-Key semantics, error codes; GET /reservations/{reservationId} for direct loads),
stacks/react/ui-specifications.md's S4/S6/S7 entries, stacks/react/state-management.md (the
mutation-invalidation table, and how a mutation's response should warm the cache rather than
trigger a redundant fetch — same pattern Step 4 already used for login/register),
stacks/react/security-implementation.md's "Payment data" section, stacks/react/error-handling.md's
402/409/404 tables. Stay in stacks/react/ only.

CURRENT STATE (confirmed by reading the actual repo — Phase 7 Step 4 is commit 69f6924):
`ResultCard.selectRoom()` already navigates to `/properties/:propertyId/book` carrying
`roomTypeId` (a UUID, NOT `roomTypeCode`), `checkInDate`, `checkOutDate`, `numGuests`,
`rateCategory` — that route 404s to S15 today. `RequireAuth`/`RequireStaff`/`RequireManager`
exist (Step 4) but are wired into `routes.tsx` nowhere yet — this is their first real consumer.
`useAvailability` and `useProperty` already exist and both accept the params this step needs
without modification. `lib/format.ts`'s `formatDate` and `formatTimestamp` exist but have never
been called by any screen yet — this is genuinely the first step that needs them, and neither
currently matches the spec exactly (see point 1). No `reservation` entry exists in
`api/queryKeys.ts`. No `features/booking/` folder exists.

SCOPE — item 5 only: S4 (booking summary), S6 (payment form), S7 (confirmation). Do NOT build S8
(account/history) or anything admin.

1. Fix `lib/format.ts` first, since this step is what actually exercises it:
   - `formatDate` needs a full form and a dense form per ui-specifications.md §1 ("Sat, Nov 14,
     2026" in full; "Nov 14" in dense tables) — current implementation has neither exactly.
     Full: `{ weekday: "short", month: "short", day: "numeric", year: "numeric", timeZone: "UTC" }`.
     Dense: `{ month: "short", day: "numeric", timeZone: "UTC" }`. Add a parameter rather than a
     second function with a different name — this is still "the one place," just with an option.
   - `formatTimestamp` is missing `timeZoneName: "short"` — without it, the cancellation deadline
     can't show "EST"/"PST"/etc., which ui-specifications.md requires by name for this exact field
     ("the only timestamp that represents a real moment").

2. api/types.ts: `PaymentInput` (cardholderName, cardNumber, expiryMonth, expiryYear, cvv),
   `CreateReservationRequest` (roomTypeId, checkInDate, checkOutDate, numGuests, rateCategory,
   payment), `Reservation` (the full `POST /reservations` response shape — id,
   confirmationNumber, status, property, roomType, room, checkInDate, checkOutDate, nights,
   numGuests, rateCategory, pricing, cancellation, payment, bookedAt).
   api/endpoints/reservations.ts: `createReservation(body, idempotencyKey)`,
   `getReservation(id)`.
   api/queryKeys.ts: add `reservation(id)`.

3. features/booking/hooks/useBookingContext.ts — a SHARED hook, since S4 and S6 both need the
   same "condensed booking summary and the total" (S6's own words). Reads `propertyId` from
   `useParams` and `roomTypeId`/`checkInDate`/`checkOutDate`/`numGuests`/`rateCategory` from
   `useSearchParams`, then calls the EXISTING `useProperty(propertyId)` and `useAvailability(...)`
   hooks. **Do not filter `useAvailability` by `roomTypeCode`** — the URL only carries
   `roomTypeId`, and `room_type_code` is deliberately not unique per property (a property can
   offer two "KING" room types at different rates), so filtering by code could match the wrong
   one. Call availability with just `propertyId`/dates/`numGuests`/`rateCategory`, then find
   `.data.find(r => r.roomType.id === roomTypeId)` client-side. This also satisfies S4's
   "re-validation on arrival" requirement for free — the same call that builds the summary is the
   live availability check. If no match is found in the results, that's the "no longer available"
   case, not an error.

4. features/booking/BookingSummaryScreen.tsx (S4) at `/properties/:propertyId/book`. Summary
   card (hotel name/address from `useProperty`, room type name/bed config, dates via
   `formatDate(..., "full")` with nights count, guests, rate category label when not NONE, price
   breakdown `nightlyRate × nights = total` via `formatMoney`), then the cancellation policy in
   plain language using the fixed `formatTimestamp` for the deadline. "Continue to payment"
   navigates to `/properties/:propertyId/book/payment` carrying the same query params forward — no
   pricing is passed through props/state, since S6 re-derives it itself via the same shared hook.
   Not-found state (no matching result from point 3): "Those dates are no longer available." +
   "Back to search", "Continue to payment" disabled/absent.

5. features/booking/PaymentScreen.tsx (S6) at `/properties/:propertyId/book/payment`. Demo-payment
   banner (non-dismissible, exact wording from ui-specifications.md). Fields: cardholder name,
   card number, expiry month/year, CVV, via React Hook Form + a new
   `lib/validation/paymentSchema.ts` (same location convention as Step 4's `authSchemas.ts`) —
   Luhn check on the card number, expiry in the future, CVV 3-4 digits, cardholder name required.
   Condensed booking summary + total from the same shared hook as S4. Collapsible "Test card
   numbers" panel listing `4242 4242 4242 4242` (succeeds) and any number ending `0000` (declines).
   Card-number grouping-of-four formatting and a leading-digit brand indicator are nice-to-have
   polish, not required for this step to be done — skip them if time/budget is tight rather than
   spending on them before the functional path works.

   **Idempotency-Key**: `useRef(crypto.randomUUID())`, created once on mount — stable across
   re-renders AND repeat submit attempts. An inline `crypto.randomUUID()` inside the submit
   handler is the exact bug this guards against (a double-click would then create two
   reservations instead of retrying safely under one key).

   **THE GENUINELY SUBTLE PART**: ui-specifications.md's implementation note says to block
   navigation while submitting with "a `beforeunload` listener plus React Router's blocker." The
   blocker half (`useBlocker`) requires a **data router** (`createBrowserRouter`/`RouterProvider`)
   — Step 2 deliberately moved this app OFF the data router and onto declarative `<BrowserRouter>`
   + `<Routes>` for the room-type modal's background-location pattern, and `useBlocker` doesn't
   work under plain `<BrowserRouter>`. Don't spend time trying to make it work — use the
   `beforeunload` listener (covers tab-close/refresh/external navigation) plus disabling the form
   and showing the "Confirming your booking…" overlay (which removes any in-page navigation
   affordance while submitting) as the practical substitute, and say so in a comment so a future
   step doesn't rediscover the same incompatibility from scratch.

   On submit: `POST /reservations` with the Idempotency-Key header. `201`: warm the cache with
   `queryClient.setQueryData(qk.reservation(response.id), response)` (same pattern Step 4 used for
   login/register — avoids S7 needing a redundant fetch when it arrives right after this), then
   `navigate(..., { replace: true })` to `/reservations/{id}/confirmation` so Back can't
   resubmit. Also invalidate the `["availability"]` query subtree per state-management.md's
   mutation table — the other two invalidation targets it lists (`reservations`, `admin
   reservations`/calendar) don't exist yet, nothing to do there. Errors: `PAYMENT_DECLINED`
   field-level on `cardNumber`, form stays filled; `ROOM_UNAVAILABLE` form-level prominent + "Back
   to search"; `VALIDATION_FAILED` field-level; `NOT_FOUND` "That room is no longer offered." +
   link back to the property. `401` is already handled globally, nothing screen-specific needed.
   Never let card number/CVV/expiry reach a log, the query cache, a URL, or survive past unmount —
   component-local form state only.

6. features/booking/ConfirmationScreen.tsx (S7) at
   `/reservations/:reservationId/confirmation`. `useQuery(qk.reservation(id), () =>
   getReservation(id))` — benefits from the pre-warmed cache on arrival from S6, does a real fetch
   on a direct load/share/reload. Confirmation number as the most prominent element, large
   monospace, with a copy button (`navigator.clipboard.writeText`). Full details per the contract
   response, cancellation deadline via the fixed `formatTimestamp`. `404` (non-owner or unknown):
   same not-found treatment already established, since the API returns `404` for another guest's
   reservation by design, not `403`.

7. routes.tsx: wrap S4/S6/S7 in `<Route element={<RequireAuth />}>` per
   architecture-specification.md's route tree — this is the first time `RequireAuth` actually
   guards anything. The anonymous → login → back-to-here round trip should just work already,
   since booking context lives entirely in the URL and `RequireAuth`'s `next=` param already
   captures the full path and query string.

NOT in scope: S8, admin. Don't scaffold their folders speculatively.

VERIFICATION: npm run lint / typecheck / test:run / build all green. Manually, logged in as the
guest account created in Step 4, from Harborview Grand with the seeded KING room type: reach S4
and see the correct room/price/cancellation-deadline-with-zone-abbreviation; continue to payment,
submit `4242 4242 4242 4242`, land on S7 with a confirmation number; reload S7's URL directly (a
fresh tab, not a reload of one that's already navigated there — the BFCache lesson from Step 2)
and confirm it still renders from a real fetch; go back to S6 and submit a card ending `0000`,
confirm the field-level decline message and that the form kept its values; log out mid-flow (open
a fresh incognito tab) and hit `/properties/<id>/book` directly — confirm it redirects to
`/login?next=...` and that logging in returns you to S4 with the booking context intact.

Flag judgment calls in code and summarize them at the end, same discipline as every prior step.
```

---

## Follow-up (same step, after review): standing rule + cancellationDeadline tests

Not a Copilot prompt — done directly in Claude Code after Step 5's review found an 856-line
commit with one test touched. Recorded here because it produced the second commit
(`f746c07`) attributed to this step above.

- Added `src/lib/cancellationDeadline.test.ts`, pinned to `acceptance-criteria.md`'s own
  AC-CX-04 (baseline `America/New_York`, and `America/Los_Angeles`) and AC-CX-05 (the
  DST-transition case) worked examples.
- Added a standing rule to `hotelapp-client-react/.github/copilot-instructions.md`: any new pure
  function with non-obvious logic (date/money arithmetic, validation algorithms, anything
  hand-verified against a spec's worked examples) ships with unit tests in the same commit,
  regardless of what a given step's prompt says.
