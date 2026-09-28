# State Management — React

How `hotelapp-client-react` holds state. This is a framework-specific answer to a question both
frontend stacks face; the Angular answer is in
[`stacks/angular/state-management.md`](../angular/state-management.md) and reaches a different
conclusion about libraries while agreeing on behavior.

Target: **React 19.3**. Screens are specified in
[ui-specifications.md](./ui-specifications.md); the API in
[api-contracts.md](../../shared/api-contracts.md).

---

## The four kinds of state, kept separate

Most state-management pain in a React application comes from treating these as one problem. They
are not, and HotelApp keeps them in four distinct places.

| Kind | Examples | Where it lives |
|------|----------|----------------|
| **Server state** | Properties, room types, availability, reservations, rate plans | TanStack Query cache |
| **Session state** | The current `user` object and whether bootstrap has resolved | TanStack Query, exposed through one context |
| **Form state** | Search inputs, payment fields, admin forms | React Hook Form, component-local |
| **URL state** | Filters, sort, page, booking context | The URL itself, via `useSearchParams` |

Nothing in HotelApp needs a fifth category. There is no global client store, and adding one would
mostly duplicate the query cache.

---

## Server state — TanStack Query v5

> **Design Decision — TanStack Query for all API data, and no Redux-style store alongside it.**
> Verified current as of September 2026: TanStack Query is at **v5** and is the default answer for
> server state in React applications with a backend. It supplies caching, stale-while-revalidate,
> background refetch, request deduplication, and per-query loading and error states — which is
> precisely the list of things every screen in
> [ui-specifications.md](./ui-specifications.md) needs and would otherwise be hand-rolled once per
> screen.
>
> **Why not Redux Toolkit, Zustand, or a hand-rolled context?** Almost every piece of state in this
> application is a cached copy of something the server owns. A Redux store would model it as client
> state that happens to have been fetched, which means writing the fetch, loading flag, error flag,
> and invalidation logic by hand for each of 42 endpoints, and then keeping the cache coherent after
> every mutation. Zustand is a fine client-state store and this application has almost no client
> state to put in one. A bare `useEffect` + `useState` fetch per screen is what TanStack Query
> exists to replace, and at this project's screen count the difference is large.
>
> **What it costs:** one dependency, plus a convention discipline — query keys must be structured
> consistently or cache invalidation becomes guesswork. The key factory below is not optional
> styling; it is the thing that makes the cache predictable.
>
> **Not used:** `useSuspenseQuery` and React 19's `use()` for data fetching. Both are viable, and
> both make the loading-state specification in
> [ui-specifications.md](./ui-specifications.md) harder to express per screen, since the skeleton
> layouts are specified per screen rather than as one boundary. Explicit `isPending` handling
> matches the spec more directly.

### Query keys

One factory module, the single source of every key. Hierarchical, so a prefix invalidates a subtree.

```ts
export const qk = {
  session:      ()                  => ['session'] as const,
  properties:   (params?: object)   => ['properties', params ?? {}] as const,
  property:     (id: string)        => ['properties', id] as const,
  roomTypes:    (propertyId: string)=> ['properties', propertyId, 'room-types'] as const,
  roomType:     (id: string)        => ['room-types', id] as const,
  amenities:    ()                  => ['amenities'] as const,
  rateCategories: ()                => ['rate-categories'] as const,
  availability: (params: object)    => ['availability', params] as const,
  me:           ()                  => ['me'] as const,
  reservations: (params?: object)   => ['reservations', params ?? {}] as const,
  reservation:  (id: string)        => ['reservations', id] as const,
  adminReservations: (params?: object) => ['admin', 'reservations', params ?? {}] as const,
  adminReservation:  (id: string)   => ['admin', 'reservations', id] as const,
  adminProperties:   ()             => ['admin', 'properties'] as const,
  rooms:        (propertyId: string)=> ['admin', 'properties', propertyId, 'rooms'] as const,
  ratePlans:    (propertyId: string)=> ['admin', 'properties', propertyId, 'rate-plans'] as const,
  calendar:     (propertyId: string, from: string, to: string) =>
                  ['admin', 'properties', propertyId, 'calendar', from, to] as const,
  occupancy:    (propertyId: string, date: string) =>
                  ['admin', 'properties', propertyId, 'occupancy', date] as const,
  arrivals:     (propertyId: string, date: string, page: number) =>
                  ['admin', 'properties', propertyId, 'arrivals', date, page] as const,
};
```

