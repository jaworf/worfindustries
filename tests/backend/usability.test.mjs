import test from "node:test";
import assert from "node:assert/strict";
import { createStagingDatabase } from "./staging-database.mjs";
test("flexible openings, duplicate/trash protection, safe account linking and newest eligible 100", async () => {
  const db = await createStagingDatabase();
  const id = (n) => "71000000-0000-4000-8000-" + String(n).padStart(12, "0");
  const q = (sql, args = []) => db.query(sql, args);
  const auth = async (n) => {
    await db.exec("reset role");
    await q("select set_config('request.jwt.claim.sub',$1,false)", [id(n)]);
    await db.exec("set role authenticated");
  };
  const rpc = async (name, args = {}) => {
    const k = Object.keys(args);
    return (
      await q(
        "select public." +
          name +
          "(" +
          k.map((x, i) => x + "=> $" + (i + 1)).join(",") +
          ") result",
        k.map((x) => args[x]),
      )
    ).rows[0].result;
  };
  const cmd = (p_action, p_data) =>
    rpc("placement_command", { p_action, p_data });
  try {
    await q(
      "insert into public.churches(id,name,slug) values($1,'Usability Church','usability-test'),($2,'Other Church','usability-other')",
      [id(100), id(101)],
    );
    await q(
      "insert into public.people(id,church_id,first_name,last_name,email,mobile_phone) values($1,$2,'Real','Caller','real@example.invalid','555-0100'),($3,$4,'Other','Person','real@example.invalid','555-9999'),($5,$2,'Shared','One','shared@example.invalid','555-0101'),($6,$2,'Shared','Two','shared@example.invalid','555-0102')",
      [id(10), id(100), id(11), id(101), id(12), id(13)],
    );
    for (const [n, email, role] of [
      [1, "real@example.invalid", "admin"],
      [2, "shared@example.invalid", "editor"],
      [3, "viewer@example.invalid", "viewer"],
    ]) {
      await q(
        "insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())",
        [id(n), email],
      );
      await q(
        "update public.profiles set church_id=$1,app_role=$2 where user_id=$3",
        [id(100), role, id(n)],
      );
    }
    const linked = (
      await q("select * from public.profiles where user_id=$1", [id(1)])
    ).rows[0];
    assert.equal(linked.person_id, id(10));
    assert.equal(linked.display_name, "Real Caller");
    assert.equal(linked.phone, "555-0100");
    assert.equal(
      (
        await q("select person_id from public.profiles where user_id=$1", [
          id(2),
        ])
      ).rows[0].person_id,
      null,
    );
    await auth(2);
    await assert.rejects(
      () =>
        rpc("complete_staff_profile", {
          p_first_name: "New",
          p_last_name: "Editor",
          p_phone: "",
        }),
      /phone/,
    );
    await rpc("complete_staff_profile", {
      p_first_name: "New",
      p_last_name: "Editor",
      p_phone: "555-0123",
    });
    assert.equal(
      (
        await q("select display_name from public.profiles where user_id=$1", [
          id(2),
        ])
      ).rows[0].display_name,
      "New Editor",
    );
    await assert.rejects(
      () =>
        q("update public.profiles set app_role='admin' where user_id=$1", [
          id(2),
        ]),
      /permission denied/,
    );
    await auth(1);
    const o = await cmd("opening", {
      new_role_name: "New Ministry",
      new_position_name: "Helper",
    });
    const opening = (
      await q("select * from public.placement_openings where id=$1", [o.id])
    ).rows[0];
    assert.ok(opening.sub_role_id);
    await assert.rejects(
      () =>
        cmd("opening", {
          new_role_name: "new ministry",
          new_position_name: "helper",
        }),
      /already exists/,
    );
    const voted = await cmd("opening", {
      new_role_name: "New Voted Ministry",
      new_position_name: "Chair",
      new_position_vote: true,
      new_term_name: "2027-2028",
      term_start: "2027-01-01",
      term_end: "2028-12-31",
    });
    assert.ok(
      (
        await q("select term_id from public.placement_openings where id=$1", [
          voted.id,
        ])
      ).rows[0].term_id,
    );
    for (const person_id of [id(10), id(12)]) {
      const c = await cmd("candidate", { opening_id: o.id, person_id });
      await cmd("call", { candidate_id: c.id, response: "yes" });
      await cmd("appoint", { candidate_id: c.id });
    }
    assert.equal(
      (
        await q("select status from public.placement_openings where id=$1", [
          o.id,
        ])
      ).rows[0].status,
      "open",
    );
    assert.equal(
      (
        await q(
          "select count(*)::int n from public.assignments where role_id=$1",
          [opening.role_id],
        )
      ).rows[0].n,
      2,
    );
    await cmd("finish_opening", { opening_id: o.id });
    await cmd("restore_opening", { opening_id: o.id });
    await cmd("cancel_opening", { opening_id: o.id });
    const duplicate = await cmd("opening", {
      role_id: opening.role_id,
      sub_role_id: opening.sub_role_id,
    });
    await assert.rejects(
      () => cmd("restore_opening", { opening_id: o.id }),
      /already exists/,
    );
    await cmd("cancel_opening", { opening_id: duplicate.id });
    await cmd("restore_opening", { opening_id: o.id });
    await db.exec("reset role");
    // 130 eligible people plus newer ineligible/assigned/different-church fixtures.
    for (let n = 0; n < 130; n++) {
      await q(
        "insert into public.people(id,church_id,first_name,last_name,membership_status,source_created_at) values($1,$2,$3,'Newest','Member',$4)",
        [
          id(1000 + n),
          id(100),
          "Person " + n,
          new Date(Date.UTC(2026, 0, 1 + n)).toISOString(),
        ],
      );
      await q(
        "insert into public.person_external_ids(church_id,person_id,source_system,external_id) values($1,$2,'planning_center',$3)",
        [id(100), id(1000 + n), "pco-" + n],
      );
    }
    await q(
      "update public.people set membership_status='Visitor' where id=$1",
      [id(1129)],
    );
    await q(
      "insert into public.assignments(church_id,person_id,role_id,status) values($1,$2,$3,'active')",
      [id(100), id(1128), opening.role_id],
    );
    await auth(1);
    await rpc("save_focus_memberships", { p_statuses: ["member"] });
    const recent = await rpc("volunteer_activation");
    assert.equal(recent.length, 100);
    assert.equal(recent[0].id, id(1127));
    assert.equal(recent.at(-1).id, id(1028));
    assert.ok(
      recent.every(
        (p) => p.church_id === id(100) && p.membership_status === "Member",
      ),
    );
    await db.exec("reset role;set role service_role");
    await rpc("cache_pco_membership_types", {
      p_church_id: id(100),
      p_values: ["Member", "Visitor", "Newcomer"],
    });
    await auth(1);
    assert.ok((await rpc("focus_preferences")).options.includes("Newcomer"));
    await auth(3);
    await rpc("complete_staff_profile", {
      p_first_name: "New",
      p_last_name: "Viewer",
      p_phone: "555-0188",
    });
    const created = (
      await q(
        "select p.is_public,p.mobile_phone from public.profiles u join public.people p on p.id=u.person_id where u.user_id=$1",
        [id(3)],
      )
    ).rows[0];
    assert.equal(created.is_public, false);
    assert.equal(created.mobile_phone, "555-0188");
    await assert.rejects(
      () => rpc("save_focus_memberships", { p_statuses: ["Visitor"] }),
      /Administrator/,
    );
    assert.equal((await rpc("volunteer_activation")).length, 100);
    await assert.rejects(
      () =>
        rpc("cache_pco_membership_types", {
          p_church_id: id(100),
          p_values: ["Visitor"],
        }),
      /permission denied/,
    );
  } finally {
    await db.close();
  }
});
