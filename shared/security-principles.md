# Security Principles

Security policy for HotelApp: what is protected, by what rule, and where the line is drawn.
This document states *policy*. Implementation detail belongs in
`stacks/<tech>/security-implementation.md` (Phases 3 and 4), and the mechanisms themselves
are specified in [api-contracts.md](./api-contracts.md) and
[data-model.md](./data-model.md) — referenced here rather than repeated.

---

## Threat model

Worth stating, because it explains every decision below and every exclusion at the end.

**In scope.** HotelApp is a public web application with three privilege tiers and real
credentials. The realistic threats are: credential attacks against the login endpoint;
session theft or fixation; one authenticated user reaching another's data (horizontal
escalation); a guest reaching admin functions or a front-desk user reaching another property
(vertical escalation); injection through any user-controlled input; and accidental
disclosure through logs, error messages, or over-broad responses.

**Out of scope.** This is a portfolio demonstration with no real guests, no real money, and
no production deployment. It holds no cardholder data by design, no real personal data, and
nothing worth a targeted attack. The absences at the end of this document follow from that,
and are choices rather than gaps.

**The design principle throughout:** the server is the only authority. Every client-side
check — route guards, disabled buttons, hidden nav items — exists for user experience and is
assumed bypassed.

---

## Authentication

### Passwords

