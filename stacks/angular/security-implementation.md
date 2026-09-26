# Security Implementation — Angular

How `hotelapp-client-angular` implements the policy in
[security-principles.md](../../shared/security-principles.md). Policy lives there; this document says
where each control sits in this codebase and what would break it.

The framing from that document applies throughout: **the server is the only authority.** Every control
here exists for user experience or defense in depth, and every one is assumed bypassable.

---

## Sessions: what this client does and does not do

**Does:** send the session cookie on every request, resolve `GET /auth/me` during app initialization,
and clear everything on `401`.

**Does not:** store, read, refresh, rotate, attach, or inspect any credential. There is nothing to
store — the session cookie is `HttpOnly`, so script cannot read it even deliberately.

| Rule | Where | Consequence of getting it wrong |
|------|-------|---------------------------------|
| `withCredentials: true` on **every** request | `core/api/http.interceptor.ts`, one place | A request that omits it is anonymous, producing a `401` on exactly one screen — a confusing, screen-specific bug |
| Session resolved via `GET /auth/me` | `core/session/session.initializer.ts` | The cookie is unreadable; there is no other way to know |
| Nothing in `localStorage` or `sessionStorage` | — | See the prohibition below |
| `401` → clear state, route to login | the same interceptor | See below |

**`withCredentials` is set in the interceptor, never per call.** Angular's `HttpClient` defaults it to
`false`, so a service that bypasses the interceptor sends no cookie — which is the concrete reason
[architecture-specification.md](./architecture-specification.md#the-api-client-layer) requires all HTTP
to go through it.

### The `401` rule

Implemented once, in the functional interceptor, so no component or store handles it:

1. Clear all feature-store state.
2. Clear the `SessionStore`.
3. Navigate to `/login` with `next` set to the current URL.
4. Toast: "Your session has expired. Please log in again."

**No retry. No refresh call. No queue of pending requests to replay.**

Clearing every feature store — not just the session — is a security requirement, not tidiness: leaving
another guest's reservations in memory on a shared machine is a disclosure bug. The same applies on
explicit logout. Because stores are route-provided, most are discarded by navigation anyway, but the
root-provided ones must be cleared explicitly.

One exception, documented so nobody removes it: the bootstrap `GET /auth/me` suppresses the redirect,
because a `401` there is the expected anonymous answer. Without the suppression the app navigates every
anonymous visitor to login on page load. Relatedly, `provideAppInitializer` must **resolve** on `401`
rather than reject — an anonymous visitor is not a startup failure.

### What must never reappear

> This codebase has **no** token handling, and the absence is deliberate. The project originally
> specified JWT access tokens with rotating refresh tokens and reversed that decision — see
> [decision-log.md](../../shared/decision-log.md) entry 2.
>
> If any of the following appears in this repository, it is the removed design leaking back in, not a
> feature:
>
> - An in-memory access-token store, or a token in a signal, store, or service field
> - A `401`-triggered refresh-and-retry interceptor
> - A request queue awaiting a refreshed credential
> - An `Authorization: Bearer` header
> - A call to `/auth/refresh` — **the endpoint does not exist**
> - Anything reading, decoding, or inspecting a JWT
> - A token in `localStorage`, `sessionStorage`, IndexedDB, or a non-`HttpOnly` cookie
>
> Treat each as a review blocker. `grep -rniE "bearer|jwt|accessToken|refreshToken|auth/refresh"` over
> `src/` should return nothing.
>
> One Angular-specific note: do **not** reach for `HttpClientXsrfModule` or
> `withXsrfConfiguration()`. They implement the cookie-to-header CSRF pattern, which this API does not
> use — it relies on `SameSite=Lax` instead. Adding it would send a header the server ignores and
> imply a mechanism that is not there.

---

## Route guards, and their real status

`authGuard`, `staffGuard`, `managerGuard` in `core/guards/`, as functional `CanActivateFn`s. They keep a
guest from seeing an admin screen shell and a broken page. **They are not access control** — the API
is. A guard that fails open is a UX bug; an API that fails open is a vulnerability, and only one of
those exists here.

**No bootstrap race to handle.** Because `provideAppInitializer` resolves the session before the first
route activates, a guard cannot observe an unresolved session. This is a structural advantage over the
React client, which must check for it in every guard — see
[state-management.md](./state-management.md#session-state). Guards still read defensively, but the
hazard cannot arise.

**Compare rank, not set membership.** `role >= FRONT_DESK_STAFF`, never
`role in {STAFF, MANAGER}`, matching
[api-contracts.md](../../shared/api-contracts.md#authorization). Set membership means a new tier must be
added in every place it is enumerated, and one will be missed.

**Hidden controls follow the same logic as guards**, from one shared `can()` helper reading the
`SessionStore` — so a control's visibility and a route's guard cannot disagree. Hiding a control is
cosmetic; the server still refuses.

---

## XSS

Angular escapes interpolated content by default. The rule is to not defeat it.

**`bypassSecurityTrustHtml` — and every other `DomSanitizer.bypassSecurityTrust*` method — is
prohibited on any path carrying user or admin input**: property descriptions, room-type names and
descriptions, bed configurations, photo captions, guest names, amenity labels. All render as text via
interpolation. Enforced by an ESLint rule and a review blocker, per
[security-principles.md](../../shared/security-principles.md#injection).

`[innerHTML]` is likewise prohibited on API data. Angular sanitizes it, but sanitization is a weaker
guarantee than never parsing the string as markup, and nothing in this application needs rich text.

**URL fields are the one real hazard**, because a manager types them and they become attributes rather
than text: property `photoUrl` and room-type photo `url`.

```ts
export function safeImageUrl(url: string | null): string | null {
  if (!url) return null;
  try {
    const u = new URL(url, window.location.origin);
    return u.protocol === 'https:' || u.protocol === 'http:' ? u.href : null;
  } catch { return null; }
}
```

Every `[src]` built from API data goes through it, returning the placeholder on rejection. This blocks
`javascript:` and `data:` URLs reaching an attribute. Validate on write too (S12), but the read path
cannot assume the write path held — existing rows may predate the validation.

Angular's own URL sanitization already blocks `javascript:` in `[src]` and `[href]`, so this is defense
in depth plus a predictable placeholder rather than a blank image. Also prohibited: injecting API data
into `[style]`, or into a `<script>` or `<style>` element.

---

## Content Security Policy

CSP is served by whatever serves the static assets, **not** by this client's code — a fact worth stating
because no backend is involved and it is therefore the control most easily forgotten. Under the Docker
Compose setup that is the frontend container's web server.

```
default-src 'self';
img-src 'self' https: data:;
script-src 'self';
style-src 'self' 'unsafe-inline';
connect-src 'self' <the configured API origin>;
frame-ancestors 'none';
```

`img-src` must permit the external photo host, since photos are URLs rather than uploads.
`connect-src` must include the configured API origin, which differs per backend — and is why the runtime
`window.__HOTELAPP_CONFIG__` mechanism and the CSP have to be configured together, per
[environment-setup-guide.md](./environment-setup-guide.md).

`style-src 'unsafe-inline'` is required by Angular's component style injection and cannot simply be
dropped here. Do **not** add `'unsafe-inline'` to `script-src` — that would forfeit most of CSP's value.
Angular's build output needs no inline script, so `script-src 'self'` holds.

---

## Payment data

The payment form (S6) collects card-shaped input and the backend keeps only brand and last four.

**In this client, card data exists only in the form's signal state and is discarded when the component
is destroyed.** It is never:

- written to `localStorage`, `sessionStorage`, or any store
- placed in a URL, query parameter, or router state
- logged, at any level, in any environment
- included in an error report or breadcrumb
- patched into a feature store — which is why the booking submission is a direct API call from the
  component's form rather than store-held state

The prominent demo banner required by
[ui-specifications.md](./ui-specifications.md) is a security control, not copy: a form that looks real
without saying otherwise invites a real card.

---

## Input validation

Client validation is **UX, not security** — it gives fast feedback and reduces round-trips. The server
validates independently, rejects unknown fields, and never trusts this client.

Two things follow that are easy to get wrong:

**Never send a server-owned value.** `POST /reservations` has **no price field** by contract design;
this client must not add one. Same for `role`, `status`, `confirmationNumber`, `cancellationDeadline`,
and every `*_at` timestamp. The field's absence is the control. Reactive and signal forms make it easy
to `patchValue` a whole object at a server endpoint — send an explicit payload, not a form dump.

**Never weaken a client check to match a bug.** If the server rejects something the client allowed, the
client is wrong.

---

## Dependencies

Per [security-principles.md](../../shared/security-principles.md#dependencies): pinned versions,
`package-lock.json` committed, `npm ci` in CI. Prefer platform and framework primitives over a small
package — which Angular 22 makes materially easier, since **Angular ARIA is stable** and supplies
accessible dialog, menu, listbox, and tab behavior without a component library. No dependency
scanning — a declined cost, explained there; the same document names it as the easiest item to add
later.

No third-party script tags: no analytics, no tag manager, no font CDN beyond the permitted stylesheet
origin. Each would be script execution in the app's origin with access to the DOM of a page that handles
credentials. Detail in [dependency-policy.md](./dependency-policy.md).

---

## Deliberately absent

| Absent | Why |
|--------|-----|
| CSRF token handling, `HttpClientXsrfModule` | `SameSite=Lax` covers it, because **no `GET` endpoint mutates state** — [security-principles.md](../../shared/security-principles.md#sessions). That invariant is what makes this safe, so adding a state-changing `GET` would silently break it |
| Client-side rate limiting | The server limits; a client limiter is trivially bypassed and would only mislead |
| Encryption of anything client-side | Nothing is stored; a key shipped to the browser protects nothing |
| Session timeout warning / countdown | The 8-hour sliding window rarely expires mid-use, and a countdown would need a token to inspect — which is exactly what this design removed |
| Subresource Integrity | No third-party scripts to pin |
| A token refresh mechanism | No tokens. See the prohibition above |
