# State Management — Angular

How `hotelapp-client-angular` holds state. This is a framework-specific answer to a question both
frontend stacks face; the React answer is in
[`stacks/react/state-management.md`](../react/state-management.md) and reaches a different
conclusion about libraries while agreeing on behavior.

Target: **Angular 22.1**. Screens are specified in
[ui-specifications.md](./ui-specifications.md); the API in
[api-contracts.md](../../shared/api-contracts.md).

---

## The four kinds of state, kept separate

| Kind | Examples | Where it lives |
|------|----------|----------------|
| **Server state** | Properties, room types, availability, reservations, rate plans | Feature-level `signalStore`s over `HttpClient` |
| **Session state** | The current `user` and whether bootstrap has resolved | One root-provided `SessionStore` |
| **Form state** | Search inputs, payment fields, admin forms | Signal forms, component-local |
| **URL state** | Filters, sort, page, booking context | The router's query parameters |

---

## The library decision

> ### Design Decision — NgRx SignalStore for feature state, plain signals for the rest, and **not** classic NgRx Store
>
> This was left open for Phase 3 to decide with reasoning rather than defaulted, so here is the
> reasoning, against current (September 2026) guidance rather than older assumptions.
>
> **What current guidance actually says.** The 2026 consensus is not "NgRx is obsolete" — it is that
> the decision is no longer old-versus-new but *global event-driven store versus signal-based
> feature store*. SignalStore is itself an NgRx package, not a competitor to it. The prevailing
> recommendation for a new Angular 22 application is: plain services with signals for small or
> isolated state, **NgRx SignalStore for medium applications that want structure**, and classic
> NgRx Store reserved for enterprise applications that genuinely need global event traceability,
> time-travel debugging, and a strict action/reducer/effect discipline across a large team.
>
> **Where HotelApp sits.** Squarely in the middle band, and the specifics matter more than the size:
>
> - **State is feature-local, not global.** The availability search, the admin calendar, the
>   reservation list, and rate-plan management share almost nothing. There is no cross-cutting state
>   that many unrelated features read and write — which is the condition a global store is *for*.
>   The one genuinely global thing is the session, and it is a single object.
> - **Almost all of it is cached server data**, not derived client state. What each feature needs is
>   load / loading / error / reload, scoped to one screen — which is what a SignalStore's
>   `withState` + `withMethods` expresses directly.
> - **No undo, no time-travel, no event sourcing requirement.** Nothing in
>   [project-overview.md](../../shared/project-overview.md) asks for a replayable action log, and the
>   audit trail that does exist is server-side columns rather than client actions.
> - **Angular 22 is signal-first.** Signal forms and Angular ARIA components are stable as of this
>   release, and the framework's own direction is signals. A store built on signals composes with
>   `computed()`, `input()`, `OnPush`, and the template's `@if`/`@for` without a bridge.
>
> **Why not classic NgRx Store.** For this application it would mean an action, a reducer case, an
> effect, and a selector for every one of ~42 endpoints — a large amount of ceremony whose payoff
> (global traceability, time travel, strict unidirectional discipline at team scale) this project
> cannot collect on. Choosing it here would demonstrate familiarity with a pattern while
> demonstrating poor judgment about when it earns its cost, which is the opposite of what this
> portfolio piece is for.
>
> **Why not plain services with signals alone.** Tempting, and it would work. Rejected because
> fifteen-plus screens each need the same load/loading/error/reload shape, and hand-rolling it per
> service produces fifteen slightly different versions of the same thing — exactly the drift this
> project is organized against. SignalStore supplies one shape, and `rxMethod` gives request
> cancellation and switching for free, which the availability search and the calendar's window
> paging both need.
>
> **What it costs, honestly.** A dependency, and a smaller body of community examples than classic
> NgRx has. Also a real asymmetry with the React client: TanStack Query brings a caching layer that
> SignalStore does not, so **cache semantics that React gets from a library are explicit code here**
> — the "caching" section below exists to keep the two clients' observable behavior the same despite
> that. That asymmetry is the most significant difference between the two frontends, and it is a
> consequence of the frameworks' ecosystems rather than a divergence in requirements.

---

## Feature stores

One `signalStore` per feature, provided at the route level so its state is discarded when the
feature unloads:

| Store | Backs |
|-------|-------|
| `PropertiesStore` | S1, S2 |
| `AvailabilityStore` | S3 |
| `BookingStore` | S4, S6, S7 |
| `MyReservationsStore` | S8b, S8c |
| `ProfileStore` | S8a, S8d |
| `AdminReservationsStore` | S9, S9b, S10 |
| `CalendarStore` | S11 |
| `InventoryStore` | S12 |
| `RatePlansStore` | S13 |
| `ReportsStore` | S14 |

