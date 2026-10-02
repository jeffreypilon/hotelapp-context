# Coding Standards — AI Service (Python)

Conventions for `hotelapp-ai-service`: language level, typing, async discipline, how values cross
the boundary into JSON, and the rules that are specific to writing code around a language model.

Project-wide naming is fixed in
[glossary-of-conventions.md](../../shared/glossary-of-conventions.md) and is not restated here —
only what it means in Python.

---

## Language level and tooling

- **Python 3.13**, pinned in `pyproject.toml` and matched by the Docker base image.
- **Type hints are mandatory** on every function signature, including tests. `mypy` runs in
  strict mode and **fails CI**. Untyped code in a service that marshals data between four
  external systems is how a `str` that was supposed to be a `Decimal` reaches production.
- **`ruff` for lint and format**, one tool, failing CI. No `black`, no `isort`, no `flake8`.
- `from __future__ import annotations` is unnecessary at 3.13 and should not be added.

---

## Async is the default, and blocking is a bug

Every I/O path in this service is async: HTTP to the backends, SQL via `psycopg`'s async
connection pool, and model calls. The service is I/O-bound almost everywhere, which is the whole
reason FastAPI was chosen.

- **A `def` route handler that performs I/O is a defect.** Use `async def`.
- **Never call a synchronous HTTP client.** `requests` is banned outright in
  [dependency-policy.md](./dependency-policy.md#explicitly-not-allowed) for this reason: one
  blocking call stalls the event loop for every concurrent request, and the symptom appears under
  load as unexplained latency rather than as an error.
- **CPU-bound work goes through `asyncio.to_thread`.** The cross-encoder reranker is the one
  genuinely CPU-bound step in the request path; running it inline blocks the loop for the duration
  of the rerank.
- **No `time.sleep`.** `asyncio.sleep`, always.

---

## Crossing the boundary: Python ↔ JSON

[glossary-of-conventions.md](../../shared/glossary-of-conventions.md) fixes `snake_case` in SQL,
`camelCase` in JSON, and `SCREAMING_SNAKE_CASE` enum values crossing every layer unchanged. Python
is `snake_case` internally, so the conversion happens in exactly one place:

- **Every request and response model is a Pydantic model** with a camelCase alias generator.
  Hand-written `dict` payloads at a route boundary are prohibited — they bypass both validation
  and the casing rule, and they drift.
- **Enum values are never translated, lowercased, or prettified.** `CONFERENCE_ROOM` stays
  `CONFERENCE_ROOM` in Python, in JSON, in a prompt, and in a tool schema. Display formatting is
  the frontends' job, and they already own it.
- **Unknown fields are rejected** on inbound models (`model_config = ConfigDict(extra="forbid")`),
  matching Spring Boot's `fail-on-unknown-properties=true` and Node's zod schemas.

### Money is a string, and parsing it is a defect

The project rule — `numeric(10,2)` → decimal **string** in JSON, never a float, at any layer —
applies here with a sharper edge, because Python makes the mistake easy and silent.

- Money arriving from a backend is a `str`. **It stays a `str`.** This service displays and
  relays prices; it does not compute them, because computing them is what the backends already do
  under test.
- `float("249.00")` anywhere in this repo is a defect. If arithmetic ever becomes genuinely
  necessary, it is `decimal.Decimal`, never `float`, and it needs a documented reason.
- **A price must never be interpolated into a prompt as a number.** Ask a model to do arithmetic
  on a nightly rate and it will sometimes produce a plausible wrong total; the totals come from
  `GET /availability`, already computed.

### Dates carry their type in the name

`_date` is a calendar date, `_at` is an instant. `check_in_date` is a `datetime.date`;
`cancelled_at` is an aware `datetime`. A naive `datetime` crossing a module boundary is a defect —
the cancellation-deadline rules are timezone-sensitive and already caused real bugs in two other
stacks in this project.

---

## Writing code around a language model

The rules in this section exist because the usual ones do not cover a component whose output is
probabilistic and whose input may be hostile.

### Prompts are files

Prompts live in `prompts/` as `.md` files and are loaded by name. No multi-line string literals
in service modules, no prompt assembled by concatenation across functions. A prompt is behaviour,
so it belongs where behaviour is reviewed and attributed.

### Untrusted content is delimited and labelled, never interpolated into instructions

Retrieved chunks, guest questions, and anything arriving from an MCP client are **data**. They are
inserted into clearly fenced, labelled regions of the prompt — never into the instruction section,
and never by f-string into a sentence that reads as an instruction.

```python
# WRONG — the chunk's text becomes part of the instruction
prompt = f"Answer using this policy: {chunk.text}"

# RIGHT — the chunk is delimited, labelled, and positioned as data
prompt = render("answer.md", documents=[chunk])   # template fences each document
```

This does not *solve* prompt injection — nothing published does, and
[ai-enablement-overview.md §5](../../shared/ai-enablement-overview.md#5-the-authorization-model-and-why-it-is-the-interesting-part)
is explicit that the security model does not depend on it. It raises the cost of the easy attacks,
and the authorization model contains the rest.

### Structured output over parsing prose

Where the model's answer feeds code — F2's parameter extraction, the retrieval grading step —
use the provider's structured-output mode with a Pydantic schema. **Never** regex a model's prose
for a value. A parser that works on nine phrasings and fails on the tenth is worse than one that
fails loudly.

### Every model call is bounded

Explicit `max_tokens`, explicit timeout, explicit retry policy. A call with no ceiling is a cost
incident waiting for an unusual input, and the per-request cost figure in
[§10](../../shared/ai-enablement-overview.md#10-non-functional-targets) is only meaningful if the
ceiling exists.

### Non-determinism stays out of `domain/`

`domain/` is pure. Anything model-touched is, by definition, not. Retrieval fusion, chunk
boundaries and citation rendering stay deterministic precisely so that *something* in this service
can be asserted exactly.

---

## Error handling, briefly

Full mapping is in [error-handling.md](./error-handling.md). The conventions:

- **No bare `except:`**, and no `except Exception` that swallows. Catch what you can act on.
- **A failed model call is a handled condition**, not a 500. Provider timeouts, rate limits and
  content filters each map to a known problem code.
- **Never let a provider's raw error text reach a client.** It can echo prompt content, which may
  include retrieved document text.

---

## Forbidden

| Forbidden | Why |
|-----------|-----|
| `float` for money | Above |
| `requests`, any sync HTTP | Blocks the event loop |
| Prompt text in service modules | Belongs in `prompts/` |
| Regex over model prose to extract a value | Use structured output |
| A model call outside `services/` | Layering — [module-registry.md](./module-registry.md) |
| SQL outside `repositories/` | Same |
| An HTTP call to a backend outside `gateways/` | Same |
| `print()` | `structlog` — [logging-observability.md](./logging-observability.md) |
| Logging a prompt, a completion, or a retrieved chunk at INFO | May contain guest data — same document |
| `# type: ignore` without a reason comment | Strict mypy is the point |

---

## Commits

Conventional Commits, as everywhere in this project. Two additions specific to this stack:

- **A prompt change is `feat:` or `fix:`, never `chore:`.** It changes behaviour.
- **A commit that moves a RAGAS floor states the before and after numbers in the body.** That is
  the only durable record of why a threshold is where it is.
