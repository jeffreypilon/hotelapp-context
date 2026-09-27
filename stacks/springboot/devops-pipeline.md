# DevOps Pipeline — Spring Boot

CI for `hotelapp-server-springboot`. The cross-repo shape — platform, triggers, the absence of any
deployment step, and the two cross-repo checks — is settled in
[devops-pipeline-overview.md](../../shared/devops-pipeline-overview.md) and is **not** re-litigated
here.

**No deployment step. No release. No published artifact.** This job answers one question per push:
does this still build, lint clean, and pass its tests against a real PostgreSQL?

---

## The job

One workflow, `.github/workflows/ci.yml`, on push to `main` and on pull requests targeting `main`.

> ## This repo also needs the context checkout — but for a different reason
>
> Both backend pipelines check out `hotelapp-context`, and it is worth being precise that they do so
> for opposite reasons:
>
> | Repo | Why it checks out the context repo |
> |------|-----------------------------------|
> | **Node** | It **cannot** migrate. Flyway must be invoked separately, as an external CLI, before any test runs |
> | **This repo** | The build **copies** the migrations into the artifact, because Flyway runs here as part of startup |
>
> So the checkout is a *build input* here and a *test prerequisite* there. Same YAML step, different
> role — and this repo's tests then use the same Flyway mechanism as production, which the Node repo's
> cannot.
>
> ```yaml
> - uses: actions/checkout@<pinned>
> - uses: actions/checkout@<pinned>
>   with:
>     repository: jeffreypilon/hotelapp-context
>     path: hotelapp-context
>     ref: main
> ```
>
> **The build must fail loudly if that directory is missing**, rather than producing an artifact with no
> migrations. A jar that starts against an unmigrated database fails later and less clearly.
>
> Pinning to `main` means a merged schema change immediately affects this pipeline. Intended — it is
> how drift becomes visible — and a real coupling.

| Step | Command | Fails the build? |
|------|---------|------------------|
| Checkout this repo | `actions/checkout@<pinned>` | — |
| **Checkout `hotelapp-context`** | `actions/checkout@<pinned>` | Yes |
| JDK setup + build cache | `actions/setup-java@<pinned>`, `cache: maven` | — |
| Copy migrations into resources | build plugin, `generate-resources` | **Yes** |
| Compile | `./mvnw -B compile` | **Yes** |
| Format / static analysis | `./mvnw spotless:check` | **Yes** |
| Unit + slice tests | `./mvnw -B test` | **Yes** |
| Integration tests | `./mvnw -B verify` | **Yes** |
| Package | `./mvnw -B package -DskipTests` | **Yes** |
| Publish the OpenAPI document | Upload `openapi.json` as an artifact | No |

`setup-java` with `cache: maven` (or `gradle`) matters more here than npm caching does in the other
repo — a cold Maven repository dominates the runtime.

