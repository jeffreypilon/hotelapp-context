# Error Handling — React

How `hotelapp-client-react` turns an RFC 9457 Problem Details response into something a person can
act on.

> ### The message text in section 2 is shared, verbatim, with the other frontend stack
>
> **Sections 1 through 4 below are byte-identical to
> [`stacks/angular/error-handling.md`](../angular/error-handling.md).** A guest must see the same
> wording for the same failure regardless of which client they are using, and
> [ui-specifications.md](./ui-specifications.md) states that screens pull their error text from this
> document rather than composing their own. **Any diff in sections 1–4 is a defect**, the same
> standard the paired `ui-specifications.md` files are held to.
>
> Section 5 holds the React implementation and is the only part that differs.

The error format itself, and the catalogue of codes, are fixed in
[api-contracts.md](../../shared/api-contracts.md#error-responses). This document does not restate
them — it says what the user sees and where the handling lives.

---

## 1. Principles

**Branch on `code`, never on `detail` or on the HTTP status alone.** `code` is the stable
machine-readable member of the Problem Details document. `detail` is prose that may be reworded
without notice — per
[versioning-strategy.md](../../shared/versioning-strategy.md#what-counts-as-a-breaking-change) a
`detail` change is explicitly *not* breaking, so any client matching on it is depending on something
the contract does not promise.

**Never show the server's `detail` to a user.** It is written to be safe to display, but showing it
means the user-facing copy lives in the backend, in two implementations, with no way to keep them
matched. The mapping in section 2 is the only source of user-facing error text in this client.

**Three presentation shapes, chosen by the code, not by the screen.**

| Shape | Used for | Behavior |
|-------|----------|----------|
| **Field-level** | `VALIDATION_FAILED`, and specific codes named in section 2 | Message beside the offending input, `aria-describedby` on the field, focus moves to the first error |
| **Form-level** | Codes that indict the submission as a whole | Message in an alert region above the submit control, `aria-live="assertive"` |
| **Page-level** | Read failures — the screen has no content to show | Replaces the screen body; the app shell and navigation stay usable |

**Every message follows three rules.** Say what happened, in the user's terms, not the system's. Say
what to do next when there is something to do. Never blame the user for a server-side outcome — a
lost booking race is bad luck, not a mistake.

**`traceId` is shown only for `INTERNAL_ERROR`**, as small print, so a developer can correlate a
report with a log line. Every other code has an actionable message and does not need one.

**Unknown codes must not crash the screen.** A `code` this client does not recognize falls back to
the generic message for its HTTP status class. This is required, not defensive padding: per
[versioning-strategy.md](../../shared/versioning-strategy.md#what-counts-as-a-breaking-change),
adding a new error code is a **non-breaking** change the backend may make at any time, so a client
that switches exhaustively over the catalogue will break on a legal server change.

---

## 2. The mapping

**The `message` column is the exact user-facing string.** It is identical in both frontend stacks —
a guest must see the same wording regardless of which client they are using, and
[ui-specifications.md](./ui-specifications.md) states that screens pull their error text from here
rather than composing their own. Copying a message and altering its wording is a defect, not a
localization.

### 400 — `VALIDATION_FAILED`

Field-level, always. The response carries an `errors[]` array of `{ field, code, message }`; map each
entry onto the matching form field by `field` name. The per-field text comes from the field-code
table below, **not** from the server's `errors[].message` — same reasoning as `detail`.

| Field `code` | Message |
|--------------|---------|
| `REQUIRED` | This field is required. |
| `MIN` | *(field-specific — see the field table below)* |
| `MAX` | *(field-specific — see the field table below)* |
| `AFTER_CHECK_IN` | Check-out must be after check-in. |
| `PAST_DATE` | Please choose a date that isn't in the past. |
| `MAX_STAY` | Stays can be at most 30 nights. |
| `INVALID_EMAIL` | Please enter a valid email address. |
| `INVALID_FORMAT` | Please check the format of this entry. |
| `OUT_OF_RANGE` | Please enter a value within the allowed range. |

Field-specific messages, so the same constraint reads naturally per field:

| Field | Message |
|-------|---------|
| `password` (too short) | Passwords must be at least 12 characters. |
| `numGuests` (below 1) | At least one guest is required. |
| `numGuests` (above occupancy) | This room sleeps up to {maxOccupancy} guests. |
| `pageSize` | Choose a page size of 100 or fewer. |
| `discountPercent` | Enter a discount between 0 and 100. |
| `baseRate` | Enter a nightly rate greater than $0.00. |
| `cardNumber` | Please check the card number. |
| `expiryMonth`, `expiryYear` | Please enter a valid expiry date. |
| `cvv` | Please enter the 3- or 4-digit security code. |
| `timezone` | Please choose a valid time zone. |

If a `field` in `errors[]` matches no form control — which means the client and contract disagree
about a field name — show the form-level fallback **"Please check the highlighted fields and try
again."** and log the mismatch. Silently dropping it would hide a real contract drift.

### 401 — authentication

| Code | Shape | Message | Notes |
|------|-------|---------|-------|
| `AUTHENTICATION_REQUIRED` | *(no message)* | Your session has expired. Please log in again. | **Not rendered as a screen error.** Handled globally — clear state, route to login, show this as a toast on the login screen. See section 3 |
| `INVALID_CREDENTIALS` | Form-level | That email or password is incorrect. | **Never field-level.** The server deliberately does not say which is wrong; attaching it to one field would invent information the API withheld on purpose |

### 402 — `PAYMENT_DECLINED`

| Shape | Message |
|-------|---------|
| Field-level, on `cardNumber` | This card was declined. Please try another card. |

The form keeps its values. Per
[ui-specifications.md](./ui-specifications.md) this is deterministically reachable with a card number
ending `0000`, which makes it testable without a processor.

### 403 — authorization

| Code | Shape | Message |
|------|-------|---------|
| `ACCOUNT_INACTIVE` | Form-level | This account has been deactivated. Please contact the property for help. |
| `INSUFFICIENT_ROLE` | Page-level | You don't have permission to view this page. |
| `PROPERTY_OUT_OF_SCOPE` | Page-level | You don't have access to that hotel's information. |

`INSUFFICIENT_ROLE` and `PROPERTY_OUT_OF_SCOPE` **should be unreachable through the UI**, because
route guards and hidden controls prevent the requests that produce them. Reaching one means a guard
is wrong. So they must render visibly rather than being swallowed — a silently-ignored `403` hides a
real authorization bug.

`ACCOUNT_INACTIVE` can arrive on **any** authenticated request, not just login: per
[acceptance-criteria.md](../../shared/acceptance-criteria.md#ac-az-11--inactive-accounts-cannot-authenticate)
a live session belonging to a deactivated user fails on its next request. Treat it like the `401`
rule — clear state and route to login — but show this message instead of the session-expired one.

### 404 — `NOT_FOUND`

Page-level, with wording chosen by what was being fetched, because "Not found" alone tells a guest
nothing:

| Context | Message |
|---------|---------|
| Property | We couldn't find that hotel. |
| Room type | We couldn't find that room. |
| Reservation | We couldn't find that reservation. |
| Unmatched route (S15) | We couldn't find that page. |
| Anything else | We couldn't find what you were looking for. |

Each includes a link back — to the hotel list for a property or room, to the guest's reservations for
a reservation.

**A guest requesting another guest's reservation gets `404`, not `403`**, by contract design — see
[security-principles.md](../../shared/security-principles.md#authorization). The message must be the
ordinary not-found text, with nothing hinting that the reservation exists but belongs to someone
else.

### 409 — conflicts

The most domain-specific group, and where careless wording does the most harm.

| Code | Shape | Message |
|------|-------|---------|
| `ROOM_UNAVAILABLE` | Form-level, prominent | Those dates are no longer available. Someone else may have booked the last room. |
| `CANCELLATION_WINDOW_CLOSED` | Form-level | Changes are no longer available for this reservation. |
| `INVALID_STATUS_TRANSITION` | Form-level | This reservation has changed. We've refreshed it — please try again. |
| `EMAIL_ALREADY_REGISTERED` | Field-level, on `email` | An account with this email already exists. |
| `ROOM_NUMBER_IN_USE` | Field-level, on `roomNumber` | That room number already exists at this hotel. |
| `SLUG_IN_USE` | Field-level, on `slug` | That URL slug is already in use. |

**`ROOM_UNAVAILABLE` is the one message worth getting exactly right.** It is the client-visible face
of the database exclusion constraint — the project's central correctness guarantee, per
[data-model.md](../../shared/data-model.md#no-overbooking) — and the guest did nothing wrong. The
wording says what happened and why, and the presentation offers "Back to search" rather than leaving
them on a dead form. It must never read as a validation failure.

`INVALID_STATUS_TRANSITION` means the client's view of state is stale, so the handler **refetches the
resource** before showing the message; the message says so, which is why it reads as an action taken
rather than an error scolded.

`EMAIL_ALREADY_REGISTERED` includes a link to the login screen. This is the one deliberate account
oracle in the API, accepted knowingly for a usable signup form — see
[security-principles.md](../../shared/security-principles.md#account-lockout) — so the message is
plainly useful rather than coy.

### 429 — `RATE_LIMITED`

| Shape | Message |
|-------|---------|
| Form-level | Too many attempts. Please try again in a few minutes. |

Disable the submit control for the `Retry-After` duration and show a countdown when the header is
present. The message deliberately does not name the exact limit.

### 500 — `INTERNAL_ERROR`

| Shape | Message |
|-------|---------|
| Form-level on a write, page-level on a read | Something went wrong on our end. Please try again. |

Plus `traceId` as small print: **"Reference: {traceId}"**. Never a stack trace, never the server's
`detail`.

### Network and transport failures

Not Problem Details — the request never got an answer — but they need the same discipline:

| Situation | Shape | Message |
|-----------|-------|---------|
| Request failed / offline | Form or page level | We couldn't reach the server. Please check your connection and try again. |
| Timeout | same | That took longer than expected. Please try again. |
| Non-JSON or unparseable response | same | Something went wrong on our end. Please try again. |

A CORS rejection surfaces indistinguishably from a network failure in the browser, so it lands here.
During development that almost always means a misconfigured base URL or an allowed-origins list — see
[environment-setup-guide.md](./environment-setup-guide.md).

### Fallbacks for unrecognized codes

| Status class | Message |
|--------------|---------|
| `4xx` | We couldn't complete that request. Please check your entry and try again. |
| `5xx` | Something went wrong on our end. Please try again. |
| Anything else | Something went wrong. Please try again. |

---

## 3. Globally handled codes

Two codes never reach a screen's error handling, because handling them per screen would mean
repeating the same sequence in fifteen places.

**`AUTHENTICATION_REQUIRED` (401)** — the shared rule from
[api-contracts.md](../../shared/api-contracts.md#client-obligations): clear all cached server state,
clear the session, route to `/login?next=<current path>`, and show "Your session has expired. Please
log in again." **No retry, no refresh call, no queued replay** — the superseded token design needed
all three; sessions need none.

One exception: the bootstrap `GET /auth/me`. A `401` there is the expected anonymous answer and must
not trigger the redirect, or the app bounces to login on every anonymous page load.

**`ACCOUNT_INACTIVE` (403)** — same sequence, different message: "This account has been deactivated.
Please contact the property for help."

Both live in the single place this client touches HTTP. Everything else in section 2 is screen-level.

---

## 4. Error state requirements

Applies to every screen, so it is stated once here rather than per screen in
[ui-specifications.md](./ui-specifications.md).

- **Never a silent failure.** Every rejected request produces visible feedback. A spinner that stops
  with nothing shown is the worst outcome available.
- **Writes preserve their input.** A failed submission never clears the form. Re-entering a card
  number because the room sold out is punishing the guest for the server's answer.
- **Read failures offer a retry**; write failures offer a retry only when repeating is safe. `POST
  /reservations` retries under the **same `Idempotency-Key`**, which is what makes retrying a booking
  safe at all.
- **Errors are announced.** Form and field errors go in an `aria-live="assertive"` region; page-level
  errors move focus to the heading. A sighted-user-only error is an accessibility failure on a screen
  a guest may be trying to pay on.
- **One error at a time per region.** A new error replaces the previous one rather than stacking.
- **Errors clear on the next attempt**, so a stale message never sits above a fresh submission.

---

## 5. React implementation

Target **React 19.3**. Structure per
[architecture-specification.md](./architecture-specification.md).

### Where each layer lives

| Concern | Location |
|---------|----------|
| Parsing `problem+json` into `ApiError` | `api/client.ts` |
| The two global codes (section 3) | `api/client.ts`, before the throw |
| Code → message lookup | `lib/errors/messages.ts` — the section 2 table as data |
| Field-error application | Per-form, via React Hook Form `setError` |
| Presentation | `components/feedback/ErrorMessage`, `EmptyState`, and the S15 boundary |

### The message module

Section 2's table is data, not `switch` statements scattered across screens:

```ts
export type ErrorShape = 'field' | 'form' | 'page';

export const errorMessages: Record<string, { shape: ErrorShape; message: string; field?: string }> = {
  INVALID_CREDENTIALS:        { shape: 'form',  message: 'That email or password is incorrect.' },
  PAYMENT_DECLINED:           { shape: 'field', message: 'This card was declined. Please try another card.', field: 'cardNumber' },
  ROOM_UNAVAILABLE:           { shape: 'form',  message: 'Those dates are no longer available. Someone else may have booked the last room.' },
  CANCELLATION_WINDOW_CLOSED: { shape: 'form',  message: 'Changes are no longer available for this reservation.' },
  EMAIL_ALREADY_REGISTERED:   { shape: 'field', message: 'An account with this email already exists.', field: 'email' },
  // …the remainder of section 2, one entry per code
};

export function resolveError(err: unknown): ResolvedError { /* falls back by status class */ }
```

`resolveError` is the **only** place an `ApiError` becomes user-facing text. A component writing its
own string for a known code is a review finding.

### Query and mutation error handling

TanStack Query surfaces `error` as the typed `ApiError`, so screens read it rather than catching:

```tsx
const { data, isPending, error } = useQuery({ queryKey: qk.property(id), queryFn: () => getProperty(id) });

if (isPending) return <PropertySkeleton />;
if (error)     return <ErrorMessage error={error} context="property" />;
```

`context` selects the `NOT_FOUND` wording from section 2's context table.

Mutations apply field errors in `onError`:

```ts
onError: (err: ApiError) => {
  if (err.code === 'VALIDATION_FAILED' && err.errors) {
    for (const fe of err.errors) setError(fe.field as never, { message: fieldMessage(fe) });
    return;
  }
  const r = resolveError(err);
  if (r.shape === 'field' && r.field) setError(r.field as never, { message: r.message });
  else setFormError(r.message);
}
```

**`retry` must not retry a `4xx`**, per
[state-management.md](./state-management.md#defaults) — retrying a definitive answer delays it, and
retrying a `429` makes the limit worse.

### The error boundary

One `<ErrorBoundary>` inside the router (S15), rendering "Something went wrong." with a reload
action. It catches **render** errors only — React error boundaries do not catch rejected promises, so
request failures must be handled through the query/mutation paths above. Assuming otherwise is the
common mistake here.

`react-error-boundary` is permitted for the reset ergonomics; a hand-written class boundary is also
fine. See [dependency-policy.md](./dependency-policy.md).

### Announcing errors

`ErrorMessage` renders `role="alert"`, which is implicitly `aria-live="assertive"`. Field errors use
`aria-describedby` on the input plus `aria-invalid`. React Hook Form's `setError` does not move
focus, so forms call `setFocus` on the first errored field explicitly — otherwise a keyboard user is
told there is an error but not taken to it.
