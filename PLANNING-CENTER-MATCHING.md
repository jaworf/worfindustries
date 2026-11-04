# Planning Center contact matching

Church admins with a configured Planning Center integration see a Planning Center Matching card in the web People Directory. Other roles and churches without an integration do not receive the card or matching data.

The page lists unlinked app contacts and Planning Center profiles from the latest completed full sync. Suggestions show matching names, email addresses and phones. Names and shared household phone numbers do not establish identity. Search can find a profile even when a name changed. Existing links are flagged; this workflow never silently merges duplicate people or moves their histories.

Before linking, the server fetches the chosen profile directly from the church's configured Planning Center account. The comparison shows current app and Planning Center identity/contact fields, membership and active status, plus Planning Center's update date. The admin must confirm these are the same person. The server fetches again on confirmation and rejects changed Planning Center data, changed app records and competing links. It accepts the contact data only from Planning Center, never from the browser's request body.

Linking uses one transaction to establish the church-scoped external ID, refresh the existing person using the normal sync mapping, resolve matching import conflicts and record an admin-only audit entry. Assignments, candidates, call history, local notes and ordination status remain on the same person. Duplicate profiles already linked elsewhere must be reviewed separately.

Security checks cover admin-only reads and writes, church isolation, anonymous denial, inactive-account rejection, connection requirements, stale-record rejection, duplicate links, audit visibility and history preservation. Browser tests use fictional data at desktop/phone widths, covering card visibility, refreshed comparisons, explicit confirmation and duplicate blocking. Resource mapping keys Planning Center relationship resources by both JSON:API type and ID.

This feature is web-only initially. Native apps receive refreshed contact data through the existing shared database after a confirmed link. No unreviewed contacts are linked automatically, and no private church contact data belongs in this repository.

Deployment: apply the new migration, deploy planning-center-matching with its explicit server-side sign-in checks, then deploy the web build. If the connector assigns a different migration timestamp, reconcile that new filename with production immediately as described in MIGRATIONS.md. Do not edit applied migration SQL or rerun older migrations.