Actions pinned to a specific version, never a floating tag, for the same reproducibility reason Docker
images are pinned in
[versioning-strategy.md](../../shared/versioning-strategy.md#versions-of-the-platform-itself).

Target runtime: **under 5 minutes**, the cross-repo budget. Expect this job to be the slower of the
two backends — a JVM build and a Spring context per test class cost more than a TypeScript compile. A
shared `static` Testcontainers instance across the test hierarchy is the single biggest saving
available.

---

## The database in CI

**Testcontainers, not a service container** — the opposite choice from the Node repo, and deliberate.

`@ServiceConnection` wires the datasource with no property plumbing, and the test base class already
depends on it
([testing-standards.md](./testing-standards.md#flyway-in-tests-is-the-same-mechanism-as-production)).
Rewiring the suite to accept an external service container would mean maintaining two datasource paths
for no benefit, since the JVM runner has Docker available anyway.

```java
@Container @ServiceConnection
static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:18.6");
```

**`postgres:18.6`, pinned.** Not `latest`, not 17 — the schema uses `uuidv7()`, a PostgreSQL 18 core
function.

**No substitute is acceptable.** H2 has no exclusion constraints, so an H2-backed run would pass while
the project's central guarantee was entirely absent.

**`ddl-auto` stays `validate` in the CI profile.** Setting `create-drop` for CI is the common shortcut
and defeats a check this repo gets for free: `validate` failing is how entity drift from the canonical
schema is caught. **That failure is a feature of this pipeline**, and it is the check the Node repo has
to reconstruct by diffing `schema.prisma` —
[stacks/nodejs/devops-pipeline.md](../nodejs/devops-pipeline.md#schemaprisma-drift--a-check-this-repo-needs-and-the-other-does-not).

---

## Timezone pass

```yaml
- run: ./mvnw -B verify -Duser.timezone=Asia/Tokyo
```

A second run under a non-UTC process timezone. Cheap, and the only thing that catches a
process-timezone dependency in the cancellation-deadline arithmetic —
[AC-CX-04](../../shared/acceptance-criteria.md#ac-cx-04--deadline-respects-the-propertys-timezone-not-the-servers).

The JVM makes this both easier and more necessary than in Node: `-Duser.timezone` is a clean switch,
and `java.time` will happily use the default zone if a `ZoneId` is ever omitted.

---

## This repo's part in the cross-repo checks

**The OpenAPI diff** is the primary defense against the two backends drifting —
[devops-pipeline-overview.md](../../shared/devops-pipeline-overview.md#1-the-openapi-diff). This repo
**publishes `openapi.json` as a build artifact** for the comparison job in `hotelapp-context`.

Generating it requires the application context, so the step runs against a started app (or
`springdoc`'s Maven plugin) rather than reading source. Worth knowing because it makes this step
slower than the Node repo's equivalent, where the document is a hand-maintained module.

**The generator asymmetry is the reason the comparison must normalize.** `springdoc` derives
`operationId`s, schema names, and `x-*` extensions its own way; the Node document is hand-written to
the contract. A raw text diff would fail on every run and be switched off within a week — so the
comparison job sorts keys and drops descriptions, examples, and extensions before comparing. Stated in
[architecture-specification.md](./architecture-specification.md#openapi) and in the shared overview.

A useful local check: assert `BigDecimal` fields are documented as `type: string`, since `springdoc`
will otherwise describe them as numbers and the document would then contradict the contract even
while the runtime serialization is correct.

**The Docker Compose smoke test** lives in `hotelapp-context` and is where
[AC-SE-05](../../shared/acceptance-criteria.md#ac-se-05--a-session-works-interchangeably-against-both-backends)
runs for real. This repo's obligation is a **Dockerfile that can run with Flyway disabled**, because
the Compose topology runs migrations as a separate service before either backend starts:

```
spring.flyway.enabled=${FLYWAY_ENABLED:true}
```

Default `true` so local and CI behavior are unchanged; set `false` in Compose so two components do not
race to migrate the same database at startup. **That race is the exact failure the single-executor rule
prevents everywhere else**, and it would be embarrassing to reintroduce it in the one topology where
both backends run at once.

---

## What this job does NOT do

| Absent | Why |
|--------|-----|
| Deploy anything | There is no environment |
| Publish a Docker image or a Maven artifact | Nothing consumes either |
| Author migration SQL | It is authored in `hotelapp-context` |
| Run the other backend | Cross-backend behavior is the Compose smoke test's job |
| End-to-end browser tests | The acknowledged gap — [devops-pipeline-overview.md](../../shared/devops-pipeline-overview.md#deliberately-absent) |
| Coverage threshold gate | Reported, not enforced — [testing-standards.md](./testing-standards.md#5-what-is-not-tested-here) |
| Dependency scanning | A declined cost, explained in [security-principles.md](../../shared/security-principles.md#out-of-scope-and-why-that-line-is-acceptable) |
| Load testing | No throughput target exists to regress against |
| Release tagging, version bumping | Nothing consumes this as a versioned artifact |

---

## Secrets

**None.** Testcontainers generates its own credentials. The `hotelapp-context` checkout uses the
default token, which suffices for a repo on the same account.

**No build-time secret is needed or possible**: all configuration is read at runtime from the
environment, so there is nothing to bake into the jar.

---

## Local equivalence

```bash
./mvnw -B verify          # what CI runs, minus the second checkout
```

CI running something a developer cannot reproduce locally is how a red build becomes someone else's
problem. The one difference is the migrations source: locally `hotelapp-context` is a sibling
directory, in CI it is a checkout. That is why the copy step's source path is a configurable property
rather than a hard-coded `../` —
[environment-setup-guide.md](./environment-setup-guide.md#how-the-migration-sql-reaches-flyway).
