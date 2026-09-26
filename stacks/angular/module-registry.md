# Module Registry — Angular

Inventory of `hotelapp-client-angular`'s modules and what each owns.

**This is bookkeeping, not design.** Everything here is derived from the folder layout in
[architecture-specification.md](./architecture-specification.md#folder-layout) and the screen list in
[ui-specifications.md](./ui-specifications.md). If this document and either of those disagree, they are right
and this is stale.

Its purpose is orientation: a developer or coding agent asking "where does X live" should find the answer here
without reading the tree.

> **"Module" here means a folder or a provider, not an `NgModule`.** This client is standalone throughout —
> there are no `NgModule` declarations for new code, per
> [coding-standards.md](./coding-standards.md#components). The word is kept because it is the filename this
> document is required to have.

---

## Core modules

| Module | Owns | Must not |
|--------|------|----------|
| `main.ts` | `bootstrapApplication` with `appConfig` | Contain application logic |
| `app/app.config.ts` | Providers, the interceptor, `provideAppInitializer`, zoneless change detection | Be bypassed by a component providing its own `HttpClient` |
| `app/app.component.ts` | The S0 shell: header, nav, footer, user area | Fetch anything — the session is resolved before it renders |
| `app/app.routes.ts` | The entire route tree, guard placement, lazy boundaries, route-level store providers | Be split across files — one tree, one place (feature `*.routes.ts` files are loaded from it) |
| `core/config/env.ts` | Runtime config resolution and validation | Be read anywhere but through its exports |
| `core/session/session.store.ts` | `user`, `isResolved`, `role`, `propertyId` as signals | Be duplicated by a second session source |
| `core/session/session.initializer.ts` | The `GET /auth/me` bootstrap | **Reject on `401`** — it must resolve, or the app never starts |
| `core/guards/` | `authGuard`, `staffGuard`, `managerGuard` | Be treated as access control — the API is |
| `shared/util/format.ts` | **All** money, date, and percentage formatting | Have a second implementation anywhere |
| `shared/util/logger.ts` | Console logging with redaction | Log bodies, cards, or passwords |
| `shared/util/validation/` | Validators shared across forms | Duplicate a server rule with different wording |

---

## The API layer

| Module | Owns |
|--------|------|
| `core/api/http.interceptor.ts` | **`withCredentials: true`**, base URL, `problem+json` → `ApiError`, **the `401` rule** |
| `core/api/api-error.ts` | The `ApiError` type and problem-code constants |
| `core/api/types.ts` | Hand-written request/response types mirroring the contract |
| `core/api/*.api.ts` | One injectable service per contract resource; typed `Observable`s, no state |

API services and the endpoints each covers:

| Service | Endpoints |
|---------|-----------|
| `auth.api.ts` | `POST /auth/register`, `/auth/login`, `/auth/logout`, `GET /auth/me` |
| `properties.api.ts` | `GET /properties`, `/properties/{id}`, `/properties/{id}/room-types` |
| `room-types.api.ts` | `GET /room-types/{id}` |
| `reference.api.ts` | `GET /amenities`, `/rate-categories` |
| `availability.api.ts` | `GET /availability` |
| `me.api.ts` | `GET /me`, `PATCH /me`, `PUT /me/password` |
| `reservations.api.ts` | `GET`/`POST /reservations`, `GET`/`PATCH /reservations/{id}`, `POST /reservations/{id}/cancel` |
| `admin-reservations.api.ts` | `GET /admin/reservations`, `/admin/reservations/{id}`, check-in, check-out, cancel |
| `admin-inventory.api.ts` | Admin properties, room types, amenities, photos, rooms |
| `rate-plans.api.ts` | `GET`/`PUT /admin/properties/{id}/rate-plans` |
| `calendar.api.ts` | `GET /admin/properties/{id}/calendar` |
| `reports.api.ts` | `GET .../reports/occupancy`, `.../reports/arrivals` |

`GET /health` has no service — nothing in the UI consumes it. It is an operational endpoint, noted here so its
absence is a recorded decision rather than an oversight.

---

## Features

One folder per feature, each owning its routes, its store, its pages, and its feature-local components. **No
feature imports from another feature** — the rule that keeps this layout navigable, enforced by ESLint.

| Feature | Screens | Store | Provided at |
|---------|---------|-------|-------------|
| `properties/` | S1 property list, S2 property detail | `PropertiesStore` | route |
| `search/` | S3 search and results | `AvailabilityStore` | route |
| `booking/` | S4 summary, S6 payment, S7 confirmation | `BookingStore` | route |
| `auth/` | S5 login and registration | — (uses `SessionStore`) | — |
| `account/` | S8a profile, S8b reservations, S8c detail, S8d password | `ProfileStore`, `MyReservationsStore` | route |
| `admin-reservations/` | S9 list, S9b detail, S10 arrivals | `AdminReservationsStore` | route |
| `admin-calendar/` | S11 calendar | `CalendarStore` | route |
| `admin-inventory/` | S12a–S12e properties, room types, photos, rooms | `InventoryStore` | route |
| `admin-rate-plans/` | S13 rate plans | `RatePlansStore` | route |
| `admin-reports/` | S14a occupancy, S14b arrivals report | `ReportsStore` | route |

Two root-provided stores, the only ones that outlive a route:

| Store | Why root |
|-------|----------|
| `SessionStore` | The one genuinely global piece of state |
| `ReferenceDataStore` | `amenities` and `rate-categories` are fetched once per session and never refetched |

**Route-level provision is load-bearing**, not a style choice: it is what discards feature state on navigation
and gives the "refetch on feature entry" caching policy in
[state-management.md](./state-management.md#caching-made-explicit) for free.

**Page components inject the store; presentational children take `input()`s and inject nothing.**

---

## Shared components

`shared/ui/` — presentational only. **No `Router`, no `SessionStore`, no API service.** That is what makes
them testable without a `TestBed` provider tree.

| Component | Notes |
|-----------|-------|
| `app-button` | Variants, loading state, disabled |
| `app-input`, `app-select`, `app-textarea`, `app-checkbox` | Label, error, and helper text wired for accessibility |
| `app-money-input` | Two decimals, **string value** — never a `number` |
| `app-date-input`, `app-date-range-input` | Guest-count and stay-length constraints live in the validators, not here |
| `app-dialog` | Built on **Angular ARIA** — focus trap and `aria-modal` from the framework, not hand-rolled |
| `app-badge` | Status and role badges — "Front Desk", "Manager", reservation statuses |
| `app-table` | Sortable headers, dense admin variant, stacked layout below 1024 px |
| `app-pagination` | The shared envelope's page, total pages, total items |
| `app-skeleton` | Layout-matching placeholders, not a spinner |
| `app-tabs`, `app-tooltip`, `app-toast` | Tabs on Angular ARIA. Tooltip content must also be keyboard-reachable |

`shared/layout/` — `app-header`, `app-footer`, `app-nav`, `app-admin-sidebar`, `app-user-menu`,
`app-property-switcher`. The switcher renders for Manager only, and the sidebar's Manager-only items come from
the shared `can()` helper so visibility and guards cannot disagree.

`shared/feedback/` — `app-error-message` (takes an `ApiError` plus a `context`, renders the mapped message),
`app-empty-state` (distinguishes no-data from filtered-empty), `app-loading-skeleton`, `app-toast`.

`shared/pipes/` — `money`, `calendarDate`, `denseDate`, `propertyDateTime`, `percentRate`. Each is a thin pipe
over `shared/util/format.ts`; **no pipe implements its own formatting**, which is how the single-formatter rule
survives contact with templates.

---

## Ownership of the tricky bits

Where the things most likely to be reimplemented in the wrong place actually live:

| Concern | Sole owner |
|---------|-----------|
| The `401` rule | `core/api/http.interceptor.ts` |
| `withCredentials: true` | the same interceptor — `HttpClient` defaults it to `false` |
| Session bootstrap | `core/session/session.initializer.ts` |
| Money formatting | `shared/util/format.ts`, via the `money` pipe |
| Occupancy-rate conversion to a percentage | `shared/util/format.ts`, via `percentRate` |
| Cancellation deadline in the property's timezone | `shared/util/format.ts`, via `propertyDateTime` |
| Error code → user message | `shared/util/errors/messages.ts` |
| Role comparison (rank, not membership) | one `can()` helper in `core/session/` |
| `Idempotency-Key` generation | the S6 payment component's field initializer — **not** the submit handler |
| Booking context across the login detour | the URL, via router query parameters |
| Calendar segment → cell expansion | `admin-calendar/`, in a `computed()` |
| Request cancellation on rapid re-search | `switchMap` inside each store's `rxMethod` — never `mergeMap` |

Every row is something that could plausibly be written twice. The second copy is how an invariant breaks
quietly, which is why this table exists rather than being left implicit.
