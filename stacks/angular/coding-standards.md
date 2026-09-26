# Coding Standards — Angular

Conventions for `hotelapp-client-angular`. Target **Angular 22.1**, TypeScript, Tailwind CSS.

Naming that crosses layers — JSON, SQL, URLs, enum values, booleans, dates, money — is fixed in
[glossary-of-conventions.md](../../shared/glossary-of-conventions.md#the-identifier-casing-rule) and
is **not** re-derived here. Folder layout is fixed in
[architecture-specification.md](./architecture-specification.md#folder-layout). This document covers
what those two leave open.

---

## TypeScript

`strict: true` **and `strictTemplates: true`**, plus `noUncheckedIndexedAccess` and
`noImplicitOverride`. **`any` is a review finding**, not a shortcut: this client's contract types are
hand-written rather than generated, so the compiler is the only thing standing between a contract
mismatch and a runtime surprise. Use `unknown` and narrow when a type is genuinely unknown.

`strictTemplates` matters more here than `strict` does. Angular templates are where a type error
otherwise becomes a silent runtime failure, and this client's hand-written contract types only pay off
if templates are checked against them.

| Rule | Detail |
|------|--------|
| `type` vs `interface` | `type` by default. `interface` only where declaration merging is genuinely needed, which is nowhere in this codebase |
| No enums | Use `as const` objects or string-literal unions. TypeScript `enum` emits runtime code and does not match the API's string values cleanly |
| Contract enums | String-literal unions mirroring the API exactly: `type Role = 'GUEST' \| 'FRONT_DESK_STAFF' \| 'PROPERTY_MANAGER'` |
| No non-null `!` | Except immediately after an explicit guard, or on a signal read already guarded in the template by `@if` |
| Return types | Explicit on public members; inferred on local ones |
| No default exports | Named exports only |

**Never model money as `number`.** A money field is `string` in every type in `core/api/types.ts`. Per
[glossary-of-conventions.md](../../shared/glossary-of-conventions.md#money-dates-and-formatting-in-code)
a `number` there is a bug rather than a simplification — the value came from `numeric(10,2)` and must
survive to the pipe intact.

**Unrecognized enum values must not crash.** A `@switch` over a status has a `@default` that renders
the raw value; per
[versioning-strategy.md](../../shared/versioning-strategy.md#what-counts-as-a-breaking-change) adding
an enum value is a change the backend may make, and a `@switch` without `@default` turns that into a
blank region.

---

## Components

**Standalone components only.** No `NgModule` declarations for new code — Angular 22 treats standalone
as the default rather than the modern option.

| Rule | Detail |
|------|--------|
| One component per file | `kebab-case.component.ts`, class `PascalCaseComponent` |
| Change detection | `ChangeDetectionStrategy.OnPush` on **every** component, no exceptions |
| Size | Past ~150 lines of class code, extract. Templates past ~120 lines usually want a child component |
| Inputs / outputs | The `input()` and `output()` functions, not `@Input()` / `@Output()` decorators |
| Required inputs | `input.required<T>()` rather than a non-null assertion on an optional input |
| Page vs. presentational | Page components inject the feature store; presentational children take `input()`s and emit `output()`s, injecting nothing |
| Template location | Inline for under ~30 lines, otherwise a `.html` file. Consistent within a feature |

**Presentational components in `shared/ui/` inject nothing** — no `Router`, no `SessionStore`, no API
service. That is what makes them testable without a `TestBed` provider tree, and it is the rule most
easily broken by a "just this once" `inject(Router)`.

```ts
@Component({
  selector: 'app-reservation-card',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `…`,
})
export class ReservationCardComponent {
  reservation = input.required<ReservationSummary>();
  cancel = output<string>();
}
```

---

## Signals and reactivity

Angular 22 is signal-first, and this codebase is written that way rather than translated into it.

- **`signal()` for local mutable state**, `computed()` for anything derived. A `computed()` that could
  be a plain getter is fine; a field manually kept in sync with another is not.
- **`inject()` in field initializers**, not constructor parameters. Constructor injection still works;
  `inject()` is the current idiom and composes with functional guards and interceptors.
- **`toSignal()` at the boundary** where an `Observable` — router parameters, an API call — enters
  signal-land. Avoid `toObservable()` going the other way unless an RxJS operator is genuinely needed.
- **`effect()` is a last resort.** It is not for deriving state (that is `computed()`) and not for
  fetching (that is the store's `rxMethod`). Legitimate uses here are narrow: the `beforeunload` guard
  on the payment form, and focusing the first invalid control after a failed submit.
- **No `async` pipe on store state.** Stores expose signals; templates read them by call.
- **RxJS is confined to `rxMethod` bodies and the interceptor.** Per
  [state-management.md](./state-management.md#feature-stores) `switchMap` is required there, not
  `mergeMap` — a late response from an abandoned availability search must not overwrite a newer one.

`provideZonelessChangeDetection()` is on, so **nothing may depend on zone-based change detection** —
no `setTimeout` expecting a re-render, no mutation of an object hoping the view notices. State changes
go through signals.

---

## Templates

- **Native control flow only**: `@if`, `@for`, `@switch`, `@let`. Not `*ngIf`, `*ngFor`, `*ngSwitch`.
- **`@for` always has `track`**, keyed on a stable id — never `$index`. On the calendar grid (S11) this
  is a correctness requirement, not a performance nicety.
- Early `@if` branches for loading, error, and empty states rather than nested conditionals. The store
  exposes `isLoading()`, `error()`, and `isEmpty()` precisely so the template reads as three branches.
- `@let` for a value used repeatedly, instead of calling a signal five times in one template.
- No function calls in templates beyond signal reads and pipes. A method invoked from a template runs
  on every check.
- No comments explaining what the markup does — if it needs one, it needs a child component.

---

## Naming

| Thing | Convention | Example |
|-------|-----------|---------|
| Component | `kebab-case.component.ts` / `PascalCaseComponent` | `reservation-card.component.ts` |
| Store | `kebab-case.store.ts` / `PascalCaseStore` | `availability.store.ts` |
| API service | `kebab-case.api.ts` / `PascalCaseApi` | `reservations.api.ts` |
| Guard | `kebab-case.guard.ts` / `camelCaseGuard` | `manager.guard.ts` |
| Pipe | `kebab-case.pipe.ts` / `PascalCasePipe` | `money.pipe.ts` |
| Selector | `app-` + `kebab-case` | `app-reservation-card` |
| Type | `PascalCase` | `ReservationSummary` |
| Constant | `SCREAMING_SNAKE_CASE` | `MAX_STAY_NIGHTS` |
| Output | The event, no `on` prefix | `cancel`, `dateChange` — **not** `onCancel` |
| Boolean | `is` / `has` / `can` | `isLoading`, `hasDiscount`, `canCancel` |
| Folder | `kebab-case` | `admin-rate-plans/` |

> **Note a deliberate difference from the React client.** Angular outputs are named for the event
> (`cancel`) because the template reads `(cancel)=`, while React props are named `onCancel` because
> the prop *is* the handler. Both follow their framework's idiom, and this is one of the framework
> differences [ui-specifications.md](./ui-specifications.md) section 3 exists to hold.

Domain terms use the vocabulary fixed in
[domain-glossary.md](../../shared/domain-glossary.md): a variable holding a reservation is
`reservation`, never `booking`; a property is `property`, never `hotel`, even though "hotel" is the
right word in guest-facing copy. Code and copy diverge here deliberately, and both are specified.

---

## Imports

Order, enforced by ESLint, blank line between groups:

1. Angular packages (`@angular/*`)
2. Third-party (`@ngrx/*`, `rxjs`)
3. Absolute internal (`@core`, `@shared`)
4. Relative (`./`, `../`)
5. Types (`import type`)

Absolute imports via path aliases for anything outside the current feature; relative only within one.
**A feature never imports from another feature** — the rule from
[architecture-specification.md](./architecture-specification.md#folder-layout), enforced by an ESLint
`no-restricted-imports` rule rather than by memory.

---

## Async and data

- Components never inject an `*.api.ts` service or call `HttpClient` directly. Components read the
  store; the store calls the API service; the service goes through the interceptor. Skipping a layer
  bypasses the store's loading and error state.
- Errors are never swallowed. Every failure path produces user-visible feedback per
  [error-handling.md](./error-handling.md).
- **`tapResponse` in every `rxMethod`**, never a bare `error` callback: an unhandled error inside the
  inner observable kills the stream and the store silently stops responding — a failure with no
  visible symptom.
- No manual `subscribe()` in a component. If one is unavoidable, `takeUntilDestroyed()`.

---

## Styling

Tailwind utilities in templates. Tokens from the Tailwind config by name — **no ad-hoc hex values**,
since the token set is shared verbatim with the React client so the two look like one product.

Component `styles` only where a utility genuinely cannot express it, and never `::ng-deep`, which
defeats view encapsulation and is the Angular-specific version of the specificity problem Tailwind
exists to avoid.

Utility order: layout → spacing → sizing → typography → color → state, enforced by
`prettier-plugin-tailwindcss`.

---

## Accessibility in code

Not a separate pass — a coding standard, because retrofitting it is far more expensive:

- Semantic elements first. A `<div (click)>` is a review finding; it is a `<button>`.
- Every input has a `<label for>`.
- `@angular-eslint/template/accessibility-*` rules run as **errors**.
- **Prefer Angular ARIA primitives** — stable in Angular 22 — for dialog, menu, listbox, and tabs,
  rather than hand-rolling focus management. That is the main reason no component library is needed
  here; see [dependency-policy.md](./dependency-policy.md).
- Focus is visible; never removed without a replacement.

---

## Comments

Comment **why**, never **what**. The code says what it does; the comment says why it has to.

Worth a comment in this codebase: why `switchMap` rather than `mergeMap`; why the `Idempotency-Key` is
created in a field initializer rather than the submit handler; why optimistic updates are absent; why
the bootstrap `GET /auth/me` suppresses the `401` redirect; why `provideAppInitializer` must resolve
rather than reject on `401`. Each is a decision a later reader would otherwise "simplify" into a bug.

No commented-out code, no `TODO` without an owner and a reason, no JSDoc restating a signature the
types already give.

---

## Forbidden

| Never | Why |
|-------|-----|
| `bypassSecurityTrustHtml` on user or admin input | XSS. See [security-implementation.md](./security-implementation.md) |
| `localStorage` / `sessionStorage` for session data | There is no token to store; the cookie is `HttpOnly` |
| `any`, `@ts-ignore` | See TypeScript above. `@ts-expect-error` with a reason is the narrow exception |
| `console.log` in committed code | Use the logger — [logging-observability.md](./logging-observability.md) |
| A second money or date formatter | One in `shared/util/format.ts`, exposed as pipes. A second is how the formatting rule breaks quietly |
| Parsing a money string into `number` | Precision loss on a value that came from `numeric(10,2)` |
| `::ng-deep` | Defeats encapsulation; unsupported and slated for removal |
| Legacy structural directives (`*ngIf`, `*ngFor`) | Native control flow only |
| `NgModule` for new code | Standalone is the default |
| `window.location` for in-app navigation | Bypasses the router; use `Router` or `routerLink` |
| Importing across features | Breaks the layout that keeps this codebase navigable |
| `$index` as `@for` track | Reorder bugs and lost input state |
