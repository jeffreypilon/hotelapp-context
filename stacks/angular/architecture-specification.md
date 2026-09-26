# Architecture Specification — Angular

Structure of `hotelapp-client-angular`: folder layout, routing, and the API client layer.

Target: **Angular 22.1**, TypeScript, Tailwind CSS. The system-level shape — two frontends, two
backends, one database, REST as the only integration point — is in
[architecture-overview.md](../../shared/architecture-overview.md) and is not restated here.

---

## Fixed at the system level

| Constraint | Source |
|-----------|--------|
| Browser-only SPA. **No SSR**, no Angular Universal, no server-rendered route | [architecture-overview.md](../../shared/architecture-overview.md#frontend-architecture-in-outline) |
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

Organized **by feature, not by file type**, and **standalone throughout** — no `NgModule`
declarations for new code, which Angular 22 treats as the default rather than the modern option.

```
src/
  main.ts                      bootstrapApplication + providers
  app/
    app.component.ts           root component (S0 shell)
    app.routes.ts              the route tree, one place
    app.config.ts              ApplicationConfig: providers, interceptors, initializer

    core/
      config/env.ts            runtime config access, validated once
      api/
        api-error.ts           ApiError type, problem-code constants
        http.interceptor.ts    withCredentials, ApiError mapping, the 401 rule
        *.api.ts               one service per contract resource:
                               auth, properties, room-types, availability,
                               reservations, me, admin-reservations,
                               admin-inventory, rate-plans, calendar,
                               reports, reference
        types.ts               request/response types, mirroring the contract
      session/
        session.store.ts       root-provided SessionStore
        session.initializer.ts GET /auth/me during app init
      guards/
        auth.guard.ts  staff.guard.ts  manager.guard.ts

    features/
      properties/              S1, S2
      search/                  S3
      booking/                 S4, S6, S7
      auth/                    S5
      account/                 S8a–S8d
      admin-reservations/      S9, S9b, S10
      admin-calendar/          S11
      admin-inventory/         S12
      admin-rate-plans/        S13
      admin-reports/           S14
        — each: <name>.routes.ts, <name>.store.ts, components/, pages/

    shared/
      ui/                      button, input, select, dialog, badge, skeleton, pagination…
      layout/                  header, footer, admin-sidebar, nav
      feedback/                error-message, empty-state, loading-skeleton, toast
      pipes/                   money, calendar-date, property-datetime, percent-rate
      util/
        format.ts              money, dates, occupancy rate — ONE place
        validation/            shared form schemas
  styles.css                   Tailwind entry + design tokens
```

**Rules that keep this honest:**

- A feature folder never imports from another feature folder. Shared code moves to `shared/` or
  `core/`. This is the single rule that prevents the layout decaying.
- `shared/ui/` is presentational only: inputs in, template out, no HTTP, no router, no session.
- **`shared/util/format.ts` and the pipes over it are the only place money, dates, and the occupancy
  rate are formatted.** Per
  [glossary-of-conventions.md](../../shared/glossary-of-conventions.md#money-dates-and-formatting-in-code)
  money is a decimal string end to end and must never be parsed into a `number`; a second formatter
  is how that rule gets broken quietly.
- Page components own the store; presentational children take `input()`s.

---

## Routing

One tree in `app.routes.ts`, with feature routes lazy-loaded via `loadChildren`. Paths mirror the
screen list in [ui-specifications.md](./ui-specifications.md), which is normative.

```
''                                        S1
'properties'                              S1
'properties/:propertyId'                  S2
'room-types/:roomTypeId'                  S2 detail (direct-load route)
'properties/:propertyId/search'           S3
'login'  'register'                       S5
  canActivate: [authGuard]
'properties/:propertyId/book'             S4
'properties/:propertyId/book/payment'     S6
'reservations/:reservationId/confirmation' S7
'account'                                 S8a
'account/reservations'                    S8b
'account/reservations/:reservationId'     S8c
'account/password'                        S8d
  canActivate: [staffGuard]  (AdminLayout)
'admin/reservations'                      S9
'admin/reservations/:reservationId'       S9b
'admin/arrivals'                          S10
'admin/calendar'                          S11
    canActivate: [managerGuard]
'admin/properties'                        S12a
'admin/properties/:propertyId'            S12b
'admin/properties/:propertyId/room-types/:rtId' S12c/d
'admin/properties/:propertyId/rooms'      S12e
'admin/properties/:propertyId/rate-plans' S13
'admin/reports'                           S14
'**'                                      S15
```

**Guards are functional `CanActivateFn`s** reading the `SessionStore`:

```ts
export const authGuard: CanActivateFn = (_route, state) => {
  const session = inject(SessionStore);
  const router = inject(Router);
  if (session.user()) return true;
  return router.createUrlTree(['/login'], { queryParams: { next: state.url } });
};
```

No `isResolved` check is needed in the guard body, and that is a structural advantage of this stack:
the session is resolved by `provideAppInitializer` **before the first route activates**, so no guard
can observe an unresolved session. The React client has to handle that case explicitly in every
guard; here it cannot arise. See
[state-management.md](./state-management.md#session-state).

`staffGuard` and `managerGuard` compare **rank**, never set membership, matching
[api-contracts.md](../../shared/api-contracts.md#authorization): a Manager passes every Staff check
without being enumerated.

**Guards are UX only.** Every one is assumed bypassable; the API refuses for real.

**Lazy boundaries:** the admin area, the booking flow, and the calendar. The admin split matters most
— a guest never loads admin code, which is most of the screen count.

**Feature stores are route-provided**, declared in each feature's route `providers`, so state is
discarded when the feature unloads. This is load-bearing for the caching policy in
[state-management.md](./state-management.md#caching-made-explicit).

---

## The API client layer

Three layers, so no component ever touches `HttpClient`.

### `core/api/http.interceptor.ts` — the functional interceptor

Registered once via `provideHttpClient(withInterceptors([apiInterceptor]))`. Responsibilities, and
nothing else:

1. Prefix the configured base URL for relative API paths.
2. **`withCredentials: true` on every request** — the session cookie rides on it, and omitting it on
   one call produces a mysterious `401` on exactly one screen.
3. Pass through `Idempotency-Key` when a caller sets it.
4. Map `application/problem+json` error bodies into a typed `ApiError`.
5. Apply the `401` rule (see [state-management.md](./state-management.md#the-401-rule--identical-in-both-stacks)),
   with the documented exception for the bootstrap `GET /auth/me`.

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

### `core/api/*.api.ts` — typed services

One injectable service per contract resource, one method per endpoint, each returning a typed
`Observable`. No store, no component, no state. Testable with `HttpTestingController`.

### Feature stores

`features/*/<name>.store.ts` wraps API services in `rxMethod`s and holds the resulting state as
signals. Components read the store; the store calls the API service; the service goes through the
interceptor. A component injecting an `*.api.ts` service directly has skipped the store's state and
loading handling, and is a review finding.

### Types mirror the contract

`core/api/types.ts` is hand-written from
[api-contracts.md](../../shared/api-contracts.md), with money as `string` and dates as `string`.
**Not generated from OpenAPI** — generated types would come from one backend's generator, making that
backend's output authoritative over the contract document, which inverts the intended relationship
and would mask exactly the drift the OpenAPI diff exists to catch. Hand-written types mean a contract
change is a deliberate edit here. The cost is that they can fall out of sync; the mitigation is
review against the contract plus integration tests against a real backend.

---

## Configuration

`core/config/env.ts` reads and validates once during initialization, failing loudly on a missing
value rather than producing `undefined` inside a URL.

| Value | Purpose |
|-------|---------|
| `apiBaseUrl` | Backend base URL, e.g. `http://localhost:8080/api/v1` |

**Switching backends must not require a rebuild.** Angular's `environment.ts` files are compile-time,
which satisfies development but not a built bundle. So the built artifact reads its configuration at
runtime from a small `/config.js` emitted beside `index.html` and loaded before the bundle:

```js
window.__HOTELAPP_CONFIG__ = { apiBaseUrl: "http://localhost:3000/api/v1" };
```

`env.ts` prefers `window.__HOTELAPP_CONFIG__` and falls back to the build-time value. This is what
makes "point either frontend at either backend by changing one configuration value" — required by
[phased-implementation-plan.md](../../shared/phased-implementation-plan.md) — literally true of a
built bundle rather than only of a dev server. **The mechanism and the global's name are deliberately
identical to the React client's**, so the same deployment step works for both. Setup steps are in
[environment-setup-guide.md](./environment-setup-guide.md).

---

## Application configuration

`app.config.ts`:

```ts
export const appConfig: ApplicationConfig = {
  providers: [
    provideZonelessChangeDetection(),
    provideRouter(routes, withComponentInputBinding()),
    provideHttpClient(withInterceptors([apiInterceptor])),
    provideAppInitializer(() => inject(SessionInitializer).resolve()),
    SessionStore,
    ReferenceDataStore,
  ],
};
```

`provideAppInitializer` resolving the session before the first route activates is the piece the guard
simplification above depends on. It must **complete on `401`, not reject** — an anonymous visitor is
not a startup failure.

`withComponentInputBinding()` lets route parameters arrive as component `input()`s, which keeps page
components free of `ActivatedRoute` plumbing.

Angular 22 is signal-first; new code should not depend on zone-based change detection, and
`ChangeDetectionStrategy.OnPush` is the default for every component.

---

## Styling

Tailwind CSS utilities in templates. Design tokens — colors, spacing, typography, radii — in the
Tailwind config, referenced by name; no ad-hoc hex values in components. Component styles only where
a utility genuinely cannot express it.

Both clients must look like one product, which is a real constraint on this file: the token values
are shared with the React client and should be copied verbatim rather than re-derived. Dark mode is
**not** in scope for either client.

**No component library** (Angular Material, PrimeNG). Per
[security-principles.md](../../shared/security-principles.md#dependencies) the preference is for
platform and framework primitives, and Angular 22 makes that materially easier: **Angular ARIA is
stable in this release**, supplying accessible dialog, menu, listbox, and tab primitives without
imposing Material's visual language. That is the right fit here — accessible behavior from the
framework, appearance from Tailwind tokens shared with the React client. Detail in
[dependency-policy.md](./dependency-policy.md).

---

## Build and tooling

| Concern | Choice |
|---------|--------|
| Build / dev server | Angular CLI |
| Language | TypeScript, `strict: true` |
| Router | Angular Router, standalone + lazy routes |
| Feature state | NgRx SignalStore — [state-management.md](./state-management.md) |
| Forms | Signal forms (stable in Angular 22) |
| Styling | Tailwind CSS + Angular ARIA primitives |
| Testing | Jest or Vitest + Angular testing utilities — [testing-standards.md](./testing-standards.md) |
| Lint / format | ESLint (`angular-eslint`) + Prettier, both failing CI |

`strict: true` plus `strictTemplates` is not negotiable, and `any` is a review finding rather than a
shortcut — a client whose contract types are hand-written depends on the compiler to catch a mismatch.

Bundle budget: **< 300 KB gzipped** for the initial chunk, per
[non-functional-requirements.md](../../shared/non-functional-requirements.md#response-time-targets).
Checked in CI as a warning, not a failure. This is the tighter of the two clients' budgets relative to
framework baseline, and aggressive lazy-loading of the admin area is how it is met. Parity with the
React client's bundle size is explicitly not a goal.

---

## Deliberately absent

| Absent | Why |
|--------|-----|
| SSR / Angular Universal / prerendering | Fixed at system level; the API is the only backend |
| Angular Material, PrimeNG | See styling above — Angular ARIA plus Tailwind covers it |
| `NgModule`s for new code | Standalone is the Angular 22 default |
| Classic NgRx Store | See [state-management.md](./state-management.md#the-library-decision) |
| OpenAPI-generated types | Would make a backend authoritative over the contract |
| Zone-dependent patterns | Signal-first; `provideZonelessChangeDetection()` |
| Monorepo sharing with the React client | Different repos by design; sharing code would defeat the two-implementation premise |
| i18n / `@angular/localize` | English only, per [non-functional-requirements.md](../../shared/non-functional-requirements.md) |
| Service worker / PWA / offline | Nothing in the product works offline, and a cached booking flow would be actively wrong |
| Dark mode | Not in scope for either client |
