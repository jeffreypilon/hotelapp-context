# Module Registry — React

Inventory of `hotelapp-client-react`'s modules and what each owns.

**This is bookkeeping, not design.** Everything here is derived from the folder layout in
[architecture-specification.md](./architecture-specification.md#folder-layout) and the screen list in
[ui-specifications.md](./ui-specifications.md). If this document and either of those disagree, they are right
and this is stale.

Its purpose is orientation: a developer or coding agent asking "where does X live" should find the answer here
without reading the tree.

---

## Core modules

| Module | Owns | Must not |
|--------|------|----------|
| `main.tsx` | Provider composition, router mount | Contain application logic |
| `App.tsx` | The S0 shell: header, nav, footer, user area | Fetch anything but the session |
| `routes.tsx` | The entire route tree and guard placement | Be split across files — one tree, one place |
| `config/env.ts` | Runtime config resolution and validation | Be read anywhere but through its exports |
| `session/AuthProvider.tsx` | `user`, `isResolved`, `role`, `propertyId` from the session query | Hold state of its own — it is a typed read over the query cache |
| `guards/` | `RequireAuth`, `RequireStaff`, `RequireManager` | Be treated as access control — the API is |
| `lib/format.ts` | **All** money, date, and percentage formatting | Have a second implementation anywhere |
| `lib/logger.ts` | Console logging with redaction | Log bodies, cards, or passwords |
| `lib/validation/` | Zod schemas shared across forms | Duplicate a server rule with different wording |

---

## The API layer

| Module | Owns |
|--------|------|
| `api/client.ts` | `credentials: 'include'`, base URL, `problem+json` → `ApiError`, **the `401` rule** |
| `api/errors.ts` | The `ApiError` type and problem-code constants |
| `api/queryKeys.ts` | The key factory — the single source of every cache key |
| `api/types.ts` | Hand-written request/response types mirroring the contract |
| `api/endpoints/` | One module per contract resource; typed functions, no React |

`api/endpoints/` modules, and the endpoints each covers:

| Module | Endpoints |
|--------|-----------|
| `auth.ts` | `POST /auth/register`, `/auth/login`, `/auth/logout`, `GET /auth/me` |
| `properties.ts` | `GET /properties`, `/properties/{id}`, `/properties/{id}/room-types` |
| `roomTypes.ts` | `GET /room-types/{id}` |
| `reference.ts` | `GET /amenities`, `/rate-categories` |
| `availability.ts` | `GET /availability` |
| `me.ts` | `GET /me`, `PATCH /me`, `PUT /me/password` |
| `reservations.ts` | `GET`/`POST /reservations`, `GET`/`PATCH /reservations/{id}`, `POST /reservations/{id}/cancel` |
| `adminReservations.ts` | `GET /admin/reservations`, `/admin/reservations/{id}`, check-in, check-out, cancel |
| `adminInventory.ts` | Admin properties, room types, amenities, photos, rooms |
| `ratePlans.ts` | `GET`/`PUT /admin/properties/{id}/rate-plans` |
| `calendar.ts` | `GET /admin/properties/{id}/calendar` |
| `reports.ts` | `GET .../reports/occupancy`, `.../reports/arrivals` |

`GET /health` has no endpoint module — nothing in the UI consumes it. It is an operational endpoint, noted
here so its absence is a recorded decision rather than an oversight.

---

## Features

One folder per feature, each owning its screens, feature-local components, and query hooks. **No feature
imports from another feature** — the rule that keeps this layout navigable, enforced by ESLint.

| Feature | Screens | Primary hooks |
|---------|---------|---------------|
| `properties/` | S1 property list, S2 property detail | `usePropertiesQuery`, `usePropertyQuery`, `useRoomTypesQuery`, `useRoomTypeQuery` |
| `search/` | S3 search and results | `useAvailabilityQuery`, `useAmenitiesQuery`, `useRateCategoriesQuery` |
| `booking/` | S4 summary, S6 payment, S7 confirmation | `useCreateReservation`, `useReservationQuery` |
| `auth/` | S5 login and registration | `useLogin`, `useRegister`, `useLogout` |
| `account/` | S8a profile, S8b reservations, S8c detail, S8d password | `useMeQuery`, `useUpdateMe`, `useChangePassword`, `useMyReservationsQuery`, `useModifyReservation`, `useCancelReservation` |
| `admin-reservations/` | S9 list, S9b detail, S10 arrivals | `useAdminReservationsQuery`, `useAdminReservationQuery`, `useCheckIn`, `useCheckOut`, `useAdminCancel`, `useArrivalsQuery` |
| `admin-calendar/` | S11 calendar | `useCalendarQuery` |
| `admin-inventory/` | S12a–S12e properties, room types, photos, rooms | `useAdminPropertiesQuery`, `useSaveProperty`, `useSaveRoomType`, `useSetAmenities`, `usePhotos`, `useSaveRoom` |
| `admin-rate-plans/` | S13 rate plans | `useRatePlansQuery`, `useSaveRatePlans` |
| `admin-reports/` | S14a occupancy, S14b arrivals report | `useOccupancyQuery`, `useArrivalsQuery` |

**Screen components own queries; child components take data as props.** A presentational component calling a
hook is the first step toward the tangle the feature layout exists to prevent.

---

## Shared components

`components/ui/` — presentational only. **No router, no session, no query client.** That is what makes them
testable without a provider tree.

| Component | Notes |
|-----------|-------|
| `Button` | Variants, loading state, disabled |
| `Input`, `Select`, `Textarea`, `Checkbox` | Label, error, and helper text wired for accessibility |
| `MoneyInput` | Two decimals, **string value** — never a `number` |
| `DateInput`, `DateRangeInput` | Guest-count and stay-length constraints live in the schema, not here |
| `Dialog` | Focus trap, focus restore on close |
| `Badge` | Status and role badges — "Front Desk", "Manager", reservation statuses |
| `Table` | Sortable headers, dense admin variant, stacked layout below 1024 px |
| `Pagination` | The shared envelope's page, total pages, total items |
| `Skeleton` | Layout-matching placeholders, not a spinner |
| `Tabs`, `Tooltip`, `Toast` | Tooltip content must also be keyboard-reachable |

`components/layout/` — `Header`, `Footer`, `Nav`, `AdminSidebar`, `UserMenu`, `PropertySwitcher`. The
switcher renders for Manager only, and the sidebar's Manager-only items come from the shared `can()` helper
so visibility and guards cannot disagree.

`components/feedback/` — `ErrorMessage` (takes an `ApiError` plus a `context`, renders the mapped message),
`EmptyState` (distinguishes no-data from filtered-empty), `LoadingSkeleton`, `Toast`, `ErrorBoundary` (S15).

---

## Ownership of the tricky bits

Where the things most likely to be reimplemented in the wrong place actually live:

| Concern | Sole owner |
|---------|-----------|
| The `401` rule | `api/client.ts` |
| Session bootstrap | `session/AuthProvider.tsx` |
| Money formatting | `lib/format.ts` |
| Occupancy-rate conversion to a percentage | `lib/format.ts` |
| Cancellation deadline in the property's timezone | `lib/format.ts` |
| Error code → user message | `lib/errors/messages.ts` |
| Cache keys | `api/queryKeys.ts` |
| Role comparison (rank, not membership) | one `can()` helper in `session/` |
| `Idempotency-Key` generation | the S6 payment screen, on mount — **not** per submit |
| Booking context across the login detour | the URL, via `useSearchParams` |
| Calendar segment → cell expansion | `admin-calendar/`, memoized |

Every row is something that could plausibly be written twice. The second copy is how an invariant breaks
quietly, which is why this table exists rather than being left implicit.
