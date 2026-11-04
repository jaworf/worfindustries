# Planning Center contact matching

Church admins with a configured Planning Center integration see a Planning Center Matching card in the web People Directory. Other roles and churches without an integration do not receive the card or matching data.

The page lists unlinked app contacts and Planning Center profiles from the latest completed full sync. Suggestions show matching names, email addresses and phones. Names and shared household phone numbers do not establish identity. Search can find a profile even when a name changed. Existing links are flagged; this workflow never silently merges duplicate people or moves their histories.

Selecting a profile automatically starts the comparison; the separate Sync all Planning Center contacts action runs a full sync. Before linking, the server fetches the chosen profile directly from the church's configured Planning Center account. The comparison shows current app and Planning Center identity/contact fields, membership and active status, plus Planning Center's update date. The admin must confirm these are the same person. The server fetches again on confirmation and rejects changed Planning Center data, changed app records and competing links. It accepts the contact data only from Planning Center, never from the browser's request body.

Linking uses one transaction to establish the church-scoped external ID, refresh the existing person using the normal sync mapping, resolve matching import conflicts and record an admin-only audit entry. Assignments, candidates, call history, local notes and ordination status remain on the same person. Profiles already linked to another app contact enter duplicate review on the same page.

Security checks cover admin-only reads and writes, church isolation, anonymous denial, inactive-account rejection, connection requirements, stale-record rejection, duplicate links, audit visibility and history preservation. Browser tests use fictional data at desktop/phone widths, covering card visibility, refreshed comparisons, explicit confirmation and duplicate blocking. Resource mapping keys Planning Center relationship resources by both JSON:API type and ID.

This feature is web-only initially. Native apps receive refreshed contact data through the existing shared database after a confirmed link. No unreviewed contacts are linked automatically, and no private church contact data belongs in this repository.

Deployment: apply the new migration, deploy planning-center-matching with its explicit server-side sign-in checks, then deploy the web build. If the connector assigns a different migration timestamp, reconcile that new filename with production immediately as described in MIGRATIONS.md. Do not edit applied migration SQL or rerun older migrations.

## Inline duplicate review and merge

When a selected Planning Center profile belongs to a second app contact, the page loads the current Planning Center details and both app records automatically. Admins can compare contact fields, ministry assignments, placements, notes, ordination and call history in the same workflow. The existing Planning Center-linked app contact is always retained.

Before merging, an admin must explicitly confirm that both app contacts and the Planning Center profile are the same person. Exact ministry/position/term overlaps and same-opening candidate entries require a choice of which current status and dates to use (including the caller for a placement). They become one operational entry. Both original versions and the choices are retained in admin-only Merge history, alongside the complete original contact snapshots. Notes are combined; every call-history row, original caller, recording user, date and response is retained. Distinct assignments and candidates keep their IDs.

The transaction reparents assignments, candidates, contact history, external source IDs, staff-person links, a single Discovery membership, import links and matching audit records. Assignment overlaps also reparent assignment external IDs, import links and candidate assignment references; candidate overlaps reparent call-history candidate references. Ordination flags are combined, and public visibility never increases. Planning Center provides refreshed contact fields and retains the same external link for future syncs. The consolidated contact is removed only after all references are handled. No Planning Center records are changed.

Two distinct Discovery memberships block merging with an explanation; their account ownership and assessments are never silently combined. A changed contact, assignment, candidate, call, source link or other reviewed reference requires a new comparison. Merge writes are service-role-only behind the authenticated admin Edge Function, with same-church validation repeated in the database. Original snapshots contain private data and are readable only by that church's admins. This is a new forward migration; existing production migration SQL remains unchanged.

The merge tests cover both overlap choices, rollback when an overlap choice is missing, stale call history, role/church boundaries, original snapshots, assignment-reference remapping, call IDs and contents, external IDs, staff links, Discovery profiles, notes, ordination and public visibility. A catalog check fails if a future person foreign key is added without updating merge coverage.
