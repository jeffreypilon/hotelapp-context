# Dependency Policy — Angular

What may be added to `hotelapp-client-angular`, what may not, and how to decide.

The governing rule is from
[security-principles.md](../../shared/security-principles.md#dependencies): **prefer the framework's own
primitives over a small package**, because every dependency is added attack surface and added maintenance.
The "deliberately absent" table in
[architecture-specification.md](./architecture-specification.md#deliberately-absent) already settled several
specific cases; this document does not reopen them.

Angular makes this rule easier to follow than most frameworks, because the platform ships more: routing,
HTTP, forms, and — as of Angular 22 — **accessible component primitives via Angular ARIA**. Much of what a
React project reaches for is already here.

---

## The approved set

Everything this client needs. Versions are pinned exactly, with `package-lock.json` committed and `npm ci`
in CI.

| Package | Role | Why it earns its place |
|---------|------|------------------------|
| `@angular/core`, `common`, `router`, `forms`, `platform-browser` | The framework | 22.1 |
| `@angular/aria` | Accessible dialog, menu, listbox, tab primitives | **Stable in Angular 22.** This is what removes the need for a component library |
| `@ngrx/signals` | Feature state | Decided with reasoning in [state-management.md](./state-management.md#the-library-decision) |
| `@ngrx/operators` | `tapResponse` | Required in every `rxMethod` — see [coding-standards.md](./coding-standards.md#async-and-data) |
| `rxjs` | Async primitives inside `rxMethod` and the interceptor | An Angular peer dependency; confined to those two places |
| `tailwindcss` | Styling | Decided at system level |
| `prettier-plugin-tailwindcss` | Utility ordering | Removes a recurring review topic |
| `@angular/cli`, `@angular-devkit/build-angular` | Build | Local, not global |
| `typescript` | | `strict` + `strictTemplates` |
| `vitest`, `@analogjs/vitest-angular` (or the CLI's supported Vitest integration), `jsdom` | Testing | [testing-standards.md](./testing-standards.md) |
| `axe-core` | Accessibility assertions | |
| `eslint`, `angular-eslint`, `prettier` | Lint and format | Including `@angular-eslint/template/accessibility-*` as **errors** |

**No separate form or validation library.** Signal forms are stable in Angular 22 and typed reactive forms
remain available; validators are functions. This is where the React client needs two dependencies
(`react-hook-form`, `zod`) and this one needs none — a genuine asymmetry, and the clearest example of the
"prefer framework primitives" rule paying off differently per stack.

**No `clsx` equivalent.** Angular's `[class.foo]` and `[ngClass]` bindings cover conditional classes natively.

---

## Explicitly not allowed

Each of these is a decision already made elsewhere, restated as a prohibition so it is not relitigated one
pull request at a time.

| Not allowed | Instead | Decided in |
|-------------|---------|-----------|
| Angular Material, PrimeNG, Ng-Zorro, Ng-Bootstrap | Angular ARIA primitives + `shared/ui/` over Tailwind tokens | [architecture-specification.md](./architecture-specification.md#styling) |
| Axios or any HTTP client | `HttpClient` through the interceptor — which **is** the interceptor layer | [architecture-specification.md](./architecture-specification.md#the-api-client-layer) |
| `@ngrx/store`, `@ngrx/effects`, `@ngrx/entity`, NGXS, Akita, Elf | `@ngrx/signals` | [state-management.md](./state-management.md#the-library-decision) |
| A date library — Moment, date-fns, Day.js, Luxon | `Intl.DateTimeFormat` in `shared/util/format.ts`, exposed as pipes | See below |
| A money library — Dinero, currency.js | Money is a **string** end to end; it is formatted, never arithmetic'd | [glossary-of-conventions.md](../../shared/glossary-of-conventions.md#money-dates-and-formatting-in-code) |
| Angular Universal / SSR / prerendering | Browser-only SPA | [architecture-overview.md](../../shared/architecture-overview.md#frontend-architecture-in-outline) |
| OpenAPI type generators | Hand-written types; a generator would make a backend authoritative over the contract | [architecture-specification.md](./architecture-specification.md#the-api-client-layer) |
| A JWT library — `jwt-decode`, `jose`, `@auth0/angular-jwt` | **There are no tokens.** See [security-implementation.md](./security-implementation.md#what-must-never-reappear) |
| `HttpClientXsrfModule` / `withXsrfConfiguration()` | Nothing — the API relies on `SameSite=Lax`, not a CSRF header | [security-implementation.md](./security-implementation.md#what-must-never-reappear) |
| Analytics, tag managers, session replay — GA, Segment, Sentry, LogRocket, Hotjar | Nothing. [logging-observability.md](./logging-observability.md) explains why |
| A charting library — ngx-charts, Chart.js, D3 | The reports are tables and stat tiles; charts are a stated future enhancement | [ui-specifications.md](./ui-specifications.md) S14 |
| A drag-and-drop or file-upload library | **There is no file upload** — photos are URLs | [data-model.md](../../shared/data-model.md#room_type_photos) |
| `@angular/localize`, `ngx-translate` | English only | [non-functional-requirements.md](../../shared/non-functional-requirements.md) |
| `lodash`, `underscore`, `ramda` | Native array and object methods cover everything here |
| A polyfill bundle — `core-js`, `zone.js` beyond the framework's own | Evergreen browsers only; and `provideZonelessChangeDetection()` is on | [non-functional-requirements.md](../../shared/non-functional-requirements.md#browser-and-device-support) |
| `moment-timezone` | `Intl.DateTimeFormat` with a `timeZone` option — see below |
| A virtual-scroll package | The calendar's 60-day cap bounds the grid; virtualizing a sticky-header grid costs more than it saves | [ui-specifications.md](./ui-specifications.md) S11 |

### On date libraries specifically

The temptation is real, because this application renders three different things: calendar dates with no time
(`checkInDate`), a timestamp in the **property's** timezone (`cancellation.deadline`), and dense table dates.

All three are `Intl.DateTimeFormat`, which is built in, needs no bundle, and — importantly — accepts a
`timeZone` option, so rendering the cancellation deadline in `America/New_York` regardless of the browser's
zone is a one-liner. Angular's own `DatePipe` handles most of it, with custom pipes over
`shared/util/format.ts` for the property-timezone case. A date library would add 15–70 KB to do what the
platform already does, and the one genuinely subtle case (never constructing a `Date` from a `YYYY-MM-DD`
string in a way that shifts the day) is a discipline no library enforces for you.

If date *arithmetic* ever becomes genuinely awkward, `Temporal` is the answer to watch rather than a library
to add.

---

## Adding something new

Five questions, in order. A "no" at any point is the answer.

1. **Does Angular, TypeScript, or the browser already do this?** Angular ARIA, `HttpClient`, signal forms,
   `DatePipe`, `Intl`, `crypto.randomUUID`, `URL`, `AbortController`. The answer here is yes more often than
   in most frameworks, which is the point of choosing a batteries-included one.
2. **Is it already prohibited above?** Then it needs a documented decision reversal, not a pull request.
3. **What does it weigh, and what does it pull in?** Check the transitive tree, not just the headline size.
   This client's bundle budget is the tighter of the two relative to framework baseline, so weight matters
   more here.
4. **Is it maintained, and does it support this Angular version?** An Angular library pinned to an older
   major is a migration blocker, which is a cost a package's README never mentions. Confirm it supports
   standalone components and signals rather than requiring `NgModule`s.
5. **Could fifty lines in `shared/util/` replace it?** If yes, write the fifty lines. They will be
   understood, tested, and free of a supply-chain relationship.

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
shared CSP guidance, but self-hosting removes a third-party request from the critical path and a privacy
consideration with it, at the cost of a few files in `public/`.

---

## Maintenance

- **Exact versions**, no `^` or `~`. A reviewer cloning this repo gets the build the author had.
- `package-lock.json` committed; `npm ci` in CI, never `npm install`.
- **Angular packages move together.** `@angular/*` are upgraded as a set via `ng update`, never individually
  — a mismatched `@angular/core` and `@angular/router` fails in ways that look like application bugs.
- **No automated dependency updates** — no Dependabot, no Renovate. Per
  [security-principles.md](../../shared/security-principles.md#out-of-scope-and-why-that-line-is-acceptable)
  this is a declined cost for a locally-run demo, and the same document names it as the easiest thing here to
  add later.
- Updates are deliberate: read the changelog, run `npm run ci`, commit with the reason.
- **Remove what stops being used.** An unused dependency is pure liability, and the audit that finds it is
  `npm ls` plus a grep, not a tool.
