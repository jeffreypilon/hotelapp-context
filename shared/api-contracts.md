# API Contracts

The REST contract for HotelApp. **hotelapp-server-nodejs** and
**hotelapp-server-springboot** must both implement this document exactly, so that
**hotelapp-client-react** and **hotelapp-client-angular** can be pointed at either backend
with no code change. Where this document and an implementation disagree, this document is
wrong or the implementation is — resolve it here first, then in code.

Derived from [project-overview.md](./project-overview.md) and
[data-model.md](./data-model.md).

---

## Conventions

| Item | Value |
|------|-------|
| Base path | `/api/v1` |
| Payload format | `application/json; charset=utf-8` |
| Error format | `application/problem+json` (RFC 9457) |
| Property names | `camelCase` in JSON; the database uses `snake_case` and each backend maps between them |
| Dates | `date` fields are ISO 8601 calendar dates, `YYYY-MM-DD`, no time or offset |
| Timestamps | ISO 8601 with offset, always UTC: `2026-09-26T14:05:00Z` |
| Money | JSON **string** in decimal form (`"189.00"`), never a float — see below |
| Currency | `"USD"` throughout; every money-bearing response carries an explicit `currency` |
| IDs | UUID strings |
| Versioning | Path-based (`/v1`). Breaking changes go to `/v2`; additive fields do not bump the version |
| **Nullable fields** | **Always present and explicitly `null`.** An absent field is never equivalent to `null` — see below |
| Trailing slashes | Not accepted; `/properties/` is a 404 |

> **Design Decision — money as a JSON string.**
> IEEE-754 doubles cannot represent `0.1` exactly, and `JSON.parse` in both frontends
> produces a `number` for any bare numeric literal. Serializing `numeric(10,2)` as a string
> keeps the value exact end to end: PostgreSQL `numeric` → Java `BigDecimal` /
> Prisma `Decimal` → JSON string → client-side decimal formatting. It also means the Node
> and Spring backends cannot silently disagree about rounding at the serialization
> boundary, which is precisely the kind of divergence this project forbids.

> **Design Decision — a nullable field is `null`, never absent.**
> A response carries every field the contract declares. `"photoUrl": null` is correct;
> omitting `photoUrl` is not. The response examples throughout this document already show
> explicit nulls (`"line2": null`, `"propertyId": null`) and they are normative.
>
> **This exists because the two backends would otherwise disagree on the wire.** Node's
> `JSON.stringify` emits `"photoUrl": null` by default; Spring with
> `spring.jackson.default-property-inclusion=non_null` omits the field entirely. Identical
> data, different bytes — and the OpenAPI diff would not catch it, because both documents
> would declare the field nullable. That is exactly the divergence this project is organized
> to prevent, and it was found by building the first real client in Phase 6 Step 0.
>
> It matters to clients too: in TypeScript, `string | null` and "may be absent" are genuinely
> different types, and a consumer testing `=== null` breaks silently against an omitted field.
>
> **Both backends must configure this deliberately**, since both defaults are wrong in opposite
> directions:
>
> - **Spring Boot** — default inclusion must be `always`. Apply `@JsonInclude(NON_NULL)` to the
>   Problem Details type *only*, which is the one place omission is wanted (keeping `errors` out
>   of non-validation bodies).
> - **Node** — do not strip nulls when building DTOs. `undefined` must not reach `JSON.stringify`
>   where `null` is meant, because `stringify` drops `undefined` properties silently.
>
> The one deliberate exception is `errors[]` in a Problem Details body, which is **absent**
> rather than null outside validation failures — stated in the table above.

### Request validation

Unknown request-body fields are **rejected** with `400`, not ignored. Silently dropping a
field that one backend understands and the other does not is how two implementations of
one contract drift. (`spring.jackson.deserialization.fail-on-unknown-properties=true`;
strict schema validation in the Node backend.)

---

## Authentication

> ### Design Decision — server-side sessions in PostgreSQL
>
> **Recommendation:** one opaque session token in an `HttpOnly` cookie, backed by a
> `sessions` row in the shared PostgreSQL database. No JWTs, no access/refresh split, no
> client-side token handling at all.
>
> **What the problem actually is.** Two backends must agree on who is logged in. They
> already share one database. A session row is the shortest path from that requirement to a
> working answer: the cookie is a lookup key, the row is the truth, and a user who logs in
> against the Node backend is logged in against the Spring backend because both read the
> same table.
>
> **Why this is sufficient.** Current guidance is that server-side sessions with opaque
> tokens are the right default for first-party web applications, and reaches for JWTs when
> a system needs stateless cross-service authorization or has no shared store to consult.
> Neither condition holds here. Both frontends are first-party; both backends sit directly
> on the one database that would have to be consulted anyway. Revocation is a single
> `revoked_at` write that takes effect on the very next request — a stronger and far simpler
> story than token rotation with reuse detection.
>
> **What it gives up, stated plainly.** A **database read on every authenticated request**,
> where a self-contained JWT needed none. That is the real cost of this choice, and at this
> project's scale it is the right trade:
>
> - It is a single-row lookup on a unique index over `sessions.token_hash`, joined to the
>   user row — sub-millisecond, and it goes to a connection the request was going to open
>   anyway to do its actual work.
> - It replaces, rather than adds to, work the JWT design also did: that design denormalized
>   `role` and `home_property_id` into token claims and *still* re-verified property scope
>   against the database on every scoped endpoint. Joining the user row to the session
>   yields the same fields, freshly, with no denormalization to keep in sync.
> - A role change or deactivation takes effect immediately. Under the JWT design it lagged
>   by up to the access-token TTL.
>
> The honest scaling caveat: at a volume where that read hurts, the fix is a cache in front
> of the lookup, not a reintroduction of tokens. That threshold is far beyond a portfolio
> demo, and nothing in this contract would have to change to cross it.
>
> **What this deliberately removes** from the previous design: the access/refresh token
> split, rotation, reuse detection and token families, in-memory token storage in both
> frontends, and the `401`-refresh-retry interceptor each of them needed. Roughly a hundred
> lines of client-side machinery per frontend, deleted. No part of it is retained as a
> future enhancement — if this project ever needs stateless cross-service authorization
> (say, a third service that cannot reach this database), that is the point at which to
> reopen the question, and it would be a new design rather than a switch to flip.

### Session token and cookie shape

**Session token** — 256 bits from a CSPRNG, base64url-encoded. Opaque: it carries no
claims and means nothing outside the `sessions` table. Only its SHA-256 hash is stored, so
a database dump cannot be replayed as live sessions. Delivered as:

```
Set-Cookie: hotelapp_session=<token>; HttpOnly; Secure; SameSite=Lax;
            Path=/api/v1; Max-Age=2592000
```

| Attribute | Why |
|-----------|-----|
| `HttpOnly` | Script cannot read the cookie, so XSS cannot exfiltrate the credential |
| `Secure` | Never sent over plain HTTP. In local development, `Secure` is exempted for `localhost` by every current browser, so this needs no dev-only relaxation |
| `SameSite=Lax` | See below |
| `Path=/api/v1` | Sent to the API and nowhere else |
| `Max-Age` | The cookie's 30-day ceiling matches the session's absolute cap; the server's `expires_at` is the authority, and the cookie merely avoids sending a token the server will reject |

> **Design Decision — `SameSite=Lax`, not `Strict`.**
> `Lax` blocks the cookie on cross-site POST, PUT, PATCH, and DELETE — the entire
> state-changing surface, which is what CSRF needs — while still sending it on a top-level
> GET navigation. That matters for the admin area: a link pasted into a chat, a bookmark, or
> an emailed deep link into a booking should land the staff member on the page rather than
> on a login screen, and `Strict` breaks exactly that.
>
> The previous design had a specific reason to reach for `Strict`: the refresh cookie was
> path-scoped to a single endpoint and was only ever sent by the SPA's own `fetch`, so
> `Strict` cost nothing. With one cookie serving one path and the whole endpoint set, that
> trade no longer exists, and `Lax` is the better fit. `Lax` is also the modern browser
> default, so this is the behavior a reviewer will expect unless told otherwise.
>
> Residual CSRF risk under `Lax` is limited to cross-site top-level GET navigation, and
> **no GET endpoint in this contract mutates state** — which is what makes `Lax` safe here
> rather than merely convenient.

