import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);

async function render(pathname = "/") {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request(`http://localhost${pathname}`, {
      headers: { accept: "text/html" },
    }),
    {
      ASSETS: {
        fetch: async () => new Response("Not found", { status: 404 }),
      },
    },
    {
      waitUntil() {},
      passThroughOnException() {},
    },
  );
}

test("server-renders the public ministry directory", async () => {
  const response = await render("/");
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);
  assert.equal(
    response.headers.get("content-security-policy"),
    "frame-ancestors 'self'",
  );

  const html = await response.text();
  assert.match(html, /Volunteer ministry directory/i);
  assert.match(html, /Pasco Riverview Adventist Church/i);
  assert.match(html, /placeholder="Person, role, position, term, or note"/i);
  assert.match(html, /Print \/ PDF/i);
  assert.match(html, /src="\/ministry-logo\.png"/i);
  assert.match(html, /Contact information[\s\S]*remain private/i);
  assert.match(html, /notes explicitly approved/i);
  assert.doesNotMatch(html, /codex-preview|Your site is taking shape/i);
});

test("provides a compact iframe route", async () => {
  const response = await render("/embed");
  assert.equal(response.status, 200);
  assert.match(
    response.headers.get("content-security-policy") ?? "",
    /https:\/\/riverviewadventist\.org/,
  );
  assert.equal(response.headers.get("x-frame-options"), null);
  const html = await response.text();
  assert.match(html, /directory-shell embedded/i);
  assert.match(html, /Volunteer ministry directory/i);
});

test("provides a password setup and recovery page", async () => {
  const response = await render("/reset-password");
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /Reset your app password/i);
  assert.match(html, /does not change the Supabase project or database password/i);
});

test("provides an App Store support page", async () => {
  const response = await render("/support");
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /App Support/i);
  assert.match(html, /jason\.worf@riverviewadventist\.org/i);
  assert.match(html, /Do not send passwords or Planning Center API secrets/i);
});

test("provides a mobile authenticated administration route", async () => {
  const response = await render("/admin");
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /Riverview Ministry Volunteers/i);
  assert.match(html, /secure database connection|Secure mobile access/i);
});

test("recovers from a briefly future-issued JWT without leaving a blank portal", async () => {
  const adminClient = await readFile(
    new URL("app/admin/admin-client.tsx", root),
    "utf8",
  );

  assert.match(adminClient, /isFutureJwtError/);
  assert.match(adminClient, /attempt < 3/);
  assert.match(adminClient, /await wait\(\(attempt \+ 1\) \* 1_200\)/);
  assert.match(adminClient, /Reconnect to ministry data/);
  assert.match(adminClient, /Try Again/);
});

