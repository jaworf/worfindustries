import test from 'node:test';
import assert from 'node:assert/strict';
import {createStagingDatabase} from './staging-database.mjs';
test('church owners, viewer privacy, value-only search and friendly validation',async()=>{
 const db=await createStagingDatabase();const id=n=>'90000000-0000-4000-8000-'+String(n).padStart(12,'0');
 const q=(sql,args=[])=>db.query(sql,args);const auth=async n=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[id(n)]);await db.exec('set role authenticated');};
 const rpc=async(name,args={})=>{const keys=Object.keys(args);return(await q('select public.'+name+'('+keys.map((k,i)=>k+'=> $'+(i+1)).join(',')+') result',keys.map(k=>args[k]))).rows[0].result;};
 const rejected=async(fn,pattern)=>assert.rejects(fn,e=>e.code==='P0001'&&pattern.test(e.message));
 try{
 await q("insert into public.churches(id,name,slug) values($1,'Review A','review-security-a'),($2,'Review B','review-security-b')",[id(101),id(102)]);
 for(const [n,role,c]of [[1,'admin',101],[2,'admin',101],[3,'viewer',101],[4,'editor',101],[5,'admin',102]]){
 await q('insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())',[id(n),'review'+n+'@example.invalid']);await q('update public.profiles set church_id=$1,app_role=$2 where user_id=$3',[id(c),role,id(n)]);
 }
 assert.equal((await q('select user_id from public.church_owners where church_id=$1',[id(101)])).rows[0].user_id,id(1));
 for(const [role,disabled]of [['viewer',null],[null,true]])await rejected(()=>rpc('manage_app_user_access',{p_actor_id:id(2),p_user_id:id(1),p_role:role,p_disabled:disabled}),/Transfer church ownership/);
 await assert.rejects(()=>q('delete from auth.users where id=$1',[id(1)]),/owner|church_owners|administrator/i);
 await rpc('manage_app_user_access',{p_actor_id:id(1),p_user_id:id(2),p_role:'editor'});
 await rpc('manage_app_user_access',{p_actor_id:id(1),p_user_id:id(2),p_role:'admin'});
 await auth(2);await rejected(()=>rpc('transfer_church_ownership',{p_church_id:id(101),p_user_id:id(2)}),/Only the church owner/);
 await auth(1);await rejected(()=>rpc('transfer_church_ownership',{p_church_id:id(101),p_user_id:id(5)}),/this church/);
 const registration=await rpc('discovery_registration');
 await auth(3);await rejected(()=>rpc('discovery_staff_search'),/Placement team access/);
 await rejected(()=>rpc('discovery_enroll',{p_token:registration.token,p_first_name:'X'.repeat(101),p_last_name:'Member',p_consent:true}),/first and last names/);
 const member=await rpc('discovery_enroll',{p_token:registration.token,p_first_name:'Participant',p_last_name:'Example',p_consent:true});
 const profile={connection:'Member',service:'Events',joy:'Helping',abilities:'Photography',hope:'Serve',occupation:'',interests:'Media',skills:[{name:'Photography',experience:'Experienced',interest:'Possibly later',notes:'Church picnic'}],availability:'limited',contact:'later',review_date:''};
 await rpc('discovery_save_profile',{p_member:member.id,p_data:profile,p_revision:0,p_submit:true});
 await auth(1);assert.equal((await rpc('discovery_staff_search',{p_filters:{q:'skills'}})).total,0);assert.equal((await rpc('discovery_staff_search',{p_filters:{q:'joy'}})).total,0);assert.equal((await rpc('discovery_staff_search',{p_filters:{q:'photography'}})).total,1);
 for(const note of ['',null,'X'.repeat(4001)])await rejected(()=>rpc('discovery_observe',{p_member:member.id,p_note:note}),/between 1 and 4000/);
 await rpc('discovery_observe',{p_member:member.id,p_note:'Helped at an event.'});
 await auth(3);await rejected(()=>rpc('discovery_staff_search',{p_filters:{member_id:member.id}}),/Placement team access/);
 await auth(4);assert.equal((await rpc('discovery_staff_search')).total,1);
 await auth(5);assert.equal((await rpc('discovery_staff_search')).total,0);
 await auth(1);await rpc('transfer_church_ownership',{p_church_id:id(101),p_user_id:id(2)});
 await rejected(()=>rpc('transfer_church_ownership',{p_church_id:id(101),p_user_id:id(1)}),/Only the church owner/);
 await db.exec('reset role');await rejected(()=>rpc('manage_app_user_access',{p_actor_id:id(1),p_user_id:id(2),p_disabled:true}),/Transfer church ownership/);
 await q('update public.profiles set is_platform_admin=true where user_id=$1',[id(1)]);await auth(1);await rpc('transfer_church_ownership',{p_church_id:id(101),p_user_id:id(1)});
 await auth(3);await assert.rejects(()=>q('update public.church_owners set user_id=$1',[id(3)]),/permission denied/);
 }finally{await db.close();}
});
