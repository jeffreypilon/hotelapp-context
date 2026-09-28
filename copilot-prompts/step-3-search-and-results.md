# Phase 7 Step 3 — search and results

Produced `hotelapp-client-react@83cb778`.

```
HotelApp — React Phase 7, Step 3: search and results (item 3)

Read first: shared/api-contracts.md (GET /availability's full parameter table and response
shape, GET /amenities, GET /rate-categories), stacks/react/ui-specifications.md's S3 entry,
stacks/react/error-handling.md sections 1-2 (the VALIDATION_FAILED field-code table — this
screen's client-side pre-validation reuses that exact wording), stacks/react/state-management.md
(per-query staleTime overrides: availability is 0, amenities/rate-categories are Infinity).
Stay in stacks/react/ only.

CURRENT STATE (confirmed by reading the actual repo — Phase 7 Step 2 is commit 96783bc):
PropertyDetailScreen's search form and each RoomTypeCard's "Check availability" button already
navigate to `/properties/:propertyId/search?checkInDate=&checkOutDate=&numGuests=&roomTypeCode=`
— that route doesn't exist yet, so it currently 404s to S15. Note the form has no `required` on
its date inputs, so genuinely empty `checkInDate`/`checkOutDate` can arrive at this screen — S3
has to handle that, not assume dates are always present. `api/queryKeys.ts` has no
`availability`/`amenities`/`rateCategories` entries yet. No `features/search/` folder exists.

PRE-STEP: seed data. Physical room inventory (`rooms`) is still zero rows for both seeded room
types from Step 2 — `GET /availability` will correctly return an empty result for every search
until some exist (this is real behavior, not a bug, but it means nothing is testable). Run
against the `hotelapp` database first:

  INSERT INTO rooms (property_id, room_type_id, room_number, floor) VALUES
    ('01a0e22c-ac6d-7a75-89f2-030097892f4f', '01a0e55e-4703-7643-953f-6a43f080563d', '201', 2),
    ('01a0e22c-ac6d-7a75-89f2-030097892f4f', '01a0e55e-4703-7643-953f-6a43f080563d', '202', 2),
    ('01a0e22c-ac6d-7a75-89f2-030097892f4f', '01a0e55e-4703-7643-953f-6a43f080563d', '203', 2),
    ('01a0e22c-ac6d-7a75-89f2-030097892f4f', '01a0e55e-4703-7643-953f-6a43f080563d', '204', 2),
    ('01a0e22c-ac6d-7a75-89f2-030097892f4f', '01a0e55e-4705-70d3-998c-71c21a833f87', '301', 3),
    ('01a0e22c-ac6d-7a75-89f2-030097892f4f', '01a0e55e-4705-70d3-998c-71c21a833f87', '302', 3);

  -- Optional but recommended: without this, the discounted-pricing display path (struck-through
  -- base rate) is never actually exercised, only the undiscounted default.
  INSERT INTO rate_plans (property_id, rate_category, discount_percent)
  VALUES ('01a0e22c-ac6d-7a75-89f2-030097892f4f', 'AAA_CAA', 10.00);

That's deliberately 4 KING rooms (above the "show a count" threshold — scarcity text should NOT
appear) and 2 SUITE rooms (within it — "Only 2 rooms left" should appear). Search Harborview with
`numGuests=3` should exclude KING (maxOccupancy 2) and return only SUITE (maxOccupancy 4) — a
free way to confirm the occupancy filter actually filters.

SCOPE — S3 only. Do NOT build S4 (booking summary), S5 (login), or anything past this screen.

1. api/types.ts: add AvailabilityRoomType (id, code, name, maxOccupancy, bedConfiguration,
   isAccessible, amenities: Amenity[], primaryPhotoUrl), Pricing (rateCategory, baseRate,
   discountPercent, nightlyRate, nights, totalAmount, currency), AvailabilityResult ({roomType,
   pricing, availableRoomCount}), AvailabilityResponse ({data, pagination}). Also
   RateCategoryOption ({value, label}) and AmenityReference ({code, name, sortOrder}) for the two
   reference endpoints — don't reuse the existing `Amenity` type for the reference-list response;
   it's a different shape (carries `sortOrder`, used for filter-list ordering) serving a different
   purpose than a room type's embedded amenity list.

2. api/endpoints/availability.ts: getAvailability(params) — propertyId, checkInDate,
   checkOutDate, numGuests, roomTypeCode (repeatable), rateCategory, accessibleOnly, amenityCode
   (repeatable), minNightlyRate/maxNightlyRate, sort, page, pageSize. Repeatable params need
   `searchParams.append()` per value, not `.set()` — a `.set()` would silently keep only the last
   selected room type or amenity.
   api/endpoints/reference.ts: getAmenities(), getRateCategories().

3. api/queryKeys.ts: add availability(params), amenities(), rateCategories() per
   state-management.md's `qk` factory. Every parameter that changes the availability result
   belongs in that key -- this is the exact bug class that document calls out as "the most likely
   cache bug in this application."

4. Hooks: useAvailability (staleTime: 0 -- explicitly override the QueryClient's 30s global
   default; this is the one query that must never serve a cached answer, per
   state-management.md), useAmenities/useRateCategories (staleTime: Infinity -- fixed reference
   data, fetch once per session).

5. features/search/SearchScreen.tsx at /properties/:propertyId/search (new route in routes.tsx).
   Everything lives in the URL via useSearchParams, matching S1's established pattern -- but this
   time apply the lesson from Step 1's own bug directly: when a filter change updates the URL,
   diff against the CURRENT params (not a stale closure) so an unrelated param (like an
   already-present roomTypeCode from the S2 handoff) never gets silently dropped by an unrelated
   filter's debounce effect. This is the same bug class Step 1 found and fixed for `page`; don't
   reintroduce it here for a different param.

   Search form: check-in/check-out dates, guests (stepper, min 1), rate-category <select>
   populated from GET /rate-categories (labels from the API, never hardcoded) with a "Clear
   selection" action resetting to NONE. Filters (sidebar at wide viewports, collapsible below):
   room type multi-select, amenities multi-select from GET /amenities, accessible-only toggle,
   nightly-rate min/max (debounce ~300ms before writing to the URL, same pattern as S1's text
   inputs). Sort: nightlyRate asc (default), nightlyRate desc, maxOccupancy, name.

   Client-side pre-validation, before any request, using error-handling.md's exact field-code
   messages (AFTER_CHECK_IN, PAST_DATE, MAX_STAY -- the wording must match what the server would
   say): check-out after check-in; check-in not in the past; stay at most 30 nights. Distinct from
   this: if checkInDate or checkOutDate is simply empty (a real possibility, since S2's form
   doesn't require them), don't fire the request and don't show a validation error either -- there
   is nothing to validate yet. Only run the three pre-validation rules once both dates are present.

6. Result cards: photo (via safeImageUrl, falling back to initials same as S2), name, bed
   configuration, "Sleeps N", amenity icons, and the exact pricing block from ui-specifications.md:
   nightly rate after discount; base rate struck through ONLY when a discount actually applied
   (`discountPercent !== "0.00"`); "N nights · $total total"; the rate-category label only when
   not NONE. Scarcity: `availableRoomCount === 1` -> "Only 1 room left"; 2-3 -> "Only N rooms
   left"; above 3 -> nothing. Reuse `lib/format.ts`'s money formatter -- don't grow a second one.
   "Select room" navigates to `/properties/:propertyId/book` carrying roomTypeId (the availability
   response's `roomType.id`, not `code`), checkInDate, checkOutDate, numGuests, and rateCategory as
   query params. That route doesn't exist until Step 5 (booking flow), so it 404s to S15 for now --
   same deferred-target pattern as every prior step.

7. States: loading keeps the form interactive, shows 4 skeleton results. Empty is a SUCCESS, not
   an error -- a 200 with no results renders "No rooms available for these dates." plus "Try
   different dates" and "Clear filters", never the error treatment. VALIDATION_FAILED: field-level
   messages via the existing error-message mapping. NOT_FOUND: "We couldn't find that hotel." (same
   wording S2 already uses). Announce results via `aria-live="polite"`: "N room types available."

NOT in scope: S4, S5, any auth-gated screen, admin. Don't scaffold their folders speculatively.

VERIFICATION: npm run lint / typecheck / test:run / build all green. Manually, against the seeded
data: searching Harborview for a valid date range with no filters returns both room types, KING
shows no scarcity text and SUITE shows "Only 2 rooms left"; setting the AAA/CAA rate category
shows a struck-through $249.00 next to a discounted nightly rate; numGuests=3 excludes KING;
sorting by name vs. nightly rate changes order; a reload of the search URL reproduces the same
results and filter state; an empty date field doesn't fire a request or show a spurious error;
check-out before check-in shows the client-side message without ever hitting the network;
"Select room" 404s cleanly to S15.

Flag judgment calls in code and summarize them at the end, same discipline as every prior step.
```
