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
