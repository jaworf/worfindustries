# Riverview Ministry

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
- Add terms and roles, or rename a role without breaking old assignments.
- Search by person and see all their roles.
- Filter by role or by terms ending within 6 or 12 months.
- Sort ministry rosters with leadership first, then last and first name.
- Preview, export, and print a landscape PDF report.
- Import the supplied Members and Assignments CSV exports.
- Pull Planning Center People through a server-side sync and signed webhooks.
- Publish only approved names and role information to the public web directory.

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
Volunteers App** (`syyennvldkenqrcbvgaq`). Both migrations are applied, the
reference roles and terms are seeded, and the supplied starting records have
been imported without committing member contact data to this repository.

For a clean database, apply the migrations in order and then run
`supabase/seed.sql`:

1. `supabase/migrations/20260730060635_initial_ministry_schema.sql`
2. `supabase/migrations/20260730154704_harden_anon_privileges_and_indexes.sql`

To finish staff access:

1. In Supabase Authentication, create the staff user.
2. Promote the first staff user to administrator in the SQL editor:

```sql
update public.profiles
set app_role = 'admin'
where user_id = (
  select id
  from auth.users
  where email = 'YOUR-EMAIL@example.com'
);
```

New accounts start as `viewer`. An administrator can set `app_role` to
`admin`, `editor`, or `viewer`. Editors can manage ministry data; viewers have
read-only access.

The schema deliberately enables Row Level Security on every public table and
uses explicit grants. Contact data is available only to signed-in staff.

## 2. Planning Center People

Planning Center synchronization is supported. It is not a client-side login:
the credentials stay in Supabase Edge Function secrets.

Create a Planning Center Personal Access Token for this single church and set:

- `PCO_CLIENT_ID` - Planning Center application ID;
- `PCO_CLIENT_SECRET` - Planning Center secret;
- `PCO_WEBHOOK_SECRET` - the webhook signing secret;
- `PCO_API_VERSION` - optional; defaults to `2026-06-04`.

Both functions are deployed. Before using them, add the Planning Center
credentials to the production project's Edge Function secrets.

Function configuration:

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
6. On first launch, enter the Supabase project URL and publishable key.
7. Sign in with the staff account created in Supabase.

Do not enter a Supabase service-role key in the app. The publishable key is the
correct key; Row Level Security provides the authorization boundary.

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
does not expose email, phone, address, notes, or internal IDs for people.

Required hosted environment variables:

```text
SUPABASE_URL
SUPABASE_PUBLISHABLE_KEY
```

The hosted private preview is connected to the production Supabase project.
Keep the site private until the directory names and roles have been reviewed
and public iframe deployment has been explicitly approved.

After the public site is deployed, embed the compact route on
`riverviewadventist.org`:

```html
<iframe
  src="https://YOUR-DIRECTORY-DOMAIN/embed"
  title="Riverview volunteer ministry directory"
  width="100%"
  height="900"
  style="border:0"
  loading="lazy"
></iframe>
```

The web view supports search, role and term-ending filters, CSV export, and
browser printing/saving as PDF.

## Verification performed

- Web production build: passed.
- Web lint: passed.
- Web route and privacy tests: 3 passed.
- macOS Swift type-check against Xcode 26.6 SDK: passed.
- iOS Swift type-check against Xcode 26.6 SDK: passed.
- PDF runtime smoke test: passed and rendered page visually checked.
- Production migrations: applied successfully.
- Supabase security advisor: no findings.
- Anonymous contact-field access: explicitly denied and verified.
- Starting data: 531 distinct people and 233 distinct assignments imported.

## Important privacy rule

The staff app can contain personal contact information. The public web view must
remain limited to names, ministry roles, positions, terms, and recorded vote
dates. Do not add contact columns to `public_directory_entries`.