Policy, restating [api-contracts.md](./api-contracts.md#post-authregister--public) briefly:

| Rule | Value |
|------|-------|
| Length | 12–128 characters |
| Composition requirements | **None** |
| Deny list | Reject passwords appearing in a common-password list |
| Hashing | bcrypt, cost factor 12 |
| Storage | `users.password_hash` only. The plaintext is never stored, logged, or returned |

> **Why no composition rules.** Mandated character classes push people toward
> `Password1!` and toward reuse, and current NIST guidance (SP 800-63B) recommends length
> and deny-listing over composition. A 12-character minimum with a deny list is stronger and
> less hostile. This is a deliberate departure from what a reviewer may expect to see, which
> is why it is justified here rather than left implicit.

**bcrypt at cost 12** was chosen for a reason specific to this project: Node's `bcrypt` and
Spring Security's `BCryptPasswordEncoder` produce and verify byte-identical modular-crypt
strings, so a password set through one backend authenticates through the other. Argon2id is
the stronger algorithm, but its Node and Java implementations must be parameter-matched to
interoperate, and cross-stack verification is a hard requirement here. The trade is recorded
in [data-model.md](./data-model.md#users).

The cost factor is **configuration, not a constant** — see
[Secrets and configuration](#secrets-and-configuration) — so it can be raised without a code
change, and both backends must read the same value.

### Password change and reset posture

- **Change** (`PUT /me/password`) requires the current password, and revokes every *other*
  session for that user while keeping the caller's. That is how a user evicts an intruder
  from other devices.
- **Reset by email is not implemented.** It needs transactional email, which
  [project-overview.md](./project-overview.md) lists as a stretch goal. The consequence is
  stated rather than hidden: a guest who forgets their password cannot self-recover, and in a
  demo an administrator would reseed the account.
- **No password expiry or forced rotation.** Periodic rotation is no longer recommended
  practice; it drives predictable increments.
- **No password history.** Nothing prevents reusing a previous password.
- **No secondary factor.** MFA is out of scope, and this is the most significant security
  capability the project does not have. For an application holding no real data, a second
  factor would be ceremony; a genuine hotel system would need one for admin tiers.

### Account lockout

**No progressive lockout. Rate limiting only**, as specified in
[api-contracts.md](./api-contracts.md#post-authlogin--public): 10 attempts per 15 minutes, keyed on
IP **and** on the submitted email, whichever trips first.

> **Design Decision — rate limiting instead of account lockout.**
> Locking an account after N failures converts a credential-guessing attempt into a
> denial-of-service against a known user: anyone who knows an email address can lock its
> owner out at will. Per-email rate limiting slows guessing to the same degree without
> handing an attacker that lever. The 15-minute window caps an attacker at roughly 40
> guesses per hour per address, which defeats credential-stuffing throughput without ever
> locking a real guest out of their booking.
>
> `users.is_active` exists for **administrative** deactivation, not automatic lockout. An
> inactive account cannot authenticate and receives `403 ACCOUNT_INACTIVE`.

**Enumeration resistance.** Login returns `401 INVALID_CREDENTIALS` identically for an
unknown email and a wrong password, and both paths must take the same time — verify against
a dummy hash when no user exists, or response timing distinguishes them. Registration is the
one unavoidable oracle: `409 EMAIL_ALREADY_REGISTERED` is necessary for a usable signup
form, and that trade is accepted knowingly.

### Sessions

Server-side sessions are the entire authentication mechanism. The cookie attributes, TTL
policy, sliding window, and revocation rules are specified in
[api-contracts.md](./api-contracts.md#authentication) and
[data-model.md](./data-model.md#sessions), and are not repeated here.

The security properties that follow, and the reasoning for each:

| Property | Consequence |
|----------|-------------|
| Token is 256 bits of CSPRNG output | Not guessable; no structure to attack |
| Only the SHA-256 hash is stored | A database dump yields no usable sessions |
| Cookie is `HttpOnly` | XSS cannot read the credential |
| Cookie is `Secure` | Never transmitted over plain HTTP |
| Cookie is `SameSite=Lax` | Blocks the cookie on every cross-site state-changing method |
| Revocation is a single row write | Logout is effective on the very next request, with no TTL lag |
| Role and scope are read from the joined user row | A revoked or downgraded role takes effect immediately |

**Session fixation** is prevented by the one rule that matters: a new session row and a new
token are created on every successful login, and the server never adopts a token supplied by
the client. There is no session id in a URL, ever.

**CSRF.** Under `SameSite=Lax` the browser withholds the session cookie from cross-site
POST, PUT, PATCH, and DELETE, which covers the entire state-changing surface. No CSRF token
is required, and none is used. This is safe **only** because no `GET` endpoint in this
contract mutates state — that invariant is what `Lax` rests on, and adding a state-changing
`GET` would silently break it. Treat "GET is always safe and idempotent" as a security rule
in this project, not merely a REST convention.

**Session cleanup.** Expired rows are deleted by a periodic job. Revoked rows are retained
until expiry so `user_agent`, `ip_address`, and `issued_at` survive as an audit trail.

---

## Authorization

Four tiers — Public, Guest, Staff, Manager — fully specified in
[api-contracts.md](./api-contracts.md#authorization). The principles behind them:

**Deny by default.** An endpoint's tier is declared explicitly. A route with no declared
tier is a bug that must fail closed, not default to public. Both backends should structure
this so that forgetting to annotate a route denies access rather than granting it.

**Rank-based role comparison, not set membership.** `PROPERTY_MANAGER` ≥
`FRONT_DESK_STAFF` ≥ `GUEST`. Checks ask "is this caller at least Staff", never "is this
caller in {STAFF, MANAGER}" — the latter invites a new tier to be forgotten in one of the
dozens of places it must be listed.

**Ownership is checked server-side on every request, never inferred from the request.** A
guest fetching a reservation is authorized by comparing `reservations.guest_user_id` to the
session's user, not by trusting a `guestId` parameter. Property scope is re-derived from the
session's `home_property_id` on every scoped route, never taken from the client.

**Authorization failures leak as little as possible**, and the distinction is deliberate:

| Case | Response | Why |
|------|----------|-----|
| Guest requests another guest's reservation | `404 NOT_FOUND` | A `403` would confirm the reservation exists — an enumeration oracle over other guests' bookings |
| Staff requests another property's resource | `403 PROPERTY_OUT_OF_SCOPE` | Staff are trusted principals; a misleading `404` sends them chasing a data problem instead of a permissions one |
| Guest requests an admin endpoint | `403 INSUFFICIENT_ROLE` | The route's existence is public knowledge from the contract |

**Confirmation numbers are not credentials.** They are short and human-quotable, therefore
guessable, therefore never sufficient to authorize anything. Every lookup by confirmation
number still applies the same ownership and scope checks.

---

## Input validation

**Validate at the boundary, then trust the validated object internally.** Validation happens
once, in the HTTP layer, against an explicit schema per endpoint. Service and data-access
layers do not re-validate shapes.

**Reject unknown fields**, established in
[api-contracts.md](./api-contracts.md#request-validation). As a general principle: silently
dropping an unrecognized field lets a client believe it set something it did not, and lets
the two backends disagree about what a request meant. A `400` is the honest answer. This is
also a mass-assignment defense — a request cannot reach a field the endpoint did not declare,
so no client can set `role`, `isActive`, or a snapshot price by adding a key.

**Allow-list, never deny-list.** Every enum, sort field, filter parameter, and status
transition is checked against the set of permitted values. No input is sanitized by stripping
"dangerous" characters; it is either a valid member of a known set or it is rejected.

**Server-authoritative values are never accepted from the client.** The clearest example:
`POST /reservations` has **no price field at all**. Pricing is resolved server-side from the
room type and rate plan. The same applies to `role`, `confirmationNumber`,
`cancellationDeadline`, `status`, and every `*_at` timestamp. If a value should be
server-determined, the contract does not name it as input — the field's absence is the
control, which is stronger than validating it away.

**Bound everything that could be unbounded**: `pageSize` ≤ 100, stays ≤ 30 nights, the admin
calendar window ≤ 60 days, and a maximum length on every string field. An out-of-range value
is a `400`, never silently clamped — clamping hides client bugs and makes the two backends'
behavior harder to compare.

---

## Injection

**SQL injection: parameterized queries only, with no exceptions.** Both ORMs parameterize by
default — Prisma's query builder and JPA/HQL with bound parameters. String-concatenated SQL
is prohibited regardless of how the values were obtained.

Two places need explicit care, because both involve hand-written SQL:

- **Raw SQL for the exclusion constraint and the availability query.**
  [data-model.md](./data-model.md#no-overbooking) specifies raw SQL in migrations and a
  hand-written availability query. Migrations contain no user input. The availability query
  must use bound parameters for every date, id, and count — it is the most
  parameter-dense query in the application and therefore the one worth reviewing by hand.
- **Dynamic sort and filter clauses.** `?sort=<field>:<direction>` cannot be a bound
  parameter, because an identifier is not a value. It must be resolved through an
  allow-list mapping API field names to column names, per endpoint. Interpolating a sort
  field into SQL, even "after validating it", is the classic version of this bug.

**Cross-site scripting.** Both frameworks escape interpolated content by default; the rule is
to not defeat that. No `dangerouslySetInnerHTML` in React, no `bypassSecurityTrustHtml` in
Angular, on any path that can carry user or admin input. Property descriptions, room-type
names, amenity labels, and guest names are all rendered as text, never as markup.

**Photo and link URLs are user-supplied** (a manager types them) and are the one field that
becomes an attribute rather than text content. Validate scheme against `https:` on write, and
never interpolate a URL into a `javascript:`-reachable context.

**Other injection surfaces**, noted because they are easy to forget: log injection (never
interpolate unescaped user input into a log line), and header injection (no user input in a
response header, which the contract avoids by never echoing input into headers).

---

## Transport security

- **HTTPS everywhere except local development.** Plain HTTP is acceptable only on
  `localhost`.
- **The `Secure` cookie flag needs no dev-only relaxation**: current browsers treat
  `http://localhost` as a secure context, so the same cookie configuration works in
  development and would work deployed. Not weakening a security attribute for local
  convenience is worth the small amount of care it takes.
- **HSTS** is set in any non-local environment, and deliberately not on `localhost`, where it
  would poison the browser's HSTS cache for every other project served from `localhost`.
- **TLS termination is out of scope** as an implementation concern, since there is no hosted
  environment. The policy exists so that deployment would not require revisiting it.

---

## Security headers

Listed in [api-contracts.md](./api-contracts.md#cross-cutting-requirements); rationale here.

| Header | Value | What it buys |
|--------|-------|--------------|
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains` | Forces HTTPS for a year after first contact, closing the initial-plain-HTTP window that a redirect alone leaves open. Non-local only |
| `X-Content-Type-Options` | `nosniff` | Stops the browser from guessing a response's type. Relevant because the API returns both `application/json` and `application/problem+json`, and a sniffed JSON response can be coerced into script in older attack patterns |
| `X-Frame-Options` | `DENY` | Prevents framing the admin area, which is the clickjacking target — a manager clicking an invisible "delete" is the realistic version of this attack |
| `Content-Security-Policy` | Restrictive; `default-src 'self'` as the base | Defense in depth for XSS: even if a payload is injected, it cannot load or exfiltrate to an outside origin. The one policy needing care is `img-src`, which must permit the external photo CDN |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Keeps paths containing reservation ids out of `Referer` headers sent to third parties — the photo CDN would otherwise see admin URLs |
| `Cache-Control` | `no-store` on authenticated responses | Keeps another guest's booking out of a shared browser's cache and off disk |

`X-Frame-Options` is superseded by CSP's `frame-ancestors` in modern browsers; both are sent,
since the cost is one header and older-browser coverage is free.

A frontend served as static assets also needs these headers from whatever serves it, not just
from the API. Under the Docker Compose setup that is the frontend container's web server, and
it is the one place these headers can be forgotten because no backend code is involved.

---

## CORS

Policy, expanding the statement in
[api-contracts.md](./api-contracts.md#cross-cutting-requirements):

- **Allowed origins come from configuration.** An explicit list per environment, never
  compiled in.
- **Never a wildcard.** `Access-Control-Allow-Origin: *` is not merely discouraged here, it
  is *inoperative*: the browser refuses a wildcard on a credentialed request, and every
  authenticated request in HotelApp is credentialed because the session cookie rides on it.
  A wildcard would break the application before it weakened it.
- **`Access-Control-Allow-Credentials: true`**, which is what makes the cookie flow work
  cross-origin between an SPA dev server and the API.
- **Reflecting the request's `Origin` header is prohibited.** Reflection is the common
  shortcut that looks like a working allow-list and is in fact a wildcard that also permits
  credentials — the exact combination the browser's wildcard rule exists to prevent.
- **Methods and headers are enumerated, not wildcarded**, and the list is deliberately
  minimal: `Content-Type` and `Idempotency-Key`. There is no `Authorization` header in this
  design, and its absence from the CORS policy is a small confirmation that no token scheme
  remains.

> **Why CORS is not a security control.** CORS restricts what *browsers* let scripts on other
> origins do with a response. It stops nothing from `curl`, and it is not the reason
> unauthorized requests fail — session and role checks are. CORS is configured correctly
> here because a permissive policy plus credentials is a real vulnerability, not because a
> strict policy is doing the authorization work.

---

## Secrets and configuration

**Everything environment-specific is an environment variable. Nothing sensitive is
committed, ever.**

| Value | Variable | Notes |
|-------|----------|-------|
| Database connection | `DATABASE_URL` | Includes credentials; differs per environment |
| bcrypt cost factor | `BCRYPT_COST` | Default 12. Both backends must use the same value |
| Session idle TTL | `SESSION_IDLE_TTL_HOURS` | Default 8 |
| Session absolute cap | `SESSION_ABSOLUTE_TTL_DAYS` | Default 30 |
| Session slide threshold | `SESSION_SLIDE_THRESHOLD_MINUTES` | Default 5 |
| Allowed CORS origins | `CORS_ALLOWED_ORIGINS` | Comma-separated |
| Login rate limit | `AUTH_RATE_LIMIT_ATTEMPTS`, `AUTH_RATE_LIMIT_WINDOW_MINUTES` | Defaults 10 / 15 |
| Log level | `LOG_LEVEL` | |

Rules:

- **`.env` is git-ignored in every repo; `.env.example` is committed** with every variable
  listed and every value either a safe default or an obvious placeholder. The example file is
  the documentation of what a fresh clone needs.
- **No secret in `application.properties`, `application.yml`, `prisma/schema.prisma`, a
  Dockerfile, a Compose file, or a CI configuration.** Spring's
  `application-local.properties` and `*-local.properties` are git-ignored precisely for
  this — see [data-model.md](./data-model.md) for the `.gitignore` provisions already made.
- **Session TTLs are configuration but must match across backends.** The defaults are
  normative; a deployment that changes one backend's value and not the other's will produce
  users who appear to be logged out by one and not the other. Called out because it is the
  kind of divergence configuration makes easy and code review does not catch.
- **The demo database password is not a secret** and is documented as `password` in the
  developer's own notes. That is acceptable for a local demo database with no real data, and
  is worth stating so nobody mistakes it for an oversight — but it must still reach the
  application through `DATABASE_URL`, not through a committed file, because the *mechanism*
  is what a reviewer is evaluating.
- **No secret-management service.** No Vault, no cloud KMS, no sealed secrets. There is no
  hosted environment for one to serve.

---

## Logging and data handling

**Never logged, at any level, in any environment:** the `Cookie` and `Set-Cookie` headers,
raw session tokens, `password` and `newPassword` fields, `payment.cardNumber`,
`payment.cvv`, and password hashes. Masking is configured at the framework level, not
per-handler, so a new endpoint inherits it. A session token in a log file is a working
credential — this is the most likely accidental-disclosure path in the whole application,
because it takes only one well-meaning "log the full request" during debugging.

**Card data is never in a database, a log, or a response.** The dummy payment form validates
card-shaped input and the backend immediately discards everything but card brand and last
four. Request-body logging must be disabled or field-masked on `POST /reservations`
specifically. The column list in [data-model.md](./data-model.md#payments) is itself the
proof that a breach here could not yield a card.

**Error responses disclose nothing internal.** RFC 9457 `detail` is safe to show a user; no
stack trace, SQL fragment, hostname, file path, or driver message reaches a client. `500
INTERNAL_ERROR` carries a generic `detail` and a `traceId`, and the specifics go to logs
only. The `traceId` is how a developer connects the two, and it is the reason a generic
message costs nothing in debuggability.

**Personal data is minimal by design**: name, email, phone, and an optional address. No date
of birth, no government id, no nationality, no payment instrument. Regulatory compliance
(GDPR, CCPA) is not addressed and not claimed; the demo holds no real personal data. Data
minimization is followed anyway, because it is the habit worth demonstrating.

---

## Dependencies

- **Pinned versions with committed lockfiles** in all four implementation repos —
  `package-lock.json`, and Maven or Gradle with resolved versions. A reviewer cloning the
  repo must get the build the author had.
- **Prefer the framework's own primitives over a small package**: Spring Security for auth
  plumbing, the platform's crypto APIs for random bytes and hashing. Every added dependency
  is added attack surface, and hand-rolled crypto is worse than both.
- **No automated dependency scanning or update pipeline.** See below.

---

## Out of scope, and why that line is acceptable

Stated explicitly so a reviewer sees judgment rather than omission. Each of these is standard
in a production system and deliberately absent here.

| Not included | Why acceptable for this project |
|--------------|--------------------------------|
| **WAF** | A WAF is a compensating control for unknown application weaknesses at an internet-facing edge. There is no internet-facing edge, and the application's own input validation and parameterization are the real controls — a WAF would obscure whether they work |
| **Dependency scanning / SCA** (Dependabot, Snyk) | Valuable, and genuinely cheap to add. Absent because there is no deployment to protect and no release cadence to gate; a vulnerable transitive dependency in a locally run demo is not exploitable by anyone. **This is the one item here that is a cost/benefit call rather than a structural one, and the easiest to add later** |
| **SAST / secret scanning in CI** | Same reasoning. `.env` is git-ignored and there are no real credentials to leak |
| **Penetration testing** | A demo with no data and no deployment has nothing to compromise. The honest framing: the security posture here is *designed* and *documented*, not *verified against an attacker* |
| **MFA / TOTP** | The most significant missing capability. A real hotel system would require it for admin tiers. Omitted because there is no real access to protect, not because it would be hard |
| **Audit log of admin actions** | Partially covered incidentally — `cancelled_by_user_id`, `checked_in_at`, session `user_agent`/`ip_address` — but there is no systematic audit trail of who changed a rate or deactivated a room. A real property-management system needs one |
| **Rate limiting beyond the auth endpoints** | A coarse per-IP ceiling is specified; there is no per-user quota, no adaptive throttling, no bot detection |
| **DDoS protection, CDN, edge filtering** | No public endpoint exists to protect |
| **Encryption at rest** | The database holds no sensitive data. Disk-level encryption is a deployment concern with no deployment |
| **Field-level encryption, tokenization** | Nothing stored warrants it, which is itself the result of the payment-data decision |
| **GDPR / CCPA compliance work** | No real personal data. Data minimization is practiced; compliance is not claimed |
| **Session anomaly detection** | `ip_address` and `user_agent` are captured, so the data exists; nothing acts on it |

**The line, stated once:** this project demonstrates that the author knows how to *build*
securely — authorization on every request, parameterized queries everywhere, no card data,
no secrets in the repo, no tokens in `localStorage`, correct cookie attributes, honest error
responses. It does not demonstrate operating a secure *service*, which requires scanning,
monitoring, incident response, and a real environment to defend. Those belong to a deployment
this project deliberately does not have, and claiming them would be less credible than
naming their absence.
