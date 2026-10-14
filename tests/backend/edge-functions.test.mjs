import assert from 'node:assert/strict';
import test from 'node:test';
import vm from 'node:vm';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {readFile} from 'node:fs/promises';
import {webcrypto} from 'node:crypto';
import ts from 'typescript';

// Run the real TypeScript handlers in isolation. All auth, database, and PCO
// boundaries are replaced; tests never send mail or touch production records.
async function handler(name, options = {}) {
  const calls = [];
  const caller = options.caller ?? {app_role:'admin',church_id:'church-a',is_platform_admin:false};
  const client = {
    auth: {
      getUser: async () => ({data:{user:options.invalidSession ? null : {id:'actor'}},error:null}),
      admin: {
        listUsers: async () => ({data:{users:options.existing ? [options.existing] : []},error:null}),
        updateUserById: async (...args) => {calls.push(['password',...args]);return {error:null};},
        createUser: async (...args) => {calls.push(['create',...args]);return {data:{user:{id:'new-user'}},error:null};},
        inviteUserByEmail: async (...args) => {calls.push(['invite',...args]);return {data:{user:{id:'new-user'}},error:null};},
        getUserById: async id => ({data:{user:{id,email:'test@example.org'}},error:null}),
        deleteUser: async id => {calls.push(['delete',id]);return {error:null};},
      },
      resetPasswordForEmail: async (...args) => {calls.push(['email',...args]);return {error:null};},
    },
    rpc: async (name,args) => {
      calls.push(['rpc',name,args]);
      if(name==='get_planning_center_credentials') return {data:[{application_id:'app-'+args.p_church_id,secret:'pco-test-secret'}],error:null};
      return {data: options.rpcData ?? {outcome:'updated',person_id:'person-1'},error:options.rpcError ?? null};
    },
    from(table) {
      const filters = [];let operation = 'read';let value;
      const query = new Proxy({}, {get(_target,key) {
        if(key==='then') return (resolve,reject) => Promise.resolve(result()).then(resolve,reject);
        return (...args) => {
          if(['insert','update','upsert'].includes(key)) {operation=key;value=args[0];calls.push([table,key,value]);}
          if(['eq','not'].includes(key)) filters.push([key,...args]);
          if(['single','maybeSingle'].includes(key)) return Promise.resolve(result());
          return query;
        };
      }});
      function result() {
        if(table==='profiles') {
          const target=filters.some(item=>item[1]==='user_id'&&item[2]!=='actor');
          return {data: target ? options.existingProfile ?? null : caller,error:target ? options.profileError ?? null : null};
        }
        if(table==='churches') return {data:{id:filters.find(item=>item[1]==='id')?.[2] ?? 'church-a',name:'Test Church',is_active:true,slug:'test-church'},error:null};
        if(table==='import_runs') return {data:{id:'run-1'},error:null};
        if(table==='webhook_deliveries') return {data:{id:'delivery-row',status:options.priorStatus ?? 'completed'},error:operation==='insert'&&options.duplicate ? {code:'23505'} : null};
        return {data: value ?? [],error:null};
      }
      return query;
    },
  };
  const env = {SUPABASE_URL:'https://test.supabase.co',SUPABASE_SERVICE_ROLE_KEY:'test-service',SUPABASE_ANON_KEY:'test-public',
    PCO_WEBHOOK_CONNECTIONS:JSON.stringify([{churchId:'church-a',secret:'secret-a'},{churchId:'church-b',secret:'secret-b'}]),...options.env};
  let serve;
  const context=vm.createContext({Request,Response,Headers,TextEncoder,TextDecoder,crypto:webcrypto,btoa,console,
    Deno:{env:{get:key=>env[key]},serve:fn=>{serve=fn;}},
    fetch:async (url,init) => {calls.push(['fetch',url,init.headers.Authorization]);return new Response(JSON.stringify({data:options.person ?? [],links:{next:null}}),{status:200});},
  });
  const cache=new Map();
  async function load(path) {
    if(cache.has(path)) return cache.get(path);
    const code=ts.transpileModule(await readFile(path,'utf8'),{compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022}}).outputText;
    const sourceModule=new vm.SourceTextModule(code,{context,identifier:path});cache.set(path,sourceModule);
    await sourceModule.link(async specifier => {
      if(specifier.startsWith('jsr:')) return new vm.SyntheticModule([],()=>{},{context});
      if(specifier.endsWith('/cors')) return new vm.SyntheticModule(['corsHeaders'],function(){this.setExport('corsHeaders',{});},{context});
      if(specifier.startsWith('npm:')) return new vm.SyntheticModule(['createClient'],function(){this.setExport('createClient',()=>client);},{context});
      return load(fileURLToPath(new URL(specifier,pathToFileURL(path))));
    });
    return sourceModule;
  }
  const root=new URL('../../supabase/functions/',import.meta.url);
  const sourceModule=await load(fileURLToPath(new URL(name+'/index.ts',root)));await sourceModule.evaluate();
  return {calls,request:async (body={},headers={Authorization:'Bearer test'}) => serve(new Request('https://test/'+name,{method:'POST',headers,body:typeof body==='string'?body:JSON.stringify(body)}))};
}
const invite={email:'pending@example.org',role:'viewer',church_id:'church-a'};
for(const confirmed of [false,true]) {
  for(const temporary of [false,true]) test(`admin-users refuses cross-church ${confirmed?'active':'pending'} user (${temporary?'password':'email'})`,async()=>{
    const {request,calls}=await handler('admin-users',{existing:{id:'target',email:invite.email,email_confirmed_at:confirmed?'now':null},existingProfile:{church_id:'church-b',app_role:'viewer'}});
    const response=await request({...invite,...(temporary?{temporary_password:'test-only-password'}:{})});
    assert.equal(response.status,409);assert.equal(calls.length,0);
  });
}
test('profile lookup errors fail closed before changing credentials or mailing',async()=>{
  const {request,calls}=await handler('admin-users',{existing:{id:'target',email:invite.email},profileError:{message:'Database unavailable'}});
  assert.equal((await request(invite)).status,500);assert.equal(calls.length,0);
});
test('unassigned existing accounts cannot be claimed',async()=>{
  const {request,calls}=await handler('admin-users',{existing:{id:'target',email:invite.email}});
  assert.equal((await request(invite)).status,409);assert.equal(calls.length,0);
});
test('same-church resend preserves membership without a profile upsert',async()=>{
  const {request,calls}=await handler('admin-users',{existing:{id:'target',email:invite.email},existingProfile:{church_id:'church-a',app_role:'viewer'}});
  assert.equal((await request(invite)).status,200);assert.equal(calls[0][0],'email');assert.equal(calls.length,1);
});
for(const flags of [{app_role:'viewer'},{app_role:'editor'},{access_disabled:true},{must_change_password:true}]) test('admin-users rejects restricted actor '+JSON.stringify(flags),async()=>{
  const {request,calls}=await handler('admin-users',{caller:{app_role:'admin',church_id:'church-a',...flags}});
  assert.equal((await request(invite)).status,403);assert.equal(calls.length,0);
});
test('temporary account creation marks mandatory initial password change',async()=>{
  const {request,calls}=await handler('admin-users');assert.equal((await request({...invite,temporary_password:'test-only-password'})).status,201);
  assert.equal(calls.find(item=>item[0]==='profiles')[2].must_change_password,true);
});
test('management RPC uses validated actor, never supplied actor',async()=>{
  const {request,calls}=await handler('admin-users');await request({action:'remove_access',user_id:'target',p_actor_id:'attacker'});
  assert.equal(calls[0][2].p_actor_id,'actor');assert.equal(calls[0][2].p_disabled,true);
});
for(const flags of [{app_role:'viewer'},{access_disabled:true},{must_change_password:true}]) test('sync rejects restricted actor '+JSON.stringify(flags),async()=>{
  const {request,calls}=await handler('planning-center-sync',{caller:{app_role:'editor',church_id:'church-b',...flags}});
  assert.equal((await request()).status,400);assert.equal(calls.length,0);
});
test('sync uses caller church for credentials and import, ignoring request church',async()=>{
  const {request,calls}=await handler('planning-center-sync',{caller:{app_role:'editor',church_id:'church-b'}});
  assert.equal((await request({church_id:'church-a'})).status,200);
  assert.equal(calls.find(item=>item[1]==='get_planning_center_credentials')[2].p_church_id,'church-b');
  assert.equal(calls.find(item=>item[0]==='import_runs')[2].church_id,'church-b');
  assert.equal(calls.find(item=>item[0]==='fetch')[2],'Basic '+btoa('app-church-b:pco-test-secret'));
});
async function signed(body,secret='secret-b') {
  const key=await webcrypto.subtle.importKey('raw',new TextEncoder().encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);
  return Buffer.from(await webcrypto.subtle.sign('HMAC',key,new TextEncoder().encode(body))).toString('hex');
}
const delivery=JSON.stringify({church_id:'church-a',data:[{id:'event-1',attributes:{name:'people.v2.events.person.deleted',payload:'{}'}}]});
test('webhook authenticates before any database operation',async()=>{
  const {request,calls}=await handler('planning-center-webhook');assert.equal((await request(delivery,{'X-PCO-Webhooks-Authenticity':'invalid'})).status,401);assert.equal(calls.length,0);
});
for(const body of ['{','{"data":{}}',JSON.stringify({data:[{id:'event',attributes:{name:'people.v2.events.person.updated',payload:'{'}}]})]) test('signed malformed webhook returns 400 without writes '+body,async()=>{
  const {request,calls}=await handler('planning-center-webhook');assert.equal((await request(body,{'X-PCO-Webhooks-Authenticity':await signed(body)})).status,400);assert.equal(calls.length,0);
});
test('signature chooses church B despite forged body church A',async()=>{
  const {request,calls}=await handler('planning-center-webhook');assert.equal((await request(delivery,{'X-PCO-Webhooks-Authenticity':await signed(delivery)})).status,200);
  assert.equal(calls.find(item=>item[0]==='webhook_deliveries')[2].church_id,'church-b');
  assert.equal(calls.find(item=>item[1]==='get_planning_center_credentials')[2].p_church_id,'church-b');
});
test('duplicate webhook has no new person fetch',async()=>{
  const {request,calls}=await handler('planning-center-webhook',{duplicate:true});const response=await request(delivery,{'X-PCO-Webhooks-Authenticity':await signed(delivery)});
  assert.equal(response.status,200);assert.equal((await response.json()).deliveries[0].status,'duplicate');assert.ok(!calls.some(item=>item[0]==='fetch'));
});
test('missing or ambiguous webhook configuration returns controlled 500',async()=>{
  const {request}=await handler('planning-center-webhook',{env:{PCO_WEBHOOK_CONNECTIONS:'[]'}});assert.equal((await request(delivery,{'X-PCO-Webhooks-Authenticity':await signed(delivery)})).status,500);
});
const personEvent=JSON.stringify({data:[{id:'event-person',attributes:{name:'people.v2.events.person.updated',payload:JSON.stringify({data:{id:'pco-person'}})}}]});
test('person webhook fetch and merge both use signature-bound church credentials',async()=>{
 const {request,calls}=await handler('planning-center-webhook',{person:{type:'Person',id:'pco-person',attributes:{first_name:'Test',last_name:'Person'}}});
 assert.equal((await request(personEvent,{'X-PCO-Webhooks-Authenticity':await signed(personEvent)})).status,200);
 assert.equal(calls.find(item=>item[0]==='fetch')[2],'Basic '+btoa('app-church-b:pco-test-secret'));
 assert.equal(calls.find(item=>item[1]==='sync_planning_center_person_for_church')[2].p_church_id,'church-b');
});
test('failed webhook delivery is retried rather than discarded as duplicate',async()=>{
 const {request,calls}=await handler('planning-center-webhook',{duplicate:true,priorStatus:'failed',person:{type:'Person',id:'pco-person',attributes:{first_name:'Test',last_name:'Person'}}});
 assert.equal((await request(personEvent,{'X-PCO-Webhooks-Authenticity':await signed(personEvent)})).status,200);
 assert.ok(calls.some(item=>item[0]==='fetch'));
});
test('database merge failure yields controlled 500 and records retryable delivery',async()=>{
 const {request,calls}=await handler('planning-center-webhook',{rpcData:{outcome:'error'},person:{type:'Person',id:'pco-person',attributes:{first_name:'Test',last_name:'Person'}}});
 assert.equal((await request(personEvent,{'X-PCO-Webhooks-Authenticity':await signed(personEvent)})).status,500);
 assert.equal(calls.filter(item=>item[0]==='webhook_deliveries'&&item[1]==='update').at(-1)[2].status,'failed');
});

