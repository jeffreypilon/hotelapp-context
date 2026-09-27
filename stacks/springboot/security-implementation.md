# Security Implementation — Spring Boot

How `hotelapp-server-springboot` implements the policy in
[security-principles.md](../../shared/security-principles.md). Policy lives there; this document
says where each control sits in this codebase and what would break it.

**This backend is one of the two places authorization is real.** The frontends' guards are UX; the
API is the enforcement point. Every control here is assumed to be the only one standing.

---

## Spring Security configuration

The framework brings more than the Node backend does, which is an advantage and a source of
specific traps. `config/SecurityConfig.java`:

| Setting | Value | Why |
|---------|-------|-----|
| Session creation policy | **`STATELESS`** | Spring must never create an `HttpSession`. The `sessions` table is the authority, and a parallel container session would be a second, competing one |
| CSRF | **Disabled** | The API relies on `SameSite=Lax`, not a token — [security-principles.md](../../shared/security-principles.md#sessions) |
| HTTP Basic, form login | **Disabled** | Neither is part of the contract |
| `AuthenticationEntryPoint` | **Custom** | See below |
| `AccessDeniedHandler` | **Custom** | See below |
| Authorization rules | Rank-based | See below |

> **Disabling CSRF needs its justification recorded, because it looks wrong.** Spring enables CSRF
> by default and disabling it is normally a mistake. It is correct here for one specific reason:
> **no `GET` endpoint in this API mutates state**, so `SameSite=Lax` — which withholds the cookie
> from every cross-site POST, PUT, PATCH, and DELETE — covers the entire state-changing surface.
> That invariant is what the decision rests on, which makes "a `GET` that mutates state" a security
> regression rather than a style question. Do **not** re-enable `withXsrfConfiguration()`: it
> implements the cookie-to-header pattern this API does not use, and would send a header the server
> ignores while implying a mechanism that is not there.

> **The most likely way this backend ends up non-conforming.** Authentication and authorization
> failures are raised **in the filter chain, before the dispatcher servlet**, so
> `@RestControllerAdvice` never sees them. Without a custom `AuthenticationEntryPoint` and
> `AccessDeniedHandler` emitting Problem Details, `401` and `403` come back in Spring Security's
> default shape — no `code`, no `traceId` — while every other error conforms. Those are the two most
> common error codes in the API and neither appears in a happy-path test. Same warning in
> [error-handling.md](./error-handling.md#the-final-safety-net) and
> [architecture-specification.md](./architecture-specification.md#filter-chain-and-request-flow);
> treat it as a checklist item.

---

## Sessions

The whole authentication mechanism, per
[api-contracts.md](../../shared/api-contracts.md#authentication). Implemented as
`web/SessionAuthFilter`, sequence in
[architecture-specification.md](./architecture-specification.md#session-handling).

**Implemented as a filter, not through Spring Session or `RememberMe`.** Those abstractions would
own session state, and the `sessions` table already does. Two authorities for one concept is the
problem being avoided.

| Control | Where | Consequence of getting it wrong |
|---------|-------|---------------------------------|
| Token compared by **SHA-256 hash**, never plaintext | `SessionService` | A database dump becomes a set of live sessions |
| Token from `SecureRandom`, 32 bytes | same | `java.util.Random` is not a CSPRNG |
| Cookie `HttpOnly; Secure; SameSite=Lax; Path=/api/v1` | login / register / logout responses | Script-readable or cross-site-sent credential |
| Validity is `revoked_at IS NULL AND expires_at > now()` | filter | A revoked session that still works is not a logout |
| `role` and `is_active` from the **joined user row** every request | same | A deactivated user keeps working — fails [AC-AZ-11](../../shared/acceptance-criteria.md#ac-az-11--inactive-accounts-cannot-authenticate) |
| New row and new token on **every** login | `AuthService` | Session fixation |

```java
var bytes = new byte[32];
SecureRandom.getInstanceStrong().nextBytes(bytes);
var raw  = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
var hash = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(raw.getBytes(UTF_8)));
// store `hash`; return `raw` in the Set-Cookie only
```

The raw token must never be logged, never written to the database, and never appear in a response
body — only in the `Set-Cookie` header. Required by
[AC-SE-01](../../shared/acceptance-criteria.md#ac-se-01--login-establishes-a-session).

**Set the cookie via `ResponseCookie`**, not a hand-built header string: `SameSite` is not on
`jakarta.servlet.http.Cookie`, so building the header manually is how the attribute gets silently
dropped. That would be a real security regression invisible to every functional test.

### What must never appear in this codebase

> This backend has **no** token-issuing machinery, and the absence is deliberate — the project
> reversed a JWT design, [decision-log.md](../../shared/decision-log.md) entry 2.
>
> Each of the following is that design leaking back in:
>
> - `spring-boot-starter-oauth2-resource-server`, `spring-security-jwt`, `java-jwt`, `jjwt`, `nimbus-jose-jwt`
> - `JwtDecoder`, `JwtAuthenticationConverter`, or any `Jwt*` bean
> - A `/auth/refresh` mapping — **the endpoint does not exist**
> - Reading an `Authorization: Bearer` header
> - A `refresh_tokens` entity, a `family_id`, or rotation logic
>
> `grep -rniE "bearer|jwt|refreshToken|auth/refresh" src/main/` should return nothing.

---

## Passwords

**bcrypt, cost 12**, via `BCryptPasswordEncoder`. Cost from `BCRYPT_COST`, defaulting to 12, and
**both backends must read the same value.**

Spring Security's `BCryptPasswordEncoder` and Node's `bcrypt` produce and verify the same `$2b$`
modular-crypt strings. **That cross-verification is the reason bcrypt was chosen over Argon2id** and
is testable: a hash produced in the Node backend must verify here.

| Rule | Detail |
|------|--------|
| 12–128 characters, no composition rules | [security-principles.md](../../shared/security-principles.md#passwords) |
| Deny-list check against common passwords | Before encoding |
| `passwordHash` excluded from every DTO | Enforced by DTO mapping, not by `@JsonIgnore` on the entity — the entity never leaves the service layer anyway |
| Never logged | — |

**Timing equality on login is a required control.** When no user is found, run
`encoder.matches(submitted, DUMMY_HASH)` before returning `401 INVALID_CREDENTIALS`. Skipping it
returns in ~2 ms versus ~200 ms and is a usable account oracle. Required by
[AC-SE-10](../../shared/acceptance-criteria.md#ac-se-10--credential-errors-do-not-reveal-whether-an-account-exists).

**Do not use `DaoAuthenticationProvider`'s built-in flow for this.** It has its own
user-not-found behavior and its own exception types, and wiring the contract's exact response
through it is more work than calling the encoder directly in `AuthService`.

---

## Authorization

Four tiers, specified in
[api-contracts.md](../../shared/api-contracts.md#authorization).

**Deny by default.** End the authorization chain with `.anyRequest().authenticated()`, never
`.permitAll()`. A route added without a matcher then requires authentication rather than being
open — forgetting a rule should deny, not expose.

**Rank comparison, never set membership.** Either a `RoleHierarchy` bean
(`PROPERTY_MANAGER > FRONT_DESK_STAFF > GUEST`) or an explicit rank check. `hasAnyAuthority('FRONT_DESK_STAFF', 'PROPERTY_MANAGER')`
is the anti-pattern: a new tier must then be added everywhere it is enumerated, and one place will
be missed. Required by
[AC-AZ-08](../../shared/acceptance-criteria.md#ac-az-08--a-manager-passes-every-staff-level-check).

**Ownership and scope are derived server-side, never read from the request.** A guest's reservation
query filters on the authenticated principal's id; a staff member's property filter comes from
`home_property_id` on the joined user row. A `guestUserId` or `propertyId` parameter from a scoped
caller is **ignored**, not honored —
[AC-AZ-02](../../shared/acceptance-criteria.md#ac-az-02--a-guests-list-contains-only-their-own-reservations)
and
[AC-AZ-05](../../shared/acceptance-criteria.md#ac-az-05--front-desk-staff-cannot-reach-another-property)
assert that.

**`home_property_id` in the authentication is for convenience only.** Property scope is re-derived
from the user row per request, because a cached authority would not reflect a reassignment — the same
reason `role` is not cached.

**The ownership check precedes the mutation.** A handler that cancels and then verifies ownership
returns `404` and has still cancelled the booking —
[AC-AZ-03](../../shared/acceptance-criteria.md#ac-az-03--a-guest-cannot-cancel-another-guests-reservation)
asserts the reservation is unchanged.

`404` versus `403` is asymmetric on purpose; table and reasoning in
[error-handling.md](./error-handling.md#ownership-404-versus-403).

**`@PreAuthorize` is permitted but not the primary mechanism.** URL-level rules in `SecurityConfig`
are the enforcement point because they are enumerable in one place — a reviewer can read the whole
authorization surface without opening every controller. Method-level annotations are for the cases
URL rules cannot express.

---

## Injection

**Parameterized queries only.** JPA and Spring Data parameterize by default; the rules that matter
are where that is bypassed:

| Rule | Why |
|------|-----|
| Native queries use `:named` or positional bound parameters for every value | Interpolation is injection |
| **Never string-concatenate JPQL or SQL**, including to build a `WHERE` clause | Same |
| The availability query's every date, id, and count is bound | The most parameter-dense query, and hand-written — [architecture-specification.md](./architecture-specification.md#query-rules) |
| Dynamic sort fields go through an **allow-list** mapping API names to columns | An identifier cannot be a bound parameter. `Sort.by(userSuppliedString)` reaches the SQL as an identifier and is the Spring-specific form of this bug |
| `Specification` / Criteria API for dynamic filters, not string building | Type-safe and parameterized by construction |

**`Pageable` and `Sort` from a request are not automatically safe.** `@PageableDefault` binds a
client-supplied `sort` parameter straight into the query's ordering. Validate the field against an
allow-list before it reaches the repository, and cap `size` — per
[api-contracts.md](../../shared/api-contracts.md#pagination-sorting-filtering) an out-of-range
`pageSize` is a `400`, not a silently clamped result.

**Log injection:** never concatenate user input into a log message. Parameterized logging only, so a
newline in a guest's name cannot forge a log line.

---

## This backend runs the migrations, and that has a security cost

> **The migration asymmetry cuts the other way here.** Per
> [versioning-strategy.md](../../shared/versioning-strategy.md#database-schema-migrations), Flyway
> runs in this backend, which means:
>
> - **This backend's database role needs DDL rights** — `CREATE`, `ALTER`, and the `btree_gist`
>   extension. The Node backend's role does not, and can be granted DML only. So **this is the more
>   privileged of the two backends**, and that is a direct consequence of the ownership decision
>   rather than an oversight.
> - **The least-privilege improvement available is two roles**: a migration role with DDL rights used
>   only by Flyway at startup, and a runtime role with DML only used by the application afterwards.
>   Spring supports this with a separate `spring.flyway.user` / `spring.flyway.password` from the
>   main datasource. **Recommended**, and worth doing precisely because it makes the elevated
>   privilege bounded to startup instead of held for the process's lifetime.
> - **`ddl-auto` stays `validate`.** Relaxing it to `update` would let Hibernate alter the schema at
>   runtime using those DDL rights — combining the elevated privilege with an uncontrolled writer,
>   which is the worst available configuration. This is a security reason on top of the
>   ownership reason.
> - Migration SQL is **not authored here**; it comes from `hotelapp-context`. A migration reviewed in
>   one repo and executed by another is an intentional separation, and it means a change to what this
>   backend will execute is visible in a different repo's history.

---

## Transport, CORS, and headers

**CORS** — `config/WebConfig` or a `CorsConfigurationSource` bean, with explicit origins from
`CORS_ALLOWED_ORIGINS` and `allowCredentials = true`.

- **Never `addAllowedOriginPattern("*")` with credentials.** Spring will accept that configuration
  and the browser will reject the response, producing a failure that looks like a bug rather than a
  policy. `allowedOrigins` with explicit values, always.
- **Never reflect the request's `Origin`.** Reflection looks like an allow-list and is a wildcard
  that also permits credentials.
- Allowed headers enumerated and minimal: `Content-Type`, `Idempotency-Key`. **No
  `Authorization`** — its absence confirms no token scheme remains.
- **CORS must be registered with the security filter chain** (`http.cors(...)`), not only as MVC
  configuration. Registered only in MVC, the preflight `OPTIONS` is rejected by Spring Security
  before CORS handling runs — a classic and confusing failure.

**Security headers** — values and rationale in
[security-principles.md](../../shared/security-principles.md#security-headers). Spring Security
sets several by default; HSTS is enabled only outside local development, deliberately, so it does
not poison the browser's HSTS cache for every other project on `localhost`.

**`Cache-Control: no-store` on authenticated responses.** Spring Security's default cache headers
cover much of this; verify rather than assume.

---

## Payment data

The dummy payment form's input reaches this backend and must leave almost all of it behind.

**Stored:** `card_brand` and `card_last_four`. **Never stored, never logged, never returned:** the
PAN, the CVV, the expiry. Per
[data-model.md](../../shared/data-model.md#payments) the column list is itself the proof a breach
here could not yield a card.

**Concretely in this codebase:**

- **Request-body logging is disabled on `POST /reservations`.** In particular, do not enable
  `CommonsRequestLoggingFilter` with `setIncludePayload(true)` — it logs every body on every route,
  including this one. That filter is the specific Spring mechanism by which card data would reach a
  log file.
- The `PaymentRequest` record is read to derive brand and last four, then not passed further. It
  never enters a service signature beyond the payment mapper.
- **`toString()` is a hazard.** A `record`'s generated `toString()` includes every component, so
  logging a `CreateReservationRequest` at debug level prints the card number. Either override
  `toString()` on the payment record to redact, or never log the request object. **Overriding is
  preferred** — it makes the safe behavior the default rather than a rule to remember.
- Never echo the value in a validation message: "Please check the card number", not the number.

---

## Rate limiting

Applied to `POST /auth/login` and `POST /auth/register`: **10 attempts per 15 minutes, keyed on IP
and on the submitted email**, whichever trips first. `429` with `Retry-After`.

**A correct password inside the window still gets `429`** —
[AC-SE-09](../../shared/acceptance-criteria.md#ac-se-09--login-rate-limiting).

Implement as a filter ordered before authentication, with an in-process store (Bucket4j, or a
`ConcurrentHashMap` of counters — the latter is sufficient and avoids a dependency). **Stated
limitation:** in-process means a restart clears the window and the limit is not shared across
processes. Adequate here; the scale-up answer is a shared store, and there is no second process.

**Per-email keying is what makes this a limiter rather than a lockout** — reasoning in
[security-principles.md](../../shared/security-principles.md#account-lockout).

**`ForwardedHeaderFilter` must be configured deliberately if a proxy is ever in front.** Wrong,
every request appears to come from one IP and per-IP limiting collapses to a global one.

---

## Secrets

`@ConfigurationProperties` with validation, bound at startup and failing fast. Variables and
defaults in
[security-principles.md](../../shared/security-principles.md#secrets-and-configuration).

- **No secret in `application.properties` or `application.yml`.** Values come from the environment;
  the committed files carry placeholders and safe defaults only.
- **`application-local.properties` and `*-local.properties` are git-ignored** — the provision already
  made in this repo's `.gitignore`.
- **Never log the datasource URL or password**, including in a startup banner.
- **Do not enable `/actuator/env` or `/actuator/configprops`.** They expose resolved configuration
  including secrets. Only a health endpoint is exposed —
  [architecture-specification.md](./architecture-specification.md#deliberately-absent).
- Session TTLs are configuration but **must match the other backend's**, or users appear logged out
  by one and not the other.

---

## Deliberately absent

| Absent | Why |
|--------|-----|
| CSRF tokens | See the justification above — rests on no `GET` mutating state |
| MFA | The most significant missing capability, named in [security-principles.md](../../shared/security-principles.md#password-change-and-reset-posture) |
| Password reset by email | Needs transactional email, a stated stretch goal |
| Account lockout | Deliberate — see rate limiting |
| OAuth2 / OIDC / resource server | No external identity provider; sessions are the mechanism |
| Spring Session | The `sessions` table is the authority |
| Method security as the primary mechanism | URL rules are enumerable in one place |
| Actuator beyond health | Exposes configuration and internals |
| Dependency scanning | A declined cost, explained in [security-principles.md](../../shared/security-principles.md#out-of-scope-and-why-that-line-is-acceptable) |
| Encryption at rest, field-level encryption | Nothing stored warrants it |
| A systematic admin audit log | A named real gap in [security-principles.md](../../shared/security-principles.md#out-of-scope-and-why-that-line-is-acceptable) |
| A WAF, DDoS protection | No internet-facing edge |
