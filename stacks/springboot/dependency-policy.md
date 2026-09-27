# Dependency Policy — Spring Boot

What may be added to `hotelapp-server-springboot`, what may not, and how to decide.

The governing rule is from
[security-principles.md](../../shared/security-principles.md#dependencies): **prefer the framework's own
primitives over a small package.** Every dependency is added attack surface and added maintenance, and a
backend's dependency tree is the part of this project with the most realistic supply-chain exposure — it
runs with database credentials, and in this backend's case with **DDL rights**.

Spring Boot makes the rule easy to follow, because the starters bring nearly everything: HTTP,
validation, JPA, security, and migrations. The discipline is mostly about *not* adding things.

The "deliberately absent" table in
[architecture-specification.md](./architecture-specification.md#deliberately-absent) already settled
several cases; this document does not reopen them.

---

## The approved set

Versions managed by the Spring Boot parent BOM where possible, with the lockfile or resolved-version
report committed, and the build wrapper pinned.

| Dependency | Role | Why it earns its place |
|------------|------|------------------------|
| `spring-boot-starter-web` | HTTP, Jackson, validation | Includes `ProblemDetail`, which is why RFC 9457 was chosen |
| `spring-boot-starter-data-jpa` | Data access | Decided at system level |
| `spring-boot-starter-security` | Filter chain, `BCryptPasswordEncoder` | The encoder **must** produce `$2b$` strings so Node's `bcrypt` verifies them — the cross-stack requirement that chose bcrypt over Argon2id |
| `spring-boot-starter-validation` | Bean Validation | |
| `flyway-core`, `flyway-database-postgresql` | **Schema migration — this backend is the sole executor** | [versioning-strategy.md](../../shared/versioning-strategy.md#database-schema-migrations) |
| `postgresql` (JDBC driver) | Database | **The reason `23P01` detection is reliable here**: it exposes SQLSTATE as structured data via `SQLException.getSQLState()` |
| `logstash-logback-encoder` | JSON logging | Logback is already present; this makes the output structured, and the MDC carries `traceId` automatically |
| `springdoc-openapi-starter-webmvc-ui` | OpenAPI generation | Mature, derives the document from annotations that already exist |
| `junit-jupiter`, `assertj`, `spring-boot-starter-test` | Testing | |
| `testcontainers`, `testcontainers:postgresql`, `spring-boot-testcontainers` | Testing against real PostgreSQL | **Not optional** — see below |
| `spotless-maven-plugin` (or Gradle equivalent) | Format check | Fails CI |

**`java.time`, `java.security.SecureRandom`, `MessageDigest`, `HexFormat`, and `Base64` are all
standard library** — session tokens, token hashing, confirmation numbers, and every date computation
need no dependency. `SecureRandom.getInstanceStrong()` is the session-token generator; reaching for a
UUID or random-string library would add a dependency to do what the JDK already does.

**`Clock` is standard library** and is the injected time source the cancellation criteria require —
[architecture-specification.md](./architecture-specification.md#package-layout). No test-clock library.

> **Testcontainers is a hard requirement, not a preference.** H2 has no exclusion constraints, no
> `daterange`, no `&&` operator, and no `uuidv7()`. An H2-backed suite would pass while the project's
> central guarantee was **entirely absent** — the worst possible test outcome. Reasoning in
> [testing-standards.md](./testing-standards.md).

---

## Explicitly not allowed

| Not allowed | Instead | Decided in |
|-------------|---------|-----------|
| **`ddl-auto` other than `validate`** (not a dependency, but the same class of decision) | Flyway applies DDL, Hibernate validates | [versioning-strategy.md](../../shared/versioning-strategy.md#database-schema-migrations) |
| Liquibase | Flyway. The "or Liquibase" phrasing was removed from the shared docs deliberately — there is no choice to make | same |
| A JWT library — `jjwt`, `java-jwt`, `nimbus-jose-jwt` | **There are no tokens** | [security-implementation.md](./security-implementation.md#what-must-never-appear-in-this-codebase) |
| `spring-boot-starter-oauth2-resource-server` | Same | same |
| Spring Session | The `sessions` table is the authority | [architecture-specification.md](./architecture-specification.md#deliberately-absent) |
| Lombok | `record` covers DTOs; entity `equals`/`hashCode` must be id-only, which Lombok's generated versions get wrong. One less annotation processor in a project meant to be read | [coding-standards.md](./coding-standards.md#forbidden) |
| MapStruct, ModelMapper, Dozer | Hand-written mappers, because the mapping is where `BigDecimal`-as-string is enforced and a convention-based mapper gets that wrong silently | [architecture-specification.md](./architecture-specification.md#dtos) |
| Spring Data REST, `@RepositoryRestResource` | The API shape is fixed by the contract | same |
| Spring Cloud, Eureka, Config Server | One service |
| WebFlux / reactive | Blocking request/response, with no concurrency target to justify reactive |
| A second JSON library — Gson, JSON-B | Jackson, once |
| Joda-Time, `commons-lang3` `DateUtils` | `java.time` |
| A money library — Joda-Money, JSR-354 / Moneta | `BigDecimal` internally, decimal **string** on the wire |
| `commons-lang3`, Guava | The JDK covers what is needed here. Both are large and mostly unused |
| `spring-boot-starter-actuator` | A custom health controller; Actuator exposes `/env` and `/configprops` including secrets | [logging-observability.md](./logging-observability.md#health) |
| Micrometer, Prometheus registries | No scraper | same |
| APM or error-reporting agents — Sentry, Datadog, New Relic, Elastic APM | Nowhere to send to, and each is a Java agent in a process with DDL rights | same |
| A caching provider — Caffeine, Redis, Hazelcast | Only the session lookup would benefit; named as the scale-up path in [api-contracts.md](../../shared/api-contracts.md#authentication) |
| Quartz, a job scheduler | `@Scheduled` covers the one periodic task: session cleanup |
| Mockito for repositories in criterion tests | The database is the component under test — see below |
| `@EnableJpaAuditing`, `@CreatedDate` | `created_at` and `updated_at` have database defaults | [coding-standards.md](./coding-standards.md#forbidden) |
| An H2 or HSQLDB test dependency | **Would make the suite lie** — see the Testcontainers note above |

### Why mocking the repository layer is prohibited in criterion tests

Mockito is present via `spring-boot-starter-test` and is fine for controller slices. It is prohibited in
the acceptance-criteria tests, and the reason is the same class of problem the Node backend has with
mocking Prisma:

several criteria are **about database behavior** — the exclusion constraint firing, a transaction rolling
back, exactly one row existing. A mocked repository asserts that *the mock behaves as configured*, which
is true regardless of whether the constraint exists. `@MockBean` on a repository in an AC test removes
the component under test while leaving the test green.

The corollary is worth stating: **`ddl-auto=validate` plus a real container is this backend's equivalent
of the Node backend's `schema.prisma` drift check** — the mechanism by which a test suite notices that
the canonical schema moved. Replacing the container with H2 or a mock would remove it.

---

## Adding something new

Five questions, in order. A "no" at any point is the answer.

1. **Does Spring Boot, the JDK, or Hibernate already do this?** The starters, `java.time`,
   `java.security`, `HexFormat`, `Clock`, `@Scheduled`, `ProblemDetail`. The answer is yes more often
   than in most ecosystems, which is the point of choosing a batteries-included framework.
2. **Is it already prohibited above?** Then it needs a documented decision reversal, not a pull request.
3. **Is it managed by the Spring Boot BOM?** If yes, take the BOM's version rather than pinning your
   own — an unmanaged transitive version conflict in a Spring application is a long afternoon.
4. **Does it add an annotation processor or a Java agent?** Both are build-time or runtime code with
   broad reach. Lombok was declined partly on this basis; an agent in a process with DDL rights needs a
   strong argument.
5. **Could fifty lines replace it?** If yes, write the fifty lines. They will be understood, tested, and
   free of a supply-chain relationship to the most privileged process in the project.

Each addition is a separate commit with the reason in the message, per
[glossary-of-conventions.md](../../shared/glossary-of-conventions.md#commit-message-convention).

---

## Maintenance

- **The Spring Boot parent BOM manages versions.** Do not pin a managed dependency's version
  independently; upgrade the parent instead.
- **`spring-boot-starter-*` move together** with the parent. A mismatched `spring-core` and
  `spring-web` fails in ways that look like application bugs.
- **The JDBC driver upgrade is the one to run the full suite on.** `23P01` detection walks the Hibernate
  wrapping chain to reach `SQLException.getSQLState()` —
  [error-handling.md](./error-handling.md#jpa--sql--problem-details) — and a driver or Hibernate upgrade
  that changes the nesting breaks it silently. That makes
  [AC-OB-01](../../shared/acceptance-criteria.md#ac-ob-01--two-concurrent-bookings-for-the-last-room-exactly-one-wins)
  a required gate on those specific upgrades, not just on code changes.
- **A Flyway upgrade is a schema-authority upgrade.** This backend applies DDL for the whole project, so
  a Flyway major version bump deserves more care than an ordinary dependency — verify the migration
  history is still readable and the checksums still match before merging.
- **Resolved versions are committed** (a lockfile, or `mvn dependency:tree` output under review), so a
  reviewer gets the build the author had.
- **No automated dependency updates** — no Dependabot, no Renovate. A declined cost, explained in
  [security-principles.md](../../shared/security-principles.md#out-of-scope-and-why-that-line-is-acceptable).
- **Remove what stops being used.** An unused dependency in this process is the most privileged liability
  in the project.
