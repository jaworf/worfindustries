# Riverview Ministry Volunteers

Volunteer ministry management for Pasco Riverview Adventist Church.

This repository contains:

- one shared SwiftUI app for iPhone, iPad, and macOS;
- a Supabase database, security policies, seed data, and Planning Center sync;
- a public, searchable, printable web directory with an iframe route;
- conservative CSV import that deduplicates and enriches people without silently
  overwriting conflicting contact details.

## What the app does

- Find an existing person or add a new person.
- Assign a ministry role, position/sub-role, two-year term, church vote date,
  notes, and public/private status.
- Add a ministry-specific position from the Assign screen and select it
  immediately for the current placement.
- Give each ministry and each ministry-specific position its own church-vote rule.
- Correct or clear vote dates from the Ministry or People Directory.
- Use the Votes work queue or report filter to find every required vote still missing.
- Use Placement Focus to see empty ministries, unfilled expired positions, and
  active people who do not yet have a ministry assignment.
- Hand an empty ministry, open position, or unassigned person directly to the
  Assign screen with the relevant record already selected.
- Prioritize unassigned Riverview Members in the volunteer activation list,
  while retaining New, Local, All, membership, and search filters.
- Add terms and ministries, or rename a ministry without breaking old assignments.
- Search the People Directory to see current assignments and archived history.
- Reversibly archive assignments and ministries without deleting their history.
- Automatically archive active assignments each day after their term ends.
- Filter by role or by terms ending within 6 or 12 months.
- Sort ministry rosters with leadership first, then last and first name.
- Preview, export, and print a landscape PDF report.
- Import the supplied Members and Assignments CSV exports.
- Pull Planning Center People through a server-side sync and signed webhooks.
- Preserve Planning Center's original person-created date so genuinely new
  people can be highlighted without confusing them with an older bulk import.
- Publish only approved names and role information to the public web directory.
- Resize all app typography with working S, M, L, and XL settings on both macOS
  and iOS/iPadOS.

## Project map

| Folder | Purpose |
| --- | --- |
| `ios/RiverviewMinistry.xcodeproj` | Open this in Xcode for the iOS/macOS app |
| `ios/RiverviewMinistry` | Shared SwiftUI app code |
| `supabase/migrations` | Complete database schema and Row Level Security |
| `supabase/seed.sql` | Supplied roles, sub-roles, and known term dates |
| `supabase/functions` | Planning Center full sync and signed webhook receiver |
| `app` | Public web directory and `/embed` iframe view |

## 1. Supabase setup

The production database is deployed in the Supabase project **Ministry
Volunteers App** (`syyennvldkenqrcbvgaq`). All migrations are applied, the
reference roles and terms are seeded, and the supplied starting records have
been imported without committing member contact data to this repository.

For a clean database, apply every file in `supabase/migrations` in filename
order, then run `supabase/seed.sql`.

To create a staff account without SQL:

1. Sign in with an administrator account.
2. Open **Settings & Import** and find **Team Access**.
3. Enter the person's email and choose **Editor** or **Viewer**.
4. Select **Create User & Send Setup Email**.
5. The new user opens the newest email, chooses a password, and signs in.

Only an administrator sees Team Access. The `admin-users` Edge Function checks
the administrator role again on the server before using Supabase's invitation
API, so an editor or viewer cannot bypass the hidden interface. The app does not
offer `admin` as a new-user choice; grant that higher access directly in Supabase
only when another person genuinely needs to manage staff accounts. Editors can
manage ministry data, while viewers have read-only access.

The schema deliberately enables Row Level Security on every public table and
uses explicit grants. Contact data is available only to signed-in staff.

## 2. Planning Center People

Planning Center synchronization is supported. It is not a client-side login:
the credentials stay in Supabase Edge Function secrets.

Synchronization is deliberately one-way. Planning Center People is authoritative
for names, contact details, membership status, and active status. A sync replaces
those mirrored fields in this database, including clearing a field that was
cleared in Planning Center. The app never sends person changes to Planning Center;
ministry roles, terms, votes, and assignments remain local to this app.

For this one-church app, use a Planning Center Personal Access Token. This is
the path the deployed functions currently implement, and it does not use an
OAuth application or an authorization callback URL. Set:

