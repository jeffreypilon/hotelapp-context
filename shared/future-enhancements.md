# Future Enhancements

Candidate work that is **deliberately not being built now**, recorded so the deferral stays a
choice rather than becoming an oversight. Nothing here is committed to a phase.

**What belongs here, and what does not.** This project already has three other places that track
things, and duplicating between them is how they drift apart:

| If it is… | It goes in |
|-----------|-----------|
| A bug in application code | [defect-log.md](./defect-log.md) |
| A specification decision that was made and then reversed | [decision-log.md](./decision-log.md) |
| Work that is planned, scheduled, or in a phase | [phased-implementation-plan.md](./phased-implementation-plan.md) |
| A design question that **blocks** work already in a phase | That phase's own document, not here |
| An idea worth keeping but not worth doing yet | **Here** |

Entries cross-reference the document that owns the detail rather than restating it.

---

## 1. MCP tools for profile and password management

**Deferred from:** Phase 9, F1's first cut — see
[ai-enablement-overview.md §6](./ai-enablement-overview.md#6-the-mcp-server).

The MCP server's first cut exposes catalogue and availability reads, a guest's own reservation
reads, `modify_reservation`, `cancel_reservation`, and `prepare_booking`. `GET`/`PATCH /me` and
`PUT /me/password` are deliberately absent.

**Why deferred:** the write surface already demonstrates consequential, rule-bound agent action —
modification and cancellation both run against the cancellation-deadline rules. Profile editing
adds surface area without adding a new *kind* of capability, and password change through an agent
is a credential operation with a materially worse risk profile than anything else in the tool
list.

**If revisited:** `PUT /me/password` should probably stay out permanently rather than being
deferred. An agent that can change a password can lock a guest out of their own account, and the
blast-radius argument in
[§5](./ai-enablement-overview.md#5-the-authorization-model-and-why-it-is-the-interesting-part)
— "bounded by what that guest could already do" — is least comfortable precisely where the
operation changes the credential itself.

---

## 2. Agent-initiated booking that creates a reservation

**Deferred from:** Phase 9, F1 — see the design decision in
[ai-enablement-overview.md §6](./ai-enablement-overview.md#6-the-mcp-server).

Today `prepare_booking` returns a deep link into the existing booking flow; the guest completes
payment in the first-party UI. The fuller version would have the agent create a reservation in a
pending state, with payment completed afterwards.

**Why deferred:** it is a larger change than the entire AI service, and it lands on the project's
most load-bearing constraint. It requires a new `reservation_status` value, a rewritten
`reservations_status_timestamps_chk`, a decision about whether pending reservations hold
inventory under `reservations_no_overlap_excl` (and therefore hold expiry plus a sweeper),
`ReservationStatusRules` changes in **both** backends, and a reworked S6 in **both** frontends so
payment can settle an existing reservation rather than create one.

**If revisited:** the inventory-hold question is the real decision, not the enum value. A pending
reservation that does not hold its room is cheap and races at payment time; one that does hold it
needs expiry, and abandoned agent bookings then become an availability problem.

---

## 3. Remote-deployable MCP server

**Deferred from:** Phase 9.

The MCP server runs locally. The "any agent, anywhere, can transact with this hotel" story is
therefore demonstrated rather than deployed, which is consistent with the project-wide
**Hosting: None** decision in
[devops-pipeline-overview.md](./devops-pipeline-overview.md#deliberately-absent).

**If revisited:** this is mostly a hosting question rather than a code question — the HTTP
transport and OAuth 2.1 authorization are built either way. Client ID Metadata Documents would
become worth implementing at that point, since pre-registering every client stops being viable
once clients are not all yours.

---

## 4. Staff-facing document upload for the RAG corpus

**Deferred from:** Phase 9. Raised directly — *"do we need an admin console that would allow staff
to upload the PDF documents, presumably that is how staff would submit them so they could be
sliced and vectorized?"*

Today the corpus is authored as Markdown in `hotelapp-ai-service/corpus/`, reviewed in a pull
request, rendered to PDF by a committed script, and ingested by a CLI. Staff cannot add a document;
a developer adds one and it goes through review like any other behavioural change.

The fuller version would let Front Desk or Manager staff upload a PDF through the admin console,
which would then be parsed, chunked, embedded and retrievable.

### Why deferred — three reasons, in order of weight

**1. It presupposes an admin console that does not exist.** Admin endpoints (Phase 6 items 9–12)
are unbuilt in **both** backends, and admin screens (Phase 7 items 7–8) are unbuilt in **both**
frontends. "Add upload to the admin console" is really "build the admin console across four repos,
keeping the two frontends byte-identical in `ui-specifications.md`, then add upload." That is
plausibly a larger body of work than the entire AI service, spent to deliver its least
differentiated part.

**2. It is CRUD, and CRUD is not what is scarce here.** The capabilities that make this project
unusual are the MCP server, hybrid retrieval with committed evaluation floors, the pass-through
authorization model, and the policy-consistency test. A file-upload form competes for time against
those and wins nothing a reviewer has not seen many times.

**3. It materially weakens two properties the current design guarantees.** This is the real
argument, and the one worth preserving:

- **The corpus is authored *from* the implemented rules and reviewed before it binds anything.**
  Allow upload, and a well-meaning staff member can publish a document stating a 72-hour
  cancellation window while both backends enforce 48. That answer then scores **perfectly** on
  every standard RAG metric, because faithfulness measures agreement with the retrieved document,
  not with the running application. The guarantee stops being structural and becomes a matter of
  staff discipline — which is exactly the kind of guarantee this project exists to avoid relying on.
- **The prompt-injection posture shifts.**
  [security-implementation.md](../stacks/ai-service/security-implementation.md#3-prompt-injection-defence-in-depth-without-depending-on-it)
  already states the principle: *a pipeline that is only safe because of who wrote the input is a
  pipeline that becomes unsafe the first time a document is uploaded rather than committed.* Upload
  also introduces untrusted PDF parsing, which has a genuine CVE history, plus file storage, size
  and type validation, and a malware question none of which exist today.

### The answer this absence buys

Worth recording, because it is the point: *"Staff cannot upload documents. The corpus is
version-controlled and reviewed like code, because a RAG corpus is behaviour — and here is the test
asserting it still agrees with what the API enforces. If we allowed upload, these four things would
have to change."*

That is a stronger response to the question than a working upload form, and it is difficult to give
without having actually reasoned it through.

### A cheaper middle option, if the "operable, not a toy" signal is wanted

A **read-only** corpus view in the admin console: documents, chunk counts, last-ingested
timestamps, embedding cost, and the latest RAGAS scores from `ai_eval_runs`. It demonstrates
operational awareness at a fraction of the cost, requires no upload path, and leaves the security
posture and the authored-from-the-spec guarantee untouched. It would slot naturally beside the
staff assistant (F4) once an admin UI exists.

### If revisited, what actually has to be solved

Not the upload itself — that part is easy. These are the hard parts, and skipping any of them is
how this feature becomes a liability:

1. **Reconciling an uploaded document with the implemented rules.** Either the policy-consistency
   check runs against uploaded content and *blocks publication* on a contradiction, or a reviewer
   approves each document before it becomes retrievable. Doing neither means the assistant can be
   made to contradict the system by someone with no intent to.
2. **A review and publication state.** A document would need to be uploaded, reviewed, and
   *published* as distinct states, which is a workflow rather than a form.
3. **Untrusted parsing.** Sandboxing or hardening the PDF parse path, with size and type limits
   enforced before parsing begins.
4. **Authorization.** Who may publish is a Manager-level decision, not Front Desk, and needs its
   own acceptance criteria.
5. **Re-ingestion and cost.** Publication triggers embedding, which costs money and must be
   idempotent and rate-limited, or a staff member clicking twice pays twice.

---

## 5. Guest reservation awareness inside the F3 assistant

**Deferred from:** AI Step 3's design discussion.

F3 as built answers from the document corpus only — policy, house rules, amenities, directions.
It does not call `gateways/hotelapp.py` and has no notion of "my reservation." A guest who asks the
assistant "when do I check in" gets the general policy answer, not their own booking's dates.

**Why deferred:** it is distinct from F4 in [ai-enablement-overview.md §2](./ai-enablement-overview.md#2-scope)
(staff viewing *any* guest's reservations, blocked on an admin UI) — this would be a guest viewing
their *own* reservation through the assistant instead of the existing account screens. Its value is
genuinely modest: a guest can already see their own reservation in the UI without invoking AI at
all, so this is a convenience layer on an already-solved problem rather than new capability. Adding
it to Step 3 would also have meant building a tool-calling branch into the graph that Step 3's own
verification text implied but never specified — caught during the Step 3 design discussion rather
than built un-designed.

**If revisited:** this is additive to the existing graph, not a redesign — a new tool node calling
`gateways/hotelapp.py` with the caller's forwarded session, gated the same way MCP's reservation
tools already are (session required, backend's own authorization applies unchanged). The interesting
design question is UX, not architecture: how the assistant should ask the guest to confirm which
reservation they mean, if they hold more than one.

---

## Not here: open questions that block Phase 9

One item discussed alongside these is **not** a future enhancement and is deliberately not
tracked here — **how an OAuth access token becomes a backend-callable identity**. MCP over HTTP
presents an OAuth token; the backends only understand session cookies. Until that is resolved the
HTTP transport cannot work at all, so it is a Phase 9 design question, not an optional
improvement. It is recorded in
[ai-enablement-overview.md §13](./ai-enablement-overview.md#13-defaults-and-remaining-open-questions)
along with the recommended answer, and must be settled before `api-contracts.md` gains the MCP
endpoints.

Filing a blocker as an enhancement is how a blocker gets found at implementation time instead of
at design time, which is the failure mode this repository exists to prevent.