**Every query parameter that changes the result belongs in the key.** Availability keyed only on
property id would serve one date range's results for another — the most likely cache bug in this
application, and the reason the availability key carries the whole parameter object.

### Defaults

```ts
new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30_000,
      gcTime: 5 * 60_000,
      retry: (count, err) => count < 2 && !isClientError(err),
      refetchOnWindowFocus: false,
    },
  },
});
```

`retry` must **not** retry a `4xx`. Retrying a `401`, a `403`, a `404`, or a `409
ROOM_UNAVAILABLE` delays a definitive answer for no benefit — and retrying a `429` makes the
rate-limit worse. Only network failures and `5xx` are worth a second attempt.

`refetchOnWindowFocus: false` is deliberate: the admin calendar and booking list are dense and a
refetch-on-focus reshuffles what someone was reading. Screens that genuinely want freshness ask for
it explicitly.

Per-query overrides:

| Data | `staleTime` | Why |
|------|-------------|-----|
| `amenities`, `rate-categories` | `Infinity` | Fixed reference data; fetch once per session |
| `properties`, `room-types` | 5 minutes | Changes rarely |
| `availability` | **0** | Never serve a cached answer — it decides whether a room can be booked |
| `calendar`, `arrivals`, `occupancy` | 0 | Operational data read to act on |

### Mutations and invalidation

Every mutation declares what it invalidates. Stated as a table so it is reviewable rather than
scattered:

| Mutation | Invalidates |
|----------|-------------|
| `POST /reservations` | `['reservations']`, `['availability']`, `['admin','reservations']`, calendar |
| `PATCH /reservations/{id}` | that reservation, `['reservations']`, `['availability']`, calendar |
| `POST /reservations/{id}/cancel` | that reservation, `['reservations']`, `['availability']`, `['admin','reservations']`, calendar |
| check-in / check-out | that admin reservation, `['admin','reservations']`, arrivals, calendar |
| `PATCH /me` | `['me']`, `['session']` |
| `PUT /me/password` | nothing — the caller's session stays valid |
| property / room-type / room / photo writes | the affected subtree plus the public `['properties']` tree |
| `PUT .../rate-plans` | that property's rate plans, and `['availability']` — discounts change prices |

**No optimistic updates anywhere.** Every mutation in this application can be refused by the server
for a reason the client cannot predict: `ROOM_UNAVAILABLE` from the exclusion constraint,
`CANCELLATION_WINDOW_CLOSED` from a deadline, `INVALID_STATUS_TRANSITION` from stale state. Showing
a booking as confirmed and then retracting it is worse than a brief spinner. This is a deliberate
departure from TanStack Query's marquee feature and the reason is the domain, not the library.

---

## Session state

One `useQuery` on `GET /auth/me` with `staleTime: Infinity` and `retry: false`, wrapped in a small
`AuthProvider` context exposing:

```ts
{ user: User | null, isResolved: boolean, role: Role | null, propertyId: string | null }
```

The context exists so route guards and the shell read one value rather than each calling the query.
It holds **no state of its own** — it is a typed read over the query cache, which keeps a single
source of truth.

**`retry: false` matters.** A `401` here is the correct answer for an anonymous visitor, not a
failure to retry.

**`isResolved` is what guards wait on.** A guard that evaluates before bootstrap resolves will
redirect an authenticated user to login on every page refresh — the most common bug in this pattern.

Login and registration write the returned `user` into `qk.session()` with `setQueryData`, avoiding a
redundant fetch. Logout calls `queryClient.clear()`, which must remove **all** cached server data,
not just the session: leaving another user's reservations in the cache on a shared machine is a
disclosure bug.