- `PCO_CLIENT_ID` - Planning Center Personal Access Token application ID;
- `PCO_CLIENT_SECRET` - Planning Center Personal Access Token secret;
- `PCO_WEBHOOK_SECRET` - the webhook signing secret;
- `PCO_API_VERSION` - optional; defaults to `2026-06-04`.

The **Authorization callback URLs** field belongs only to an OAuth flow. Do not
put the webhook URL in that field. If the app later needs to connect multiple
churches, first add a server-side OAuth callback and token-storage flow, then
register its exact HTTPS URL in Planning Center. A suitable future route would
be:

```text
https://syyennvldkenqrcbvgaq.supabase.co/functions/v1/planning-center-oauth-callback
```

That callback function does not exist yet, so registering this URL by itself
will not enable OAuth. A confidential Planning Center client secret must stay
in Supabase and never be placed in the Apple or web app.

Both functions are deployed, and the Personal Access Token credentials are set
in the production project's Edge Function secrets. The webhook still requires a
`PCO_WEBHOOK_SECRET` and a matching Planning Center webhook subscription before
automatic event delivery is active.

Function configuration:

- `admin-users` with Supabase JWT verification enabled and an additional
  administrator-role check inside the function;
- `planning-center-sync` with Supabase JWT verification enabled;
- `planning-center-webhook` with Supabase JWT verification disabled, because
  the function verifies Planning Center's HMAC signature itself.

Use this webhook endpoint in Planning Center:

```text
https://syyennvldkenqrcbvgaq.supabase.co/functions/v1/planning-center-webhook
```

Subscribe to People person-created and person-updated events. The webhook makes
new or changed people available quickly. The app's **Sync Planning Center
People** button performs a full reconciliation in case a webhook was missed.

## 3. Open the Apple app

1. Open `ios/RiverviewMinistry.xcodeproj` in Xcode.
2. Select the **RiverviewMinistry** scheme.
3. Choose **My Mac**, an iPhone simulator, or a connected iPhone.
4. In **Signing & Capabilities**, choose the church's Apple Developer team.
5. Press Xcode's Run button.
6. The production project URL and public publishable key are included in the
   app build, so a fresh install opens at the staff sign-in screen.
7. Sign in with the staff account created in Supabase. Use **Change Supabase
   connection** only when intentionally pointing the app at another project.

Do not enter a Supabase service-role key in the app. The publishable key is the
correct key; Row Level Security provides the authorization boundary.

This project includes `ios/Tools/clang-probe-wrapper.sh` because Xcode 26.6
(17F113) can stall during its verbose clang macro probe. The wrapper removes
`-v` only from that probe and delegates all compilation and linking to Xcode's
own clang. It can be removed after Apple fixes the toolchain issue and a clean
build succeeds without it.

## 4. Import the supplied CSV files

In the app, open **Settings & Import**:

1. Choose **Members** and import the Members CSV first.
2. Choose **Assignments** and import the Assignments CSV second.
3. Review the completion summary. Ambiguous matches are preserved as conflicts
   in Supabase instead of being guessed.

The importer follows these rules:

- Reuses a stable source ID when the CSV includes one.
- Merges automatically only when one person matches the normalized name plus
  email or phone.
- Fills blank contact fields from newer CSV data.
- Preserves an existing value when the incoming CSV disagrees and records the
  mismatch for review.
- Does not merge household members merely because they share an email or phone.
- Prevents repeated assignment imports from creating duplicate placements.

The supplied exports include some missing terms and vote dates. Those values
remain visibly missing rather than being invented.

## 5. Public web directory

The public site reads only `public.public_directory_entries`; that database view
does not expose email, phone, address, staff-only notes, or internal person IDs.
An assignment note appears only when staff explicitly enables its report/web
visibility toggle.

Required hosted environment variables:

```text
SUPABASE_URL
SUPABASE_PUBLISHABLE_KEY
```

The hosted directory is connected to the production Supabase project. The
directory route is intentionally public; access control for the church's copy is
handled by the members-only page that contains the iframe.

After the public site is deployed, embed the compact route on
`riverviewadventist.org`:

