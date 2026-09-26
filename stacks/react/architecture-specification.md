# Architecture Specification — React

Structure of `hotelapp-client-react`: folder layout, routing, and the API client layer.

Target: **React 19.3**, TypeScript, Tailwind CSS, Vite. The system-level shape — two frontends, two
backends, one database, REST as the only integration point — is in
[architecture-overview.md](../../shared/architecture-overview.md) and is not restated here.

---

## Fixed at the system level

| Constraint | Source |
|-----------|--------|
| Browser-only SPA. **No SSR**, no Next.js, no server-rendered route | [architecture-overview.md](../../shared/architecture-overview.md#frontend-architecture-in-outline) |
| Builds to static assets; no Node process serves it in production | same |
| Backend base URL is **runtime-readable configuration**, not a compile-time constant | same |
| No client-side session storage; the session cookie is `HttpOnly` | [api-contracts.md](../../shared/api-contracts.md#client-obligations) |
| No adapter or translation layer over API responses | [architecture-overview.md](../../shared/architecture-overview.md#frontend-architecture-in-outline) |
| Three surfaces: public browsing, guest account, admin | [project-overview.md](../../shared/project-overview.md) |

That third-to-last point deserves emphasis: **if a response shape needs reshaping to be usable by
this client, the contract is wrong and gets fixed in
[api-contracts.md](../../shared/api-contracts.md)** — not worked around here. A shim in one client is
drift with extra steps.

---

## Folder layout

Organized **by feature, not by file type**. A `components/` tree holding every component in the
application is the layout that stops scaling first: work on a feature touches four directories, and
nothing shows which parts belong together.

```
src/
  main.tsx                     entry: providers, router mount
  App.tsx                      root layout (S0 shell)
  routes.tsx                   the route tree, one place

  config/
    env.ts                     runtime config access, validated once

  api/
    client.ts                  fetch wrapper: credentials, ApiError, 401 rule
    errors.ts                  ApiError type, problem-code constants
    queryKeys.ts               the key factory (state-management.md)
    endpoints/                 one module per contract resource
      auth.ts  properties.ts  roomTypes.ts  availability.ts
      reservations.ts  me.ts  adminReservations.ts  adminInventory.ts
      ratePlans.ts  calendar.ts  reports.ts  reference.ts
    types.ts                   request/response types, mirroring the contract

  features/
    properties/                S1, S2
    search/                    S3
    booking/                   S4, S6, S7
    auth/                      S5
    account/                   S8a–S8d
    admin-reservations/        S9, S9b, S10
    admin-calendar/            S11
    admin-inventory/           S12
    admin-rate-plans/          S13
    admin-reports/             S14
      — each: components/, hooks/, <Screen>.tsx, index.ts

  components/                  shared presentational primitives only
    ui/                        Button, Input, Select, Dialog, Badge, Skeleton, Pagination…
    layout/                    Header, Footer, AdminSidebar, Nav
    feedback/                  ErrorMessage, EmptyState, LoadingSkeleton, Toast

  guards/                      RequireAuth, RequireStaff, RequireManager
  session/                     AuthProvider, useSession
  lib/
    format.ts                  money, dates, occupancy rate — ONE place
    validation/                Zod schemas shared across forms
  styles/
    index.css                  Tailwind entry + design tokens
```

**Rules that keep this honest:**

- A feature folder never imports from another feature folder. Shared code moves to
  `components/`, `lib/`, or `api/`. This is the single rule that prevents the layout decaying into
  the tangle it was chosen to avoid.
- `components/ui/` is presentational only: props in, markup out, no fetching, no router, no
  session.
- **`lib/format.ts` is the only place money, dates, and the occupancy rate are formatted.** Per
  [glossary-of-conventions.md](../../shared/glossary-of-conventions.md#money-dates-and-formatting-in-code)
  money is a decimal string end to end and must never be parsed into a `number`; a second formatter
  is how that rule gets broken quietly.
- Screen components own queries; presentational children take data as props.

---

## Routing

One route tree in `routes.tsx`, using React Router in declarative mode. The tree mirrors the screen
list in [ui-specifications.md](./ui-specifications.md); the table there is normative for paths.

```
<App>                                    S0 shell — session bootstrap
  /                                      S1
  /properties                            S1
  /properties/:propertyId                S2
  /room-types/:roomTypeId                S2 detail (direct-load route)
  /properties/:propertyId/search         S3
  /login  /register                      S5
  <RequireAuth>
    /properties/:propertyId/book             S4
    /properties/:propertyId/book/payment     S6
    /reservations/:reservationId/confirmation S7
    /account                                 S8a
    /account/reservations                    S8b
    /account/reservations/:reservationId     S8c
    /account/password                       S8d
  <RequireStaff> /admin  (AdminLayout)
    reservations                             S9
    reservations/:reservationId              S9b
    arrivals                                 S10
    calendar                                 S11
    <RequireManager>
      properties                             S12a
      properties/:propertyId                 S12b
      properties/:propertyId/room-types/:rtId S12c/d
      properties/:propertyId/rooms           S12e
      properties/:propertyId/rate-plans      S13
    reports                                  S14
  *                                      S15
```

**Guards are layout routes** rendering `<Outlet />` or a redirect. Each must wait for the S0
bootstrap:

```tsx
function RequireAuth() {
  const { isResolved, user } = useSession();
  if (!isResolved) return <FullPageSkeleton />;
  if (!user) return <Navigate to={`/login?next=${encodeURIComponent(location.pathname + location.search)}`} replace />;
  return <Outlet />;
}
```

The `!isResolved` branch is not defensive padding — without it an authenticated user is redirected to
login on every page refresh, which is the most common bug in this pattern.

`RequireStaff` and `RequireManager` compare **rank**, never set membership, matching
[api-contracts.md](../../shared/api-contracts.md#authorization): a Manager passes every Staff check
without being enumerated.

**Guards are UX only.** Every one is assumed bypassable; the API refuses for real.

**Code splitting** at three boundaries: the admin area, the booking flow, and the calendar. The admin
split matters most — a guest never loads admin code, which is most of the screen count.

---

## The API client layer

Three layers, so no component ever touches `fetch`.

### `api/client.ts` — the fetch wrapper

Every request goes through it. Responsibilities, and nothing else:

1. Prefix the configured base URL.
2. **`credentials: 'include'` on every request** — the session cookie rides on it, and omitting this
   on one call produces a mysterious `401` on exactly one screen.
3. `Content-Type: application/json` on bodies; pass through `Idempotency-Key` when given.
4. Parse `application/problem+json` into a typed `ApiError`.
5. Apply the `401` rule (see [state-management.md](./state-management.md#the-401-rule--identical-in-both-stacks)),
   with the documented exception for the bootstrap `GET /auth/me`.
6. Throw `ApiError` for any non-2xx, so TanStack Query's error path is the only error path.

```ts
export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    readonly detail: string,
    readonly traceId?: string,
    readonly errors?: FieldError[],
  ) { super(detail); }
}
```

`code` is the branch key everywhere — never `detail`, whose wording may change without notice per
[versioning-strategy.md](../../shared/versioning-strategy.md#what-counts-as-a-breaking-change).

**`fetch`, not Axios.** Native `fetch` covers everything needed here, and the wrapper is the only
place HTTP is touched, so a library's ergonomics buy little. The one thing Axios would add —
interceptors — is exactly what this module already is.

### `api/endpoints/*.ts` — typed functions

One module per contract resource, one exported function per endpoint, each returning parsed,
typed data. No React, no hooks, no caching. Testable without a renderer.

### Feature hooks

`features/*/hooks/` wraps endpoint functions in `useQuery` / `useMutation` with keys from the factory.
Screens call hooks; hooks call endpoints; endpoints call the wrapper. A component importing from
`api/endpoints/` directly has skipped the cache and is a review finding.

### Types mirror the contract

`api/types.ts` is hand-written from [api-contracts.md](../../shared/api-contracts.md), with money as
`string` and dates as `string`. **Not generated from OpenAPI** — generated types would come from one
backend's generator, making that backend's output authoritative over the contract document, which
inverts the intended relationship and would mask exactly the drift the OpenAPI diff exists to catch.
Hand-written types mean a contract change is a deliberate edit here. The cost is that they can fall
out of sync; the mitigation is that they are checked against the contract in review, and that
integration tests hit a real backend.

---

## Configuration

`config/env.ts` reads and validates once at startup, failing loudly on a missing value rather than
producing `undefined` inside a URL.

| Variable | Purpose |
|----------|---------|
| `VITE_API_BASE_URL` | Backend base URL, e.g. `http://localhost:3000/api/v1` |

**Switching backends must not require a rebuild.** Vite inlines `VITE_*` at build time, which
satisfies development (where `.env.local` plus a dev-server restart is fine) but not a built bundle.
So the built artifact reads its configuration at runtime from a small `/config.js` emitted beside
`index.html` and loaded before the bundle:

```js
window.__HOTELAPP_CONFIG__ = { apiBaseUrl: "http://localhost:8080/api/v1" };
```

`env.ts` prefers `window.__HOTELAPP_CONFIG__` and falls back to the build-time value. This is what
makes "point either frontend at either backend by changing one configuration value" — required by
[phased-implementation-plan.md](../../shared/phased-implementation-plan.md) — literally true of a
built bundle rather than only of a dev server. Setup steps are in
[environment-setup-guide.md](./environment-setup-guide.md).

---

## Provider composition

`main.tsx`, outermost to innermost:

```
<StrictMode>
  <QueryClientProvider>        server state
    <BrowserRouter>            routing
      <AuthProvider>           session, reads GET /auth/me
        <ToastProvider>        transient notifications
          <ErrorBoundary>      S15 fallback
            <RouterProvider />
```

`AuthProvider` sits inside `QueryClientProvider` because the session is a query. `ErrorBoundary` is
innermost so a render failure in a screen does not take down the shell's navigation.

---

## Styling

Tailwind CSS utilities in markup. Design tokens — colors, spacing, typography, radii — in the
Tailwind config, referenced by name; no ad-hoc hex values in components.

Both clients must look like one product, which is a real constraint on this file: the token values
are shared between the React and Angular clients and should be copied verbatim rather than
re-derived. Dark mode is **not** in scope for either client.

No CSS-in-JS and no component library (MUI, Chakra, shadcn). Per
[security-principles.md](../../shared/security-principles.md#dependencies) the preference is for
platform and framework primitives; the shared components in `components/ui/` are small enough that a
library would mostly add surface and opinion. Detail in
[dependency-policy.md](./dependency-policy.md).

---

## Build and tooling

| Concern | Choice |
|---------|--------|
| Bundler / dev server | Vite |
| Language | TypeScript, `strict: true` |
| Router | React Router, declarative mode |
| Server state | TanStack Query v5 — [state-management.md](./state-management.md) |
| Forms | React Hook Form + Zod |
| Styling | Tailwind CSS |
| Testing | Vitest + React Testing Library — [testing-standards.md](./testing-standards.md) |
| Lint / format | ESLint + Prettier, both failing CI |

`strict: true` is not negotiable, and `any` is a review finding rather than a shortcut — a client
whose contract types are hand-written depends on the compiler to catch a mismatch.

Bundle budget: **< 300 KB gzipped** for the initial chunk, per
[non-functional-requirements.md](../../shared/non-functional-requirements.md#response-time-targets).
Checked in CI as a warning, not a failure. Parity with the Angular client's bundle size is explicitly
not a goal.

---

## Deliberately absent

| Absent | Why |
|--------|-----|
| SSR / Next.js / static pre-rendering | Fixed at system level; the API is the only backend |
| A component library | See styling above |
| Axios | The wrapper *is* the interceptor layer |
| OpenAPI-generated types | Would make a backend authoritative over the contract |
| A global client store | Nearly all state is server state — [state-management.md](./state-management.md) |
| Monorepo sharing with the Angular client | Different repos by design; sharing code would defeat the two-implementation premise |
| i18n | English only, per [non-functional-requirements.md](../../shared/non-functional-requirements.md) |
| Service worker / PWA / offline | Nothing in the product works offline, and a cached booking flow would be actively wrong |
| Dark mode | Not in scope for either client |
