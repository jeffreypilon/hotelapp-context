# Testing Standards — AI Service

How `hotelapp-ai-service` is tested, what each layer proves, and — stated as plainly as possible —
**what these suites do not cover.**

The project-wide approach is in both backends' `testing-standards.md` and the criteria themselves
in [acceptance-criteria.md](../../shared/acceptance-criteria.md). This document covers what is
different here, which is more than it first appears.

---

## 1. The asymmetry, stated first

For the four existing repositories, a green test suite is sufficient evidence that a change is
safe. **Here it is not.**

A model upgrade, an embedding change, a chunking tweak or a prompt edit can leave every test
passing while answer quality falls off a cliff. Nothing in pytest can see that. So this stack has
two independent gates, and **both** must hold:

| Gate | Catches | Runs |
|------|---------|------|
| **Test suite** (pytest) | Logic, wiring, SQL, auth, protocol, regressions in anything deterministic | Every commit |
| **Evaluation suite** (RAGAS over a golden set) | Retrieval and answer quality | Every commit touching retrieval, prompts, models, or the corpus |

Treating the test suite as sufficient is the single most likely way this service ships a
regression. [dependency-policy.md](./dependency-policy.md#maintenance) makes the evaluation suite
the upgrade gate for exactly this reason.

---

## 2. Far more is deterministic than people assume

Non-determinism is confined to **generation**. Everything else is exactly assertable, and is
tested as strictly as any backend:

| Deterministic, asserted exactly | Where |
|---------------------------------|-------|
| RRF fusion, including ties, one-sided hits, empty inputs | `domain/fusion.py` |
| Chunk boundaries and heading-path propagation — the same document must chunk identically every time | `domain/chunking.py` |
| Citation rendering | `domain/citations.py` |
| Retrieved chunk IDs for a given query, against a fixed corpus and fixed embeddings | `repositories/chunks.py` |
| Session forwarding, and the absence of any credential-adding path | `gateways/hotelapp.py` |
| Tool schemas, allow-listing, pre-dispatch validation | `transport/mcp/tools.py` |
| OAuth: PKCE, audience binding, rejection behaviour | `transport/oauth/` |
| SSE framing, event ordering, terminal-event guarantees | `transport/rest/assistant.py` |
| Problem Details mapping, including backend pass-through | `transport/rest/problem.py` |

**`gateways/hotelapp.py` is the most security-critical module in the service** and is tested
accordingly: that the caller's cookie is forwarded unchanged, that no code path adds credentials,
and that a request without a session cannot reach an authenticated endpoint.

---

## 3. Integration tests use a real database, always

Same rule as both backends, same reasoning, sharper stakes.

- **Testcontainers PostgreSQL with the real `vector` extension** — the `pgvector/pgvector:pg18`
  image, not stock Postgres, which ships no third-party extensions.
- **Flyway applies the canonical migrations**, plus `migrations-ai/` via its own invocation, exactly as in the
  Node repo's integration setup. The service never creates its own schema, in tests or anywhere.
- **Retrieval is never mocked** —
  [dependency-policy.md](./dependency-policy.md#why-mocking-the-retrieval-path-is-prohibited-specifically).
  Correctness lives in pgvector's distance operator and Postgres full-text ranking; a mock asserts
  the test author's belief about those instead.
- **Real embeddings, computed once and cached as a fixture.** Embedding the test corpus on every
  run is slow and costs money; embedding it with a *different* model than production would make
  the retrieval assertions meaningless.
- **The LLM provider may be stubbed** in integration tests. Provider output is non-deterministic
  and asserting on it is the evaluation suite's job, not pytest's.

### The `EXPLAIN` test

Direct analogue of the existing Spring Boot test that proves the availability query uses
`reservations_no_overlap_excl`: an integration test seeds enough chunks to make a plan choice
meaningful, runs `ANALYZE`, and asserts the hybrid query's plan **uses the HNSW index** rather than
a sequential scan.

It calls the same query method the production path calls, so the test cannot drift from what
actually runs — the property that made the backend version of this test worth having.

---

## 4. Two tests with no backend equivalent

### Policy consistency

**The corpus must agree with what the backends enforce.** A document stating a 72-hour
cancellation window while the system enforces 48 would produce a fluent, well-retrieved, perfectly
*faithful* answer that is wrong about the running application — and every standard RAG metric
would score it well, because faithfulness measures agreement with the retrieved document, not with
the system.

So a test asks the assistant the cancellation question and asserts the stated rule matches what
`POST /reservations/{id}/cancel` actually does at the boundary. The reasoning is in
[ai-enablement-overview.md §8](../../shared/ai-enablement-overview.md#8-the-document-corpus).

This is the AI service's version of the drift prevention the whole repository exists for: the
corpus is now one of the parallel implementations.

### Additive-ness

**Every existing acceptance criterion must still pass with this service stopped.** Booking,
search, reservation management and account screens never depended on it, and a test asserts that
they still do not. This is what makes the availability row in
[§10](../../shared/ai-enablement-overview.md#10-non-functional-targets) a guarantee rather than an
intention.

---

## 5. The evaluation suite

- **`eval/golden_set.yaml` is committed** — 50–100 question/expected-answer pairs derived from the
  corpus and the acceptance criteria. It is built **before** retrieval parameters are tuned, so
  chunk size, `k`, and fusion weights are chosen against evidence rather than impression.
- **RAGAS metrics are reported separately for retrieval and generation**, because they fail
  independently and can mask each other: context precision and recall for retrieval, faithfulness
  and answer relevancy for generation.
- **Floors are committed values.** A change that drops faithfulness or context recall below its
  floor fails CI exactly as a failing test does. Moving a floor requires stating the before and
  after numbers in the commit body
  ([coding-standards.md](./coding-standards.md#commits)) — otherwise thresholds drift downward one
  justified exception at a time.
- **Runs are persisted to `ai_eval_runs`**, so quality over time is a queryable history rather
  than a number someone remembers.

---

## 6. What these suites do not cover

Stated plainly, in the house tradition of naming the gap rather than implying coverage.

| Not covered | Consequence |
|-------------|-------------|
| **Whether an answer is *good*** — only whether it is faithful, relevant, and well-retrieved | A dull, hedging, technically-faithful answer passes every gate. Human review is the only check on tone and usefulness, and it does not run in CI |
| **Adversarial prompt injection** | The suite tests the *blast radius* (§1 of [security-implementation.md](./security-implementation.md)), not whether an injection succeeds. No published defence survives adaptive attack, so the security model does not depend on one — but neither does the test suite prove the model resisted |
| **Provider behaviour changes** | A provider silently updating a model behind a stable name can change outputs with no change in this repository. The evaluation suite detects it *after* the fact, on the next run, not before |
| **Corpus completeness** | Nothing asserts the corpus covers every question a guest might ask. The golden set tests the questions someone thought of |
| **End-to-end browser behaviour of AI features** | Same acknowledged gap as the rest of the project — [devops-pipeline-overview.md](../../shared/devops-pipeline-overview.md#deliberately-absent) |
| **Cost under adversarial load** | Rate limits and ceilings are tested; a sustained denial-of-wallet attempt is not simulated |
| **Real MCP client compatibility** | Protocol conformance is tested against the spec, not against every client's interpretation of it. Claude Desktop is verified by hand |

The first row is the important one. **Every automated gate here can pass while the assistant is
unhelpful**, and no amount of additional metrics changes that. The golden set is the closest thing
to a defence, and it is only as good as the questions in it.
