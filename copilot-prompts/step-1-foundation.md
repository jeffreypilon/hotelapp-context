# Phase 7 Step 1 — foundation

Produced `hotelapp-client-react@fbcd8df`.

```
HotelApp — React Phase 7, Step 1: foundation (Phase 7 item 1 + session bootstrap)

Read first, in order: hotelapp-context/context-map.md, shared/api-contracts.md (GET /properties
and GET /auth/me), stacks/react/architecture-specification.md, stacks/react/state-management.md,
stacks/react/error-handling.md, stacks/react/security-implementation.md,
stacks/react/environment-setup-guide.md. Stay in stacks/react/ only — never read
stacks/angular/ or stacks/nodejs/ for implementation guidance, even though several of these
documents are byte-identical to their Angular counterparts through certain sections.

CURRENT STATE (confirmed by reading the actual files, don't assume): Step 0 already built a bare
App shell (just an <Outlet/>), a minimal S1 property list with no search/filter/sort/pagination,
a GET-only fetch wrapper with no error-mapping and no 401 handling, and package.json with
Tailwind/Vite/TanStack Query/React Router but no ESLint, Prettier, Vitest, React Testing Library,
react-hook-form, or zod installed. QueryClient is constructed with zero defaultOptions.

SCOPE — do all of the following, and nothing from items 2-6 (no property-detail screen, no
search, no auth screens, no booking flow, no account screens):

1. Toolchain: add ESLint + Prettier (zero-warning CI per architecture-specification.md) and
   Vitest + React Testing Library per testing-standards.md. Make `npm run lint`, `npm run
   typecheck`, `npm run test:run` actually pass. Do NOT add react-hook-form or zod yet — nothing
   in this step's scope is a form; the S1 search/city inputs are plain controlled inputs synced to
   the URL, not a form-library concern. Adding it now would be reaching for a dependency before
   the step that needs it (S5).

2. QueryClient defaults, in main.tsx: staleTime 30_000, gcTime 5*60_000, refetchOnWindowFocus
   false, and retry: (count, err) => count < 2 && !isClientError(err) exactly per
   state-management.md's Defaults section. The current `new QueryClient()` has none of this,
   which means TanStack Query's library default (retries on ANY error, including 4xx) is silently
   active right now — a 404 or a validation 400 currently retries 2-3 times before the error
   state renders. Fix this now; don't let it ride into later steps where a 401 or 404 becomes
   common and the extra round-trips become a visible delay.

3. Query key factory at api/queryKeys.ts, per state-management.md's `qk` object — at minimum
   `session`, `properties(params)`, `property(id)`, `roomTypes(propertyId)`, `roomType(id)` for
   this step (add the rest as later steps need them, not speculatively). Migrate
   useProperties.ts off its current ad-hoc `["properties", "list"]` key onto `qk.properties(params)`
   — every query parameter that changes the result must be IN the key, per that document's own
   flagged "most likely cache bug" warning. This matters starting now: the moment S1 gets a city
   filter, a key that doesn't include it will serve the unfiltered cache for every filtered view.

4. Full fetch wrapper in api/client.ts: add POST/PATCH/PUT/DELETE, Idempotency-Key header
   passthrough, and the global 401 rule from state-management.md and
   security-implementation.md — on any 401: queryClient.clear() (all cached data, not just
   session — leaving another user's data in cache on a shared machine is a disclosure bug, not
   just a UX one), clear session context, route to /login?next=<path>, show "Your session has
   expired. Please log in again." No retry, no refresh call — if you write anything that reads,
   decodes, or refreshes a token, stop, that's the removed JWT design leaking back in
   (decision-log.md entry 2).

   THE ONE SUBTLE PART: GET /auth/me during bootstrap must NOT trigger this redirect — a 401
   there is the correct anonymous answer, and without an explicit suppression flag on that one
   call, every anonymous page load bounces to /login. Build the flag, and verify BOTH paths
   explicitly: (a) an expired/invalid session on a protected-feeling request still redirects, and
   (b) a genuinely fresh incognito window with no cookie at all loads the property list without
   ever touching /login. Don't rely on (a) alone — a dev browser that's had a valid cookie set
   from earlier manual testing will pass (b) by accident even with the suppression flag missing,
   because there's no 401 to mishandle yet. Test it cookie-free.

5. Session: session/AuthProvider.tsx + useSession, per state-management.md — a useQuery on
   GET /auth/me with staleTime: Infinity, retry: false, exposing
   { user, isResolved, role, propertyId }. isResolved is what every future route guard waits on;
   it doesn't matter yet since no guard exists in this step, but the context needs to exist now so
   item 4 wires guards against it rather than inventing session access twice.

6. Error-mapping module at lib/errors/messages.ts, per error-handling.md section 5 — the code→
   message table as data, resolveError(err) falling back by status class for any code not yet in
   the table (only NOT_FOUND and generic fallbacks are actually exercised by this step's one
   screen; add the rest of section 2's table now anyway since it's pure data entry and every later
   step needs entries already present rather than growing this file piecemeal).

7. Real S0 shell: header (wordmark linking to property list, primary nav, user-area), footer
   (copyright + "Demo application — no real bookings"), mobile hamburger below 768px. User-area
   renders per its 5-state table — but only Resolving and Anonymous are actually reachable this
   step (Guest/Front Desk/Manager need item 4's login to exist; wire the JSX for all 5 states from
   the spec, but note in your step summary that only 2 of 5 are exercised, don't claim you
   verified all 5).

8. S1 to its full spec: search field + city filter + sort control (name/city) + pagination, all
   as URL query parameters via useSearchParams (not component state). Extend
   api/endpoints/properties.ts's listProperties to accept and forward page/pageSize/sort/city/q
   to GET /properties. Keep the existing loading/empty/error treatment; add the "empty because
   filtered" variant ("No hotels match your search." + "Clear filters") distinct from "empty
   because no data" per ui-specifications.md's S1 states table.

9. lib/format.ts: money and date formatters, even though S1 doesn't render money — get this
   started now since architecture-specification.md is explicit that it must be the ONLY place
   these are formatted, and the sooner it exists, the less likely a second ad-hoc formatter
   appears in item 2's property-detail screen next.

10. Rewrite this repo's .github/copilot-instructions.md build/test section with commands you
    actually ran (mirroring the discipline already applied to hotelapp-server-springboot's
    instructions after each step) — it currently still says "this repository is empty."

NOT in scope for this step: property detail (S2), room-type detail, search/availability (S3),
login/register screens (S5) or route guards (RequireAuth etc. — nothing to guard yet), any
booking or account screen. Don't scaffold empty folders for them speculatively.

VERIFICATION before calling this done: npm run lint / typecheck / test:run all green. Manually:
anonymous incognito load of localhost:5173 shows the property list with no redirect; searching
and filtering update the URL and survive a hard reload; sort by city works; an out-of-range page
returns the same "not clamped" 400 behavior the backend already enforces (check
error-handling.md's fallback message renders sanely for it, since VALIDATION_FAILED isn't
explicitly mapped for a page-level context yet). Confirm CORS is not an issue you need to
touch — Spring Boot's application.properties already defaults CORS_ALLOWED_ORIGINS to include
localhost:5173 (verified by reading WebConfig.java), so if something breaks it's very unlikely to
be that.

Flag any judgment call you make the way Spring Boot's steps did — in code comments, and
summarized at the end. Separate checkable facts (test counts, commands actually run) from
judgment calls, and don't state a checkable fact unless the command producing it is in this
session's actual tool calls.
```
