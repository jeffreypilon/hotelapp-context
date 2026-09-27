# Environment Setup Guide — Spring Boot

Clone to running, for `hotelapp-server-springboot`. Written to be followed literally.

> ## Read this first: this is the backend that migrates the database
>
> **Flyway runs here, on startup.** This backend is the sole DDL executor for the whole project —
> [versioning-strategy.md](../../shared/versioning-strategy.md#database-schema-migrations). Two
> consequences for setup:
>
> - **Starting this backend against an empty database Just Works.** It creates the schema. This is the
>   convenient backend to stand up first, and the reason Phase 6 builds it before the Node one.
> - **The migration SQL is not in this repo.** It lives in `hotelapp-context/shared/migrations/`, and
>   the build copies it in before running. A sibling checkout of `hotelapp-context` is therefore a
>   prerequisite.
>
> The Node backend has the opposite problem: it cannot migrate at all. That asymmetry is deliberate,
> and it is the price of one schema authority instead of two.

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| **JDK** — an LTS release | Pinned in the build file. Check with `java -version` |
| **Maven or Gradle wrapper** | Use `./mvnw` or `./gradlew` — never a system-installed build tool at a different version |
| **PostgreSQL 18.6** | **18 specifically** — the schema uses `uuidv7()`, a PostgreSQL 18 core function. 17 or earlier will not apply the migrations |
| **Docker** | For Testcontainers in the test suite |
| **A sibling checkout of `hotelapp-context`** | The migration SQL comes from there |
| Git | |

```
Documents/GitHub/hotelapp/
  hotelapp-context/            <- must be present
  hotelapp-server-springboot/  <- you are here
```

---

## Quick start

```bash
git clone https://github.com/jeffreypilon/hotelapp-server-springboot.git
cd hotelapp-server-springboot

createdb hotelapp

cp src/main/resources/application-local.properties.example \
   src/main/resources/application-local.properties
# edit the datasource credentials if yours differ

./mvnw spring-boot:run          # copies migrations, runs Flyway, starts on :8080
```

Startup applies the canonical migrations and logs each one. Confirm:

```bash
curl http://localhost:8080/api/v1/health
# {"status":"UP","database":"UP","version":"1.0.0","backend":"springboot"}
```

Then seed demo data:

```bash
./mvnw exec:java -Dexec.mainClass=com.hotelapp.seed.SeedRunner
# or: java -jar target/app.jar --seed
```

---

## How the migration SQL reaches Flyway

The canonical SQL is in another repository, which needs a mechanism. **The build copies it**, per
[architecture-specification.md](./architecture-specification.md#this-backend-owns-schema-application):

```xml
<!-- maven-resources-plugin, bound to generate-resources -->
<resource>
  <directory>${hotelapp.context.dir}/shared/migrations</directory>
  <targetPath>db/migration</targetPath>
</resource>
```

with `hotelapp.context.dir` defaulting to `../hotelapp-context` and overridable:

```bash
./mvnw spring-boot:run -Dhotelapp.context.dir=/path/to/hotelapp-context
```

> **Why copy rather than point Flyway at the directory.** `spring.flyway.locations=filesystem:../hotelapp-context/shared/migrations`
> would work locally and needs no copy step. It was rejected because it assumes a sibling checkout at
> runtime — which breaks in CI, breaks in a container without a bind mount, and breaks in a packaged
> jar. Copying at build time makes the migrations part of the artifact, so the jar is
> self-contained and runs anywhere. The copy is a build output, not committed duplication, so there is
> still exactly one authored copy. Alternatives considered: a git submodule (adds submodule mechanics
> to every clone) and committing a copy here (two authored copies, which defeats the decision).

**The copy step must not be skipped**, and if the context directory is missing the build should fail
loudly rather than start with no migrations — a backend that starts against an unmigrated database
fails later and less clearly.

---

## Configuration

`application.properties` holds non-secret defaults and is committed.
`application-local.properties` holds local overrides and is **git-ignored** — the provision already
made in this repo's `.gitignore`.

```properties
# ---- Datasource ----
spring.datasource.url=${DATABASE_URL:jdbc:postgresql://localhost:5432/hotelapp}
spring.datasource.username=${DATABASE_USER:postgres}
spring.datasource.password=${DATABASE_PASSWORD:postgres}
spring.datasource.hikari.maximum-pool-size=15

# ---- Schema: Flyway owns it, Hibernate validates ----
spring.flyway.enabled=true
spring.flyway.locations=classpath:db/migration
spring.jpa.hibernate.ddl-auto=validate

# ---- Jackson: both are load-bearing, not preferences ----
spring.jackson.deserialization.fail-on-unknown-properties=true
spring.jackson.default-property-inclusion=non_null

# ---- Problem Details: we produce our own ----
spring.mvc.problemdetails.enabled=false

# ---- Server ----
server.port=${PORT:8080}
server.shutdown=graceful

# ---- Auth ----
hotelapp.bcrypt-cost=${BCRYPT_COST:12}
hotelapp.session.idle-ttl-hours=${SESSION_IDLE_TTL_HOURS:8}
hotelapp.session.absolute-ttl-days=${SESSION_ABSOLUTE_TTL_DAYS:30}
hotelapp.session.slide-threshold-minutes=${SESSION_SLIDE_THRESHOLD_MINUTES:5}

# ---- CORS: never a wildcard ----
hotelapp.cors.allowed-origins=${CORS_ALLOWED_ORIGINS:http://localhost:5173,http://localhost:4200}

# ---- Rate limiting ----
hotelapp.rate-limit.attempts=${AUTH_RATE_LIMIT_ATTEMPTS:10}
hotelapp.rate-limit.window-minutes=${AUTH_RATE_LIMIT_WINDOW_MINUTES:15}

# ---- Logging ----
logging.level.com.hotelapp=${LOG_LEVEL:INFO}
logging.level.org.hibernate.orm.jdbc.bind=OFF
```

Four of these are worth calling out because the defaults are wrong for this contract:

| Property | Why it must be set |
|----------|--------------------|
| `fail-on-unknown-properties=true` | **Off by default.** Leaving it off violates the reject-unknown-fields rule and fails [AC-CC-02](../../shared/acceptance-criteria.md#ac-cc-02--unknown-request-fields-are-rejected) |
| `problemdetails.enabled=false` | On, Spring emits its own problem documents alongside ours — some errors then carry `code` and some do not |
| `ddl-auto=validate` | Anything else lets Hibernate alter the schema this repo is supposed to be validating against |
| `org.hibernate.orm.jdbc.bind=OFF` | It logs bound parameter values, which on the login query means a password |

> **Both frontend origins are listed.** `5173` is Vite (React), `4200` is the Angular CLI. Either
> frontend must be able to point at either backend by changing one value.

> **The session TTL values must match the Node backend's exactly.** A divergence produces users who
> appear logged out by one backend and not the other. [data-model.md](../../shared/data-model.md#sessions)
> holds the normative values.

**No secret in a committed file.** The `postgres/postgres` default is a local demo credential and still
reaches the application through a property or environment variable, not a hardcoded constant — the
*mechanism* is what matters.

---

## A two-role database setup, recommended

Because this backend needs DDL rights and the Node backend does not, the least-privilege improvement
is worth doing —
[security-implementation.md](./security-implementation.md#this-backend-runs-the-migrations-and-that-has-a-security-cost):

```properties
# Flyway migrates as a DDL-capable role, at startup only
spring.flyway.user=${FLYWAY_USER:hotelapp_migrator}
spring.flyway.password=${FLYWAY_PASSWORD}

# the application runs as a DML-only role thereafter
spring.datasource.username=${DATABASE_USER:hotelapp_app}
```

That bounds the elevated privilege to startup rather than holding it for the process's lifetime.
Optional for a local demo, and the reasoning is recorded so it is a choice rather than an oversight.

---

## Seeding

Loads demo data at the volumes in
[non-functional-requirements.md](../../shared/non-functional-requirements.md#scale): 3 properties,
~300 rooms, ~3,000 reservations spanning 18 months back and 6 months forward, ~200 guests, 8 admin
users.

**Seed to those volumes, not to the minimum.** A booking flow tested against three reservations proves
nothing about the availability query or the admin calendar.

**Seeding is not a migration.** The seven `amenities` rows come from a migration, because the codes are
a contract — [data-model.md](../../shared/data-model.md#amenities-and-room_type_amenities). Everything
else is the seed runner, which is re-runnable and truncates first.

---

## Working alongside the other backend

Legitimate and how interchangeability is demonstrated. Run this on `8080` and Node on `3000`,
**against the same database**. Because browsers scope cookies by host and not by port, a session
established against one is honored by the other —
[AC-SE-05](../../shared/acceptance-criteria.md#ac-se-05--a-session-works-interchangeably-against-both-backends).

```bash
curl -c /tmp/c.txt -X POST localhost:8080/api/v1/auth/login \
  -H 'Content-Type: application/json' -d '{"email":"…","password":"…"}'
curl -b /tmp/c.txt localhost:3000/api/v1/auth/me      # -> 200, same user
```

**Start this one first** on a fresh database, so the schema exists before the Node backend introspects
it. Doing it the other way round means the Node backend's `prisma db pull` finds nothing.

PostgreSQL's default `max_connections` is 100; two backends with pools of 10–20 are fine, but do not
raise both carelessly.

---

## Tests

```bash
./mvnw test                  # unit + slices, no container
./mvnw verify                # + @SpringBootTest with Testcontainers — what CI runs
./mvnw verify -Duser.timezone=Asia/Tokyo    # timezone-independence pass
```

**Testcontainers needs Docker.** `postgres:18.6` is pinned; H2 is not an option, because it has no
exclusion constraints and a suite on it would pass while the project's central guarantee was absent —
[testing-standards.md](./testing-standards.md).

**`ddl-auto` stays `validate` in the test profile too.** Setting `create-drop` for tests is the common
shortcut and defeats the point: `validate` failing in a test is how entity drift from the canonical
schema gets caught.

---

## Troubleshooting

| Symptom | Cause |
|---------|-------|
| Build fails: migrations directory not found | `hotelapp-context` is not a sibling checkout, or `hotelapp.context.dir` is wrong |
| `function uuidv7() does not exist` | PostgreSQL is not 18.x |
| `SchemaManagementException` at startup | Entity mappings disagree with the migrated schema. **This is the check working** — fix the entities, do not relax `ddl-auto` |
| Flyway: "checksum mismatch" | A merged migration was edited. Migrations are immutable — [versioning-strategy.md](../../shared/versioning-strategy.md#migration-authoring-rules) |
| `401`/`403` come back without `code` or `traceId` | `AuthenticationEntryPoint` / `AccessDeniedHandler` are not customized — [security-implementation.md](./security-implementation.md#spring-security-configuration) |
| Unknown fields in a request body are silently accepted | `fail-on-unknown-properties` is not set |
| Preflight `OPTIONS` rejected | CORS registered in MVC only, not on the security filter chain |
| Money serializes as a JSON number | `BigDecimal` needs `ToStringSerializer` — [architecture-specification.md](./architecture-specification.md#dtos) |
| Sessions expire sooner than in Node | The `SESSION_*` values differ between the two backends |
| `LazyInitializationException` | An entity escaped the service layer |
| `UnexpectedRollbackException` on booking | The allocation retry has been moved inside the transaction — [error-handling.md](./error-handling.md#transactions) |

---

## What is not part of setup

| Not needed | Why |
|------------|-----|
| Writing migration SQL here | It is authored in `hotelapp-context` |
| `ddl-auto=update` or `create-drop`, ever | Flyway is the sole DDL executor |
| A global Maven or Gradle install | Use the wrapper |
| Actuator configuration | Only a custom health endpoint is exposed |
| A Docker build for development | Native is the inner loop; Compose is for verification and for other people |
