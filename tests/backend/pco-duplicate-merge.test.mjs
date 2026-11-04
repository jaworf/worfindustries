import test from 'node:test';import assert from 'node:assert/strict';import {createStagingDatabase} from './staging-database.mjs';
test('duplicate merging preserves histories and links, resolves overlaps explicitly and rejects unsafe or stale requests',async()=>{
 const db=await createStagingDatabase(),id=n=>'e2000000-0000-4000-8000-'+String(n).padStart(12,'0'),q=(s,a=[])=>db.query(s,a),rows=async(s,a=[])=>(await q(s,a)).rows;
 const as=async(n,role='service_role')=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[n?id(n):'']);await db.exec('set role '+role);};
 const review=async(actor=1,source=300,external='111')=>(await rows('select public.review_planning_center_duplicate($1,$2,$3) result',[id(actor),id(source),external]))[0].result;
 const record={first_name:'Taylor',last_name:'Example',email:'current@example.invalid',mobile_phone:'555-0101',is_active:true};
 const merge=(rev,choices={},actor=1,source=300,external='111')=>q('select public.merge_planning_center_duplicate($1,$2,$3,$4,$5,$6)',[id(actor),id(source),external,record,rev,choices]);
 try{
  const dependencies=(await rows("select distinct conrelid::regclass::text child from pg_constraint where confrelid='public.people'::regclass order by 1")).map(r=>r.child);
  assert.deepEqual(dependencies,['assignments','discovery_memberships','import_rows','person_external_ids','person_merge_audit','placement_candidates','planning_center_match_audit','profiles','volunteer_contact_history']);
  await q("insert into public.churches(id,name,slug) values($1,'Merge A','merge-a'),($2,'Merge B','merge-b')",[id(100),id(101)]);
  for(const[n,role,church]of [[1,'admin',100],[2,'editor',100],[3,'viewer',100],[4,'admin',101]]){await q('insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())',[id(n),'merge'+n+'@example.invalid']);await q('update public.profiles set church_id=$1,app_role=$2,display_name=$3 where user_id=$4',[id(church),role,'Staff '+n,id(n)]);}
  await q('insert into private.planning_center_connections(church_id,application_id_secret_id,secret_secret_id) values($1,$3,$3),($2,$3,$3)',[id(100),id(101),id(900)]);
  await q("insert into public.people(id,church_id,first_name,last_name,notes,is_ordained_elder,is_public) values($1,$4,'Taylor','Example','Source note',true,false),($2,$4,'Taylor','Example','Target note',false,true),($3,$5,'Other','Church',null,false,true)",[id(300),id(301),id(302),id(100),id(101)]);
  await q("insert into public.person_external_ids(id,church_id,person_id,source_system,external_id) values($1,$3,$4,'planning_center','111'),($2,$3,$5,'members_csv','original-member')",[id(310),id(311),id(100),id(301),id(300)]);
  await q("insert into public.roles(id,church_id,name) values($1,$4,'Welcome'),($2,$4,'Music'),($3,$4,'Teaching')",[id(400),id(401),id(402),id(100)]);
  for(const[n,person,role,status,note]of [[500,300,400,'completed','Source assignment note'],[501,301,400,'active','Target assignment note'],[502,300,401,'active','Music note'],[503,301,402,'active','Teaching note']])await q('insert into public.assignments(id,church_id,person_id,role_id,status,notes) values($1,$2,$3,$4,$5,$6)',[id(n),id(100),id(person),id(role),status,note]);
  await q("insert into public.assignment_external_ids(church_id,assignment_id,source_system,external_id) values($1,$2,'assignments_csv','keep-external')",[id(100),id(500)]);
  for(const[n,role]of [[600,400],[601,401],[602,402]])await q('insert into public.placement_openings(id,church_id,role_id) values($1,$2,$3)',[id(n),id(100),id(role)]);
  for(const[n,person,opening,stage,assignment]of [[700,300,600,'withdrawn',500],[701,301,600,'nominated',501],[702,300,601,'appointed',502],[703,301,602,'considering',null]])await q("insert into public.placement_candidates(id,church_id,opening_id,person_id,stage,response,assigned_to,assignment_id) values($1,$2,$3,$4,$5,'yes',$6,$7)",[id(n),id(100),id(opening),id(person),stage,id(2),assignment?id(assignment):null]);
  for(const[n,person,candidate]of [[800,300,700],[801,301,701],[802,300,702],[803,301,703]])await q("insert into public.volunteer_contact_history(id,church_id,candidate_id,person_id,kind,happened_on,response,notes,recorded_by,recorder_name,role_label) values($1,$2,$3,$4,'call',current_date,'yes',$5,$6,'Staff 1','Welcome')",[id(n),id(100),id(candidate),id(person),'Original call '+n,id(1)]);
  await q('update public.profiles set person_id=$1 where user_id=$2',[id(300),id(2)]);
  await q("insert into public.discovery_memberships(id,church_id,user_id,person_id,first_name,last_name,consent_version) values($1,$2,$3,$4,'Taylor','Example','v1')",[id(850),id(100),id(2),id(300)]);
  await q('insert into public.discovery_profiles(membership_id,church_id,submitted) values($1,$2,$3)',[id(850),id(100),{skills:'Preserved assessment profile'}]);
  await q("insert into public.import_runs(id,church_id,source_type) values($1,$2,'members_csv')",[id(860),id(100)]);
  await q("insert into public.import_rows(id,church_id,import_run_id,person_id,assignment_id,outcome) values($1,$2,$3,$4,$5,'updated')",[id(861),id(100),id(860),id(300),id(500)]);
  await q("insert into public.import_conflicts(church_id,import_run_id,import_row_id,candidate_person_ids,conflict_type) values($1,$2,$3,$4,'ambiguous_person')",[id(100),id(860),id(861),[id(300),id(301)]]);
  await as(0,'anon');await assert.rejects(()=>review(),/permission denied/);await assert.rejects(()=>merge('x'),/permission denied/);
  await as(1,'authenticated');await assert.rejects(()=>review(),/permission denied/);await assert.rejects(()=>merge('x'),/permission denied/);
  await as(0);for(const actor of [2,3,4])await assert.rejects(()=>review(actor),/Administrator|not in your church/);
  await assert.rejects(()=>review(1,302),/not in your church/);
  await assert.rejects(()=>merge('x',{},2),/Administrator/);
  let r=await review();assert.equal(r.target_id,id(301));assert.equal(r.snapshot.calls.length,4);assert.equal(r.snapshot.assignments.length,4);assert.deepEqual(r.blockers,[]);
  // No partial writes if a later overlap has no explicit choice.
  await assert.rejects(()=>merge(r.merge_revision),/overlapping ministry/);
  assert.equal((await rows('select count(*)::int n from public.person_merge_audit'))[0].n,0);
  const choices={assignments:{[id(500)]:id(501)},candidates:{[id(700)]:id(701)}};
  await assert.rejects(()=>merge(r.merge_revision,{assignments:choices.assignments}),/overlapping placement/);
  assert.equal((await rows('select count(*)::int n from public.assignments where church_id=$1',[id(100)]))[0].n,4);
  await q('update public.volunteer_contact_history set notes=$1 where id=$2',['Changed during review',id(800)]);
  await assert.rejects(()=>merge(r.merge_revision,choices),/records changed/);
  r=await review();
  // Two Discovery identities are never silently combined or reassigned.
  await q("insert into public.discovery_memberships(id,church_id,user_id,person_id,first_name,last_name,consent_version) values($1,$2,$3,$4,'Taylor','Example','v1')",[id(851),id(100),id(3),id(301)]);
  const blocked=await review();assert.equal(blocked.blockers.length,1);await assert.rejects(()=>merge(blocked.merge_revision,choices),/separate Ministry Discovery/);
  await q('delete from public.discovery_memberships where id=$1',[id(851)]);r=await review();
  const calls=await rows('select id,notes,caller_id,recorded_by,response,happened_on from public.volunteer_contact_history order by id');
  await merge(r.merge_revision,choices);
  assert.equal((await rows('select count(*)::int n from public.people where id=$1',[id(300)]))[0].n,0);
  const person=(await rows('select * from public.people where id=$1',[id(301)]))[0];assert.equal(person.email,record.email);assert.equal(person.is_ordained_elder,true);assert.equal(person.is_public,false);assert.equal(person.notes,'Target note\n\nSource note');
  assert.equal((await rows('select count(*)::int n from public.assignments where person_id=$1',[id(301)]))[0].n,3);
  const shared=(await rows('select * from public.assignments where id=$1',[id(501)]))[0];assert.equal(shared.status,'active');assert.equal(shared.notes,'Target assignment note\n\nSource assignment note');
  assert.deepEqual(await rows('select id,notes,caller_id,recorded_by,response,happened_on from public.volunteer_contact_history order by id'),calls);
  assert.equal((await rows('select count(*)::int n from public.volunteer_contact_history where person_id=$1',[id(301)]))[0].n,4);
  assert.equal((await rows('select candidate_id from public.volunteer_contact_history where id=$1',[id(800)]))[0].candidate_id,id(701));
  assert.equal((await rows('select assignment_id from public.assignment_external_ids where external_id=$1',['keep-external']))[0].assignment_id,id(501));
  assert.equal((await rows("select person_id from public.person_external_ids where source_system='planning_center'"))[0].person_id,id(301));
  assert.equal((await rows('select count(*)::int n from public.person_external_ids where person_id=$1',[id(301)]))[0].n,2);
  assert.equal((await rows('select person_id from public.profiles where user_id=$1',[id(2)]))[0].person_id,id(301));
  assert.equal((await rows('select person_id from public.discovery_memberships where id=$1',[id(850)]))[0].person_id,id(301));
  assert.equal((await rows('select submitted from public.discovery_profiles where membership_id=$1',[id(850)]))[0].submitted.skills,'Preserved assessment profile');
  const imported=(await rows('select * from public.import_rows where id=$1',[id(861)]))[0];assert.equal(imported.person_id,id(301));assert.equal(imported.assignment_id,id(501));
  const audit=(await rows('select * from public.person_merge_audit'))[0];assert.deepEqual(audit.snapshot,r.snapshot);assert.deepEqual(audit.choices,choices);assert.equal(audit.removed_person_id,id(300));assert.equal(audit.survivor_id,id(301));
  await assert.rejects(()=>merge(r.merge_revision,choices),/not in your church/);
  for(const n of [2,3,4]){await as(n,'authenticated');assert.equal((await rows('select count(*)::int n from public.person_merge_audit'))[0].n,0);}
  await as(1,'authenticated');assert.equal((await rows('select count(*)::int n from public.person_merge_audit'))[0].n,1);
  await as(0);
  // Choosing the source overlap must remap its assignment reference before
  // applying candidate details. Distinct assignments retain their original IDs.
  await q("insert into public.people(id,church_id,first_name,last_name) values($1,$3,'Jamie','Example'),($2,$3,'Jamie','Example')",[id(303),id(304),id(100)]);
  await q("insert into public.person_external_ids(church_id,person_id,source_system,external_id) values($1,$2,'planning_center','222')",[id(100),id(304)]);
  for(const[n,person,role]of [[510,303,400],[511,304,400],[512,303,401]])await q("insert into public.assignments(id,church_id,person_id,role_id,status,notes,vote_date,first_reading_published) values($1,$2,$3,$4,'active',$5,$6,$7)",[id(n),id(100),id(person),id(role),'Assignment '+n,n===510?'2026-10-01':null,n===510]);
  for(const[n,person,opening,assignment,stage]of [[710,303,600,510,'elected'],[711,304,600,511,'nominated'],[712,303,601,512,'appointed']])await q("insert into public.placement_candidates(id,church_id,person_id,opening_id,assignment_id,stage,response) values($1,$2,$3,$4,$5,$6,'yes')",[id(n),id(100),id(person),id(opening),id(assignment),stage]);
  const next=await review(1,303,'222');
  await q('update public.profiles set must_change_password=true where user_id=$1',[id(1)]);await assert.rejects(()=>merge(next.merge_revision,{},1,303,'222'),/Administrator/);await q('update public.profiles set must_change_password=false where user_id=$1',[id(1)]);
  const nextChoices={assignments:{[id(510)]:id(510)},candidates:{[id(710)]:id(710)}};
  await merge(next.merge_revision,nextChoices,1,303,'222');
  const selected=(await rows('select * from public.assignments where id=$1',[id(511)]))[0];assert.equal(new Date(selected.vote_date).toISOString().slice(0,10),'2026-10-01');assert.equal(selected.first_reading_published,true);
  const candidate=(await rows('select * from public.placement_candidates where id=$1',[id(711)]))[0];assert.equal(candidate.stage,'elected');assert.equal(candidate.assignment_id,id(511));
  assert.equal((await rows('select person_id from public.assignments where id=$1',[id(512)]))[0].person_id,id(304));assert.equal((await rows('select person_id from public.placement_candidates where id=$1',[id(712)]))[0].person_id,id(304));
  // Previously unlinked selections no longer appear after consolidation.
  await as(1,'authenticated');const workspace=(await rows('select public.planning_center_matching(false) data'))[0].data;assert(!workspace.people.some(p=>[id(300),id(303)].includes(p.id)));

 }finally{await db.close();}
});