Each follows one shape, so a reader who understands one understands all ten:

```ts
export const AvailabilityStore = signalStore(
  withState<{
    results: AvailabilityResult[];
    pagination: Pagination | null;
    status: 'idle' | 'loading' | 'success' | 'error';
    error: ApiError | null;
  }>({ results: [], pagination: null, status: 'idle', error: null }),

  withComputed(({ results, status }) => ({
    isLoading: computed(() => status() === 'loading'),
    isEmpty:   computed(() => status() === 'success' && results().length === 0),
  })),

  withMethods((store, api = inject(AvailabilityApi)) => ({
    search: rxMethod<AvailabilityQuery>(pipe(
      tap(() => patchState(store, { status: 'loading', error: null })),
      switchMap(q => api.search(q).pipe(
        tapResponse({
          next:  r  => patchState(store, { results: r.data, pagination: r.pagination, status: 'success' }),
          error: (e: ApiError) => patchState(store, { status: 'error', error: e }),
        }),
      )),
    )),
  })),
);
```

**`switchMap`, not `mergeMap`.** The availability search and the calendar's window paging both fire
rapidly as someone adjusts dates, and a late response from an abandoned request overwriting a newer
one is a real bug that `switchMap` prevents structurally.

**`isEmpty` distinguishes empty-success from loading**, so the empty states specified in
[ui-specifications.md](./ui-specifications.md) render correctly rather than flashing during load.

---

## Caching, made explicit

TanStack Query gives the React client caching, staleness, and deduplication as defaults. This stack
has to state them, and the observable behavior must match:

| Data | Policy | How |
|------|--------|-----|
| `amenities`, `rate-categories` | Fetch **once per session** | Root-provided `ReferenceDataStore`, loaded during app initialization; never refetched |
| `properties`, `room-types` | Cache in the feature store; refetch on feature entry | Store is route-provided, so re-entry naturally refetches |
| `availability` | **Never cached.** Always a fresh request | It decides whether a room can be booked |
| `calendar`, `arrivals`, `occupancy` | Never cached; refetch on every parameter change | Operational data read in order to act |
| Mutations | Explicitly reload the affected store | See below |

**In-flight deduplication** uses `shareReplay({ bufferSize: 1, refCount: true })` on the reference-data
requests only. Elsewhere the route-scoped store lifetime makes duplicate requests unlikely enough
that a general dedupe layer would be speculative.

### Post-mutation reloads

The Angular analogue of query invalidation. The same table as the React client's, so the two
behave identically:

| Mutation | Reloads |
|----------|---------|
| `POST /reservations` | `MyReservationsStore`, `AvailabilityStore`, `AdminReservationsStore`, `CalendarStore` |
| `PATCH /reservations/{id}` | that reservation, `MyReservationsStore`, `AvailabilityStore`, `CalendarStore` |
| `POST /reservations/{id}/cancel` | that reservation, `MyReservationsStore`, `AvailabilityStore`, `AdminReservationsStore`, `CalendarStore` |
| check-in / check-out | `AdminReservationsStore`, arrivals, `CalendarStore` |
| `PATCH /me` | `ProfileStore`, `SessionStore` |
| `PUT /me/password` | nothing — the caller's session stays valid |
| property / room-type / room / photo writes | `InventoryStore`, `PropertiesStore` |
| `PUT .../rate-plans` | `RatePlansStore`, `AvailabilityStore` — discounts change prices |

Because stores are route-provided, a store for an unmounted feature does not exist to reload; it
will fetch fresh on next entry. Cross-store reloads are therefore best expressed as a small
root-provided event signal that mounted stores react to, rather than stores reaching into each other.

**No optimistic updates anywhere.** Identical reasoning to the React client: every mutation here can
be refused for a reason the client cannot predict — `ROOM_UNAVAILABLE` from the exclusion
constraint, `CANCELLATION_WINDOW_CLOSED` from a deadline, `INVALID_STATUS_TRANSITION` from stale
state. Showing a booking as confirmed and then retracting it is worse than a spinner.

---

## Session state

One root-provided `SessionStore`, the only genuinely global store:

```ts
{
  user: Signal<User | null>,
  isResolved: Signal<boolean>,
  role: Signal<Role | null>,
  propertyId: Signal<string | null>,
}
```

**Bootstrap resolves once, during app initialization**, via a `provideAppInitializer` that calls
`GET /auth/me` and completes regardless of outcome — `200` sets the user, `401` sets `null`, and
neither rejects. Getting this wrong makes every guard racy.

This is a genuine advantage over the React client's arrangement: because initialization completes
before the first route activates, **no guard can observe an unresolved session**, so the
"guard fires before bootstrap" hazard is structurally absent rather than something each guard must
remember. Guards still read `isResolved` defensively.

