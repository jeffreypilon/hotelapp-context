# Security Implementation — React

How `hotelapp-client-react` implements the policy in
[security-principles.md](../../shared/security-principles.md). Policy lives there; this document says
where each control sits in this codebase and what would break it.

The framing from that document applies throughout: **the server is the only authority.** Every control
here exists for user experience or defense in depth, and every one is assumed bypassable.

---

## Sessions: what this client does and does not do

**Does:** send the session cookie on every request, ask `GET /auth/me` on startup whether a session
exists, and clear everything on `401`.

**Does not:** store, read, refresh, rotate, attach, or inspect any credential. There is nothing to
store — the session cookie is `HttpOnly`, so script cannot read it even deliberately.

| Rule | Where | Consequence of getting it wrong |
|------|-------|---------------------------------|
| `credentials: 'include'` on **every** request | `api/client.ts`, one place | A request that omits it is anonymous, producing a `401` on exactly one screen — a confusing, screen-specific bug |
| Session discovered via `GET /auth/me` | `session/AuthProvider` | The cookie is unreadable; there is no other way to know |
| Nothing in `localStorage` or `sessionStorage` | — | See the prohibition below |
| `401` → clear state, route to login | `api/client.ts` | See below |

### The `401` rule

Implemented once, in the fetch wrapper, so no screen handles it:

1. `queryClient.clear()` — **all** cached server data, not just the session.
2. Clear the session context.
3. Route to `/login?next=<current path>`.
4. Toast: "Your session has expired. Please log in again."

**No retry. No refresh call. No queue of pending requests to replay.**

`queryClient.clear()` clearing everything is a security requirement, not tidiness: leaving another
guest's reservations in the cache on a shared machine is a disclosure bug. The same applies on explicit
logout.

One exception, documented so nobody removes it: the bootstrap `GET /auth/me` suppresses the redirect,
because a `401` there is the expected anonymous answer. Without the suppression the app bounces every
anonymous visitor to login on page load.

### What must never reappear

> This codebase has **no** token handling, and the absence is deliberate. The project originally
> specified JWT access tokens with rotating refresh tokens and reversed that decision — see
> [decision-log.md](../../shared/decision-log.md) entry 2.
>
> If any of the following appears in this repository, it is the removed design leaking back in, not a
> feature:
>
> - An in-memory access-token store, or a token in React state or context
> - A `401`-triggered refresh-and-retry interceptor
> - A request queue awaiting a refreshed credential
> - An `Authorization: Bearer` header
> - A call to `/auth/refresh` — **the endpoint does not exist**
> - Anything reading, decoding, or inspecting a JWT
> - A token in `localStorage`, `sessionStorage`, IndexedDB, or a non-`HttpOnly` cookie
>
> Treat each as a review blocker. `grep -rniE "bearer|jwt|accessToken|refreshToken|auth/refresh"` over
> `src/` should return nothing.

---

## Route guards, and their real status

`RequireAuth`, `RequireStaff`, `RequireManager` in `guards/`, as layout routes. They keep a guest from
seeing an admin screen shell and a broken page. **They are not access control** — the API is. A guard
that fails open is a UX bug; an API that fails open is a vulnerability, and only one of those exists
here.

Two implementation requirements:

**Wait for bootstrap.** A guard evaluating before `GET /auth/me` resolves redirects an authenticated
user to login on every refresh. Every guard checks `isResolved` first and renders a skeleton until then.

**Compare rank, not set membership.** `role >= FRONT_DESK_STAFF`, never
`role in {STAFF, MANAGER}`, matching
[api-contracts.md](../../shared/api-contracts.md#authorization). Set membership means a new tier must
be added in every place it is enumerated, and one will be missed.

**Hidden controls follow the same logic as guards**, from one shared `can()` helper reading the session
role — so a control's visibility and a route's guard cannot disagree. Hiding a control is cosmetic; the
server still refuses.

---

## XSS

React escapes interpolated content by default. The rule is to not defeat it.

**`dangerouslySetInnerHTML` is prohibited on any path carrying user or admin input** — property
descriptions, room-type names and descriptions, bed configurations, photo captions, guest names,
amenity labels. All render as text. Enforced by an ESLint rule and a review blocker, per
[security-principles.md](../../shared/security-principles.md#injection).

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

Every `<img src>` built from API data goes through it, returning the placeholder on rejection. This
blocks `javascript:` and `data:` URLs reaching an attribute. Validate on write too (S12), but the read
path cannot assume the write path held — existing rows may predate the validation.

Also prohibited: injecting API data into `href` without the same check, into inline `style`, or into a
`<script>` or `<style>` element.

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
`connect-src` must include the configured API origin, which differs per backend — and is why the
runtime `window.__HOTELAPP_CONFIG__` mechanism and the CSP have to be configured together, per
[environment-setup-guide.md](./environment-setup-guide.md).

`style-src 'unsafe-inline'` is a concession Tailwind's build does not require but some tooling does;
drop it if the build permits. Do **not** add `'unsafe-inline'` to `script-src` — that would forfeit
most of CSP's value.

---

## Payment data

The payment form (S6) collects card-shaped input and the backend keeps only brand and last four.

**In this client, card data exists only in React Hook Form state and is discarded on unmount.** It is
never:

- written to `localStorage`, `sessionStorage`, or any cache
- placed in a URL, query parameter, or route state
- logged, at any level, in any environment
- included in an error report or breadcrumb
- put in the TanStack Query cache — which is why the booking mutation's variables must not be retained,
  and why `POST /reservations` uses `useMutation` rather than being modelled as cached state

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
and every `*_at` timestamp. The field's absence is the control.

**Never weaken a client check to match a bug.** If the server rejects something the client allowed, the
client is wrong.

---

## Dependencies

Per [security-principles.md](../../shared/security-principles.md#dependencies): pinned versions,
`package-lock.json` committed, `npm ci` in CI. Prefer platform and framework primitives over a small
package. No dependency scanning — a declined cost, explained there; the same document names it as the
easiest item to add later.

No third-party script tags: no analytics, no tag manager, no font CDN beyond the permitted stylesheet
origin. Each would be script execution in the app's origin with access to the DOM of a page that
handles credentials. Detail in [dependency-policy.md](./dependency-policy.md).

---

## Deliberately absent

| Absent | Why |
|--------|-----|
| CSRF token handling | `SameSite=Lax` covers it, because **no `GET` endpoint mutates state** — [security-principles.md](../../shared/security-principles.md#sessions). That invariant is what makes this safe, so adding a state-changing `GET` would silently break it |
| Client-side rate limiting | The server limits; a client limiter is trivially bypassed and would only mislead |
| Encryption of anything client-side | Nothing is stored; a key shipped to the browser protects nothing |
| Session timeout warning / countdown | The 8-hour sliding window rarely expires mid-use, and a countdown would need a token to inspect — which is exactly what this design removed |
| Subresource Integrity | No third-party scripts to pin |
| A token refresh mechanism | No tokens. See the prohibition above |
