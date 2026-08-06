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
  const page = await readFile(new URL("app/page.tsx", root), "utf8");
  assert.match(page, /SUPABASE_PUBLISHABLE_KEY/);
  assert.doesNotMatch(client, /service[_-]?role/i);
  assert.match(layout, /\/og-blue\.png/);
});