### Client obligations

Considerably shorter than a token scheme's, which is much of the point.

1. Send `credentials: "include"` on every request (`fetch`) or `withCredentials: true`
   (Angular `HttpClient`). The browser attaches the cookie and applies any updated
   `Set-Cookie`; there is nothing for the client to store, read, or renew.
2. Never attempt to read the session cookie from script. It is `HttpOnly` and reading it is
   not possible by design.
3. On app start, call `GET /auth/me` to discover whether a session already exists. A `200`
   means logged in; a `401` means not.
4. On any `401`, clear client-side user state and route to login. There is no retry to
   attempt — an expired or revoked session is final.
5. Treat the `user` object from login or `/auth/me` as cached display data, not as an
   authority. The server re-checks role and property scope on every request.

### Session lifetime

`expires_at` starts at `now() + 8 hours` and slides forward on authenticated activity,
capped at `issued_at + 30 days`. To keep a read-hot path from becoming write-hot, the
server only extends `expires_at` when it is more than 5 minutes stale. Both backends must
use the same window and threshold; see
[data-model.md](./data-model.md) for the full rationale.

Sessions are revoked — `revoked_at` set — on logout and on password change. A revoked or
expired session is indistinguishable from a nonexistent one in the response: both produce
`401 AUTHENTICATION_REQUIRED`.

---

## Authorization

Four levels, referenced in every endpoint table below:

| Level | Meaning |
|-------|---------|
| **Public** | No session required. An authenticated caller is served identically |
| **Guest** | Any authenticated user. Ownership-scoped: acts on the caller's own data only |
| **Staff** | `FRONT_DESK_STAFF` or `PROPERTY_MANAGER`, scoped to the staff member's property |
| **Manager** | `PROPERTY_MANAGER` only, all properties |

Rules that apply everywhere:

- Role checks are **rank-based**: `PROPERTY_MANAGER` ≥ `FRONT_DESK_STAFF` ≥ `GUEST`. A
  manager passes every Staff check without being enumerated separately.
- A `FRONT_DESK_STAFF` request touching a property other than `home_property_id` gets
  `403`, never `404` — the resource exists and they may not reach it.
- A Guest requesting another guest's reservation gets **`404`**, not `403`. Confirming
  existence to a non-owner is an enumeration oracle.
- Missing, unknown, expired, or revoked session on a non-public endpoint → `401`. Valid
  session, insufficient role → `403`.
- Admin endpoints live under `/admin/*` so authorization is legible from the route alone.

---

## Error responses

All errors use RFC 9457 Problem Details with `Content-Type: application/problem+json`.

```json
{
  "type": "https://hotelapp.example/problems/validation-failed",
  "title": "Validation failed",
  "status": 400,
  "detail": "The request body contains 2 invalid fields.",
  "instance": "/api/v1/reservations",
  "code": "VALIDATION_FAILED",
  "traceId": "0192f3a1-9e33-7d40-b512-2ac8d5f3e211",
  "errors": [
    { "field": "checkOutDate", "code": "AFTER_CHECK_IN", "message": "checkOutDate must be after checkInDate." },
    { "field": "numGuests",    "code": "MIN",            "message": "numGuests must be at least 1." }
  ]
}
```

| Member | Presence | Notes |
|--------|----------|-------|
| `type` | always | Stable URI identifying the problem kind. The client's switch key |
| `title` | always | Short, human-readable, does not vary by occurrence |
| `status` | always | Matches the HTTP status |
| `detail` | always | Specific to this occurrence. Safe to show a user; never leaks internals |
| `instance` | always | Request path |
| `code` | always | Machine-readable constant, mirrors the `type` slug |
| `traceId` | always | Correlates to server logs |
| `errors[]` | validation only | Field-level detail |

> **Design Decision — RFC 9457 rather than a bespoke envelope.**
> RFC 9457 (which obsoleted RFC 7807 in 2023) is the standardized shape, and Spring Boot
> produces it natively via `ProblemDetail`. Adopting it means the Spring backend needs
> almost no custom error plumbing, the Node backend has one well-specified target to match,
> and both frontends share one parser. `code` and `traceId` are registered extension
> members, which the RFC explicitly permits.

### Problem catalogue

| `code` | Status | When |
|--------|--------|------|
| `VALIDATION_FAILED` | 400 | Malformed body, bad field value, unknown field, bad query parameter |
| `AUTHENTICATION_REQUIRED` | 401 | No session cookie, or a session that is unknown, expired, or revoked. One code covers all four — the client's response is the same in every case, and distinguishing them would tell an attacker whether a guessed token ever existed |
| `INVALID_CREDENTIALS` | 401 | Wrong email or password. Never says which |
| `ACCOUNT_INACTIVE` | 403 | `users.is_active = false` |
| `INSUFFICIENT_ROLE` | 403 | Authenticated, wrong tier |
| `PROPERTY_OUT_OF_SCOPE` | 403 | Staff reaching outside `home_property_id` |
| `NOT_FOUND` | 404 | No such resource, or not visible to this caller |
| `EMAIL_ALREADY_REGISTERED` | 409 | Registration with an existing email |
| `ROOM_UNAVAILABLE` | 409 | No free unit for the requested type and dates, or an overlap was caught at insert |
| `INVALID_STATUS_TRANSITION` | 409 | e.g. checking in a cancelled booking |
| `CANCELLATION_WINDOW_CLOSED` | 409 | Modification attempted inside the 48-hour window |
| `ROOM_NUMBER_IN_USE` | 409 | Duplicate `(propertyId, roomNumber)` |
| `SLUG_IN_USE` | 409 | Duplicate property slug |
| `PAYMENT_DECLINED` | 402 | Simulated decline (see the payment section) |
| `RATE_LIMITED` | 429 | Too many attempts. Carries `Retry-After` |
| `INTERNAL_ERROR` | 500 | Unexpected. `detail` is generic; specifics go to logs only |

`ROOM_UNAVAILABLE` is the contract-level expression of the database's exclusion
constraint. Both backends must translate SQLSTATE `23P01` into exactly this problem.

**AI service codes.** These are raised only by `hotelapp-ai-service` (see the AI assistant
section below). **Neither backend emits them**, and neither backend needs to know they exist.

| `code` | Status | When |
|--------|--------|------|
| `QUESTION_TOO_LONG` | 400 | Input exceeds the configured ceiling. Checked before any model call, so an oversized question costs nothing |
| `AI_CONTENT_FILTERED` | 422 | The model provider refused on policy grounds |
| `AI_RATE_LIMITED` | 429 | The **provider** rate-limited the service. Deliberately distinct from `RATE_LIMITED`, which means this service limited the caller — conflating them tells a guest to slow down when the problem is upstream |
| `AI_UNAVAILABLE` | 503 | No provider configured, provider unreachable, or circuit open. **An expected state, not a fault** — it is what the Compose demo returns with no API key |
| `RETRIEVAL_FAILED` | 503 | The vector store is unreachable or the hybrid query failed. Separate from `AI_UNAVAILABLE` because the remedies are entirely different |
| `AI_TIMEOUT` | 504 | A provider call exceeded its explicit deadline |

---

## Pagination, sorting, filtering

Every collection endpoint uses the same page-based scheme.

**Request:** `?page=1&pageSize=20` — `page` is 1-based, `pageSize` defaults to `20`, max
`100`. Out-of-range values are a `400`, not silently clamped.

**Response envelope:**

```json
{
  "data": [ /* ... */ ],
  "pagination": {
    "page": 1,
    "pageSize": 20,
    "totalItems": 137,
    "totalPages": 7,
    "hasPreviousPage": false,
    "hasNextPage": true
  }
}
```

Single-resource responses are the bare object, with no envelope.

