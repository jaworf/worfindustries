import test from 'node:test';import assert from 'node:assert/strict';import {createStagingDatabase} from './staging-database.mjs';
test('website embeds are opt-in, admin-only, scoped, and publish only bootstrap metadata',async()=>{
 const db=await createStagingDatabase();const id=n=>'b1000000-0000-4000-8000-'+String(n).padStart(12,'0');
 const q=(s,args=[])=>db.query(s,args);const as=async(n,role='authenticated')=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[n?id(n):'']);await db.exec('set role '+role);};
 const rpc=async(name,args={})=>(await q('select public.'+name+'('+Object.keys(args).map((x,i)=>x+'=> $'+(i+1)).join(',')+') result',Object.values(args))).rows[0].result;
 try{
  await q("insert into public.churches(id,name,slug) values($1,'Embed Church A','embed-a'),($2,'Embed Church B','embed-b')",[id(100),id(101)]);
  for(const[n,role,c]of [[1,'admin',100],[2,'editor',100],[3,'viewer',100],[4,'admin',101]]){
   await q("insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())",[id(n),'embed'+n+'@example.invalid']);
   await q('update public.profiles set church_id=$1,app_role=$2 where user_id=$3',[id(c),role,id(n)]);
  }
  const config=(slug='embed-a',mode='app')=>rpc('website_embed_config',{p_slug:slug,p_mode:mode});
  const save=(origins=['https://church-a.example'],secure=true,pub=false,published=false)=>rpc('save_website_embeds',{p_origins:origins,p_secure:secure,p_public:pub,p_directory_published:published});
  await as(1);assert.equal(await config(),null);
  await save();let settings=await rpc('website_embed_settings');assert.equal(settings.secure_enabled,true);assert.equal(settings.directory_published,false);
  await as(0,'anon');const value=await config();assert.deepEqual(Object.keys(value).sort(),['allowed_origins','name','slug']);assert.equal(value.slug,'embed-a');assert.equal(await config('embed-b'),null);assert.equal(await config('embed-a','directory'),null);assert.equal(await config("embed-a' or true--"),null);assert.equal(await config('embed-a','unknown'),null);
  await assert.rejects(()=>q('select * from public.church_embed_settings'),/permission denied/);
  for(const n of [2,3]){await as(n);assert.equal(await rpc('website_embed_settings'),null);await assert.rejects(()=>save(),/Administrator/);assert.equal((await q('select count(*)::int n from public.church_embed_settings')).rows[0].n,0);}
  await as(4);await save(['https://church-b.example']);assert.equal((await rpc('website_embed_settings')).allowed_origins[0],'https://church-b.example');
  await as(1);assert.equal((await rpc('website_embed_settings')).allowed_origins[0],'https://church-a.example');
  for(const bad of ['http://unsafe.example','https://good.example/path','https://good.example *','https://user:pass@good.example','*'])await assert.rejects(()=>save([bad]),/HTTPS website origin/);
  await assert.rejects(()=>save([],true),/website address/);
  await assert.rejects(()=>save(['https://church-a.example'],true,true,false),/publishing must/);
  await save(['https://church-a.example'],true,true,true);await as(0,'anon');assert.equal((await config('embed-a','directory')).slug,'embed-a');
  await as(1);await save(['https://church-a.example'],true,false,false);await as(0,'anon');assert.equal(await config('embed-a','directory'),null);assert.equal((await config()).slug,'embed-a');
  await as(1);await save([],false,false,false);await as(0,'anon');assert.equal(await config(),null);
 }finally{await db.close();}
});
