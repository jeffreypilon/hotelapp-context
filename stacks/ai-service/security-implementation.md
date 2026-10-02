# Security Implementation — AI Service

Where each control from
[security-principles.md](../../shared/security-principles.md) sits in `hotelapp-ai-service`, and
what must never reappear.

The threat model, password policy, CORS posture, secrets rules and logging rules are owned by that
document. This one covers the three things this component adds to the attack surface: a model that
reads attacker-influenced text, a second protocol with its own authorization, and an outbound
dependency that costs money per request.

---

## 1. The authorization model, implemented

The design is in
[ai-enablement-overview.md §5](../../shared/ai-enablement-overview.md#5-the-authorization-model-and-why-it-is-the-interesting-part).
What it means in code:

- **This service holds no credentials of its own.** There is no service account, no elevated
  database role for business data, and no API key that grants access to another user's records.
  `gateways/hotelapp.py` has **no code path that adds authentication** — it forwards what arrived
  or it calls a public endpoint.
- **The session cookie is forwarded verbatim** and never parsed, stored, logged, or cached. It is
  `HttpOnly`, so this service reads it only as an opaque header value in transit.
- **Authorization decisions are made by the backends**, which already enforce them under 44
  acceptance criteria. This service re-implements none of them. A guest asking the assistant about
  "my reservations" gets exactly what `GET /reservations` returns for that session — no more, and
  not by this service's judgement.

> **The security property, stated so it can be tested:** a perfectly successful prompt injection
> yields no more access than the asking guest already has. `tests/integration` asserts this
> directly — a question crafted to request another guest's reservation returns that guest's own
> data or a `403`, never someone else's.

### Database access

The service connects to PostgreSQL with a role scoped to `ai_*` tables only. It has **no grant** on
`reservations`, `users`, `properties`, or any other business table. The REST-only rule is therefore
enforced by the database as well as by convention — a layering mistake fails at the connection, not
in review.

---

## 2. MCP authorization

### stdio: safe by construction, not by configuration

The stdio transport registers **only the public tool surface** — catalogue, availability, and
prepared booking links. It has no authenticated user and therefore no way to reach guest data.

> **No credential is ever placed on disk to "enable" stdio.** A config-file token or a cached
> session would be exactly the standing secret
> [security-principles.md](../../shared/security-principles.md#secrets-and-configuration)
> prohibits, and it would turn a local convenience into a persistent credential on a developer's
> laptop. The surface is restricted instead.

### HTTP: OAuth 2.1 as a resource server

Per [§6](../../shared/ai-enablement-overview.md#6-the-mcp-server), the MCP server validates and
never issues:

- **RFC 9728 Protected Resource Metadata** published at `/.well-known/oauth-protected-resource`.
- **Audience binding enforced (RFC 8707).** A token not issued for *this* resource is rejected.
  A token valid for some other service is not valid here — this is the control that stops a
  confused-deputy attack between MCP servers.
- **PKCE S256 required.** No implicit grant, no password grant; both are removed in OAuth 2.1 and
  neither is accepted.
- **Opaque tokens, validated by introspection.** No JWT, per
  [decision-log.md](../../shared/decision-log.md) entry 2 — and a JWT library appearing in
  `pyproject.toml` is a signal that someone is re-litigating that reversal.
- **Rejection is uninformative.** `401` plus a `WWW-Authenticate` challenge. Never a reason.

### Token-to-session binding

An access token is bound at consent time to a `sessions` row, so introspection yields a session
usable **for that user only**, and revoking the token revokes the session. This keeps the
no-standing-privilege property intact across the protocol boundary.

> **Open and unresolved:** this interaction must be reconciled with the session model's 8-hour
> sliding idle window and 30-day absolute cap before it is written into
> [api-contracts.md](../../shared/api-contracts.md) — an OAuth token outliving its bound session,
> or sliding it indefinitely, are both wrong in different ways. Tracked in
> [ai-enablement-overview.md §13](../../shared/ai-enablement-overview.md#13-defaults-and-remaining-open-questions).

---

## 3. Prompt injection: defence in depth, without depending on it

Prompt injection is OWASP's top LLM risk and has no complete published defence. **The security of
this service does not rest on the model behaving.** These controls raise the cost of easy attacks;
§1 contains the consequences of a successful one.

| Control | Where |
|---------|-------|
| Untrusted text is fenced and labelled as data, never interpolated into instructions | `prompts/`, [coding-standards.md](./coding-standards.md#untrusted-content-is-delimited-and-labelled-never-interpolated-into-instructions) |
| Tools are allow-listed and schema-validated **before** dispatch | `transport/mcp/tools.py` |
| No tool composes, derives, or accepts free-form queries | `gateways/hotelapp.py` exposes named operations only |
| No tool executes code, reads files, or makes arbitrary HTTP requests | There is no such tool, and adding one is a specification change |
| Write tools are confirmed by the client before execution | MCP clients prompt per tool call; the server does not assume consent |
| Retrieved corpus text is treated as untrusted | Even though it is authored in-repo — the posture must not depend on who wrote the document |
| Output is never executed, rendered as HTML, or used to build a query | Both frontends render assistant output as text |

**The corpus is treated as hostile on purpose.** It is authored in this repository today, but a
pipeline that is only safe because of who wrote the input is a pipeline that becomes unsafe the
first time a document is uploaded rather than committed.

---

## 4. Secrets

- **The provider API key is read from the environment, never committed, never logged, never echoed
  in an error.** It appears in no response body, including `GET /health`.
- **`OPENAI_API_KEY` absent is a valid, supported state.** The service starts and reports
  `AI_UNAVAILABLE`. This is what keeps the offline Compose path honest, and it means a missing key
  is never a reason to hand around a shared one.
- The OAuth signing key and any introspection secret follow the same rules.
- **Masking rules extend to AI-specific fields**: `authorization`, `api_key`, `prompt`,
  `completion`, and retrieved chunk text are all masked at the logger, not at call sites — see
  [logging-observability.md](./logging-observability.md).

---

## 5. Cost as a security control

New to this service: an attacker who cannot read anything can still **spend money**. Unbounded
model calls are a denial-of-wallet vector, and they are the cheapest attack available against this
component.

- **Rate limiting on `/api/v1/assistant/*`**, per session and per IP, reusing the limits and
  `RATE_LIMITED` semantics both backends already implement.
- **Input length is capped before any model call**, so an oversized question costs nothing —
  `QUESTION_TOO_LONG`, checked at the edge.
- **Every model call has an explicit `max_tokens` and timeout**
  ([coding-standards.md](./coding-standards.md#every-model-call-is-bounded)). A call with no
  ceiling is a cost incident waiting for an unusual input.
- **Per-request cost is recorded** and is a tracked metric, not an afterthought
  ([§10](../../shared/ai-enablement-overview.md#10-non-functional-targets)) — unexplained cost
  growth is a security signal as much as a budget one.
- **The semantic cache reduces exposure** as a side effect of reducing spend: a repeated question
  is answered without a provider call at all.

---

## 6. What must never reappear

| Never | Why |
|-------|-----|
| A service account or any standing credential for business data | Collapses the blast-radius guarantee in §1 |
| A JWT, a bearer token issued by this project, or `Authorization` in the CORS allow-list | [decision-log.md](../../shared/decision-log.md) entry 2 |
| A credential on disk to "enable" stdio | §2 |
| A tool that takes free-form SQL, a URL, a file path, or arbitrary code | Converts prompt injection into remote execution |
| Authorization logic re-implemented in Python | The backends own it, under test |
| A model's output deciding whether a caller is permitted something | Authorization is a property of the request, never of the response |
| Guest data, prompts, or completions in logs at INFO | [logging-observability.md](./logging-observability.md) |
| An error body that reveals why a token was rejected | An oracle |
| Retry-on-`401` | Entry 2 again, in a new costume |
