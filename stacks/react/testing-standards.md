# Testing Standards — React

What gets tested in `hotelapp-client-react`, how, and — importantly — what these suites **do not**
cover.

Tooling per
[architecture-specification.md](./architecture-specification.md#build-and-tooling): **Vitest + React
Testing Library**, with MSW for HTTP interception.

---

## The honest boundary

Stated first, because the most useful thing this document can do is not overclaim.

| Layer | Covered by | Where |
|-------|-----------|-------|
| Pure functions — formatters, validators, error resolution | Unit tests | this repo |
| Components and screens — rendering, states, interaction | Component tests, mocked HTTP | this repo |
| API client behavior — `credentials`, `401`, error mapping | Integration-style tests, mocked HTTP | this repo |
| **Business rules** — no overbooking, the 48-hour boundary, role scoping, session behavior | **Backend integration tests** | the two backend repos, driven by [acceptance-criteria.md](../../shared/acceptance-criteria.md) |
| **The whole system through a browser** | **Nothing yet** | — |

That last row is real and is the acknowledged gap in
[devops-pipeline-overview.md](../../shared/devops-pipeline-overview.md#deliberately-absent). **There are
no end-to-end browser tests in this project.** No Playwright, no Cypress. Nothing in this repository
verifies that a guest can actually search, book, and receive a confirmation against a live backend.

So these suites must not be described as covering the booking flow. A component test of the payment form
proves the form validates and submits what it claims; it proves nothing about whether a reservation gets
created, whether the exclusion constraint fires, or whether the confirmation number is real. Those are
[acceptance-criteria.md](../../shared/acceptance-criteria.md)'s job, tested server-side.

**What a component test here actually proves** is that given a known API response, the screen renders the
state [ui-specifications.md](./ui-specifications.md) specifies. That is a narrow claim, and worth making
precisely because the screen specification is shared with the Angular client — the two clients'
component tests are the closest thing to a check that both implement the same spec.

---

## Unit tests

Fast, no DOM, no providers. These are where the exactness lives.

**`lib/format.ts` is the highest-value target in the codebase**, because it handles money:

```ts
formatMoney('224.10')   → '$224.10'
formatMoney('1234.50')  → '$1,234.50'
formatMoney('0.00')     → '$0.00'
formatMoney('672.3')    → '$672.30'   // server may omit a trailing zero
```

Assert on **strings in, strings out**, and add a test asserting the formatter never converts to
`number` — the precision rule from
[glossary-of-conventions.md](../../shared/glossary-of-conventions.md#money-dates-and-formatting-in-code)
is exactly the kind of thing a later refactor breaks invisibly.

Also unit-tested:

| Target | Cases worth pinning |
|--------|--------------------|
| Occupancy rate | `'0.7439'` → `'74.4%'`; `'0.0000'` → `'0.0%'`; never `NaN` |
| Date formatting | Full and dense forms; a date string never shifted by the local timezone |
| Property-timezone timestamp | The cancellation deadline renders in the property's zone, not the browser's |
| Zod schemas | Each boundary: 11 vs 12 character password; 30 vs 31 nights; check-out equal to check-in |
| `resolveError` | Every code in [error-handling.md](./error-handling.md); **plus an unknown code falling back by status class**, which is the case a real backend change will hit |
| `safeImageUrl` | `javascript:` and `data:` rejected; `https:` accepted |
| `can()` role helper | Manager passes every Staff check — the rank-not-membership rule |

---

## Component tests

React Testing Library. **Query by role and accessible name, not by test id.** A test that finds a button
by `data-testid` passes even when the button is unreachable by keyboard or screen reader; one that finds
it by `getByRole('button', { name: 'Complete booking' })` fails when the accessible name breaks, which
is a bug worth failing on. Reserve `data-testid` for genuinely nameless containers, like the calendar
grid.

**Every screen's five states get a test.** This is the coverage rule that matters, because
[ui-specifications.md](./ui-specifications.md) specifies all five per screen and the empty and error
states are the ones that get forgotten:

| State | How |
|-------|-----|
| Loading | Skeleton present, content absent |
| Success | Content from the fixture rendered |
| Empty — no data | The no-data message, per the spec's exact wording |
| Empty — filtered | The filtered message plus a clear-filters control |
| Error | The mapped message from [error-handling.md](./error-handling.md) |
| Role-gated | Each variant: Front Desk sees no property filter; Manager does |

**Assert the specified copy, verbatim.** `expect(screen.getByText('Those dates are no longer available. Someone else may have booked the last room.'))`
looks brittle and is the point: the string is shared with the Angular client, and a test that accepts any
error text lets the two drift.

### HTTP is mocked at the network boundary

MSW, not a mocked fetch wrapper and not mocked hooks. Mocking the wrapper skips the `credentials`,
error-mapping, and `401` logic — the code most worth exercising.

```tsx
function renderScreen(ui: ReactElement, { route = '/' } = {}) {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  // fresh QueryClient per test, or cache leaks across tests produce order-dependent passes
  return render(/* providers + router + ui */);
}
```

`retry: false` in tests, or an error-state test waits out the retries.

### Screens worth extra attention

| Screen | Why, and what to test |
|--------|----------------------|
| S3 search | URL is the source of truth: filter changes update query parameters; mounting with parameters populates the form |
| S4 booking summary | **The login-detour test**: booking context survives a route away and back via the URL. This guards the worst available UX failure |
| S6 payment | `Idempotency-Key` is **identical across two submit attempts** — the single most valuable test in this suite, since a per-attempt key silently permits double bookings |
| S6 payment | Card number, CVV, and expiry never appear in any mocked request URL and never in `localStorage` |
| S8c reservation detail | Action availability across the full status × deadline matrix from the spec |
| S9 admin list | Front Desk renders no property filter; a `propertyId` parameter does not widen their results |
| S11 calendar | Segments expand to the right cells; a segment extending past the window is clipped, not dropped |

---

## API client tests

`api/client.ts` gets its own tests, because it holds the rules with the widest blast radius:

- `credentials: 'include'` is present on **every** request — assert it, since a regression here is a
  screen-specific `401` nobody reproduces.
- A `problem+json` body becomes an `ApiError` with `code`, `detail`, `traceId`, and `errors[]`.
- A non-JSON error body still yields an `ApiError` rather than throwing a parse error.
- A `401` clears the query cache, clears the session, and navigates to `/login?next=…`.
- **A `401` from the bootstrap `GET /auth/me` does *not* redirect** — the documented exception, and a
  regression would send every anonymous visitor to login.
- `Idempotency-Key` passes through unmodified.

---

## Accessibility tests

`vitest-axe` on every screen's success state, as an assertion rather than a report. Plus, by hand where
axe cannot reach:

- Tab order through the booking flow is sensible.
- Dialogs trap focus and restore it to the invoking control.
- A failed submit moves focus to the first errored field — React Hook Form's `setError` does not do this,
  so it is explicit code and therefore worth a test.
- Results counts and errors land in live regions.

WCAG 2.1 AA is the target per
[non-functional-requirements.md](../../shared/non-functional-requirements.md#browser-and-device-support),
and no audit has been run — these tests are a floor, not a certification.

---

## Coverage

**No coverage threshold gate.** Per
[devops-pipeline-overview.md](../../shared/devops-pipeline-overview.md#deliberately-absent), a percentage
gate rewards tests that execute lines. What is required instead is enumerable:

- Every screen: all specified states.
- Every formatter and validator: boundary cases.
- Every error code: its mapping.
- Every role-gated variant: each role.

Coverage is *reported* in CI so a gap is visible, and not enforced.

**Not tested:** Tailwind classes, exact markup structure, third-party library internals, or snapshots.
No snapshot tests — they fail on every intentional change and get regenerated without being read, which
trains people to ignore the one time it mattered.

---

## Fixtures

`src/test/fixtures/`, hand-written to match [api-contracts.md](../../shared/api-contracts.md) response
shapes exactly — money as strings, dates as `YYYY-MM-DD`, the pagination envelope present.

**A fixture that does not match the contract makes a passing test a false positive**, which is the main
risk in a suite where all HTTP is mocked. Build fixtures from the contract's example bodies, and treat a
contract change as requiring a fixture change. The mitigation for the residual risk is that the backends
are tested against a real database and a real contract.

A builder per resource keeps a test's intent readable: `aReservation({ status: 'CHECKED_IN' })` says what
the test is about; a 40-line literal does not.
