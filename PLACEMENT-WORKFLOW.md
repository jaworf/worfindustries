# Placement workflow

Integrated into the current `ministry-discovery` checkout, preserving the existing Discovery release. Both forward migrations and the web update were deployed on November 3, 2026. Apple version 1.3 build 17 has been uploaded; App Store review status is tracked in the release record.

## Using it

Open **Placement** / **Placement Process**. Create an opening with a ministry, optional position, term, and number of volunteers needed, then add candidates from the existing people directory. Blank positions remain team memberships with no church vote, matching the existing assignment rules.

An administrator can assign each call to an active church administrator or editor. **My Calls** shows the signed-in caller’s open tasks and follow-ups. Candidate details include both phone numbers with calling links, email, current ministry commitments, other recruitment activity, and the person’s lasting history.

Record Yes / Willing, No, Maybe later, Considering, No answer, Message left, or Other, plus factual notes and an optional follow-up date. Other requires an explanation. History is linked to the person and the opening; closing an opening does not erase it. Backdated entries do not overwrite a more recent response. All contact history is private to signed-in members of that church and absent from public directories and bulletin text.

- **Admin:** assign or clear callers; record own calls or another active admin/editor’s calls.
- **Editor:** record calls made by that editor; cannot assign calls or record another caller’s results.
- **Viewer:** read only.

The database records the actual caller and the person entering the result separately. Saved entries are append-only through the app; subsequent calls add history rather than erase earlier answers. Caller and recorder display names are retained even if staff accounts are removed.

After willingness is recorded, voted positions use **Nominate → First Reading → Second Reading → Vote Passed**. Non-voted positions use **Appoint**. Pending nominees never become active assignments. A successful vote or appointment creates the assignment and updates the opening in one transaction. Openings with multiple places close after all places are filled. Failed votes, deferrals, resuming, and withdrawals preserve history. The Nominations view supplies selectable bulletin text without private contact details or notes.

The existing Assign and missing-vote record screens remain available for existing workflows and historical data entry. Existing assignments are not reclassified as nominees.

## Validation

- All 21 migrations applied to an isolated PostgreSQL database.
- Existing church-isolation, access-management, account-deletion, onboarding and support-security SQL regressions pass.
- 45 additional database checks cover actual permissions, caller attribution, history after caller-account deletion, response history, cross-church denial, anonymous denial, reading order, willingness at activation, nomination capacity, failed votes, and atomic rollback on duplicate assignment.
- 84 backend/web tests and 18 rendered-route tests pass, including seven rendered workflow UI checks and the new review-security regression suite.
- TypeScript check and production web build pass; workflow lint passes. Existing unrelated admin-page lint warnings remain.
- Swift type checks pass for macOS and iOS; full unsigned iOS simulator build succeeds.
- Browser checks on fictional data pass for admin call assignment, entering another caller’s result, nomination, both readings, successful vote, editor controls, and a 390-pixel mobile layout.

The original `node_modules` contains cloud-evicted files. Web verification used an isolated copy at `/tmp/ministry-placement-workflow-verification` with the pinned dependencies installed from the lockfile. No production data was used for these checks. The browser harness uses fictional fixtures; actual database authorization is separately exercised by the PostgreSQL tests.

From a checkout with dependencies installed:

```sh
pnpm run typecheck
pnpm run test:backend
pnpm run test:database
pnpm run build
```

## Release

Apply `supabase/migrations/20261104014409_placement_workflow.sql` to the intended environment before enabling the new screens, deploy the web build, and build/upload the Apple app with the next release number. Verify using dedicated test records before wider use. The new tables are church-scoped, reject direct client writes, and are not readable anonymously. The new RPCs delegate to checked private database functions; every mutation checks the stored profile and church.

A physical-device call-link and email-link check remains advisable before the Apple release. This implementation does not send reminders, calls, emails, bulletin content, or votes automatically.

## Review findings addressed

- Church ownership is stored in a server-controlled record. Approved founders are selected first; legacy churches use the earliest active administrator. Other administrators cannot demote, disable, move, or delete the owner. Only the owner or platform administrator can transfer ownership to another active same-church administrator. Transfers are audited. Users includes owner information and a transfer control.
- Discovery search, profiles, assessments, and observations are restricted to administrators and editors at the database layer and hidden from viewers in the web and native screens. Participants retain access to their own member workflow.
- General Discovery search matches submitted text values rather than JSON field names. Empty/oversized observations and invalid names have explicit validation messages.
- CI type-checks `church-platform`, runs the multi-church SQL suite, and runs the placement database suite.
- Existing tests plus new tests cover protected-owner demotion, lockout, deletion, ownership transfer, cross-church transfer denial, viewer privacy, value-only search, and invalid input.

Source changes are published through a pull request rather than directly to GitHub main. The invitation email remains an explicitly recorded follow-up in BACKLOG.md.
