import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { readFile } from "node:fs/promises";
import ts from "typescript";
import { renderToStaticMarkup } from "react-dom/server";
import { createElement } from "react";
const context = vm.createContext({ console, URL });
const cache = new Map();
async function load(url) {
  if (cache.has(url.href)) return cache.get(url.href);
  const code = ts.transpileModule(await readFile(url, "utf8"), {
    compilerOptions: {
      module: ts.ModuleKind.ESNext,
      target: ts.ScriptTarget.ES2022,
      jsx: ts.JsxEmit.ReactJSX,
    },
  }).outputText;
  const loadedModule = new vm.SourceTextModule(code, {
    context,
    identifier: url.href,
  });
  cache.set(url.href, loadedModule);
  await loadedModule.link(async (spec) => {
    if (spec.startsWith("."))
      return load(
        new URL(spec.endsWith("admin-shared") ? spec + ".ts" : /\.[cm]?[jt]sx?$/.test(spec) ? spec : spec + ".tsx", url),
      );
    const ns = await import(spec);
    return new vm.SyntheticModule(
      Object.keys(ns),
      function () {
        for (const key of Object.keys(ns)) this.setExport(key, ns[key]);
      },
      { context },
    );
  });
  await loadedModule.evaluate();
  return loadedModule;
}
const { CandidateCard, ContactHistory } = (
  await load(new URL("../../app/admin/placement-workflow.tsx", import.meta.url))
).namespace;
const person = {
  id: "person",
  first_name: "Alice",
  last_name: "Example",
  mobile_phone: "+1 (555) 010-0100",
  home_phone: "555-0101",
  email: "alice@example.invalid",
};
const candidate = {
  id: "candidate",
  opening_id: "opening",
  person_id: "person",
  assigned_to: "editor",
  response: "maybe_later",
  follow_up: "2026-11-01",
  stage: "considering",
};
const opening = {
  id: "opening",
  role_id: "role",
  sub_role_id: "position",
  status: "open",
};
const snapshot = {
  people: [person],
  ministries: [{ id: "role", requires_vote: true }],
  positions: [{ id: "position", requires_vote: true }],
  terms: [],
  assignments: [],
};
const base = {
  candidate,
  person,
  opening,
  title: "Welcome · Leader",
  snapshot,
  staff: [
    { user_id: "editor", display_name: "Editor One", app_role: "editor" },
    { user_id: "admin", display_name: "Administrator", app_role: "admin" },
  ],
  history: [],
  otherCalls: [],
  busy: false,
  defaultExpanded: true,
  command: async () => true,
};
function render(role, changes = {}) {
  return renderToStaticMarkup(
    createElement(CandidateCard, {
      ...base,
      profile: { user_id: role, app_role: role },
      canEdit: role !== "viewer",
      admin: role === "admin",
      ...changes,
    }),
  );
}
test("calling card includes both phones, email, role, response and follow-up", () => {
  const html = render("editor");
  for (const value of [
    "tel:+15550100100",
    "tel:5550101",
    "mailto:alice@example.invalid",
    "Welcome · Leader",
    "Maybe later",
    "Follow up",
    "Editor One",
  ])
    assert.ok(html.includes(value), value);
});
test("editor can record own calls and cannot select another caller or assign calls", () => {
  const html = render("editor");
  assert.ok(html.includes("Save Call to Person"));
  assert.ok(html.includes("Call made by you"));
  assert.ok(!html.includes("Save Assignment"));
  assert.ok(!html.includes("Call made by<select"));
});
test("admin can assign calls and enter the actual caller", () => {
  const html = render("admin");
  assert.ok(html.includes("Save Assignment"));
  assert.ok(html.includes('role="combobox"'));
  assert.ok(html.includes("Call made by"));
  assert.ok(html.includes("Editor One"));
});
test("viewer has contact and history access without mutation controls", () => {
  const html = render("viewer");
  assert.ok(html.includes("tel:"));
  for (const value of [
    "Save Call",
    "Save Assignment",
    "Selection and approval",
  ])
    assert.ok(!html.includes(value));
});
test("willing candidate uses nomination for voted roles and appointment for team members", () => {
  assert.ok(
    render("editor", { candidate: { ...candidate, response: "yes" } }).includes(
      "Nominate — Pending Church Vote",
    ),
  );
  const html = render("editor", {
    candidate: { ...candidate, response: "yes" },
    opening: { ...opening, sub_role_id: null },
  });
  assert.ok(html.includes("Appoint Volunteer"));
  assert.ok(!html.includes("Nominate — Pending"));
});
test("publication confirmation leads directly to the vote", () => {
  assert.ok(
    render("editor", {
      candidate: { ...candidate, stage: "nominated" },
    }).includes("First reading published"),
  );
  assert.ok(
    render("editor", {
      candidate: { ...candidate, stage: "first_reading" },
    }).includes("Vote Passed — Activate"),
  );
  const html = render("editor", {
    candidate: { ...candidate, stage: "second_reading" },
  });
  assert.ok(html.includes("Vote Passed — Activate"));
  assert.ok(html.includes("Vote Did Not Pass"));
});
test("history retains role, response, caller and recorder and safely renders notes", () => {
  const html = renderToStaticMarkup(
    createElement(ContactHistory, {
      entries: [
        {
          id: "history",
          happened_on: "2026-11-01",
          kind: "call",
          response: "no",
          role_label: "Welcome · Leader",
          caller_name: "Former Editor",
          recorder_name: "Admin",
          notes: "<script>private</script>",
          follow_up: null,
        },
      ],
    }),
  );
  for (const value of [
    "Welcome · Leader",
    "Former Editor",
    "Recorded by: Admin",
    "&lt;script&gt;private&lt;/script&gt;",
  ])
    assert.ok(html.includes(value));
  assert.ok(!html.includes("<script>"));
});

test("candidate card starts compact until opened",()=>{const html=render("admin",{defaultExpanded:false});assert.ok(html.includes("Alice Example"));assert.ok(html.includes("Current positions"));assert.ok(html.includes('aria-expanded="false"'));assert.ok(!html.includes("Save Assignment"));assert.ok(!html.includes("Save Call"));});
