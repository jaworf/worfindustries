import test from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';import ts from 'typescript';import {createStagingDatabase} from './staging-database.mjs';
test('matching suggestions explain evidence without treating names or household phones as proof',async()=>{
 const source=ts.transpileModule(await readFile(new URL('../../app/admin/pco-matching-logic.ts',import.meta.url),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText,exports={};new Function('exports',source)(exports);
 const local={first_name:'José',last_name:'Example',email:'Old@example.invalid',home_phone:'(509) 555-0100'};
 const sameName={external_id:'1',first_name:'Jose',last_name:'Example',email:'new@example.invalid'};assert.deepEqual(exports.matchEvidence(local,sameName),['Same first and last name']);assert.equal(exports.matchCategory(local,[sameName]),'Confirm identity');
 const contact={...sameName,email:'old@EXAMPLE.invalid',mobile_phone:'+1 509 555 0100'};assert.equal(exports.matchCategory(local,[contact]),'Contact details match');assert.equal(exports.matchCategory(local,[{...contact,linked_person_id:'different'}]),'Review duplicate');
 assert.equal(exports.matchCategory(local,[{external_id:'2',first_name:'Unrelated',last_name:'Other'}]),'No clear match');assert.deepEqual(exports.matchEvidence({first_name:'A',last_name:'B',home_phone:'+44 1234 567890'},{first_name:'C',last_name:'D',mobile_phone:'+33 1234 567890'}),[]);
});
test('matching workspace and audited links enforce admin, church, freshness and duplicate boundaries',async()=>{
 const db=await createStagingDatabase(),id=n=>'d1000000-0000-4000-8000-'+String(n).padStart(12,'0'),q=(s,a=[])=>db.query(s,a);
 const as=async(n,role='authenticated')=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[n?id(n):'']);await db.exec('set role '+role);};
 const workspace=async(summary=false)=>(await q('select public.planning_center_matching($1) result',[summary])).rows[0].result;
 const record={first_name:'Alex',last_name:'Example',email:'current@example.invalid',mobile_phone:'509-555-0100',home_phone:null,is_active:true};let updated;
 const link=(actor=1,person=300,external='111',version=updated)=>q('select public.link_planning_center_contact($1,$2,$3,$4,$5)',[id(actor),id(person),external,record,version]);
 try{
  await q("insert into public.churches(id,name,slug) values($1,'Matching A','matching-a'),($2,'Matching B','matching-b'),($3,'Not connected','matching-none')",[id(100),id(101),id(102)]);
  for(const[n,role,c]of [[1,'admin',100],[2,'editor',100],[3,'viewer',100],[4,'admin',101],[5,'admin',102]]){await q('insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())',[id(n),'match'+n+'@example.invalid']);await q('update public.profiles set church_id=$1,app_role=$2 where user_id=$3',[id(c),role,id(n)]);}
  await q('insert into private.planning_center_connections(church_id,application_id_secret_id,secret_secret_id) values($1,$3,$3),($2,$3,$3)',[id(100),id(101),id(900)]);
  await q("insert into public.people(id,church_id,first_name,last_name,email,home_phone,notes,is_ordained_elder) values($1,$2,'Alex','Example','old@example.invalid','old number','Private local note',true),($3,$2,'Second','Example',null,null,null,false),($4,$5,'Other Church','Secret',null,null,null,false)",[id(300),id(100),id(301),id(302),id(101)]);
  await q("insert into public.roles(id,church_id,name) values($1,$2,'Welcome')",[id(400),id(100)]);
  await q("insert into public.assignments(church_id,person_id,role_id,status) values($1,$2,$3,'active')",[id(100),id(300),id(400)]);
  await q('insert into public.placement_openings(id,church_id,role_id) values($1,$2,$3)',[id(401),id(100),id(400)]);
  await q('insert into public.placement_candidates(id,church_id,opening_id,person_id) values($1,$2,$3,$4)',[id(402),id(100),id(401),id(300)]);
  await q("insert into public.volunteer_contact_history(church_id,candidate_id,person_id,kind,happened_on,notes,recorded_by,recorder_name,role_label) values($1,$2,$3,'call',current_date,'Keep this call',$4,'Administrator','Welcome')",[id(100),id(402),id(300),id(1)]);
  await q("insert into public.import_runs(id,church_id,source_type,status,completed_at) values($1,$2,'planning_center','completed_with_conflicts',now()),($3,$4,'planning_center','completed',now())",[id(500),id(100),id(501),id(101)]);
  await q("insert into public.import_rows(id,church_id,import_run_id,source_external_id,outcome,raw_record) values($1,$2,$3,'111','conflict',$4),($5,$6,$7,'999','inserted',$8)",[id(600),id(100),id(500),record,id(601),id(101),id(501),{first_name:'Other Church',last_name:'Secret'}]);
  await q("insert into public.import_conflicts(church_id,import_run_id,import_row_id,candidate_person_ids,conflict_type) values($1,$2,$3,$4,'ambiguous_person')",[id(100),id(500),id(600),[id(300)]]);
  updated=(await q('select updated_at::text t from public.people where id=$1',[id(300)])).rows[0].t;
  await as(0,'anon');await assert.rejects(()=>workspace(),/permission denied/);
  for(const n of [2,3]){await as(n);await assert.rejects(()=>workspace(),/Administrator/);assert.equal((await q('select count(*)::int n from public.planning_center_match_audit')).rows[0].n,0);}
  await as(5);assert.deepEqual(await workspace(),{connected:false});
  await as(1);const data=await workspace();assert.equal(data.people.length,2);assert.equal(data.candidates.length,1);assert.doesNotMatch(JSON.stringify(data),/Other Church|Secret|Private local note/);assert.equal((await workspace(true)).unlinked_count,2);await assert.rejects(()=>link(),/permission denied/);
  await as(0,'service_role');await assert.rejects(()=>link(2),/Administrator/);await assert.rejects(()=>link(4),/not in your church/);await assert.rejects(()=>link(1,300,'111','2000-01-01T00:00:00Z'),/changed/);
  const assignments=(await q('select * from public.assignments where person_id=$1',[id(300)])).rows,history=(await q('select * from public.volunteer_contact_history where person_id=$1',[id(300)])).rows;
  await link();const person=(await q('select * from public.people where id=$1',[id(300)])).rows[0];assert.equal(person.email,record.email);assert.equal(person.home_phone,null);assert.equal(person.notes,'Private local note');assert.equal(person.is_ordained_elder,true);assert.deepEqual((await q('select * from public.assignments where person_id=$1',[id(300)])).rows,assignments);assert.deepEqual((await q('select * from public.volunteer_contact_history where person_id=$1',[id(300)])).rows,history);
  assert.equal((await q('select count(*)::int n from public.planning_center_match_audit')).rows[0].n,1);assert.equal((await q('select resolution from public.import_conflicts where import_row_id=$1',[id(600)])).rows[0].resolution,'merge');
  updated=(await q('select updated_at::text t from public.people where id=$1',[id(301)])).rows[0].t;await assert.rejects(()=>link(1,301),/already linked/);
  await as(1);assert.equal((await workspace()).people.length,1);assert.equal((await workspace()).candidates[0].linked_person_id,id(300));
  await as(4);assert.equal((await workspace()).candidates[0].external_id,'999');assert.equal((await q('select count(*)::int n from public.planning_center_match_audit')).rows[0].n,0);
 }finally{await db.close();}
});
