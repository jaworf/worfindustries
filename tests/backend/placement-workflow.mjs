import { createStagingDatabase } from "./staging-database.mjs";
import assert from "node:assert/strict";
const db = await createStagingDatabase();
let passed = 0;
const ids = {
  church: "10000000-0000-4000-8000-000000000091",
  other: "10000000-0000-4000-8000-000000000092",
  admin: "20000000-0000-4000-8000-000000000091",
  editor: "20000000-0000-4000-8000-000000000092",
  editor2: "20000000-0000-4000-8000-000000000093",
  viewer: "20000000-0000-4000-8000-000000000094",
  outsider: "20000000-0000-4000-8000-000000000095",
};
async function as(user) {
  await db.exec("reset role");
  await db.query(`select set_config('request.jwt.claim.sub',$1,false)`, [user]);
  await db.exec("set role authenticated");
}
async function cmd(action, data) {
  return (
    await db.query("select public.placement_command($1,$2::jsonb) as result", [
      action,
      JSON.stringify(data),
    ])
  ).rows[0].result.id;
}
async function deny(action, data, pattern) {
  await assert.rejects(() => cmd(action, data), pattern);
  passed++;
}
async function count(table) {
  return (await db.query(`select count(*)::int n from public.${table}`)).rows[0]
    .n;
}
try {
  await db.query(
    `insert into public.churches(id,name,slug) values ($1,'Placement Test','placement-test'),($2,'Other Placement','other-placement')`,
    [ids.church, ids.other],
  );
  for (const [key, role] of [
    ["admin", "admin"],
    ["editor", "editor"],
    ["editor2", "editor"],
    ["viewer", "viewer"],
    ["outsider", "admin"],
  ]) {
    await db.query(`insert into auth.users(id,email) values($1,$2)`, [
      ids[key],
      `${key}@placement.invalid`,
    ]);
    await db.query(
      `insert into public.profiles(user_id,church_id,app_role,display_name) values($1,$2,$3,$4) on conflict(user_id) do update set church_id=excluded.church_id,app_role=excluded.app_role,display_name=excluded.display_name`,
      [ids[key], key === "outsider" ? ids.other : ids.church, role, key],
    );
  }
  const role = (
    await db.query(
      `insert into public.roles(church_id,name,requires_vote) values($1,'Placement Ministry',true) returning id`,
      [ids.church],
    )
  ).rows[0].id;
  const position = (
    await db.query(
      `insert into public.sub_roles(church_id,role_id,name,requires_vote) values($1,$2,'Leader',true) returning id`,
      [ids.church, role],
    )
  ).rows[0].id;
  const term = (
    await db.query(
      `insert into public.terms(church_id,name,start_date,end_date) values($1,'Placement Term','2026-11-01','2028-10-31') returning id`,
      [ids.church],
    )
  ).rows[0].id;
  const person = (
    await db.query(
      `insert into public.people(church_id,first_name,last_name,mobile_phone) values($1,'Willing','Volunteer','555-0100') returning id`,
      [ids.church],
    )
  ).rows[0].id;
  const person2 = (
    await db.query(
      `insert into public.people(church_id,first_name,last_name) values($1,'Second','Volunteer') returning id`,
      [ids.church],
    )
  ).rows[0].id;
  const otherPerson = (
    await db.query(
      `insert into public.people(church_id,first_name,last_name) values($1,'Other','Church') returning id`,
      [ids.other],
    )
  ).rows[0].id;
  await as(ids.admin);
  await deny(
    "opening",
    { role_id: role, sub_role_id: position },
    /term is required/,
  );
  const opening = await cmd("opening", {
    role_id: role,
    sub_role_id: position,
    term_id: term,
    quantity: 1,
  });
  await deny(
    "candidate",
    { opening_id: opening, person_id: otherPerson },
    /active person/,
  );
  const candidate = await cmd("candidate", {
    opening_id: opening,
    person_id: person,
  });
  const second = await cmd("candidate", {
    opening_id: opening,
    person_id: person2,
  });
  await deny(
    "candidate",
    { opening_id: opening, person_id: person },
    /duplicate key/,
  );
  await deny("nominate", { candidate_id: candidate }, /willingness/);
  await deny(
    "assign_call",
    { candidate_id: candidate, caller_id: ids.viewer },
    /active administrator or editor/,
  );
  await deny(
    "assign_call",
    { candidate_id: candidate, caller_id: ids.outsider },
    /active administrator or editor/,
  );
  await cmd("assign_call", {
    candidate_id: candidate,
    caller_id: ids.editor,
    follow_up: "2026-11-03",
  });
  await as(ids.editor);
  await deny(
    "assign_call",
    { candidate_id: candidate, caller_id: ids.editor2 },
    /Only administrators/,
  );
  await deny(
    "call",
    { candidate_id: candidate, caller_id: ids.editor2, response: "no" },
    /only record calls they made/,
  );
  await deny("call", { candidate_id: candidate, response: "other" }, /Explain/);
  await deny(
    "call",
    { candidate_id: candidate, response: "yes", date: "2099-01-01" },
    /future date/,
  );
  await deny(
    "call",
    {
      candidate_id: candidate,
      response: "maybe_later",
      date: "2026-11-02",
      follow_up: "2026-11-01",
    },
    /before the call/,
  );
  for (const response of [
    "no",
    "maybe_later",
    "other",
    "no_answer",
    "message_left",
    "considering",
    "yes",
  ]) {
    await cmd("call", {
      candidate_id: candidate,
      response,
      notes: "Factual response",
      date: "2026-11-02",
    });
  }
  assert.equal(
    (
      await db.query(
        `select count(*)::int n from public.volunteer_contact_history where candidate_id=$1 and kind='call'`,
        [candidate],
      )
    ).rows[0].n,
    7,
  );
  passed++;
  await cmd("call", {
    candidate_id: candidate,
    response: "no",
    date: "2026-11-01",
  });
  assert.equal(
    (
      await db.query(
        `select response from public.placement_candidates where id=$1`,
        [candidate],
      )
    ).rows[0].response,
    "yes",
  );
  passed++;
  await as(ids.admin);
  await cmd("call", {
    candidate_id: second,
    caller_id: ids.editor2,
    response: "yes",
    date: "2026-11-02",
  });
  const entry = (
    await db.query(
      `select * from public.volunteer_contact_history where candidate_id=$1 and kind='call'`,
      [second],
    )
  ).rows[0];
  assert.equal(entry.caller_id, ids.editor2);
  assert.equal(entry.recorded_by, ids.admin);
  assert.equal(entry.caller_name, "editor2");
  passed++;
  await deny("appoint", { candidate_id: candidate }, /requires nomination/);
  await cmd("nominate", { candidate_id: candidate, date: "2026-11-01" });
  assert.equal(await count("assignments"), 0);
  passed++;
  await cmd("nominate", { candidate_id: second });
  await cmd("withdraw", { candidate_id: second });
  passed++;
  await deny("vote_passed", { candidate_id: candidate }, /first reading publication/);
  await deny("cancel_opening", { opening_id: opening }, /Withdraw pending/);
  await cmd("first_reading", { candidate_id: candidate, date: "2026-11-01" });
  assert.equal((await db.query("select stage from public.placement_candidates where id=$1", [candidate])).rows[0].stage, "first_reading"); passed++;
  await cmd("unpublish_first_reading", {candidate_id:candidate});
  await deny("vote_passed", {candidate_id:candidate}, /first reading publication/);
  await cmd("first_reading", {candidate_id:candidate});
  // The vote itself confirms the second reading; no separate date entry.

  await cmd("defer", { candidate_id: candidate });
  await deny("vote_passed", { candidate_id: candidate }, /first reading publication/);
  await cmd("resume", { candidate_id: candidate });
  await cmd("call", {
    candidate_id: candidate,
    response: "no",
    date: "2026-11-02",
  });
  await deny(
    "vote_passed",
    { candidate_id: candidate, date: "2026-11-02" },
    /current willingness/,
  );
  await cmd("call", {
    candidate_id: candidate,
    response: "yes",
    date: "2026-11-02",
  });
  await cmd("vote_passed", { candidate_id: candidate, date: "2026-11-02" });
  assert.equal(await count("assignments"), 1);
  passed++;
  assert.equal(
    (
      await db.query(
        `select status from public.placement_openings where id=$1`,
        [opening],
      )
    ).rows[0].status,
    "open",
  );
  passed++;
  await deny("vote_passed", { candidate_id: candidate }, /closed/);
  const teamOpening = await cmd("opening", { role_id: role, quantity: 2 });
  const teamCandidate = await cmd("candidate", {
    opening_id: teamOpening,
    person_id: person,
  });
  await cmd("call", { candidate_id: teamCandidate, response: "yes" });
  await deny("nominate", { candidate_id: teamCandidate }, /appointment/);
  await cmd("appoint", { candidate_id: teamCandidate });
  assert.equal(await count("assignments"), 2);
  passed++;
  assert.equal(
    (
      await db.query(
        `select status from public.placement_openings where id=$1`,
        [teamOpening],
      )
    ).rows[0].status,
    "open",
  );
  passed++;
  const withdrawCandidate = await cmd("candidate", {
    opening_id: teamOpening,
    person_id: person2,
  });
  await cmd("call", {
    candidate_id: withdrawCandidate,
    response: "no",
    notes: "Unavailable this term",
  });
  await cmd("withdraw", { candidate_id: withdrawCandidate });
  await cmd("cancel_opening", { opening_id: teamOpening });
  assert.ok(
    (
      await db.query(
        `select count(*)::int n from public.volunteer_contact_history where person_id=$1`,
        [person2],
      )
    ).rows[0].n >= 3,
  );
  passed++;
  await cmd("finish_opening", {opening_id:opening});
  const duplicateOpening = await cmd("opening", {role_id:role, sub_role_id:position, term_id:term});
  const duplicateCandidate = await cmd("candidate", {opening_id:duplicateOpening, person_id:person});
  await cmd("call", {candidate_id:duplicateCandidate, response:"yes"});
  await cmd("nominate", {candidate_id:duplicateCandidate, date:"2026-11-01"});
  await cmd("first_reading", {candidate_id:duplicateCandidate, date:"2026-11-01"});
  await cmd("second_reading", {candidate_id:duplicateCandidate, date:"2026-11-02"});
  await deny("vote_passed", {candidate_id:duplicateCandidate}, /duplicate key/);
  assert.equal((await db.query("select stage from public.placement_candidates where id=$1", [duplicateCandidate])).rows[0].stage, "second_reading"); passed++;
  await cmd("withdraw", {candidate_id:duplicateCandidate});
  const unsuccessful = await cmd("candidate", {opening_id:duplicateOpening, person_id:person2});
  await cmd("call", {candidate_id:unsuccessful, response:"yes"});
  await cmd("nominate", {candidate_id:unsuccessful, date:"2026-11-01"});
  await cmd("first_reading", {candidate_id:unsuccessful, date:"2026-11-01"});
  await cmd("second_reading", {candidate_id:unsuccessful, date:"2026-11-02"});
  await cmd("vote_failed", {candidate_id:unsuccessful});
  assert.equal((await db.query("select status from public.placement_openings where id=$1", [duplicateOpening])).rows[0].status, "open"); passed++;
  assert.equal(await count("assignments"), 2); passed++;
  await as(ids.viewer);
  await deny(
    "call",
    { candidate_id: candidate, response: "no" },
    /Administrator or editor/,
  );
  assert.equal(await count("placement_openings"), 3);
  passed++;
  await assert.rejects(
    () =>
      db.query(
        `update public.placement_candidates set response='yes' where id=$1`,
        [candidate],
      ),
    /permission denied/,
  );
  passed++;
  await assert.rejects(
    () => db.exec(`delete from public.volunteer_contact_history`),
    /permission denied/,
  );
  passed++;
  await as(ids.outsider);
  for (const table of [
    "placement_openings",
    "placement_candidates",
    "volunteer_contact_history",
  ]) {
    assert.equal(await count(table), 0);
    passed++;
  }
  await deny("call", { candidate_id: candidate, response: "no" }, /not found/);
  const staff = (await db.query(`select public.placement_staff() staff`))
    .rows[0].staff;
  assert.equal(staff.length, 1);
  assert.equal(staff[0].user_id, ids.outsider);
  passed++;
  await db.exec("reset role; set role anon");
  await assert.rejects(
    () => db.exec("select * from public.volunteer_contact_history"),
    /permission denied/,
  );
  passed++;
  await assert.rejects(
    () => db.query(`select public.placement_command('opening','{}')`),
    /permission denied/,
  );
  passed++;
  await db.exec("reset role");
  await db.query("delete from auth.users where id=$1", [ids.editor2]);
  const retained = (await db.query("select caller_id, caller_name, recorder_name from public.volunteer_contact_history where candidate_id=$1 and kind='call'", [second])).rows[0];
  assert.equal(retained.caller_id, null);
  assert.equal(retained.caller_name, "editor2");
  assert.equal(retained.recorder_name, "admin");
  passed++;
  console.log(`PASS: ${passed} placement workflow and permission checks`);
} finally {
  await db.close();
}
