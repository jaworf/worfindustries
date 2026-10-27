
import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {createRequire} from "node:module";
import ts from "typescript";
import {createStagingDatabase} from "./staging-database.mjs";
const require=createRequire(import.meta.url);
const content=JSON.parse(await readFile(new URL("../../app/discovery/content.json",import.meta.url),"utf8"));
function compile(file,dependencies={}){
 const source=ts.transpileModule(file,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,esModuleInterop:true}}).outputText;
 const exports={};new Function("exports","require",source)(exports,id=>id in dependencies?dependencies[id]:require(id));return exports;
}
const core=compile(await readFile(new URL("../../app/discovery/core.ts",import.meta.url),"utf8"),{"./content.json":content});
const answer=(kind,n)=>Object.fromEntries(content.questions[kind].map(q=>[q.id,n]));
test("approved content, score direction and every report branch",()=>{
 assert.equal(content.questions.bigfive.length,120);assert.equal(content.questions.motivations.length,30);
 assert.equal(content.questions.bigfive.find(q=>q.id==="O6-1").text,"Enjoy considering viewpoints that challenge my assumptions.");
 for(const kind of ["bigfive","motivations"]){
  for(const n of [1,2,3,4,5,null]){
   const a=answer(kind,n),scores=core.score(kind,a);
   const attempt={kind,version:content.version,answers:a,scores,submitted_at:"2026-10-26T12:00:00Z"};
   const sections=core.reportSections(attempt,"Test Church",true);
   assert(sections.length>5);assert(sections.every(s=>!s.text.includes("{{")));
   assert(!sections.some(s=>s.text.includes("Consider concrete examples before drawing conclusions")));
   if(n===null)assert(Object.values(scores.domains).every(v=>v===null));
   if(kind==="motivations"&&n===3){assert(sections.some(s=>s.id==="MM-ALL-EQUAL"));assert(!sections.some(s=>s.id==="MM-PRIMARY"));}
  }
 }
 const answers=Object.fromEntries(content.questions.bigfive.map(q=>[q.id,q.key==="+"?1:5]));
 assert.equal(core.score("bigfive",answers).domains.N,5);
 assert.equal(core.score("bigfive",answers).domains.C,1);
 assert.throws(()=>core.score("bigfive",{bad:5}),/Unknown/);
 assert.throws(()=>core.score("bigfive",{"N1-1":6}),/Invalid/);
 for(const a of ["A","P","E","S","T"])for(const b of ["A","P","E","S","T"]){
 if(a===b)continue;
 const x=Object.fromEntries(content.questions.motivations.map(q=>[q.id,q.scale===a?5:q.scale===b?4:2]));
 const report=core.reportSections({kind:"motivations",version:content.version,answers:x,scores:core.score("motivations",x),submitted_at:"2026-10-26T12:00:00Z"},"Example");
 assert.equal(report.filter(s=>s.id.startsWith("MM-PAIR-")).length,1);
 assert(report.some(s=>s.id==="MM-"+a+"-PRIMARY"));assert(report.some(s=>s.id==="MM-"+b+"-SECONDARY"));
 }
});
test("Postgres participant isolation, matching, scoring, and registration controls",async()=>{
 const db=await createStagingDatabase();
 const uid=n=>"10000000-0000-4000-8000-"+String(n).padStart(12,"0");
 const query=(sql,args=[])=>db.query(sql,args);
 const auth=async(n,role="authenticated")=>{await db.exec("reset role;set role "+role);await query("select set_config('request.jwt.claim.sub',$1,false)",[n?uid(n):""]);};
 const rpc=async(name,args)=>{const keys=Object.keys(args);return (await query("select public."+name+"("+keys.map((k,i)=>k+" => $"+(i+1)).join(",")+") as result",keys.map(k=>args[k]))).rows[0].result;};
 try{
 const churches=(await query("select id,slug from public.churches order by slug")).rows;const ca=churches.find(c=>c.slug==="riverview").id,cb=churches.find(c=>c.slug==="apple-review").id;
 for(let n=1;n<=4;n++)await query("insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())",[uid(n),"person"+n+"@test.example"]);
 await query("update public.profiles set app_role='admin',church_id=$1,must_change_password=false where user_id=$2",[ca,uid(1)]);
 await query("update public.profiles set app_role='admin',church_id=$1,must_change_password=false where user_id=$2",[cb,uid(2)]);
 await auth(1);const sa=await rpc("discovery_registration",{});await auth(2);const sb=await rpc("discovery_registration",{});
 assert.equal(sa.token.length,64);assert.notEqual(sa.token,sb.token);
 await auth(null,"anon");assert.equal((await rpc("discovery_public_church",{p_token:sa.token})).id,ca);
 await assert.rejects(()=>rpc("discovery_staff_search",{}));
 await auth(3);const ma=await rpc("discovery_enroll",{p_token:sa.token,p_first_name:"Alex",p_last_name:"Member",p_consent:true});assert.equal(ma.person_id,null);
 await assert.rejects(()=>rpc("discovery_enroll",{p_token:sa.token,p_first_name:"Alex",p_last_name:"Member",p_consent:false}));
 const profile={connection:"A member",service:"Previous service",joy:"Helping",abilities:"Photography",hope:"Serve",occupation:"",interests:"Media",skills:[{name:"Photography",experience:"Experienced",interest:"Possibly later",notes:"Church picnic"}],availability:"limited",contact:"later",review_date:""};
 await rpc("discovery_save_profile",{p_member:ma.id,p_data:profile,p_revision:0,p_submit:true});
 await assert.rejects(()=>rpc("discovery_save_profile",{p_member:ma.id,p_data:profile,p_revision:0,p_submit:true}),/changed/);
 for(const kind of ["bigfive","motivations"]){
 const a=Object.fromEntries(content.questions[kind].map((q,i)=>[q.id,1+(i%5)]));
 const result=await rpc("discovery_save_assessment",{p_member:ma.id,p_kind:kind,p_answers:a,p_revision:0,p_submit:true,p_new_attempt:false});
 const expected=core.score(kind,a);
 for(const section of ["scales","domains"])for(const [key,value]of Object.entries(expected[section]))assert(Math.abs(result.scores[section][key]-value)<1e-9);
 await assert.rejects(()=>rpc("discovery_save_assessment",{p_member:ma.id,p_kind:kind,p_answers:a,p_revision:0,p_submit:true,p_new_attempt:false}),/new attempt/);
 }
 await assert.rejects(()=>rpc("discovery_save_assessment",{p_member:ma.id,p_kind:"bigfive",p_answers:{unknown:5},p_revision:0,p_submit:false,p_new_attempt:true}),/Unknown/);
 await assert.rejects(()=>rpc("discovery_save_assessment",{p_member:ma.id,p_kind:"bigfive",p_answers:{"N1-1":6},p_revision:0,p_submit:false,p_new_attempt:true}),/whole-number/);
 await rpc("discovery_save_profile",{p_member:ma.id,p_data:{...profile,joy:"PRIVATE DRAFT"},p_revision:1,p_submit:false});
 await auth(4);const mb=await rpc("discovery_enroll",{p_token:sb.token,p_first_name:"Other",p_last_name:"Member",p_consent:true});
 assert.equal((await query("select id from public.discovery_memberships where id=$1",[ma.id])).rows.length,0);
 await assert.rejects(()=>rpc("discovery_save_profile",{p_member:ma.id,p_data:profile,p_revision:2,p_submit:true}),/access required/);
 await assert.rejects(()=>query("update public.discovery_memberships set person_id=null"));
 await auth(1);let results=await rpc("discovery_staff_search",{});assert.equal(results.total,1);assert.equal(results.items[0].profile.joy,"Helping");assert(!("N" in results.items[0].bigfive.domains));assert(!("answers" in results.items[0]));
 assert.equal((await rpc("discovery_staff_search",{p_filters:{skill:"Photography",contact:"later"}})).total,1);
 await assert.rejects(()=>rpc("discovery_link_person",{p_member:mb.id,p_person:null,p_create:true}),/access required/);
 await db.exec("reset role");
 const pa=(await query("insert into public.people(church_id,first_name,last_name,email,is_public) values($1,'Alex','Member','person3@test.example',false) returning id",[ca])).rows[0].id;
 const pb=(await query("insert into public.people(church_id,first_name,last_name,is_public) values($1,'Other','Person',false) returning id",[cb])).rows[0].id;
 await auth(1);const suggestions=await rpc("discovery_candidates",{p_member:ma.id,p_query:""});assert(suggestions.some(p=>p.id===pa));assert(!suggestions.some(p=>p.id===pb));
 await assert.rejects(()=>rpc("discovery_link_person",{p_member:ma.id,p_person:pb,p_create:false}),/this church/);
 await rpc("discovery_link_person",{p_member:ma.id,p_person:pa,p_create:false});
 assert.equal((await rpc("discovery_staff_search",{p_filters:{person_id:pa}})).items[0].id,ma.id);
 await rpc("discovery_observe",{p_member:ma.id,p_note:"Photographed a church event."});
 await auth(3);const ws=await rpc("discovery_workspace",{p_church_id:ca});assert.equal(ws.membership.person_id,pa);assert(!("observations" in ws));
 await auth(1);const leader=await rpc("discovery_enroll_leader",{p_first_name:"Leader",p_last_name:"One",p_consent:true});assert.equal(leader.user_id,uid(1));
 assert.equal((await query("select app_role from public.profiles where user_id=$1",[uid(1)])).rows[0].app_role,"admin");
 const rotated=await rpc("discovery_registration",{p_rotate:true});assert.notEqual(rotated.token,sa.token);assert.equal(await rpc("discovery_public_church",{p_token:sa.token}),null);
 await rpc("discovery_registration",{p_enabled:false});assert.equal(await rpc("discovery_public_church",{p_token:rotated.token}),null);
 await auth(3);assert((await rpc("discovery_my_churches",{})).some(c=>c.id===ca));
 await auth(1);await rpc("discovery_member_access",{p_member:ma.id,p_disabled:true});
 await auth(3);await assert.rejects(()=>rpc("discovery_workspace",{p_church_id:ca}),/access required/);
 }finally{await db.close();}
});