Login and registration patch the returned `user` directly, avoiding a redundant fetch. Logout clears
the `SessionStore` **and** every feature store's state — leaving another user's reservations in
memory on a shared machine is a disclosure bug.

**Nothing is written to `localStorage` or `sessionStorage`.** The session cookie is `HttpOnly` and
the client has no token to keep. See
[security-implementation.md](./security-implementation.md).

---

## Form state — Signal forms

Component-local. Never in a store.

**Signal forms are stable in Angular 22** and are the default for new forms here; typed reactive
`FormGroup` is acceptable where a pattern is already established, but the two must not be mixed
within one feature.

Client validation mirrors the server's so the guest sees the same message either way, with the text
owned by [error-handling.md](./error-handling.md) rather than written per form.

Server field errors from a `400`'s `errors[]` array are applied with `setErrors` on the matching
control — which is why contract field names and control names must match exactly.

**Every form validates on blur, then re-validates live once a field has an error showing** — per
[ui-specifications.md](./ui-specifications.md#1-conventions-for-every-screen)'s input-validation
conventions. Validating a card number on every keystroke marks it invalid for most of the time
it's being typed; validating only on blur, then never again until the next blur, makes a guest
re-click out of a field just to see whether their correction worked. This was previously stated as
payment-specific; it applies to every form in this repo. The one exception is a field verifying an
existing credential (login's password, password-change's "current password") — see
ui-specifications.md's exemption for why those get no format validation to trigger in the first
place.

---

## URL state

The router owns anything that should survive a reload or be shareable: search parameters and filters
(S3), list filters, sort, and page (S8b, S9, S12), report and calendar dates (S11, S14), and the
booking context through the login detour (S4).

That last one is load-bearing. Booking context held in a store is lost on a reload during the
authentication detour, forcing the guest to search again — the worst UX failure available in this
application. In the URL it survives.

Read query parameters as signals with `toSignal(route.queryParamMap)` and feed them into the store's
`rxMethod`, so a parameter change drives a fetch through one path. Filter inputs debounce ~300 ms
before writing to the router, using `replaceUrl: true` for intermediate writes so typing does not
produce a history entry per keystroke.

---

## The `401` rule — identical in both stacks

> **This behavior is shared with React and must not diverge**, even though the mechanism differs.
> It is the client obligation stated in
> [api-contracts.md](../../shared/api-contracts.md#client-obligations).

On **any** `401` from **any** authenticated request:

1. Clear all feature-store state.
2. Clear the `SessionStore`.
3. Navigate to `/login` with `next` set to the current path.
4. Show "Your session has expired. Please log in again."

**There is no retry, no refresh call, and no queue of pending requests to replay.** The superseded
token design needed all three; sessions need none. If anything resembling a refresh interceptor
appears in this codebase, it is the removed design leaking back — see
[decision-log.md](../../shared/decision-log.md) entry 2.

Implemented once, in a functional `HttpInterceptorFn`, so no screen or store handles it. The
interceptor also maps every error response into the typed `ApiError` carrying `status`, `code`,
`detail`, and `errors[]`, and sets `withCredentials: true` on every outgoing request — see
[security-implementation.md](./security-implementation.md).

One exception: `GET /auth/me` during bootstrap. A `401` there is the expected anonymous answer and
must not trigger the redirect, or the app navigates to login on every anonymous page load. The
interceptor skips the redirect for that one request, matched by URL.

---

## What is deliberately absent

| Absent | Why |
|--------|-----|
| Classic NgRx Store, actions, reducers, effects | Ceremony this application cannot collect the payoff on — see the design decision above |
| NGXS, Akita, Elf | Same reasoning, with smaller ecosystems |
| A global store for server data | State here is feature-local; route-scoped stores discard it correctly |
| `@ngrx/entity` normalization | The API returns purpose-shaped responses per endpoint; nothing asks to normalize them |
| Optimistic updates | Server refusals are routine in this domain |
| Persisted or offline state | Would put another guest's reservations on disk on a shared machine |
| Zone.js-dependent patterns | Angular 22 is signal-first; new code should not depend on zone-based change detection |
| WebSocket or polling live updates | Nothing in the product is real-time |

Sources for the library-status claims above:
[Angular 22 State Management: Signals, SignalStore, or NgRx?](https://abp.io/community/articles/angular-22-state-management-signals-signalstore-or-ngrx-yq8zg0nw),
[Angular State Management in 2026 — compared](https://dev.to/kirandeepjassalcrypto/angular-state-management-in-2026-ngrx-signals-ngxs-akita-compared-with-bundle-loc-numbers-4amj),
[State Management in Angular: NgRx vs. SignalStore](https://johnkavanagh.co.uk/articles/state-management-in-angular-ngrx-vs-signalstore/),
[Angular releases](https://angular.dev/reference/releases).