**Nothing is written to `localStorage` or `sessionStorage`.** The session cookie is `HttpOnly` and
the client has no token to keep. See
[security-implementation.md](./security-implementation.md).

---

## Form state — React Hook Form + Zod

Component-local. Never in the query cache, never in a global store.

One Zod schema per form, giving validation and inferred types from one declaration. Client rules
mirror the server's so the guest sees the same message either way, with the text owned by
[error-handling.md](./error-handling.md) rather than written per form.

Server field errors from a `400`'s `errors[]` array are applied with `setError` keyed on the
`field` value — which is why contract field names and form field names must match exactly.

**Every form uses `mode: 'onBlur'` with `reValidateMode: 'onChange'`**, not the RHF default
(`onSubmit`) — per [ui-specifications.md](./ui-specifications.md#1-conventions-for-every-screen)'s
input-validation conventions. Validate the first time when a field is blurred, not on every
keystroke while it's still being typed (typing a card number one digit at a time would otherwise
show it as invalid for most of the process); re-validate live once an error is already showing, so
correcting it doesn't require blurring again. This was previously stated as payment-specific; it
applies to every RHF-managed form in this repo. The one exception is a field verifying an existing
credential (login's password, password-change's "current password") — see
ui-specifications.md's exemption for why those get no format validation to trigger in the first
place.

---

## URL state

The URL owns anything that should survive a reload or be shareable: search parameters and filters
(S3), list filters, sort, and page (S8b, S9, S12), report and calendar dates (S11, S14), and the
booking context through the login detour (S4).

That last one is load-bearing. Booking context in React state is lost on a reload during the
authentication detour, forcing the guest to search again — the worst UX failure available in this
application. In the URL it survives.

`useSearchParams` is the accessor; there is no mirrored copy in component state. Filter inputs
debounce ~300 ms before writing to the URL, so typing does not produce a history entry per keystroke
(use `replace: true` for intermediate writes).

---

## The `401` rule — identical in both stacks

> **This behavior is shared with Angular and must not diverge**, even though the mechanism differs.
> It is the client obligation stated in
> [api-contracts.md](../../shared/api-contracts.md#client-obligations).

On **any** `401` from **any** authenticated request:

1. Clear all cached server state — `queryClient.clear()`.
2. Clear the session context.
3. Route to `/login?next=<current path>`.
4. Show "Your session has expired. Please log in again."

**There is no retry, no refresh call, and no queue of pending requests to replay.** The superseded
token design needed all three; sessions need none. If anything resembling a refresh interceptor
appears in this codebase, it is the removed design leaking back — see
[decision-log.md](../../shared/decision-log.md) entry 2.

Implemented once, in the shared fetch wrapper, so no screen handles it. The wrapper throws a typed
`ApiError` carrying `status`, `code`, `detail`, and `errors[]`; the `401` branch runs the sequence
above before throwing, so screen-level error handling never sees it.

One exception: `GET /auth/me` during bootstrap. A `401` there is the expected anonymous answer and
must not trigger the redirect, or the app redirects to login on every anonymous page load. The
wrapper takes a flag to suppress it for that one call.

---

## What is deliberately absent

| Absent | Why |
|--------|-----|
| Redux / Redux Toolkit | Nearly all state here is server state; the query cache already holds it |
| Zustand, Jotai, Valtio | Would hold almost nothing — there is no meaningful global client state |
| `Context` for server data | Context has no caching, deduplication, or invalidation; it would be a worse query cache |
| Optimistic updates | Server refusals are routine in this domain — see above |
| Persisted / offline query cache | Would put another guest's reservations on disk on a shared machine |
| WebSocket or polling live updates | Nothing in the product is real-time |
| A normalized entity cache | The API returns purpose-shaped responses per endpoint; normalizing would add a mapping layer with nothing asking for it |

Sources for the library-status claims above:
[TanStack Query overview](https://tanstack.com/query/latest/docs/framework/react/overview),
[TanStack Query in 2026](https://blog.codercops.com/blog/tanstack-query-server-state-2026),
[React 19.3 release notes](https://react.dev/blog/2026/09/09/react-19-3).