```html
<iframe
  src="https://riverview-ministry-directory.jaworf.chatgpt.site/embed"
  title="Riverview volunteer ministry directory"
  width="100%"
  height="1100"
  style="width:100%;min-height:1100px;border:0"
  loading="lazy"
></iframe>
```

The web view supports search, role and term-ending filters, CSV export, and
browser printing/saving as PDF.

## 6. Move the web routes to church-controlled hosting

The web code already builds as a Cloudflare Worker. Moving it changes where the
iframe and password setup page run; staff passwords themselves remain securely
managed by Supabase Auth and are not stored by either web host.

1. In Cloudflare **Workers & Pages**, create a Worker and connect the GitHub
   repository.
2. Use `pnpm run build` as the build command and
   `pnpm exec wrangler deploy --config dist/server/wrangler.json` as the deploy
   command.
3. Add `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` under the Worker's
   **Settings > Variables and Secrets**. Never add a Supabase secret/service-role
   key to this web app.
4. Verify the temporary `workers.dev` address, including `/embed` and
   `/reset-password`.
5. If `riverviewadventist.org` is an active Cloudflare DNS zone, attach a custom
   domain such as `directory.riverviewadventist.org`. Otherwise use the
   `workers.dev` address until the church decides whether to move DNS to
   Cloudflare.
6. In Supabase **Authentication > URL Configuration**, set the production Site
   URL and add the exact new `/reset-password` URL to Redirect URLs.
7. Set the Supabase Edge Function secret `APP_PASSWORD_RESET_URL` to that exact
   new URL, update the Apple app's `passwordResetURL`, rebuild the Apple app, and
   replace the iframe `src` above.
8. Test one invitation and one forgot-password email before retiring the old
   hosted site.

## Verification performed

- Web production build: passed.
- Web compiler/type build: passed.
- ESLint: passed with 0 errors (one non-blocking SVG image optimization warning).
- Web route, privacy, print, password, and administrator-security tests: 7 passed.
- macOS Swift type-check against Xcode 26.6 SDK: passed.
- iOS Swift type-check against Xcode 26.6 SDK: passed.
- Clean macOS app build in Xcode 26.6: passed.
- Clean generic iOS Simulator app build in Xcode 26.6: passed.
- macOS unit tests: passed with 0 failures.
- Native PDF runtime smoke test: passed; all three rendered pages were visually checked.
- Live browser PDF: all 18 pages rendered; the first and last pages were visually
  checked with the wider margins, Term End-only table, and `1 of 18` / `18 of 18`
  footers.
- Administrator user endpoint: deployed with JWT verification; an unauthenticated
  creation request was rejected with HTTP 401.
- Production migrations: applied successfully.
- Supabase Cron runs the expired-term archive at 08:10 GMT daily (12:10 AM
  Pacific Standard Time or 1:10 AM Pacific Daylight Time). The initial run
  archived Nathan Lull's completed 2024-2026 school-board assignment.
- Supabase database security: Row Level Security is enabled on every public
  table. The Auth advisor currently recommends enabling leaked-password
  protection in the Supabase dashboard.
- Anonymous contact-field access: explicitly denied and verified.
- Current production data after full Planning Center reconciliation: 1,303
  people and 237 assignments. The sync processed 1,298 Planning Center people:
  7 added, 1,140 updated, 36 unchanged, 115 held for identity review, and 0
  errors. Membership status was imported for 1,146 linked records; 37 linked
  records do not currently have a membership value in Planning Center.
- The June 27, 2026 second-reading vote was reconciled from the approved PDF:
  89 named starred records mapped to 93 app assignments because three combined
  report headings correspond to separate app ministries. Four missing Church
  Board assignments were added; the blank TBD position and all unstarred names
  were left unchanged.
- Live app-client integration: login, reads, role add/rename, term add, voted
  assignment, and duplicate/enrichment CSV import passed; disposable records
  were removed afterward.

## Important privacy rule

The staff app can contain personal contact information. The public web view must
remain limited to names, ministries, positions, terms, recorded vote dates, and
notes that staff explicitly approve for reports/web. Do not add contact columns
or raw staff-only notes to `public_directory_entries`.
