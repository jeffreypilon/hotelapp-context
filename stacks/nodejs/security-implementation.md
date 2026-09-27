# Security Implementation — Node / Express

How `hotelapp-server-nodejs` implements the policy in
[security-principles.md](../../shared/security-principles.md). Policy lives there; this document
says where each control sits in this codebase and what would break it.

**This backend is one of the two places authorization is real.** The frontends' guards are UX; the
API is the enforcement point. Every control here is assumed to be the only one standing.

---

## Sessions

The whole authentication mechanism, per
[api-contracts.md](../../shared/api-contracts.md#authentication). Implementation in
`middleware/session.ts`, sequence in
[architecture-specification.md](./architecture-specification.md#session-handling).

| Control | Where | Consequence of getting it wrong |
|---------|-------|---------------------------------|
| Token compared by **SHA-256 hash**, never plaintext | `services/sessionService.ts` | A database dump becomes a set of live sessions |
| Token generated from `crypto.randomBytes(32)` | same | `Math.random()` is not a CSPRNG and is guessable |
| Cookie `HttpOnly; Secure; SameSite=Lax; Path=/api/v1` | login / register / logout responses | Script-readable or cross-site-sent credential |
| Validity is `revoked_at IS NULL AND expires_at > now()` | session middleware | A revoked session that still works is not a logout |
| `role` and `is_active` read from the **joined user row** every request | same | A deactivated user keeps working until their session expires — fails [AC-AZ-11](../../shared/acceptance-criteria.md#ac-az-11--inactive-accounts-cannot-authenticate) |
| New row and new token on **every** login | `authService.ts` | Session fixation |

**`crypto.timingSafeEqual` is not needed for the session lookup** and should not be reached for.
The lookup is a database query on a hashed value, not a string comparison in application code —
there is no timing channel to close. Where constant time *does* matter is password verification,
and `bcrypt.compare` already handles it.

**Token generation, explicitly:**

```ts
const raw = crypto.randomBytes(32).toString('base64url');   // 256 bits
const hash = crypto.createHash('sha256').update(raw).digest('hex');
// store `hash`; return `raw` in the Set-Cookie only
```

The raw token must never be logged, never written to the database, and never appear in a response
body — only in the `Set-Cookie` header. Required by
[AC-SE-01](../../shared/acceptance-criteria.md#ac-se-01--login-establishes-a-session), which asserts
the raw token appears nowhere in the database.

### What must never appear in this codebase

> This backend has **no** token-issuing machinery, and the absence is deliberate. The project
> originally specified JWT access tokens with rotating refresh tokens and reversed that decision —
> [decision-log.md](../../shared/decision-log.md) entry 2.
>
> Each of the following is the removed design leaking back in, not a feature:
>
> - Signing, issuing, or verifying a JWT
> - A `POST /auth/refresh` route — **the endpoint does not exist**
> - An `Authorization: Bearer` header being read
> - A `refresh_tokens` table, a `family_id`, or rotation logic
> - `jsonwebtoken`, `jose`, or any JWT library in `package.json`
>
> `grep -rniE "bearer|jwt|refreshToken|auth/refresh" src/` should return nothing.

---

## Passwords

**bcrypt, cost 12**, per
[security-principles.md](../../shared/security-principles.md#passwords). The cost factor is
`BCRYPT_COST` from the environment, defaulting to 12, and **both backends must read the same
value** — a mismatch means hashes one produces are slower or faster to verify than the other
expects, and a cost change applied to one only would leave the other unable to match new hashes'
work factor.

Use the `bcrypt` native binding or `bcryptjs`; both emit `$2b$` modular-crypt strings that
Spring Security's `BCryptPasswordEncoder` verifies. **That cross-verification is the reason bcrypt
was chosen over Argon2id** and is testable: a hash produced here must verify there.

| Rule | Detail |
|------|--------|
| 12–128 characters, no composition rules | [security-principles.md](../../shared/security-principles.md#passwords) |
| Deny-list check against common passwords | Before hashing |
| `password_hash` never in a `select` | Except the login query that needs it |
| Never logged, never in a DTO, never in a response | — |

**Timing equality on login is a required control, not a nicety.** When no user is found, verify the
submitted password against a **dummy hash** of the same cost before returning
`401 INVALID_CREDENTIALS`. Skipping it returns in ~2 ms versus ~200 ms and is a usable account
oracle. Required by
[AC-SE-10](../../shared/acceptance-criteria.md#ac-se-10--credential-errors-do-not-reveal-whether-an-account-exists).

---

## Authorization

Four tiers, specified in
[api-contracts.md](../../shared/api-contracts.md#authorization). Implemented in
`middleware/authorize.ts`.

**Deny by default.** A route with no `authorize` middleware must not be reachable. Structure the
router so public routes are registered on an explicitly public router and everything else inherits
a guard — forgetting an annotation should deny, not expose. A test enumerating every registered
route and asserting each has a declared tier is the cheap way to keep this true.

**Rank comparison, never set membership:**

```ts
const RANK = { GUEST: 0, FRONT_DESK_STAFF: 1, PROPERTY_MANAGER: 2 } as const;
const atLeast = (r: Role, min: Role) => RANK[r] >= RANK[min];
```

`role in ['FRONT_DESK_STAFF', 'PROPERTY_MANAGER']` is the anti-pattern: a new tier must then be
added everywhere it is enumerated, and one place will be missed. Required by
[AC-AZ-08](../../shared/acceptance-criteria.md#ac-az-08--a-manager-passes-every-staff-level-check).

**Ownership and scope are derived server-side, never read from the request.** A guest's reservation
query filters on `req.context.user.id`; a staff member's property filter comes from
`home_property_id`. A `guestUserId` or `propertyId` parameter from a scoped caller is **ignored**,
not honored — [AC-AZ-02](../../shared/acceptance-criteria.md#ac-az-02--a-guests-list-contains-only-their-own-reservations)
and [AC-AZ-05](../../shared/acceptance-criteria.md#ac-az-05--front-desk-staff-cannot-reach-another-property)
assert exactly that.

**The ownership check precedes the mutation.** A handler that cancels and then verifies ownership
returns `404` and has still cancelled the booking —
[AC-AZ-03](../../shared/acceptance-criteria.md#ac-az-03--a-guest-cannot-cancel-another-guests-reservation)
asserts the reservation is unchanged, not merely the status code.

`404` versus `403` is asymmetric on purpose; the table and reasoning are in
[error-handling.md](./error-handling.md#ownership-404-versus-403).

---

## Injection

**Parameterized queries only.** Prisma's query builder parameterizes by default; the rules that
matter are about the places it is bypassed:

| Rule | Why |
|------|-----|
| `$queryRaw` with tagged-template parameters only | Interpolation is injection |
| **`$queryRawUnsafe` / `$executeRawUnsafe` are forbidden with any input** | The unsafe variants exist for dynamic SQL and there is none here. The single exception is the test-suite `TRUNCATE`, which takes no input |
| The availability query's every date, id, and count is bound | The most parameter-dense query in the application, and hand-written — see [architecture-specification.md](./architecture-specification.md#query-rules) |
| Dynamic sort fields go through an **allow-list** | An identifier cannot be a bound parameter. Interpolating a "validated" sort field is the classic form of this bug |

**Always `select`.** A bare `findMany` returns every column, pulling `password_hash` and
`token_hash` into memory where they can reach a log or a serialized response. Explicit `select`
makes that impossible rather than unlikely — this is a security control, not a performance habit.

**Log injection:** never interpolate user input into a log message. The logger takes structured
context, and a newline in a guest's name should not be able to forge a log line.

---

## The schema is not this backend's to change

> **The migration asymmetry has a security dimension worth stating.** Per
> [versioning-strategy.md](../../shared/versioning-strategy.md#database-schema-migrations), Flyway
> is the sole DDL executor and this backend only introspects. That means:
>
> - **This backend's database credentials do not need DDL rights.** The application connects as a
>   role with `SELECT`, `INSERT`, `UPDATE`, `DELETE` on the application tables and nothing more.
>   Because Prisma never runs `CREATE`, `ALTER`, or `DROP`, granting those rights would be
>   privilege the application provably does not use. That is a real least-privilege win the Spring
>   Boot backend cannot have, since it must run Flyway.
> - **`prisma migrate` in this repo would require expanding those grants**, which is a second
>   reason beyond the ownership rule not to reach for it.
> - **`schema.prisma` is generated**, so a reviewer checking what this application can touch reads
>   the grants, not the ORM config.

---

## Transport, CORS, and headers

Set once, in `server.ts`, per
[architecture-specification.md](./architecture-specification.md#middleware-order).

**CORS** — `cors()` with explicit origins from `CORS_ALLOWED_ORIGINS` and
`credentials: true`.

- **Never `origin: true` and never reflecting the request's `Origin`.** Reflection looks like an
  allow-list and is a wildcard that also permits credentials — the exact combination the browser's
  wildcard rule exists to prevent. This is the single most likely CORS mistake in an Express app,
  because `origin: true` is the example in most tutorials.
- A wildcard is inoperative anyway: the browser refuses it on a credentialed request, and every
  authenticated request here is credentialed.
- Allowed headers are enumerated and minimal: `Content-Type`, `Idempotency-Key`. **No
  `Authorization`** — its absence is a small confirmation that no token scheme remains.

**Security headers** — `helmet()`, with the values and rationale in
[security-principles.md](../../shared/security-principles.md#security-headers). HSTS is enabled
only outside local development, deliberately, so it does not poison the browser's HSTS cache for
every other project served from `localhost`.

**`Cache-Control: no-store` on every authenticated response**, so another guest's booking does not
sit in a shared browser's cache.

**Body size limit** — `express.json({ limit: '100kb' })`. Unbounded is a trivial denial of service
on an API that needs none.

---

## Payment data

The dummy payment form's input reaches this backend and must leave almost all of it behind.

**Stored:** `card_brand` (derived from the leading digits) and `card_last_four`.
**Never stored, never logged, never returned:** the PAN, the CVV, the expiry.

Per [data-model.md](../../shared/data-model.md#payments) the column list is itself the proof that a
breach here could not yield a card.

**Concretely in this codebase:**

- **Request-body logging is disabled on `POST /reservations`**, at the logger, not per handler. One
  well-meaning "log the request" during debugging is the realistic way card data reaches disk.
- The Zod-validated request object is destructured immediately; `cardNumber` and `cvv` are read to
  derive brand and last four, then not passed further down. They never enter a service signature
  beyond the payment mapper.
- **Never put them in an error message.** A `VALIDATION_FAILED` for `payment.cardNumber` says
  "Please check the card number", never echoes the value.
- The simulated decline (a number ending `0000`) is evaluated without logging the number.

---

## Rate limiting

`middleware/rateLimit.ts` on `POST /auth/login` and `POST /auth/register`: **10 attempts per 15
minutes, keyed on IP and on the submitted email**, whichever trips first. `429` with
`Retry-After`.

**A correct password inside the window still gets `429`** — required by
[AC-SE-09](../../shared/acceptance-criteria.md#ac-se-09--login-rate-limiting). A limiter that lets a
correct password through mid-window does not slow credential stuffing.

**Per-email keying is what makes this a limiter rather than a lockout.** Locking an account after N
failures converts guessing into a denial of service against a known user; rate limiting slows
guessing without handing an attacker that lever. Reasoning in
[security-principles.md](../../shared/security-principles.md#account-lockout).

**In-memory store, single process.** Adequate here and stated as a limitation: a restart clears the
window, and the limiter would not be shared across processes if this were ever scaled. The scale-up
answer is a shared store, and there is no second process today.

**`app.set('trust proxy', ...)` must be configured deliberately if a proxy is ever in front.**
Getting it wrong makes every request appear to come from one IP, collapsing per-IP limiting to a
global one.

---

## Secrets

`config/env.ts`, validated once at startup, failing loudly on a missing value. Variables and
defaults in
[security-principles.md](../../shared/security-principles.md#secrets-and-configuration).

- **`.env` git-ignored; `.env.example` committed** with every variable and a placeholder.
- **`process.env` is read nowhere else.** A scattered read produces `undefined` inside a connection
  string at runtime rather than a startup failure.
- **No secret in a committed file, a Dockerfile, a Compose file, or a workflow.**
- **`DATABASE_URL` is never logged**, including in a startup banner — it contains the password.
- Session TTLs are configuration but **must match the other backend's**. A divergence produces users
  who appear logged out by one backend and not the other, which is the kind of bug configuration
  makes easy and code review does not catch.

---

## Deliberately absent

| Absent | Why |
|--------|-----|
| CSRF tokens | `SameSite=Lax` covers it, because **no `GET` endpoint mutates state** — [security-principles.md](../../shared/security-principles.md#sessions). That invariant is what makes it safe; adding a state-changing `GET` would silently break it |
| MFA | The most significant missing capability, named as such in [security-principles.md](../../shared/security-principles.md#password-change-and-reset-posture) |
| Password reset by email | Needs transactional email, a stated stretch goal |
| Account lockout | Deliberate — see rate limiting above |
| Dependency scanning | A declined cost, explained in [security-principles.md](../../shared/security-principles.md#out-of-scope-and-why-that-line-is-acceptable) |
| Encryption at rest, field-level encryption | Nothing stored warrants it — which is itself the result of the payment-data decision |
| A systematic admin audit log | Partially covered incidentally (`cancelled_by_user_id`, `checked_in_at`, session `ip_address`); named as a real gap in [security-principles.md](../../shared/security-principles.md#out-of-scope-and-why-that-line-is-acceptable) |
| A WAF, DDoS protection | No internet-facing edge |
| DDL rights on the application's database role | Not needed — see the schema section above |
