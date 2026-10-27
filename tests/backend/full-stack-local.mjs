
// Real local Supabase services only. Test email is captured in local Mailpit.
import {readFile,writeFile} from 'node:fs/promises';
import {randomBytes} from 'node:crypto';
import assert from 'node:assert/strict';
import {createClient} from '@supabase/supabase-js';
const runtime=JSON.parse(await readFile(new URL('../../.local-runtime.json',import.meta.url),'utf8'));
assert.equal(runtime.url,'http://127.0.0.1:54321','This test refuses non-local Supabase');
const options={auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}};
const service=createClient(runtime.url,runtime.serviceKey,options);
const makeClient=()=>createClient(runtime.url,runtime.publishableKey,options);
const results=[];
const passed=name=>{results.push({name,passed:true});console.log('PASS:',name);};
const ok=(result,label)=>{assert.equal(result.error,null,label+': '+(result.error?.message??''));return result.data;};
const password=()=>randomBytes(24).toString('base64url')+'Aa1!';
const tag=Date.now().toString(36);
const email=name=>`ministry-${name}-${tag}@example.invalid`;
const accounts={};
async function createConfirmed(name){const emailAddress=email(name),pw=password();const data=ok(await service.auth.admin.createUser({email:emailAddress,password:pw,email_confirm:true}),name+' creation');accounts[name]={id:data.user.id,email:emailAddress,password:pw};const client=makeClient();ok(await client.auth.signInWithPassword({email:emailAddress,password:pw}),name+' sign-in');return client;}
async function mailFor(address,seen=new Set()){
 for(let attempt=0;attempt<60;attempt++){
  const response=await fetch('http://127.0.0.1:54324/api/v1/messages');assert.ok(response.ok,'Mailpit message listing');
  const listing=await response.json();
  const message=(listing.messages??[]).find(m=>!seen.has(m.ID)&&JSON.stringify(m.To).includes(address));
  if(message){const full=await fetch('http://127.0.0.1:54324/api/v1/message/'+message.ID);assert.ok(full.ok);return {...await full.json(),fixtureId:message.ID};}
  await new Promise(resolve=>setTimeout(resolve,250));
 }
 throw Error('No locally captured authentication message arrived');
}
function actionLink(mail){const text=(mail.HTML??'')+'\n'+(mail.Text??'');const links=text.match(/https?:\/\/[^\s"'<>]+/g)??[];const link=links.map(s=>s.replaceAll('&amp;','&')).find(s=>s.includes('/auth/v1/verify?'));assert.ok(link,'Mail contains verification URL');const parsed=new URL(link);assert.ok(['127.0.0.1','localhost'].includes(parsed.hostname),'No external email link is followed');return link;}
async function follow(mail,path){const response=await fetch(actionLink(mail),{redirect:'manual'});assert.ok([302,303].includes(response.status),'Auth link redirects');const location=response.headers.get('location');assert.ok(location);const target=new URL(location);assert.equal(target.origin,'http://127.0.0.1:4173');assert.equal(target.pathname,path);const hash=new URLSearchParams(target.hash.slice(1));assert.ok(hash.get('access_token'),'Callback has an access token');return {access_token:hash.get('access_token'),refresh_token:hash.get('refresh_token')};}
async function fn(client,body){const response=await client.functions.invoke('church-platform',{body});return ok(response,body.action);}
try{
 const owner=await createConfirmed('owner');
 const ownerChurch=ok(await service.from('churches').insert({name:'Local Developer Fixture',slug:'local-developer-'+tag}).select('id').single(),'owner church').id;
 ok(await service.from('profiles').update({church_id:ownerChurch,app_role:'admin',is_platform_admin:true}).eq('user_id',accounts.owner.id),'owner role');
 const applicant=makeClient();const applicantEmail=email('applicant'),applicantPassword=password();
 const signup=ok(await applicant.auth.signUp({email:applicantEmail,password:applicantPassword,options:{emailRedirectTo:'http://127.0.0.1:4173/join',data:{is_platform_admin:true,app_role:'admin',church_id:ownerChurch}}}),'public applicant signup');
 accounts.applicant={id:signup.user.id,email:applicantEmail,password:applicantPassword};
 assert.equal(signup.session,null,'Unverified signup has no session');
 const unverified=await applicant.auth.signInWithPassword({email:applicantEmail,password:applicantPassword});assert.ok(unverified.error,'Unverified user cannot sign in');
 const confirmation=await mailFor(applicantEmail);await follow(confirmation,'/join');
 ok(await applicant.auth.signInWithPassword({email:applicantEmail,password:applicantPassword}),'verified applicant sign-in');
 passed('Real Auth signup, local email capture, confirmation redirect, and verified sign-in');
 let profile=ok(await applicant.from('profiles').select('*').eq('user_id',signup.user.id).single(),'applicant profile');
 assert.equal(profile.church_id,null);assert.equal(profile.is_platform_admin,false);assert.equal(profile.app_role,'viewer');
 assert.ok((await applicant.from('profiles').update({is_platform_admin:true}).eq('user_id',signup.user.id)).error);
 assert.equal(ok(await applicant.from('people').select('id'),'pending people').length,0);
 passed('Signup metadata cannot create church membership or platform privileges');
 await fn(applicant,{action:'apply',church_name:'Local Church Alpha '+tag,location:'Fictional City, Washington'});
 const forbidden=await applicant.functions.invoke('church-platform',{body:{action:'overview'}});assert.ok(forbidden.error);
 const overview=await fn(owner,{action:'overview'});const application=overview.applications.find(a=>a.applicant_email===applicantEmail);assert.ok(application);
 await fn(owner,{action:'decide',application_id:application.id,approve:true,note:'Local integration test approval'});
 profile=ok(await applicant.from('profiles').select('*').eq('user_id',signup.user.id).single(),'approved profile');
 const alpha=profile.church_id;assert.ok(alpha);assert.equal(profile.app_role,'admin');assert.notEqual(alpha,ownerChurch);
 assert.ok((await owner.functions.invoke('church-platform',{body:{action:'decide',application_id:application.id,approve:true}})).error);
 passed('Developer-only, transactional church approval creates exactly one scoped administrator');
 const betaClient=await createConfirmed('beta');await fn(betaClient,{action:'apply',church_name:'Local Church Beta '+tag,location:'Another Fictional City'});
 const betaApplication=(await fn(owner,{action:'overview'})).applications.find(a=>a.applicant_email===accounts.beta.email);assert.ok(betaApplication);
 await fn(owner,{action:'decide',application_id:betaApplication.id,approve:true});
 const beta=ok(await betaClient.from('profiles').select('church_id').eq('user_id',accounts.beta.id).single(),'beta profile').church_id;
 ok(await applicant.from('people').insert({church_id:alpha,first_name:'Alpha',last_name:'Fixture'}),'alpha person');
 ok(await betaClient.from('people').insert({church_id:beta,first_name:'Beta',last_name:'Fixture'}),'beta person');
 assert.equal(ok(await applicant.from('people').select('id').eq('church_id',beta),'cross church read').length,0);
 assert.ok((await applicant.from('people').insert({church_id:beta,first_name:'Blocked',last_name:'Fixture'})).error);
 assert.equal(ok(await applicant.from('profiles').select('user_id').eq('church_id',beta),'cross church profiles').length,0);
 passed('Real PostgREST enforces church-specific profile, person read, and write boundaries');
 const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jhAAAAABJRU5ErkJggg==','base64');
 const path=alpha+'/logo';
 ok(await applicant.storage.from('church-logos').upload(path,png,{contentType:'image/png',upsert:true}),'logo upload');
 const stored=ok(await applicant.storage.from('church-logos').download(path),'own logo download');assert.deepEqual(Buffer.from(await stored.arrayBuffer()),png);
 ok(await applicant.storage.from('church-logos').upload(path,png,{contentType:'image/png',upsert:true}),'logo replacement');
 assert.ok((await betaClient.storage.from('church-logos').download(path)).error);
 assert.ok((await betaClient.storage.from('church-logos').upload(path,png,{contentType:'image/png',upsert:true})).error);
 await betaClient.storage.from('church-logos').remove([path]);
 assert.deepEqual(Buffer.from(await ok(await applicant.storage.from('church-logos').download(path),'logo remains after cross delete').arrayBuffer()),png);
 assert.ok((await makeClient().storage.from('church-logos').download(path)).error);
 assert.ok((await applicant.storage.from('church-logos').upload(path,Buffer.from('<svg/>'),{contentType:'image/svg+xml',upsert:true})).error);
 assert.ok((await applicant.storage.from('church-logos').upload(path,Buffer.alloc(2_097_153),{contentType:'image/png',upsert:true})).error);
 ok(await applicant.storage.from('church-logos').remove([path]),'own logo removal');
 assert.ok((await applicant.storage.from('church-logos').download(path)).error);
 ok(await applicant.storage.from('church-logos').upload(path,png,{contentType:'image/png',upsert:true}),'logo restoration');
 passed('Real private Storage upload, download, replacement, removal, MIME/size limits, and cross-church denial');
 const invitedEmail=email('invited-admin');
 ok(await applicant.functions.invoke('admin-users',{body:{action:'invite',email:invitedEmail,role:'admin',church_id:alpha}}),'church admin invitation');
 const invitation=await mailFor(invitedEmail);const invited=makeClient();ok(await invited.auth.setSession(await follow(invitation,'/reset-password')),'invite session');
 const invitedPassword=password();ok(await invited.auth.updateUser({password:invitedPassword}),'invited password setup');
 const invitedIdentity=ok(await invited.auth.getUser(),'invited identity').user.id;
 const invitedProfile=ok(await invited.from('profiles').select('*').eq('user_id',invitedIdentity).single(),'invited profile');assert.equal(invitedProfile.church_id,alpha);assert.equal(invitedProfile.app_role,'admin');assert.equal(invitedProfile.is_platform_admin,false);
 const listed=ok(await applicant.functions.invoke('admin-users',{body:{action:'list'}}),'church users');assert.ok(listed.users.length>=2);assert.ok(listed.users.every(u=>u.church_id===alpha));
 assert.ok((await applicant.functions.invoke('admin-users',{body:{action:'invite',email:email('cross'),role:'admin',church_id:beta}})).error);
 passed('Real church-admin invitation email, password setup, administrator delegation, and scoped user listing');
 ok(await invited.auth.resetPasswordForEmail(invitedEmail,{redirectTo:'http://127.0.0.1:4173/reset-password'}),'password recovery');
 const recovery=await mailFor(invitedEmail,new Set([invitation.fixtureId]));const recoveryClient=makeClient();ok(await recoveryClient.auth.setSession(await follow(recovery,'/reset-password')),'recovery session');
 const replacementPassword=password();ok(await recoveryClient.auth.updateUser({password:replacementPassword}),'recovery password update');
 const recovered=makeClient();ok(await recovered.auth.signInWithPassword({email:invitedEmail,password:replacementPassword}),'recovered sign-in');
 passed('Real password recovery email, local callback, password change, and subsequent sign-in');
 const before=ok(await service.from('platform_support_audit').select('id').eq('church_id',beta),'audit before').length;
 const diagnostic=await fn(owner,{action:'diagnostics',church_id:beta,reason:'Local full-stack integration test of account diagnostics'});
 assert.equal(diagnostic.church.id,beta);assert.equal(diagnostic.people_count,1);assert.ok(diagnostic.users.every(u=>u.user_id===accounts.beta.id));
 assert.equal(ok(await service.from('platform_support_audit').select('id').eq('church_id',beta),'audit after').length,before+1);
 assert.ok((await betaClient.functions.invoke('church-platform',{body:{action:'diagnostics',church_id:alpha,reason:'Unauthorized cross-church support test'}})).error);
 assert.ok((await owner.functions.invoke('admin-users',{body:{action:'delete_user',user_id:accounts.beta.id,confirmation:'DELETE'}})).error);
 passed('Audited real Edge diagnostics, non-platform denial, and last church-administrator protection');
 await writeFile(new URL('../../.local-test-accounts.json',import.meta.url),JSON.stringify(accounts),{mode:0o600});
 await writeFile(new URL('../../../full-stack-results.json',import.meta.url),JSON.stringify({status:'passed',api:'http://127.0.0.1:54321',production_changed:false,email_destination:'local Mailpit only',results},null,2));
 console.log('All local full-stack checks passed. No real inbox or production project was used.');
}catch(error){await writeFile(new URL('../../../full-stack-results.json',import.meta.url),JSON.stringify({status:'failed',completed:results,error:error.message},null,2));console.error('FAIL:',error.message);process.exitCode=1;}
