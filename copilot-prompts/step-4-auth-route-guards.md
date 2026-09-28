# Phase 7 Step 4 — auth, route guards

Produced `hotelapp-client-react@69f6924`.

```
HotelApp — React Phase 7, Step 4: auth (login, registration, route guards)

Read first: shared/api-contracts.md (POST /auth/login, POST /auth/register, the 429 Retry-After
behavior under rate limiting), stacks/react/ui-specifications.md's S5 entry,
stacks/react/error-handling.md section 2 (401/402/403/409/429 tables — S5 uses
INVALID_CREDENTIALS, ACCOUNT_INACTIVE, EMAIL_ALREADY_REGISTERED, VALIDATION_FAILED, RATE_LIMITED),
stacks/react/security-implementation.md (route guards section, and the banned-patterns grep at
the end — run it as part of verification), stacks/react/state-management.md (how login/register
write the session cache), stacks/react/architecture-specification.md (the RequireAuth code
sample and route tree). Stay in stacks/react/ only.

CURRENT STATE (confirmed by reading the actual repo — Phase 7 Step 3 is commit 83cb778):
`session/AuthProvider.tsx` and `useSession` already exist and are correct (staleTime: Infinity,
retry: false, isResolved). `Header.tsx`'s `UserArea` already links to `/login` and `/register` —
both currently 404 to S15, this step is what fills them in. `useLogout` already works.
`react-hook-form` and `zod` are STILL not installed despite being this repo's stated forms
approach — first screen that actually needs them. No `guards/` folder exists. `api/client.ts`'s
`ApiError` does not currently capture the `Retry-After` header — needed for `RATE_LIMITED`,
described below. Note: `Header`'s `UserArea` is simplified relative to ui-specifications.md's full
five-state table (no "My reservations"/"Profile" menu for a Guest, no property switcher for a
Manager) — that's pre-existing from Step 1 and not this step's problem to fix; those menu items'
targets don't exist until Step 6 (guest account) and Phase 6 items 9-12 (admin), so leave it.

PREAMBLE — close part of Step 3's test-coverage gap first, cheaply: `features/search/validation.ts`
shipped with zero tests last step. Before starting this step's own scope, add unit tests for
`validateDateRange` covering: exactly 30 nights (passes), 31 nights (MAX_STAY), same-day range
(AFTER_CHECK_IN), check-in equal to today (passes — "not in the past" means today counts), and a
past check-in date (PAST_DATE). This is deliberately scoped to just the pure function, not a full
`SearchScreen` component-test suite — that fuller gap is being carried forward, not closed here.

SCOPE — item 4 only: S5 (login, registration) and the route-guard components. Do NOT build S4
(booking summary), S6/S7 (payment/confirmation), or S8 (account) — none of those routes exist yet,
so anything this step builds that would normally live inside them (e.g. an actual protected
screen) doesn't exist to wrap. See point 6 below for how to still verify the guards without one.

1. Install `react-hook-form` and `zod` (per dependency-policy.md — pinned versions, lockfile
   committed as usual).

2. api/types.ts: LoginRequest {email, password}, RegisterRequest {firstName, lastName, email,
   password, phone?: string | null}. Register and login return the same body shape (a `user`),
   per ui-specifications.md — reuse whatever type `getMe` already returns rather than inventing a
   second one.
   api/endpoints/auth.ts: add login(body), register(body) — both POST, both need the session
   cache written directly with the response, not a redundant refetch (point 5 below).

3. api/client.ts: capture `Retry-After` on the `ApiError` thrown for a 429 (read the response
   header before throwing) — nothing downstream can show the "try again in N" countdown that
   ui-specifications.md's RATE_LIMITED handling requires without it. This is a real gap in the
   current wrapper, not a hypothetical.

4. lib/validation/authSchemas.ts: Zod schemas for login (email, password) and registration
   (firstName, lastName, email, password min 12 characters, phone optional). Per
   security-principles.md, there are NO character-class requirements — the schema and the UI copy
   must not imply any (no "must contain a symbol", no strength meter). React Hook Form + these
   schemas via `zodResolver`.

5. features/auth/LoginScreen.tsx, RegisterScreen.tsx at /login and /register, one shared layout,
   a link between them that preserves `?next=`. On success: `setQueryData(qk.session(), { user:
   response.user, networkError: false })` — per state-management.md, this avoids a redundant
   `GET /auth/me` — then navigate to `?next=` if present, else `/` for a guest, else
   `/admin/reservations` for Staff/Manager (that route doesn't exist until Phase 6 items 9-12 are
   built in some future phase — it 404s to S15, same deferred pattern as everything else so far).

   Error handling exactly per error-handling.md's table: INVALID_CREDENTIALS is form-level,
   NEVER field-level (the server deliberately doesn't say which field is wrong — inventing that
   distinction client-side would leak information the API withholds on purpose).
   ACCOUNT_INACTIVE form-level. EMAIL_ALREADY_REGISTERED field-level on `email`, with a link to
   `/login`. VALIDATION_FAILED field-level via `errors[]` and `setError`. RATE_LIMITED form-level,
   disabling submit for the `Retry-After` duration with a visible countdown (needs point 3 above).
   Password field: show/hide toggle, "At least 12 characters" shown up front as a plain
   requirement, not a strength meter. Autocomplete: `email` + `current-password` on login,
   `new-password` on registration.

6. guards/RequireAuth.tsx, RequireStaff.tsx, RequireManager.tsx exactly per
   architecture-specification.md's code sample — wait for `isResolved` before deciding anything
   (the "redirects an authenticated user to login on every refresh" bug the spec calls out by
   name), redirect to `/login?next=<pathname+search>` when there's no user, compare **rank**, not
   set membership, for the staff/manager checks (Role is a string union with no inherent order —
   add a small rank map, e.g. `{ GUEST: 0, FRONT_DESK_STAFF: 1, PROPERTY_MANAGER: 2 }`, and compare
   `>=`). Since nothing in the app is protected yet (S4/S8/admin don't exist), prove these guards
   work with a small test-only protected route in `routes.test.tsx` rather than waiting for a real
   screen to hang them on — assert an anonymous visit redirects to `/login?next=...` with the
   original path preserved, and an authenticated one renders the child route. This also starts
   closing this step's own test coverage rather than adding to Step 3's carried-forward debt.

7. Verification banned-pattern check, per security-implementation.md: run
   `grep -rniE "bearer|jwt|accessToken|refreshToken|auth/refresh" src/` and confirm it returns
   nothing. This is a specified review gate in that document, not optional-extra caution — the
   project reversed a JWT design once already (decision-log.md entry 2) and it's called out by
   name as something that could quietly leak back in.

NOT in scope: S4, S6, S7, S8, admin. Don't scaffold their folders speculatively, and don't wrap
any currently-existing route in a guard that doesn't need one yet — Header's existing links are
all public.

VERIFICATION: npm run lint / typecheck / test:run / build all green (test count should be higher
than Step 3's 33, both from the validation.ts preamble and the new auth/guard tests). Manually:
register a new guest account (the `hotelapp` database currently has zero users — this is the
first time one gets created), confirm the session cookie appears in DevTools as `HttpOnly` with
`SameSite=Lax`; log out and log back in with the same credentials; attempt login with a wrong
password and confirm the message is form-level and generic, never naming which field was wrong;
register the same email twice and confirm the second attempt shows the field-level
already-registered message with a working link to `/login`; reload mid-session and confirm you're
still logged in (bootstrap still works); confirm nothing appears in `localStorage`/
`sessionStorage` (DevTools → Application) after any of the above — this is the check
environment-setup-guide.md calls "the one people skip and the one that catches a real policy
breach."

Flag judgment calls in code and summarize them at the end, same discipline as every prior step.
```