test("keeps the Planning Center connection button readable in narrow layouts", async () => {
  const adminClient = await readFile(
    new URL("app/admin/admin-client.tsx", root),
    "utf8",
  );
  const styles = await readFile(new URL("app/globals.css", root), "utf8");

  assert.match(adminClient, />Save Connection<\/button>/);
  assert.doesNotMatch(adminClient, />Save Planning Center Connection<\/button>/);
  assert.match(styles, /\.admin-connection-save\s*{[\s\S]*min-width:\s*max-content/);
  assert.match(styles, /\.admin-connection-save\s*{[\s\S]*white-space:\s*nowrap/);
});

test("keeps public data limited to approved directory fields", async () => {
  const client = await readFile(
    new URL("app/directory-client.tsx", root),
    "utf8",
  );
  const layout = await readFile(new URL("app/layout.tsx", root), "utf8");

  assert.match(client, /public_directory_entries/);
  assert.doesNotMatch(client, /mobile_phone|home_phone|address_line|Home Email/);
  assert.match(client, /entry\.note/);
  assert.match(client, /<th>Note<\/th>/);
  assert.match(client, /<th>Term end<\/th>/);
  assert.doesNotMatch(client, /<th>Term<\/th>/);
  assert.doesNotMatch(client, /data-label="Term"/);
  assert.doesNotMatch(client, /is_ordained|ordination/i);
  const page = await readFile(new URL("app/page.tsx", root), "utf8");
  assert.match(page, /SUPABASE_PUBLISHABLE_KEY/);
  assert.doesNotMatch(client, /service[_-]?role/i);
  assert.match(layout, /\/ministry-logo\.png/);
});

test("keeps ordination on people and out of the public iframe", async () => {
  const adminClient = await readFile(
    new URL("app/admin/admin-client.tsx", root),
    "utf8",
  );
  const models = await readFile(
    new URL("ios/RiverviewMinistry/Models.swift", root),
    "utf8",
  );
  const migration = await readFile(
    new URL(
      "supabase/migrations/20260814191710_add_person_ordination_status.sql",
      root,
    ),
    "utf8",
  );
  const reportGenerator = await readFile(
    new URL("ios/RiverviewMinistry/ReportGenerator.swift", root),
    "utf8",
  );

  assert.match(adminClient, /is_ordained_deacon/);
  assert.match(adminClient, /permanent person record/i);
  assert.match(adminClient, /Ordained Deacons/);
  assert.match(adminClient, /Ordination action/i);
  assert.match(adminClient, /Awaiting ordination/i);
  assert.match(adminClient, /ordination status are intentionally excluded/i);
  assert.doesNotMatch(adminClient, /service[_-]?role/i);
  assert.match(models, /var isOrdainedDeacon: Bool/);
  assert.match(models, /ordinationLabels/);
  assert.match(migration, /alter table public\.people/);
  assert.match(migration, /is_ordained_deaconess/);
  assert.match(migration, /Yadelky/i);
  assert.match(migration, /Victoria/i);
  assert.doesNotMatch(migration, /update public\.assignments[\s\S]*is_ordained/i);
  assert.doesNotMatch(reportGenerator, /ordinat/i);
});

test("prints with comfortable margins and page totals", async () => {
  const styles = await readFile(new URL("app/globals.css", root), "utf8");

  assert.match(styles, /@page\s*{[\s\S]*margin:\s*0\.65in/);
  assert.match(styles, /@bottom-right/);
  assert.match(styles, /counter\(page\)[\s\S]*counter\(pages\)/);
});

test("updates passwords with invitation or recovery tokens without privileged keys", async () => {
  const resetClient = await readFile(
    new URL("app/reset-password/password-reset-client.tsx", root),
    "utf8",
  );

  assert.match(resetClient, /window\.location\.hash/);
  assert.match(resetClient, /\/auth\/v1\/user/);
  assert.match(resetClient, /type !== "recovery" && type !== "invite"/);
  assert.match(resetClient, /Bearer \$\{accessToken\}/);
  assert.match(resetClient, /href="riverviewministry:\/\/open"/);
  assert.match(resetClient, /Open iPhone or iPad App/);
  assert.match(resetClient, /href="\/admin"/);
  assert.match(resetClient, /Open Web App/);
  assert.doesNotMatch(resetClient, /service[_-]?role/i);
});

test("keeps user creation administrator-only and server-side", async () => {
  const settings = await readFile(
    new URL("ios/RiverviewMinistry/ManageAndSettingsView.swift", root),
    "utf8",
  );
  const client = await readFile(
    new URL("ios/RiverviewMinistry/SupabaseRESTClient.swift", root),
    "utf8",
  );
  const edgeFunction = await readFile(
    new URL("supabase/functions/admin-users/index.ts", root),
    "utf8",
  );

  assert.match(settings, /if model\.isAdministrator/);
  assert.match(settings, /Create or Resend Setup Email/);
  assert.doesNotMatch(client, /SUPABASE_(?:SERVICE_ROLE|SECRET)_KEY/);
  assert.match(edgeFunction, /profile\?\.app_role !== "admin"/);
  assert.match(edgeFunction, /role !== "editor" && role !== "viewer"/);
  assert.match(edgeFunction, /inviteUserByEmail/);
  assert.match(edgeFunction, /resetPasswordForEmail/);
  assert.match(edgeFunction, /email_confirmed_at/);
});

test("isolates church data and encrypts per-church Planning Center credentials", async () => {
  const tenancy = await readFile(
    new URL("supabase/migrations/20260814230000_add_multi_church_tenancy.sql", root),
    "utf8",
  );
  const sync = await readFile(
    new URL("supabase/functions/planning-center-sync/index.ts", root),
    "utf8",
  );
  const webAdmin = await readFile(
    new URL("app/admin/admin-client.tsx", root),
    "utf8",
  );

  assert.match(tenancy, /create table public\.churches/);
  assert.match(tenancy, /private\.has_church_role\(church_id/);
  assert.match(tenancy, /vault\.create_secret/);
  assert.match(tenancy, /Apple Review Test Church/);
  assert.match(tenancy, /example\.com/);
  assert.match(sync, /get_planning_center_credentials/);
  assert.match(sync, /church_id: churchId/);
  assert.match(webAdmin, /api\.planningcenteronline\.com\/docs\/overview\/authentication/);
  assert.doesNotMatch(webAdmin, /PCO_CLIENT_SECRET/);
});
