# Phase 7 Step 7 — guest profile and password (S8a/S8d, the rest of item 6)

Drafted 2026-09-27 — not yet run through Copilot. Closes out item 6 (and, with it, React's
entire guest-facing slice, Phase 7 items 1-6) by covering the two S8 sub-screens Step 6 left out
(S8b/S8c were Step 6's scope).

```
HotelApp — React Phase 7, Step 7: guest profile and password (S8a/S8d — the rest of item 6)

Read first: shared/api-contracts.md (GET /me, PATCH /me — the null-clears/omitted-is-unchanged
semantics, PUT /me/password), stacks/react/ui-specifications.md's S8a/S8d entries,
stacks/react/state-management.md's mutation-invalidation table, stacks/react/error-handling.md
(401 INVALID_CREDENTIALS on this specific endpoint — see point 5, a real subtlety). Stay in
stacks/react/ only.

CURRENT STATE (confirmed by reading the actual repo — Phase 7 Step 6 is commit 18a0f52):
`/account/reservations` and `/account/reservations/:id` exist (Step 6); `/account` (profile) and
`/account/password` do not. No `me.ts` endpoint file, no `qk.me()` key. `User` (the session
shape from `/auth/me`) has only `id/email/firstName/lastName/role/propertyId` — `GET /me`'s full
profile shape (phone, address, createdAt) needs its own type, not a reuse of `User`. `Header`'s
`UserArea` for a logged-in Guest is still simplified from Step 1 — no "My reservations"/"Profile"
menu items — because neither route existed until now. This step is what finally closes that.

SCOPE — S8a (profile) and S8d (password) only. This closes out item 6 and, with it, React's
entire guest-facing slice (Phase 7 items 1-6).

1. api/types.ts: `Profile` — the full `GET /me` shape (`id`, `email`, `firstName`, `lastName`,
   `phone: string | null`, `address: Address`, `role`, `propertyId`, `createdAt`). Distinct from
   `User` — same reasoning as every prior summary/detail split in this API, just the mirror image
   (here the *fuller* shape is the one this screen needs, and the session's `User` is the
   narrower one). `PatchProfileRequest` (`firstName?`, `lastName?`, `phone?: string | null`,
   `address?: Address`) and `ChangePasswordRequest` (`currentPassword`, `newPassword`).
   api/endpoints/me.ts: `getProfile()`, `patchProfile(body)`, `changePassword(body)`.
   api/queryKeys.ts: add `me()`.

2. lib/validation/profileSchema.ts and passwordSchema.ts (same location convention as
   `authSchemas.ts`/`paymentSchema.ts`): profile requires `firstName`/`lastName`, `phone`
   optional; password requires `currentPassword`, `newPassword` (12+ characters, same no-
   character-class-requirements rule as registration), and a `confirmNewPassword` that must match
   `newPassword` (client-only check — the contract doesn't take a confirm field, don't send it).

3. features/account/ProfileScreen.tsx at `/account`. `GET /me` renders first name, last name,
   email (read-only, "Email cannot be changed" helper text — don't make it an editable, disabled
   input; render it as plain text so there's no disabled-field a11y ambiguity), phone, and the
   address group, in a view mode with an edit toggle.

   **The hard part, mirroring the backend's own hardest part of building this endpoint**: `PATCH
   /me` treats an omitted field as unchanged and an explicit `null` as "clear it" — `""` is a
   third, wrong thing. Use React Hook Form's `formState.dirtyFields` to build the request body
   from ONLY the fields the guest actually touched (an untouched field must not appear in the body
   at all, not even with its current value). For any touched field that's a nullable string
   (`phone`) left empty, send `null`, not `""`. For the `address` sub-object: if ANY address field
   is dirty, send the WHOLE current address object (merged with the edited value) rather than a
   partial address patch — the contract describes `address` as one of the top-level changeable
   fields, not its sub-fields individually, and this repo already has precedent for "any change to
   a nested object means resending the whole object" (S12's property form). Success: "Your profile
   has been updated." and exit edit mode.

   On success, invalidate BOTH `qk.me()` and `qk.session()` — per state-management.md's mutation
   table. The session invalidation matters concretely here, not just per the table: `Header`'s
   `UserArea` reads `firstName` from the SESSION query (`/auth/me`), not from this screen's `/me`
   data, so changing your first name here won't show up in the header until the session
   refetches. This is exactly why that table lists both targets.

4. Retrofit `Header`'s `UserArea` for a logged-in Guest: add "My reservations" (→
   `/account/reservations`) and "Profile" (→ `/account`) to the menu, per ui-specifications.md's
   S0 five-state table — this was deliberately left incomplete in Step 1 because neither route
   existed yet. It's not scope creep; it's finishing a spec requirement whose target now exists.

5. features/account/PasswordScreen.tsx at `/account/password`. Current password, new password,
   confirm. `PUT /me/password` on submit. Success: "Your password has been updated." plus a note
   that other devices have been signed out (true per the contract). `INVALID_CREDENTIALS` →
   field-level on `currentPassword`: "That password is incorrect."

   **Verify, don't assume**: this endpoint's `INVALID_CREDENTIALS` error is a `401` per
   api-contracts.md — but `api/client.ts`'s global dead-session rule keys on error `code`
   (`AUTHENTICATION_REQUIRED`/`ACCOUNT_INACTIVE`), not HTTP status, so a wrong-current-password
   attempt should fall through to this screen's own `onError` rather than triggering a global
   logout-and-redirect. Confirm this actually happens in the browser, not just in the code — if a
   wrong current password logs the guest out, that's a real bug (a status-based check somewhere
   would be the cause), not a spec-compliant "session expired." **Don't invalidate the session or
   route to login on success** — the spec is explicit that the caller stays logged in, which is
   the opposite of every other place a 401-shaped error appears in this app, and it's an easy
   place to reflexively copy the wrong pattern.

6. routes.tsx: add `/account` and `/account/password` inside the existing `<RequireAuth>` group.

NOT in scope: admin, anything for Node/Angular. Don't scaffold speculatively — this is the last
React guest-facing item.

Per the standing rules already in this repo's Copilot instructions: commit and push once
verification passes, and any new pure logic (the dirty-fields-to-patch-body builder, if you
factor it out) ships with a unit test in the same commit.

VERIFICATION: npm run lint / typecheck / test:run / build all green. Manually, as the guest
account from Steps 4-6: change only the phone number and confirm the PATCH body (Network tab)
contains just `{"phone": "..."}`, nothing else; clear the phone field entirely and confirm the
body sends `{"phone": null}`, not `{"phone": ""}`; change first name and confirm the header
updates without a manual reload; attempt a password change with the wrong current password and
confirm you're still logged in afterward (not bounced to `/login`); complete a real password
change and confirm you're still logged in in this tab. Confirm nothing appears in
`localStorage`/`sessionStorage` throughout, same check as every prior auth-adjacent step.

Flag judgment calls in code and summarize them at the end, same discipline as every prior step —
this closes out Phase 7 items 1-6, so also note in your summary whether anything from
ui-specifications.md's guest-facing screens (S0-S8) was left unimplemented or simplified, as a
clean handoff point before Node starts.
```
