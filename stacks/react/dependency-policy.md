# Dependency Policy — React

What may be added to `hotelapp-client-react`, what may not, and how to decide.

The governing rule is from
[security-principles.md](../../shared/security-principles.md#dependencies): **prefer the framework's own
primitives over a small package**, because every dependency is added attack surface and added maintenance.
The "deliberately absent" table in
[architecture-specification.md](./architecture-specification.md#deliberately-absent) already settled several
specific cases; this document does not reopen them.

---

## The approved set

Everything this client needs. Versions are pinned exactly, with `package-lock.json` committed and `npm ci`
in CI.

| Package | Role | Why it earns its place |
|---------|------|------------------------|
| `react`, `react-dom` | The framework | 19.3 |
| `react-router` | Routing | No viable alternative at this scale |
| `@tanstack/react-query` | Server state | Decided with reasoning in [state-management.md](./state-management.md#server-state--tanstack-query-v5) |
| `react-hook-form` | Form state | Uncontrolled-first, so a large admin form does not re-render per keystroke |
| `zod` | Schema validation | One declaration gives validation and inferred types |
| `@hookform/resolvers` | Bridges the two | Small, single-purpose |
| `clsx` | Conditional classes | ~200 bytes, replaces fragile template strings |
| `tailwindcss` | Styling | Decided at system level |
| `prettier-plugin-tailwindcss` | Utility ordering | Removes a recurring review topic |
| `vite`, `@vitejs/plugin-react` | Build | |
| `typescript` | | `strict: true` |
| `vitest`, `@testing-library/react`, `@testing-library/user-event`, `jsdom` | Testing | [testing-standards.md](./testing-standards.md) |
| `msw` | HTTP mocking | Mocks at the network boundary, so the fetch wrapper is exercised rather than replaced |
| `vitest-axe` | Accessibility assertions | |
| `eslint`, `prettier`, and configs | Lint and format | Including `eslint-plugin-jsx-a11y` and `eslint-plugin-react-hooks` as **errors** |

`react-error-boundary` is **permitted but optional** — see
[error-handling.md](./error-handling.md#the-error-boundary). A hand-written class boundary is equally
acceptable; use one or the other, not both.

---

## Explicitly not allowed

Each of these is a decision already made elsewhere, restated as a prohibition so it is not relitigated one
pull request at a time.

| Not allowed | Instead | Decided in |
|-------------|---------|-----------|
| A component library — MUI, Chakra, Ant, shadcn/ui | `components/ui/` over Tailwind tokens | [architecture-specification.md](./architecture-specification.md#styling) |
| Axios, ky, superagent | `api/client.ts` over native `fetch` — the wrapper **is** the interceptor layer | [architecture-specification.md](./architecture-specification.md#the-api-client-layer) |
| Redux, Redux Toolkit, Zustand, Jotai, Valtio, MobX | TanStack Query; there is almost no client state to store | [state-management.md](./state-management.md#server-state--tanstack-query-v5) |
| A date library — Moment, date-fns, Day.js, Luxon | `Intl.DateTimeFormat` in `lib/format.ts` | See below |
| A money library — Dinero, currency.js | Money is a **string** end to end; it is formatted, never arithmetic'd | [glossary-of-conventions.md](../../shared/glossary-of-conventions.md#money-dates-and-formatting-in-code) |
| Next.js, Remix, or any SSR framework | Browser-only SPA | [architecture-overview.md](../../shared/architecture-overview.md#frontend-architecture-in-outline) |
| OpenAPI type generators | Hand-written types; a generator would make a backend authoritative over the contract | [architecture-specification.md](./architecture-specification.md#the-api-client-layer) |
| A JWT library — `jwt-decode`, `jose` | **There are no tokens.** See [security-implementation.md](./security-implementation.md#what-must-never-reappear) |
| Analytics, tag managers, session replay — GA, Segment, Sentry, LogRocket, Hotjar | Nothing. [logging-observability.md](./logging-observability.md) explains why |
| A charting library — Recharts, Chart.js, D3 | The reports are tables and stat tiles; charts are a stated future enhancement | [ui-specifications.md](./ui-specifications.md) S14 |
| A drag-and-drop or file-upload library | **There is no file upload** — photos are URLs | [data-model.md](../../shared/data-model.md#room_type_photos) |
| An i18n library | English only | [non-functional-requirements.md](../../shared/non-functional-requirements.md) |
| `lodash`, `underscore`, `ramda` | Native array and object methods cover everything here |
| A polyfill bundle — `core-js`, `regenerator` | Evergreen browsers only; no IE | [non-functional-requirements.md](../../shared/non-functional-requirements.md#browser-and-device-support) |
| `moment-timezone` | `Intl.DateTimeFormat` with a `timeZone` option — see below |

### On date libraries specifically

The temptation is real, because this application renders three different things: calendar dates with no time
(`checkInDate`), a timestamp in the **property's** timezone (`cancellation.deadline`), and dense table dates.

All three are `Intl.DateTimeFormat`, which is built in, needs no bundle, and — importantly — accepts a
`timeZone` option, so rendering the cancellation deadline in `America/New_York` regardless of the browser's
zone is a one-liner. A date library would add 15–70 KB to do what the platform does, and the one genuinely
subtle case (never constructing a `Date` from a `YYYY-MM-DD` string in a way that shifts the day) is a
discipline no library enforces for you.

If date *arithmetic* ever becomes genuinely awkward, `Temporal` is the answer to watch rather than a library
to add.

---

## Adding something new

Five questions, in order. A "no" at any point is the answer.

1. **Does React, TypeScript, or the browser already do this?** `Intl`, `crypto.randomUUID`,
   `URL`, `structuredClone`, `AbortController`, `Intl.NumberFormat`. The answer here is yes more often than
   people expect.
2. **Is it already prohibited above?** Then it needs a documented decision reversal, not a pull request.
3. **What does it weigh, and what does it pull in?** Check the transitive tree, not just the headline size.
   A 2 KB package with eleven dependencies is not a 2 KB package.
4. **Is it maintained, and is it typed?** Recent releases, a real issue tracker, first-party TypeScript
   types. `@types/*` from DefinitelyTyped is acceptable; no types at all is not.
5. **Could fifty lines in `lib/` replace it?** If yes, write the fifty lines. They will be understood,
   tested, and free of a supply-chain relationship.

Each addition is a separate commit with the reason in the message, per
[glossary-of-conventions.md](../../shared/glossary-of-conventions.md#commit-message-convention). "Added while
working on X" in a large commit is how a dependency arrives without anyone deciding.

---

## Third-party scripts

**No `<script>` tag pointing anywhere but this origin.** No analytics snippet, no tag manager, no widget, no
CDN-hosted library.

This is a security rule rather than a performance one: a third-party script executes in this app's origin
with full access to the DOM of pages that handle credentials and card-shaped input. Per
[security-principles.md](../../shared/security-principles.md) the CSP sets `script-src 'self'`, which
enforces it — a script tag added anyway will simply be blocked, which is the intended outcome.

Fonts are the one borderline case. **Self-host them.** The Google Fonts stylesheet origin is permitted by the
shared CSP guidance, but self-hosting removes a third-party request from the critical path and a
privacy consideration with it, at the cost of a few files in `public/`.

---

## Maintenance

- **Exact versions**, no `^` or `~`. A reviewer cloning this repo gets the build the author had.
- `package-lock.json` committed; `npm ci` in CI, never `npm install`.
- **No automated dependency updates** — no Dependabot, no Renovate. Per
  [security-principles.md](../../shared/security-principles.md#out-of-scope-and-why-that-line-is-acceptable)
  this is a declined cost for a locally-run demo, and the same document names it as the easiest thing here to
  add later.
- Updates are deliberate: read the changelog, run `npm run ci`, commit with the reason.
- **Remove what stops being used.** An unused dependency is pure liability, and the audit that finds it is
  `npm ls` plus a grep, not a tool.