for (const resource of ['email','phone_number','address']) {
 for (const action of ['created','updated','destroyed']) test(`contact ${resource}.${action} refreshes its owning person`, async () => {
  const body=JSON.stringify({data:[{id:'contact-event',attributes:{name:`people.v2.events.${resource}.${action}`,payload:JSON.stringify({data:{id:'contact-id',relationships:{person:{data:{type:'Person',id:'parent-person'}}}}})}}]});
  const {request,calls}=await handler('planning-center-webhook',{person:{type:'Person',id:'parent-person',attributes:{first_name:'Test',last_name:'Person'}}});
  assert.equal((await request(body,{'X-PCO-Webhooks-Authenticity':await signed(body)})).status,200);
  assert.match(calls.find(item=>item[0]==='fetch')[1], /people\/parent-person\?/);
  assert.equal(calls.find(item=>item[1]==='sync_planning_center_person_for_church')[2].p_church_id,'church-b');
 });
}
test('contact events without their owner fail before database writes',async()=>{
 const body=JSON.stringify({data:[{id:'contact-event',attributes:{name:'people.v2.events.email.updated',payload:JSON.stringify({data:{id:'contact-id'}})}}]});
 const {request,calls}=await handler('planning-center-webhook');
 assert.equal((await request(body,{'X-PCO-Webhooks-Authenticity':await signed(body)})).status,400); assert.equal(calls.length,0);
});