> **Design Decision — offset pagination, not cursors.**
> Cursor pagination is strictly better at scale and under concurrent inserts. It is the
> wrong fit here: the admin booking list needs sortable columns and a page count ("Page 3
> of 7"), which cursors cannot express without a separate count query anyway. Data volumes
> for a demo property portfolio are in the thousands of rows, where `OFFSET` is measured in
> microseconds. The scale-up path is documented and unblocked — add an opaque `cursor`
> parameter alongside `page` — but building it now would be speculative complexity a
> reviewer would rightly question.

**Sorting:** `?sort=<field>:<asc|desc>`, repeatable for a compound sort
(`?sort=price:asc&sort=maxOccupancy:desc`). Each endpoint lists its sortable fields;
anything else is a `400`. Every sort is stabilized by appending `id` as the final key, so
pages never duplicate or drop a row.

---

## Endpoint index

| Method | Path | Auth |
|--------|------|------|
| `POST` | `/auth/register` | Public |
| `POST` | `/auth/login` | Public |
| `POST` | `/auth/logout` | Guest |
| `GET` | `/auth/me` | Guest |
| `GET` | `/properties` | Public |
| `GET` | `/properties/{propertyId}` | Public |
| `GET` | `/properties/{propertyId}/room-types` | Public |
| `GET` | `/room-types/{roomTypeId}` | Public |
| `GET` | `/amenities` | Public |
| `GET` | `/rate-categories` | Public |
| `GET` | `/availability` | Public |
| `GET` | `/me` | Guest |
| `PATCH` | `/me` | Guest |
| `PUT` | `/me/password` | Guest |
| `GET` | `/reservations` | Guest |
| `POST` | `/reservations` | Guest |
| `GET` | `/reservations/{reservationId}` | Guest |
| `PATCH` | `/reservations/{reservationId}` | Guest |
| `POST` | `/reservations/{reservationId}/cancel` | Guest |
| `GET` | `/admin/reservations` | Staff |
| `GET` | `/admin/reservations/{reservationId}` | Staff |
| `POST` | `/admin/reservations/{reservationId}/check-in` | Staff |
| `POST` | `/admin/reservations/{reservationId}/check-out` | Staff |
| `POST` | `/admin/reservations/{reservationId}/cancel` | Staff |
| `GET` | `/admin/properties` | Staff |
| `POST` | `/admin/properties` | Manager |
| `PATCH` | `/admin/properties/{propertyId}` | Manager |
| `POST` | `/admin/properties/{propertyId}/room-types` | Manager |
| `PATCH` | `/admin/room-types/{roomTypeId}` | Manager |
| `PUT` | `/admin/room-types/{roomTypeId}/amenities` | Manager |
| `GET` | `/admin/room-types/{roomTypeId}/photos` | Manager |
| `POST` | `/admin/room-types/{roomTypeId}/photos` | Manager |
| `DELETE` | `/admin/room-types/{roomTypeId}/photos/{photoId}` | Manager |
| `GET` | `/admin/properties/{propertyId}/rooms` | Staff |
| `POST` | `/admin/properties/{propertyId}/rooms` | Manager |
| `PATCH` | `/admin/rooms/{roomId}` | Manager |
| `GET` | `/admin/properties/{propertyId}/rate-plans` | Staff |
| `PUT` | `/admin/properties/{propertyId}/rate-plans` | Manager |
| `GET` | `/admin/properties/{propertyId}/calendar` | Staff |
| `GET` | `/admin/properties/{propertyId}/reports/occupancy` | Staff |
| `GET` | `/admin/properties/{propertyId}/reports/arrivals` | Staff |
| `GET` | `/health` | Public |

### AI service endpoints — a different component implements these

> **Everything above is implemented by *both* backends. Everything in this table is implemented
> by `hotelapp-ai-service` and by neither backend.** Building any of it in Spring Boot or Node
> is a defect, and the OpenAPI diff job — which compares the two backends to each other — would
> correctly fail if one of them grew these paths.

| Method | Path | Auth |
|--------|------|------|
| `POST` | `/assistant/ask` | Public (richer when a session is present) |
| `POST` | `/assistant/search` | Public |
| `GET` | `/assistant/health` | Public |
| `POST` | `/mcp` | OAuth 2.1 |
| `GET` | `/.well-known/oauth-protected-resource` | Public, **host root** |
| `GET` | `/.well-known/oauth-authorization-server` | Public, **host root** |
| `GET`/`POST` | `/oauth/authorize`, `/oauth/token`, `/oauth/introspect` | Per OAuth 2.1 |

---

## Authentication endpoints

### `POST /auth/register` — Public

Creates a `GUEST`. Admin accounts are never created here.

```json
{
  "email": "guest@example.com",
  "password": "correct horse battery staple",
  "firstName": "Dana",
  "lastName": "Reyes",
  "phone": "+1-555-0142"
}
```

Password rules: 12–128 characters. No composition requirements — length beats character
classes, and NIST guidance has said so for years. Reject any password appearing in a
common-password deny list.

**`201 Created`** returns the same body as `POST /auth/login` and sets the session cookie;
registration logs the guest straight in, matching the booking flow where registration
happens mid-checkout.

Errors: `400 VALIDATION_FAILED`, `409 EMAIL_ALREADY_REGISTERED`, `429 RATE_LIMITED`.

### `POST /auth/login` — Public

```json
{ "email": "guest@example.com", "password": "correct horse battery staple" }
```

**`200 OK`**, plus `Set-Cookie: hotelapp_session=...`:

```json
{
  "user": {
    "id": "0192f3a1-7c4e-7b2a-9d11-4f8a2c6e5b03",
    "email": "guest@example.com",
    "firstName": "Dana",
    "lastName": "Reyes",
    "role": "GUEST",
    "propertyId": null
  }
}
```

The cookie is the credential; the body carries no token and nothing the client must store
to stay authenticated. `user` is returned purely so the client can render the header and
route by role without a second round trip. `propertyId` is `users.home_property_id`, for UI
labelling only — every property-scoped endpoint re-derives it server-side from the
session's user row.

Errors: `400`, `401 INVALID_CREDENTIALS`, `403 ACCOUNT_INACTIVE`, `429 RATE_LIMITED`.

`INVALID_CREDENTIALS` is returned identically for an unknown email and a wrong password,
and both paths must take the same time — verify against a dummy hash when the user does
not exist, or the response time distinguishes them.

Rate limit: 10 attempts per 15 minutes per IP **and** per email, whichever trips first.

### `POST /auth/logout` — Guest

Empty body. Sets `revoked_at` on the caller's session row and clears the cookie with
`Set-Cookie: hotelapp_session=; HttpOnly; Secure; SameSite=Lax; Path=/api/v1; Max-Age=0`.

**`204 No Content`**. Idempotent: logging out twice, or with no session at all, is still
`204` — there is no state to disagree about, and a `401` here would only complicate client
sign-out code.

The revocation is effective **immediately**: the very next request carrying that token is
`401`. Only the caller's own session is revoked; the same user's other sessions on other
devices are untouched.

> Rows are revoked rather than deleted so that `user_agent`, `ip_address`, and `issued_at`
> survive as an audit trail. The cleanup job deletes them once past `expires_at`.

### `GET /auth/me` — Guest

**`200 OK`** with the `user` object above. This is how a client discovers on startup
whether a session cookie it cannot read is still valid; a `401` simply means no session.

---

## Public catalogue endpoints

### `GET /properties` — Public

Active properties only. Sortable: `name`, `city`. Default `name:asc`.

Query: `page`, `pageSize`, `sort`, `city` (exact, case-insensitive), `q` (substring of
name or city).

**`200 OK`**

```json
{
  "data": [
    {
      "id": "0192f3a2-1100-7000-8000-000000000001",
      "name": "Harborview Grand",
      "slug": "harborview-grand",
      "description": "A waterfront hotel steps from the ferry terminal.",
      "photoUrl": "https://cdn.example/harborview/hero.jpg",
      "address": {
        "line1": "18 Wharf Street",
        "line2": null,
        "city": "Portland",
        "stateProvince": "ME",
        "postalCode": "04101",
        "countryCode": "US"
      },
      "phone": "+1-207-555-0100",
      "timezone": "America/New_York",
      "roomTypeCount": 5
    }
  ],
  "pagination": { "page": 1, "pageSize": 20, "totalItems": 3, "totalPages": 1, "hasPreviousPage": false, "hasNextPage": false }
}
```

`timezone` is exposed because the client needs it to render cancellation deadlines in the
property's local terms.

### `GET /properties/{propertyId}` — Public

**`200 OK`** — the property object above plus its `roomTypes` array (summary form).
Accepts either a UUID or a slug in the path segment. `404 NOT_FOUND` if unknown or
inactive.

### `GET /properties/{propertyId}/room-types` — Public

**`200 OK`** — non-paginated array. A property has a handful of room types; a page
envelope here would be ceremony without benefit. Active room types only.

```json
[
  {
    "id": "0192f3a3-2200-7000-8000-000000000011",
    "propertyId": "0192f3a2-1100-7000-8000-000000000001",
    "code": "KING",
    "name": "Deluxe King, Harbor View",
    "description": "Corner room with a king bed and harbor-facing windows.",
    "baseRate": "249.00",
    "currency": "USD",
    "maxOccupancy": 2,
    "bedConfiguration": "one king bed",
    "isAccessible": true,
    "amenities": [
      { "code": "WIFI", "name": "Wi-Fi" },
      { "code": "AIR_CONDITIONING", "name": "Air conditioning / climate control" },
      { "code": "SAFE", "name": "Safe for valuables" }
    ],
    "photos": [
      { "id": "0192f3a4-3300-7000-8000-000000000021", "url": "https://cdn.example/king-1.jpg", "caption": "Harbor view", "sortOrder": 0, "isPrimary": true }
    ]
  }
]
```

Public room-type responses never include `roomCount` or room numbers. Physical inventory
size is operational data, and exposing it invites scraping of occupancy.

### `GET /room-types/{roomTypeId}` — Public

**`200 OK`** — a single room type in the shape above. `404` if unknown or inactive.

### `GET /amenities` — Public

**`200 OK`** — non-paginated array of `{ code, name, sortOrder }`, ordered by
`sortOrder`. Lets both clients build amenity filters without hardcoding the list.

### `GET /rate-categories` — Public

**`200 OK`** — the selectable special-rate categories. Non-paginated.

```json
[
  { "value": "NONE", "label": "None" },
  { "value": "AAA_CAA", "label": "AAA/CAA" },
  { "value": "AARP", "label": "AARP" },
  { "value": "GOVERNMENT_PER_DIEM", "label": "Government/Per Diem" },
  { "value": "MILITARY_VETERAN", "label": "Military/Veteran" },
  { "value": "SENIOR", "label": "Senior" },
  { "value": "CORPORATE_CODE", "label": "Corporate Code" },
  { "value": "GROUP_CODE", "label": "Group Code" }
]
```

`NONE` is included as the default selection. The "clear selection" control in the UI sets
the field back to `NONE`; it is not a separate value.

---

## Availability search

### `GET /availability` — Public

The search behind the guest booking flow. Returns **room types** that have at least one
free unit for the whole requested range, with pricing resolved for the chosen rate
category.

| Parameter | Required | Notes |
|-----------|----------|-------|
| `propertyId` | yes | UUID or slug |
| `checkInDate` | yes | `YYYY-MM-DD`, not in the past |
| `checkOutDate` | yes | Must be after `checkInDate`; max stay 30 nights |
| `numGuests` | yes | ≥ 1. Filters on `maxOccupancy >= numGuests` |
| `roomTypeCode` | no | Repeatable: `?roomTypeCode=KING&roomTypeCode=SUITE` |
| `rateCategory` | no | Defaults to `NONE` |
| `accessibleOnly` | no | `true` restricts to `isAccessible` room types |
| `amenityCode` | no | Repeatable. A room type must have **all** requested amenities |
| `minNightlyRate` / `maxNightlyRate` | no | Applied to the **discounted** nightly rate |
| `sort` | no | `nightlyRate`, `maxOccupancy`, `name`. Default `nightlyRate:asc` |
| `page`, `pageSize` | no | Standard |

**`200 OK`**

```json
{
  "data": [
    {
      "roomType": {
        "id": "0192f3a3-2200-7000-8000-000000000011",
        "code": "KING",
        "name": "Deluxe King, Harbor View",
        "maxOccupancy": 2,
        "bedConfiguration": "one king bed",
        "isAccessible": true,
        "amenities": [ { "code": "WIFI", "name": "Wi-Fi" } ],
        "primaryPhotoUrl": "https://cdn.example/king-1.jpg"
      },
      "pricing": {
        "rateCategory": "AAA_CAA",
        "baseRate": "249.00",
        "discountPercent": "10.00",
        "nightlyRate": "224.10",
        "nights": 3,
        "totalAmount": "672.30",
        "currency": "USD"
      },
      "availableRoomCount": 4
    }
  ],
  "pagination": { "page": 1, "pageSize": 20, "totalItems": 2, "totalPages": 1, "hasPreviousPage": false, "hasNextPage": false }
}
```

`availableRoomCount` is a scarcity signal ("only 1 left"), not a booking token. It is
accurate as of the query and may change before the guest confirms — which is exactly why
allocation happens server-side at booking time.

Errors: `400 VALIDATION_FAILED` (missing dates, `checkOutDate` not after `checkInDate`,
past date, stay over 30 nights), `404 NOT_FOUND` (unknown property).

An empty `data` array is `200`, not `404`: "no rooms available" is a successful search.

> **Design Decision — search returns room types; the server assigns the room.**
> Guests shop for a *kind* of room (photos, amenities, bed configuration), which is the
> level the overview describes. But the no-overbooking guarantee lives on the physical
> room. The contract therefore takes `roomTypeId` on booking and lets the backend pick a
> free unit inside the same transaction that inserts the reservation, where the exclusion
> constraint can adjudicate a race. Letting the client name a `roomId` would put a stale
> availability read on the critical path and expose room numbers to anonymous users for no
> guest-facing benefit.
>
> **Allocation rule (both backends, identically):** among non-out-of-service rooms of the
> requested type with no overlapping non-cancelled reservation, take the lowest
> `room_number` by natural sort. Deterministic ordering keeps the two backends' behavior
> comparable and makes integration tests reproducible. On `23P01`, retry allocation with
> the next candidate room, up to 3 attempts, then return `409 ROOM_UNAVAILABLE`.

---

## Guest account endpoints

### `GET /me` — Guest

**`200 OK`** — the full profile, including the contact fields the guest may edit.

```json
{
  "id": "0192f3a1-7c4e-7b2a-9d11-4f8a2c6e5b03",
  "email": "guest@example.com",
  "firstName": "Dana",
  "lastName": "Reyes",
  "phone": "+1-555-0142",
  "address": { "line1": "44 Elm Street", "line2": "Apt 3", "city": "Portland", "stateProvince": "ME", "postalCode": "04102", "countryCode": "US" },
  "role": "GUEST",
  "propertyId": null,
  "createdAt": "2026-04-11T15:22:03Z"
}
```

### `PATCH /me` — Guest

Partial update of `firstName`, `lastName`, `phone`, and the `address` sub-object. `email`
and `role` are **not** editable here: changing a login identifier needs verification, and
role escalation must never be self-service.

Omitted fields are unchanged; an explicit `null` clears a nullable field. **`200 OK`** with
the updated profile. Errors: `400`, `401`.

### `PUT /me/password` — Guest

```json
{ "currentPassword": "...", "newPassword": "..." }
```

**`204 No Content`**. Revokes every **other** session for the user; the caller's current
session stays valid, so changing a password does not log you out of the tab you changed it
in. This is the standard behavior users expect, and it is also the security-relevant half:
a password change is how someone evicts an intruder from every other device.

Errors: `400`, `401 INVALID_CREDENTIALS` (wrong `currentPassword`).

> **Assumption.** The overview lists profile and contact editing but never mentions
> password change. An account system without one is not defensible, so it is specified
> here as a minimal addition. Password *reset* by email is **not** included — it needs
> transactional email, which the overview lists as a stretch goal.

---

## Guest reservation endpoints

### `POST /reservations` — Guest

Creates the booking and its dummy payment in **one transaction**. This is the "confirm
booking" step of the guest flow.

```json
{
  "roomTypeId": "0192f3a3-2200-7000-8000-000000000011",
  "checkInDate": "2026-11-14",
  "checkOutDate": "2026-11-17",
  "numGuests": 2,
  "rateCategory": "AAA_CAA",
  "payment": {
    "cardNumber": "4242424242424242",
    "expiryMonth": 12,
    "expiryYear": 2029,
    "cvv": "123",
    "cardholderName": "Dana Reyes"
  }
}
```

Optional header: `Idempotency-Key: <uuid>`. When present, a repeat of the same key within
24 hours returns the original `201` response instead of creating a second booking. This
guards the double-submitted confirm button, which is the most likely way a demo produces a
duplicate reservation.

**Server-side sequence:**

1. Validate the body. Reject past dates, `checkOutDate <= checkInDate`, stays over 30
   nights.
2. Load the room type; verify it is active and `numGuests <= maxOccupancy`.
3. Resolve pricing from `base_rate` and the property's active rate plan for
   `rateCategory`. **Never trust a client-supplied price** — the request carries no price
   field at all, by design.
4. Validate the payment input shape (Luhn check, expiry in the future, CVV length). See
   the payment note below.
5. Allocate a free room per the allocation rule.
6. Compute `cancellation_deadline` from `checkInDate` and the property timezone.
7. Generate `confirmationNumber`.
8. Insert the reservation (`status = 'CONFIRMED'`) and the payment row
   (`status = 'SUCCEEDED'`) in one transaction. A `23P01` violation retries step 5.

**`201 Created`**, `Location: /api/v1/reservations/{id}`:

```json
{
  "id": "0192f3a5-4400-7000-8000-000000000031",
  "confirmationNumber": "HA7K2M9QX4",
  "status": "CONFIRMED",
  "property": { "id": "0192f3a2-1100-7000-8000-000000000001", "name": "Harborview Grand", "timezone": "America/New_York" },
  "roomType": { "id": "0192f3a3-2200-7000-8000-000000000011", "code": "KING", "name": "Deluxe King, Harbor View" },
  "room": { "id": "0192f3a6-5500-7000-8000-000000000041", "roomNumber": "412" },
  "checkInDate": "2026-11-14",
  "checkOutDate": "2026-11-17",
  "nights": 3,
  "numGuests": 2,
  "rateCategory": "AAA_CAA",
  "pricing": { "baseRate": "249.00", "discountPercent": "10.00", "nightlyRate": "224.10", "totalAmount": "672.30", "currency": "USD" },
  "cancellation": { "deadline": "2026-11-12T05:00:00Z", "isRefundableNow": true },
  "payment": { "status": "SUCCEEDED", "cardBrand": "VISA", "cardLastFour": "4242", "processedAt": "2026-09-26T14:05:00Z" },
  "bookedAt": "2026-09-26T14:05:00Z"
}
```

Errors: `400 VALIDATION_FAILED`, `401`, `402 PAYMENT_DECLINED`, `404 NOT_FOUND` (unknown
or inactive room type), `409 ROOM_UNAVAILABLE`.

> **Design Decision — no hold, cart, or pending state.**
> One atomic `POST` creates a confirmed booking. A real hotel system would place a
> time-boxed hold while the guest enters payment; the overview describes no such step, and
> a `PENDING` status would need expiry sweeping, and would have to participate in the
> exclusion constraint to be meaningful. The guest-facing consequence — a room can sell out
> between search and confirm — is handled honestly with `409 ROOM_UNAVAILABLE` and a
> re-search prompt.

> **The payment payload, and what happens to it.** The form collects card-shaped input
> because the overview says it does. The backend validates its *shape* and immediately
> discards everything but `cardBrand` (derived from the leading digits) and the last four.
> The PAN, CVV, and expiry are never written to the database, never logged, and never
> echoed in a response. Request-body logging must be disabled or field-masked on this
> route in both backends. A card number ending in `0000` simulates `402 PAYMENT_DECLINED`,
> giving the clients a deterministic way to exercise the failure path without a processor.

### `GET /reservations` — Guest

The caller's own bookings, always — there is no parameter to widen the scope.

Query: `status` (repeatable), `from` / `to` (filter on `checkInDate`), `page`, `pageSize`,
`sort` (`checkInDate`, `bookedAt`; default `checkInDate:desc`).

**`200 OK`** — paginated array of reservation summary objects: `id`,
`confirmationNumber`, `status`, `property` (id, name), `roomType` (code, name),
`checkInDate`, `checkOutDate`, `nights`, `totalAmount`, `currency`, `cancellation`.

Booking *history* and *upcoming stays* are the same endpoint with different filters —
`?to=<today>` and `?from=<today>` respectively. Two endpoints for one query would be
redundant.

### `GET /reservations/{reservationId}` — Guest

**`200 OK`** — the full reservation object from `POST /reservations`.
`cancellation.isRefundableNow` is evaluated at request time.

`404 NOT_FOUND` if the reservation belongs to another guest — not `403`.

### `PATCH /reservations/{reservationId}` — Guest

Modifies an existing booking. Permitted only while `status = 'CONFIRMED'` **and**
`now() < cancellation_deadline`, per the overview's "modify where cancellation policy
allows".

```json
{ "checkInDate": "2026-11-15", "checkOutDate": "2026-11-18", "numGuests": 1 }
```

Changeable: `checkInDate`, `checkOutDate`, `numGuests`, `rateCategory`. Not changeable:
`roomTypeId` (cancel and rebook — a different room type is a different product),
`propertyId`, or anything in `pricing`.

A date change re-runs allocation and re-prices the stay at **current** rates, and the
response states the new total. The reservation may move to a different room; the response
carries the current `room`. `cancellation.deadline` is recomputed from the new
`checkInDate`.

**`200 OK`** with the updated reservation. Errors: `400`, `401`, `404`,
`409 CANCELLATION_WINDOW_CLOSED`, `409 INVALID_STATUS_TRANSITION` (not `CONFIRMED`),
`409 ROOM_UNAVAILABLE`.

### `POST /reservations/{reservationId}/cancel` — Guest

Empty body, or `{ "reason": "..." }` (stored nowhere; accepted and ignored — reserved for
a future audit field, and documented as such so no client depends on it).

Permitted while `status = 'CONFIRMED'`. Cancellation is allowed **inside** the 48-hour
window too — it is simply non-refundable there, which is the policy, not a block.

**`200 OK`**

```json
{
  "id": "0192f3a5-4400-7000-8000-000000000031",
  "confirmationNumber": "HA7K2M9QX4",
  "status": "CANCELLED",
  "cancelledAt": "2026-09-26T14:40:11Z",
  "wasRefundable": true,
  "refund": { "status": "REFUNDED", "amount": "672.30", "currency": "USD" }
}
```

`refund` is `null` when `wasRefundable` is `false`, and the payment row keeps
`SUCCEEDED`. No money moves in either case; this is the demo's record of the policy
decision.

Errors: `401`, `404`, `409 INVALID_STATUS_TRANSITION` (already cancelled, checked in, or
checked out). Cancelling an already-cancelled booking is a `409`, not a silent `200`: the
guest's mental model and the server's state genuinely disagree, and hiding that helps
nobody.

---

## Admin reservation endpoints

Staff-level. A `FRONT_DESK_STAFF` caller is restricted to `home_property_id`; a
`PROPERTY_MANAGER` may pass any `propertyId` or omit it to span all properties.

### `GET /admin/reservations` — Staff

| Parameter | Notes |
|-----------|-------|
| `propertyId` | Manager: optional filter. Staff: ignored, forced to their own property |
| `status` | Repeatable |
| `guestName` | Case-insensitive substring of first or last name |
| `guestEmail` | Exact, case-insensitive |
| `confirmationNumber` | Exact |
| `checkInFrom` / `checkInTo` | Date range on `checkInDate` |
| `roomNumber` | Exact, within the scoped property |
| `page`, `pageSize` | Standard |
| `sort` | `checkInDate`, `checkOutDate`, `bookedAt`, `guestLastName`, `status`. Default `checkInDate:asc` |

**`200 OK`** — paginated reservation summaries, each additionally carrying `guest`
(`id`, `firstName`, `lastName`, `email`, `phone`) and `room` (`id`, `roomNumber`), which
the guest-facing list omits.

This single endpoint covers the overview's "view all bookings, with search and filtering
by date, guest name, status".

### `GET /admin/reservations/{reservationId}` — Staff

**`200 OK`** — full reservation plus guest contact details. `403 PROPERTY_OUT_OF_SCOPE`
for staff reaching another property. (Unlike the guest case, an out-of-scope admin gets
`403`: staff are trusted principals, and a misleading `404` would send them chasing a
data problem instead of a permissions one.)

### `POST /admin/reservations/{reservationId}/check-in` — Staff

Empty body. Requires `status = 'CONFIRMED'`. Sets `status = 'CHECKED_IN'` and
`checked_in_at = now()`.

**`200 OK`** with the updated reservation. Errors: `403`, `404`,
`409 INVALID_STATUS_TRANSITION`.

> **Assumption.** The overview says staff check a guest in "on their arrival date". The
> contract does **not** hard-block check-in on a date other than `checkInDate`: early and
> late arrivals are routine, and a demo whose front desk cannot check in a guest because
> the clock says otherwise demos badly. Instead, the response includes
> `"dateWarning": "EARLY" | "LATE" | null` when the current date in the property's timezone
> differs from `checkInDate`, and the admin UI surfaces it as a confirmation prompt. This
> is a deliberate reading of an underspecified rule, flagged here for review.

### `POST /admin/reservations/{reservationId}/check-out` — Staff

Empty body. Requires `status = 'CHECKED_IN'` — a guest cannot check out without having
checked in, and that ordering is enforced by the database `CHECK` constraint as well as
here. Sets `status = 'CHECKED_OUT'` and `checked_out_at = now()`.

Checking out does **not** release the remainder of the booked range. The reservation keeps
its `stay_period`, so the exclusion constraint still holds those dates and an early
departure never resells the room. Modeling the difference between booked and actual stay
would need a second date range, which the overview does not ask for.

**`200 OK`**. Errors: `403`, `404`, `409 INVALID_STATUS_TRANSITION`.

### `POST /admin/reservations/{reservationId}/cancel` — Staff

Same semantics as the guest cancel, with two differences: staff may cancel any reservation
in their scope, and the body accepts `{ "waiveFee": true }` to force
`wasRefundable = true` inside the 48-hour window. Front-desk fee waivers are ordinary
hotel practice, and modeling them costs one boolean.

`cancelled_by_user_id` records the admin. **`200 OK`**; errors as the guest version, plus
`403`.

---

## Admin property and inventory endpoints

### `GET /admin/properties` — Staff

**`200 OK`** — paginated. Includes inactive properties and adds `roomCount`,
`roomTypeCount`, and `isActive`, which the public listing omits. Staff see only their own
property; managers see all.

### `POST /admin/properties` — Manager

```json
{
  "name": "Lakeside Inn",
  "slug": "lakeside-inn",
  "description": "Twenty-four rooms on the north shore.",
  "photoUrl": "https://cdn.example/lakeside/hero.jpg",
  "address": { "line1": "7 North Shore Road", "line2": null, "city": "Burlington", "stateProvince": "VT", "postalCode": "05401", "countryCode": "US" },
  "phone": "+1-802-555-0177",
  "timezone": "America/New_York"
}
```

`slug` is optional; when omitted it is derived from `name` and de-duplicated with a
numeric suffix. `timezone` must be a valid IANA zone identifier.

**`201 Created`**, `Location` header. Errors: `400`, `403 INSUFFICIENT_ROLE`,
`409 SLUG_IN_USE`.

### `PATCH /admin/properties/{propertyId}` — Manager

Partial update of every creation field plus `isActive`. Deactivating a property hides it
from public browsing and availability search; it does **not** cancel existing
reservations, and those remain visible and actionable in the admin area.

**`200 OK`**. Errors: `400`, `403`, `404`, `409 SLUG_IN_USE`.

### `POST /admin/properties/{propertyId}/room-types` — Manager

```json
{
  "code": "SUITE",
  "name": "Lakeview Suite",
  "description": "Separate sitting room with a lake-facing balcony.",
  "baseRate": "389.00",
  "maxOccupancy": 4,
  "bedConfiguration": "one king bed and one queen sleeper sofa",
  "isAccessible": false,
  "amenityCodes": ["WIFI", "AIR_CONDITIONING", "REFRIGERATOR", "WET_BAR", "SAFE"]
}
```

**`201 Created`**. Errors: `400 VALIDATION_FAILED` (unknown `amenityCode`, non-positive
`baseRate`), `403`, `404`, `409` (duplicate `(propertyId, name)`).

### `PATCH /admin/room-types/{roomTypeId}` — Manager

Partial update of the creation fields plus `isActive`. This is the overview's "manage
rates" path: changing `baseRate` affects **future** bookings only, because every
reservation snapshots its own rate. Existing reservations are never re-priced.

**`200 OK`**. Errors: `400`, `403`, `404`, `409`.

### `PUT /admin/room-types/{roomTypeId}/amenities` — Manager

```json
{ "amenityCodes": ["WIFI", "TELEVISION", "SAFE"] }
```

Replaces the whole set — `PUT`, not `PATCH`, because the request is the complete desired
state and that makes it idempotent. **`200 OK`** with the resulting amenity array.

### Room-type photos — Manager

- `GET /admin/room-types/{roomTypeId}/photos` → **`200 OK`**, array ordered by
  `sortOrder`.
- `POST /admin/room-types/{roomTypeId}/photos` with
  `{ "url": "...", "caption": "...", "sortOrder": 2, "isPrimary": false }` → **`201
  Created`**. Setting `isPrimary: true` clears the flag on the room type's other photos in
  the same transaction, honoring the partial unique index.
- `DELETE /admin/room-types/{roomTypeId}/photos/{photoId}` → **`204 No Content`**.
  Deleting the primary photo leaves the room type with none until another is promoted; the
  clients must tolerate a null `primaryPhotoUrl`.

### `GET /admin/properties/{propertyId}/rooms` — Staff

Query: `roomTypeId`, `isOutOfService`, `page`, `pageSize`, `sort` (`roomNumber`, `floor`;
default `roomNumber:asc`).

**`200 OK`** — paginated `{ id, propertyId, roomTypeId, roomType: { code, name }, roomNumber, floor, isOutOfService }`.

### `POST /admin/properties/{propertyId}/rooms` — Manager

```json
{ "roomTypeId": "0192f3a3-2200-7000-8000-000000000011", "roomNumber": "412", "floor": 4 }
```

The room type must belong to this property, or `400`. **`201 Created`**. Errors: `400`,
`403`, `404`, `409 ROOM_NUMBER_IN_USE`.

### `PATCH /admin/rooms/{roomId}` — Manager

Updates `roomNumber`, `floor`, `isOutOfService`, or `roomTypeId` (within the same
property). Marking a room out of service removes it from future availability but does
**not** cancel its existing reservations — those must be cancelled or moved deliberately,
and the response includes `"futureReservationCount"` so the UI can warn.

**`200 OK`**. Errors: `400`, `403`, `404`, `409 ROOM_NUMBER_IN_USE`.

### `GET /admin/properties/{propertyId}/rate-plans` — Staff

**`200 OK`** — non-paginated array covering all seven discountable categories. Categories
with no stored row are returned with `discountPercent: "0.00"` and `isActive: false`, so
the admin UI can render a complete editable table without special-casing absence.

```json
[
  { "rateCategory": "AAA_CAA", "discountPercent": "10.00", "isActive": true },
  { "rateCategory": "AARP", "discountPercent": "8.00", "isActive": true },
  { "rateCategory": "GOVERNMENT_PER_DIEM", "discountPercent": "0.00", "isActive": false }
]
```

### `PUT /admin/properties/{propertyId}/rate-plans` — Manager

Replaces the property's whole rate-plan set — the overview's "manage special rate
discounts".

```json
{
  "ratePlans": [
    { "rateCategory": "AAA_CAA", "discountPercent": "12.00", "isActive": true },
    { "rateCategory": "SENIOR", "discountPercent": "10.00", "isActive": true }
  ]
}
```

`NONE` in the array is a `400`. Categories omitted from the array are deactivated.
Changes affect future bookings only. **`200 OK`** with the full array.

Errors: `400 VALIDATION_FAILED` (`NONE` present, percentage out of 0–100, duplicate
category), `403`, `404`.

---

## Admin calendar and reporting

### `GET /admin/properties/{propertyId}/calendar` — Staff

The overview's "room/rate calendar — a table showing rooms across dates and their
availability status, at a glance".

| Parameter | Notes |
|-----------|-------|
| `from` | Required, `YYYY-MM-DD` |
| `to` | Required. Max span 60 days |
| `roomTypeId` | Optional filter |

**`200 OK`** — deliberately **not** paginated: a calendar is one grid, and splitting it
across pages would break the very "at a glance" property it exists for. The 60-day cap is
what bounds the response instead.

```json
{
  "propertyId": "0192f3a2-1100-7000-8000-000000000001",
  "from": "2026-11-01",
  "to": "2026-11-14",
  "rooms": [
    {
      "roomId": "0192f3a6-5500-7000-8000-000000000041",
      "roomNumber": "412",
      "roomType": { "id": "0192f3a3-2200-7000-8000-000000000011", "code": "KING", "name": "Deluxe King, Harbor View" },
      "baseRate": "249.00",
      "isOutOfService": false,
      "occupancy": [
        {
          "reservationId": "0192f3a5-4400-7000-8000-000000000031",
          "confirmationNumber": "HA7K2M9QX4",
          "guestLastName": "Reyes",
          "status": "CONFIRMED",
          "checkInDate": "2026-11-14",
          "checkOutDate": "2026-11-17"
        }
      ]
    }
  ]
}
```

Each room carries the reservation *segments* intersecting the window rather than one entry
per date. A 60-day window for 200 rooms is 12,000 cells but only a few hundred segments;
the client expands segments into grid cells, which is cheap. Segments may extend past
`from`/`to` — the client clips them. `baseRate` is the room type's current rate, undiscounted —
the calendar has no guest or `rateCategory` in play, unlike `GET /availability` and
`POST /reservations`, where `nightlyRate` names the *discounted* per-night price. Naming this
field `baseRate` rather than reusing `nightlyRate` is deliberate: the same name meaning two
different things across endpoints is exactly the kind of thing that drifts invisibly between two
independent implementations. This is the "rate" half of "room/rate calendar".

### `GET /admin/properties/{propertyId}/reports/occupancy` — Staff

Query: `date` (optional, defaults to today in the property's timezone).

**`200 OK`**

```json
{
  "propertyId": "0192f3a2-1100-7000-8000-000000000001",
  "date": "2026-09-26",
  "totalRooms": 84,
  "sellableRooms": 82,
  "occupiedRooms": 61,
  "occupancyRate": "0.7439",
  "byRoomType": [
    { "roomTypeId": "0192f3a3-2200-7000-8000-000000000011", "code": "KING", "name": "Deluxe King, Harbor View", "sellableRooms": 20, "occupiedRooms": 17, "occupancyRate": "0.8500" }
  ]
}
```

`occupiedRooms` counts rooms whose non-cancelled `stay_period` contains `date`.
`sellableRooms` excludes out-of-service rooms, and `occupancyRate =
occupiedRooms / sellableRooms` — the denominator hoteliers actually use. `occupancyRate`
is a decimal string in `[0, 1]`, not a percentage, so the clients decide the formatting.
`"0.0000"` when `sellableRooms` is zero, never a division error.

### `GET /admin/properties/{propertyId}/reports/arrivals` — Staff

Query: `date` (defaults to today in the property's timezone), `page`, `pageSize`.

**`200 OK`** — paginated reservations with `checkInDate = date` and
`status = 'CONFIRMED'`, ordered by guest last name. This is both the "upcoming arrivals"
report and the front desk's check-in worklist, so it returns the guest contact block and
the assigned room.

> **Assumption.** The overview says "upcoming arrivals" without defining the horizon. This
> is scoped to a single date, defaulting to today, because the front desk's real question
> is "who is arriving today". A multi-day view is available through
> `GET /admin/reservations?status=CONFIRMED&checkInFrom=&checkInTo=`, so no capability is
> lost.

Deliberately absent: ADR, RevPAR, and revenue-by-segment. The overview lists them under
future enhancements.

---

## AI assistant endpoints

> **Implemented by `hotelapp-ai-service`, not by either backend.** Design and reasoning in
> [ai-enablement-overview.md](./ai-enablement-overview.md). These endpoints are **strictly
> additive**: every criterion in [acceptance-criteria.md](./acceptance-criteria.md) must still
> pass with this service stopped, and both frontends must render AI features as unavailable
> rather than broken when it is.

**They mount under `/api/v1/` for one specific reason.** The session cookie is scoped
`Path=/api/v1`, and cookie scope is host plus path and **ignores port** — so a browser sends the
session to `localhost:8000/api/v1/assistant/...` even though the backends are on `:8080`/`:3000`.
Mounted anywhere else, the service receives no caller identity and pass-through authorization
silently stops working. The two `.well-known` documents are the exception: RFC 9728 and RFC 8414
require them at the **host root**, and they are unauthenticated metadata that needs no cookie.

**The service never reads business data from the database.** Every live figure in an answer comes
from the endpoints above, called with the caller's own session, so the assistant cannot report
availability or pricing that the API would not also report.

### `POST /assistant/ask` — Public

Grounded question answering over the hotel document corpus. **A session is optional**: without
one the assistant answers from public catalogue data and the corpus; with one it may additionally
answer about the caller's own reservations, because the session is forwarded to the backend and
the backend's existing authorization applies unchanged.

```json
{
  "question": "Can I cancel my stay next Friday and get a refund?",
  "history": [
    { "role": "user", "content": "What's the cancellation policy?" },
    { "role": "assistant", "content": "..." }
  ]
}
```

`history` is **optional and client-held**. The service stores no conversation state between
requests; multi-turn context is whatever the client sends back. That keeps the component stateless
and means a conversation is never readable by anyone who later obtains the database.

**`200 OK`**, `Content-Type: text/event-stream`. Three event types:

```
event: token
data: {"text":"You can cancel up to "}

event: citation
data: {"documentTitle":"Harborview Grand — Cancellation Policy","section":"Flexible rates","chunkId":"…"}

event: done
data: {"usage":{"promptTokens":1840,"completionTokens":212},"costUsd":"0.0043","cacheHit":false}
```

**A `done` event is the only successful terminator.** A stream that closes without one is a
failure, and clients must treat it as such — a truncated stream is otherwise indistinguishable
from a complete answer.

**Failure after streaming has begun** cannot change the status code, so it arrives as a terminal
event carrying the ordinary Problem Details body, after which the stream closes:

```
event: error
data: {"code":"AI_TIMEOUT","detail":"…","traceId":"…"}
```

Text already streamed is **not** retracted; the client marks the answer incomplete. Removing text
a guest has already read is worse than labelling it.

Errors before the first byte are ordinary Problem Details responses: `400 QUESTION_TOO_LONG`,
`429 RATE_LIMITED` (this service limited you) or `429 AI_RATE_LIMITED` (the provider did),
`503 AI_UNAVAILABLE`, `503 RETRIEVAL_FAILED`.

### `POST /assistant/search` — Public

Resolves a free-text request into the parameters `GET /availability` already accepts, runs that
search, and returns both.

```json
{ "query": "a quiet room for two next weekend, under $300, with a fridge" }
```

**`200 OK`**

```json
{
  "interpretation": "2 guests · Fri 10 Oct – Sun 12 Oct · up to $300/night · refrigerator",
  "parameters": {
    "propertyId": "0192f3a5-…",
    "checkInDate": "2026-10-10",
    "checkOutDate": "2026-10-12",
    "numGuests": 2,
    "maxNightlyRate": "300.00",
    "amenityCode": "REFRIGERATOR",
    "rateCategory": "AAA_CAA"
  },
  "results": { "data": [], "pagination": {} }
}
```

`rateCategory` is extracted the same way as `amenityCode` when the guest names one ("I'm a AAA
member") — one of the fixed enum values, defaulting to `NONE` exactly as `GET /availability` already
does when omitted.

`results` is the **verbatim `GET /availability` envelope**, so both frontends reuse their existing
types and rendering with no new shape to support. `parameters` is returned so the UI can show what
was understood and let the guest correct it — an interpretation the guest cannot see or edit is an
interpretation they cannot trust.

**`maxNightlyRate` is a decimal string**, like every other money value in this contract. The model
never performs arithmetic on prices; totals come from `GET /availability`, already computed.

> **Design Decision — no property named, no problem: search fans out instead of guessing or
> rejecting.** `GET /availability` is single-property by design
> ([its own section above](#get-availability--public)), but a guest should not have to name a
> property before searching — most real hotel search works the other way around, and this chain
> has exactly two properties to check. When extraction resolves a property (named, or implied by
> city), this endpoint behaves exactly as shown above: one `GET /availability` call, the response
> passed through unchanged. When it cannot, the service calls `GET /availability` **once per
> property**, merges `data`, re-applies the requested sort, and recomputes `pagination` over the
> combined set. The response **shape** is identical either way — a client cannot tell from the
> envelope how many backend calls produced it, which is the point. This does not scale past a
> handful of properties and is not meant to; it is sized to this chain, the same way the
> in-process idempotency cache in `POST /reservations` is sized to a demo rather than a production
> fleet.
>
> **Property names are resolved against the live `GET /properties` list, never against names
> written into a prompt.** A name baked into the extraction prompt would go stale the moment a
> property is renamed or a third one is added — the same reasoning that keeps rate categories and
> amenity codes sourced from their own enums rather than hand-typed.
>
> **"Next weekend" needs a concrete today.** The extraction prompt is given the current date
> explicitly, in UTC — there is no signal in free text to infer a guest's own timezone from, and
> this matches the product's existing "dates only" posture elsewhere.

Errors: `400 VALIDATION_FAILED` when the request resolves to parameters the availability endpoint
itself rejects (the service does not silently repair them), plus the `AI_*` codes above. **When
the gap is something extraction itself noticed** — most commonly no check-in/check-out date
anywhere in the text — `detail` names what is missing in plain language ("I didn't catch your
dates — what check-in and check-out are you thinking?") rather than passing through
`GET /availability`'s generic validation message. The status code and `code` stay
`400 VALIDATION_FAILED` either way; only the human-readable `detail` differs by origin. The service
never invents a date to fill the gap.

### `GET /assistant/health` — Public

**`200 OK`**

```json
{
  "status": "UP",
  "provider": "UP" ,
  "retrieval": "UP",
  "backend": "UP",
  "backendTarget": "springboot"
}
```

`provider` may be `NOT_CONFIGURED`, which is a **supported state, not a failure** — the service
runs without an API key and reports AI features unavailable. `status` stays `UP` in that case:
"the service is running" and "the service can answer questions" are different facts, and collapsing
them produces a green health check beside a broken assistant.

`backendTarget` names which backend this instance is configured against, for the same reason
`GET /health` carries `backend` — a tester needs to know which implementation answered.

### MCP and OAuth endpoints

`POST /mcp` is the MCP HTTP transport. The protocol and its authorization are defined by the MCP
specification (revision **2026-07-28**) and the OAuth 2.1 RFCs, and **are not restated here** —
restating a standard is how a project ends up with a subtly non-conformant version of it.

What this contract fixes, because it is a choice rather than a given:

- The MCP server is a **pure resource server**. It validates tokens; it never issues one and never
  logs a user in. Per RFC 9728 it publishes Protected Resource Metadata, and per RFC 8707 it
  rejects any token not audience-bound to itself.
- **Access tokens are opaque and validated by introspection — never JWTs.** OAuth 2.1 does not
  require a JWT, and [decision-log.md](./decision-log.md) entry 2 removed bearer-JWT
  authentication from this project deliberately. This extends that decision rather than reversing
  it.
- **Dynamic Client Registration is not implemented.** The 2026-07-28 revision deprecated it in
  favour of Client ID Metadata Documents; the single client is pre-registered.
- **The stdio transport exposes only the public tool surface** and carries no credential. Guest
  data and writes require the HTTP transport and a real authorization flow.

Tool-level behaviour, including which tools write, is specified in
[ai-enablement-overview.md §6](./ai-enablement-overview.md#6-the-mcp-server).

---

## Operational endpoints

### `GET /health` — Public

**`200 OK`** `{ "status": "UP", "database": "UP", "version": "1.0.0", "backend": "nodejs" | "springboot" }`.
**`503`** with `status: "DOWN"` when the database is unreachable. `backend` exists so a
tester can confirm which implementation the frontend is actually talking to — directly
useful given that either backend must serve either client.

---

## Cross-cutting requirements

**CORS.** Both backends allow the two client origins with
`Access-Control-Allow-Credentials: true`, methods `GET, POST, PATCH, PUT, DELETE,
OPTIONS`, and headers `Content-Type, Idempotency-Key`. Origins come from configuration,
never a wildcard — `*` is incompatible with credentialed requests anyway, and every
authenticated request here is credentialed because the session cookie rides on it.

**Rate limiting.** `POST /auth/login` and `/auth/register` are limited as described above;
all other endpoints get a coarse per-IP ceiling. `429` responses carry `Retry-After`.

**Security headers.** `Strict-Transport-Security`, `X-Content-Type-Options: nosniff`,
`X-Frame-Options: DENY`, and a restrictive `Content-Security-Policy` on any
server-rendered surface. Detail belongs in
[security-principles.md](./security-principles.md).

**Logging.** Every response carries `traceId`, echoed in logs. Never log: the `Cookie` or
`Set-Cookie` header, raw session tokens, `payment.cardNumber`, `payment.cvv`, or `password`
fields. Both backends must mask these at the framework level, not per-handler. A session
token in a log file is a usable credential, so `Cookie` masking is not optional.

**Idempotency summary.** `GET` and `DELETE` are naturally idempotent. `PUT` endpoints
replace whole collections and so are idempotent by construction. `POST /reservations`
supports `Idempotency-Key`. `POST /auth/logout` is idempotent. The check-in, check-out,
and cancel transitions are **not** idempotent — a repeat returns `409
INVALID_STATUS_TRANSITION`, which is the correct signal that the caller's view of state is
stale.

**OpenAPI.** Each backend publishes a generated OpenAPI 3.1 document at
`/api/v1/openapi.json`. The two documents should be diffable; a meaningful diff is a
contract violation in one of them. That diff is the cheapest available test that this
document is being honored, and it belongs in CI.

---

## Summary of design decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Authentication | Opaque session token in an `HttpOnly; SameSite=Lax` cookie, backed by a `sessions` row in the shared database | Both backends already share the database that would have to be consulted anyway; revocation is immediate, and the clients need no token handling at all |
| Cookie `SameSite` | `Lax` | Blocks every cross-site state-changing method while allowing top-level GET deep links into the admin area; no GET endpoint here mutates state |
| Session lifetime | 8-hour sliding idle window, 30-day absolute cap, `expires_at` written at most once per 5 minutes | Covers a full front-desk shift without logging anyone out, without turning a read-hot path into a write-hot one |
| Error format | RFC 9457 `application/problem+json` | Standardized; native in Spring Boot, one parser for both clients |
| Pagination | 1-based offset with a `pagination` envelope | Admin tables need page counts and arbitrary sorts; data volumes make `OFFSET` a non-issue |
| Money in JSON | Decimal strings | Avoids IEEE-754 drift between two backends and two clients |
| Booking granularity | Search by room type, server allocates the room | Keeps the no-overbooking guarantee on the database constraint, not on a stale client read |
| Booking creation | One atomic `POST`, no hold/pending state | The overview describes no hold step; `PENDING` would need expiry sweeping |
| Overbooking response | `409 ROOM_UNAVAILABLE` from SQLSTATE `23P01` | The database is the single arbiter both backends share |
| Versioning | Path-based `/api/v1` | Legible in logs and in client configuration |

Sources consulted for current practice:
[Stop Defaulting to JWTs: Choosing the Right Session Architecture in 2026](https://reptile.haus/journal/stop-defaulting-to-jwts-choosing-the-right-session-architecture-in-2026/),
[API Authentication Best Practices: 7 Strategies for 2026](https://unlocked.everykey.com/api-authentication-best-practices/).
