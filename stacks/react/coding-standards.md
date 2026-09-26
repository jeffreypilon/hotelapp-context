# Coding Standards — React

Conventions for `hotelapp-client-react`. Target **React 19.3**, TypeScript, Tailwind CSS.

Naming that crosses layers — JSON, SQL, URLs, enum values, booleans, dates, money — is fixed in
[glossary-of-conventions.md](../../shared/glossary-of-conventions.md#the-identifier-casing-rule) and
is **not** re-derived here. Folder layout is fixed in
[architecture-specification.md](./architecture-specification.md#folder-layout). This document covers
what those two leave open.

---

## TypeScript

`strict: true`, plus `noUncheckedIndexedAccess` and `noImplicitOverride`. **`any` is a review
finding**, not a shortcut: this client's contract types are hand-written rather than generated, so the
compiler is the only thing standing between a contract mismatch and a runtime surprise. Use `unknown`
and narrow when a type is genuinely unknown.

| Rule | Detail |
|------|--------|
| `type` vs `interface` | `type` by default. `interface` only where declaration merging is genuinely needed, which is nowhere in this codebase |
| No enums | Use `as const` objects or string-literal unions. TypeScript `enum` emits runtime code and does not match the API's string values cleanly |
| Contract enums | String-literal unions mirroring the API exactly: `type Role = 'GUEST' \| 'FRONT_DESK_STAFF' \| 'PROPERTY_MANAGER'` |
| No non-null `!` | Except immediately after an explicit guard, where it is a readability choice rather than an assertion about unknown data |
| Return types | Explicit on exported functions; inferred on local ones |
| No default exports | Named exports only, so a symbol has one name across the codebase and rename-refactors are reliable |

**Never model money as `number`.** A money field is `string` in every type in `api/types.ts`. Per
[glossary-of-conventions.md](../../shared/glossary-of-conventions.md#money-dates-and-formatting-in-code)
a `number` there is a bug rather than a simplification — the value came from `numeric(10,2)` and must
survive to the formatter intact.

**Unrecognized enum values must not crash.** Rendering an unexpected status or rate category shows the
raw value rather than throwing; per
[versioning-strategy.md](../../shared/versioning-strategy.md#what-counts-as-a-breaking-change) adding
an enum value is a change the backend may make, and a `switch` with no `default` turns that into a
blank screen.

---

## Components

**Function components only.** No classes, with one permitted exception: an error boundary, which has
no hook equivalent.

| Rule | Detail |
|------|--------|
| One component per file | Filename matches the component, `PascalCase.tsx` |
| Size | Past ~150 lines, extract. A long component is usually two components and a hook |
| Props | A named `Props` type, destructured in the signature. No `React.FC` — it adds nothing and historically complicated `children` typing |
| Container vs. presentational | Route-level components own queries and mutations; children take data as props and fetch nothing |
| No prop drilling past two levels | Past that, either the child should own its query or the value belongs in the session context |
| `children` | Typed `ReactNode`. Prefer composition over a `render` prop |

**Presentational components in `components/ui/` take no dependency on the router, the session, or the
query client.** That is what makes them testable without a provider tree, and it is the rule most
easily broken by a "just this once" `useNavigate`.

```tsx
type Props = { reservation: ReservationSummary; onCancel: (id: string) => void };

export function ReservationCard({ reservation, onCancel }: Props) { … }
```

---

## Hooks

- Custom hooks are `useThing`, one per file, in the owning feature's `hooks/` folder.
- A hook that fetches is named for its data: `usePropertyQuery`, `useCancelReservation`.
- `useEffect` is a last resort. It is **not** for fetching — that is TanStack Query's job — and not
  for deriving state, which is what a plain computed value is for. Legitimate uses here are narrow:
  subscribing to a browser event, and the `beforeunload` guard on the payment form.
- Dependency arrays are complete. `eslint-plugin-react-hooks` runs as an **error**, never a warning;
  silencing it with a comment requires a comment explaining why.
- No conditional hooks, no hooks in loops.

**`useMemo` and `useCallback` only where a measurement or an obvious cost justifies them.** One place
genuinely qualifies: expanding calendar segments into grid cells on S11, per
[ui-specifications.md](./ui-specifications.md). Memoizing everything is noise that makes the one real
case invisible.

---

## Naming

| Thing | Convention | Example |
|-------|-----------|---------|
| Component file and symbol | `PascalCase` | `ReservationCard.tsx` |
| Hook | `useCamelCase` | `useAvailabilitySearch.ts` |
| Non-component module | `camelCase.ts` | `queryKeys.ts`, `format.ts` |
| Type | `PascalCase` | `ReservationSummary` |
| Constant | `SCREAMING_SNAKE_CASE` | `MAX_STAY_NIGHTS` |
| Event handler prop | `on` + event | `onCancel`, `onDateChange` |
| Event handler implementation | `handle` + event | `handleCancel` |
| Boolean | `is` / `has` / `can` | `isLoading`, `hasDiscount`, `canCancel` |
| Folder | `kebab-case` | `admin-rate-plans/` |

Domain terms use the vocabulary fixed in
[domain-glossary.md](../../shared/domain-glossary.md): a variable holding a reservation is
`reservation`, never `booking`; a property is `property`, never `hotel`, even though "hotel" is the
right word in guest-facing copy. Code and copy diverge here deliberately, and both are specified.

---

## Imports

Order, enforced by ESLint, blank line between groups:

1. React
2. Third-party
3. Absolute internal (`@/api`, `@/components`, `@/lib`)
4. Relative (`./`, `../`)
5. Types (`import type`)

Absolute imports via a `@/` alias for anything outside the current feature; relative only within one.
**A feature never imports from another feature** — the rule from
[architecture-specification.md](./architecture-specification.md#folder-layout), enforced by an ESLint
`no-restricted-imports` rule rather than by memory.

`import type` for type-only imports, so the bundler can drop them.

---

## Async and data

- `async`/`await`, not `.then()` chains.
- Components never call `fetch` or an `api/endpoints/` function directly. Screens call hooks; hooks
  call endpoints; endpoints call the wrapper. Skipping a layer bypasses the cache.
- Errors are never swallowed. Every failure path produces user-visible feedback per
  [error-handling.md](./error-handling.md).
- No `try`/`catch` around a query — TanStack Query surfaces `error` as state, and catching it hides it
  from the screen.

---

## JSX

- Early return for loading, error, and empty states rather than nesting ternaries. Three nested
  ternaries in a return statement is the signature of a component that should have returned early.
- `&&` for conditional rendering; ternaries only for either/or. Guard against `0 && …` rendering a
  literal `0` — use an explicit boolean.
- `key` is a stable id, never an array index, in every list.
- No inline object or arrow props in hot lists (the calendar); acceptable elsewhere.
- Fragments as `<>`, except when a `key` is needed.
- No comments in JSX explaining what the markup does — if it needs one, the component needs a name.

---

## Styling

Tailwind utilities in `className`. `clsx` for conditionals. Tokens from the Tailwind config by name —
**no ad-hoc hex values**, since the token set is shared verbatim with the Angular client so the two
look like one product.

Utility order: layout → spacing → sizing → typography → color → state. `prettier-plugin-tailwindcss`
enforces it, so it is never a review topic.

Past roughly a dozen utilities on one element, extract a component rather than reaching for `@apply`,
which recreates the specificity problems Tailwind exists to avoid.

---

## Accessibility in code

Not a separate pass — a coding standard, because retrofitting it is far more expensive:

- Semantic elements first. A `<div onClick>` is a review finding; it is a `<button>`.
- Every input has a `<label>` with `htmlFor`.
- `eslint-plugin-jsx-a11y` runs as an **error**.
- Icon-only controls carry `aria-label`.
- Focus is visible; focus is never removed with `outline: none` without a replacement.
- Dialogs trap focus and restore it to the invoking element on close.

---

## Comments

Comment **why**, never **what**. The code says what it does; the comment says why it has to.

Worth a comment in this codebase: why `retry` excludes `4xx`; why the `Idempotency-Key` is created on
mount rather than per submit; why optimistic updates are absent; why the bootstrap `GET /auth/me`
suppresses the `401` redirect. Each is a decision a later reader would otherwise "simplify" into a
bug.

No commented-out code, no `TODO` without an owner and a reason, no JSDoc restating a signature the
types already give.

---

## Forbidden

| Never | Why |
|-------|-----|
| `dangerouslySetInnerHTML` on any user or admin input | XSS. See [security-implementation.md](./security-implementation.md) |
| `localStorage` / `sessionStorage` for session data | There is no token to store; the cookie is `HttpOnly` |
| `any`, `@ts-ignore` | See TypeScript above. `@ts-expect-error` with a reason is the narrow exception |
| `console.log` in committed code | Use the logger — [logging-observability.md](./logging-observability.md) |
| A second money or date formatter | One in `lib/format.ts`. A second is how the formatting rule breaks quietly |
| Parsing a money string into `number` | Precision loss on a value that came from `numeric(10,2)` |
| `window.location` for in-app navigation | Bypasses the router; use `useNavigate` or `<Link>` |
| Importing across features | Breaks the layout that keeps this codebase navigable |
| Index as a React `key` | Reorder bugs and lost input state |
