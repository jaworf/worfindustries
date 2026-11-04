import test from 'node:test';import assert from 'node:assert/strict';import {readFile,writeFile} from 'node:fs/promises';import {createRequire} from 'node:module';import ts from 'typescript';import {PDFDocument} from 'pdf-lib';import {createStagingDatabase} from './staging-database.mjs';
test('limited public directory exposes only ministry, volunteer and term; branding is account-scoped',async()=>{
 const db=await createStagingDatabase(),id=n=>'c1000000-0000-4000-8000-'+String(n).padStart(12,'0');const q=(s,a=[])=>db.query(s,a);const as=async(n,role='authenticated')=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[n?id(n):'']);await db.exec('set role '+role);};const rpc=async(name)=>(await q('select public.'+name+'() result')).rows[0].result;
 try{
  await q("insert into public.churches(id,name,slug,public_directory_enabled) values($1,'Oak Valley Church','public-a',true),($2,'Another Church','public-b',true)",[id(100),id(101)]);
  for(const[n,role,c]of [[1,'admin',100],[2,'editor',100],[3,'admin',101]]){await q('insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())',[id(n),'limited'+n+'@example.invalid']);await q('update public.profiles set church_id=$1,app_role=$2 where user_id=$3',[id(c),role,id(n)]);}
  await q("insert into public.roles(id,church_id,name,is_public) values($1,$2,'Welcome',true),($3,$4,'Other ministry',true)",[id(200),id(100),id(201),id(101)]);
  await q("insert into public.people(id,church_id,first_name,last_name,email,mobile_phone,is_public) values($1,$2,'José','Example','SECRET_EMAIL@example.invalid','SECRET_PHONE',true),($3,$2,'Hidden','Example',null,null,false),($4,$5,'Other','Person',null,null,true)",[id(300),id(100),id(301),id(302),id(101)]);
  await q("insert into public.terms(id,church_id,name,start_date,end_date) values($1,$2,'2027-2028','2027-01-01','2028-12-31')",[id(400),id(100)]);
  await q("insert into public.assignments(church_id,person_id,role_id,term_id,notes,note_is_public,status,is_public) values($1,$2,$3,$4,'NOTE_MUST_NOT_EXPORT',true,'active',true),($1,$5,$3,$4,'HIDDEN_PRIVATE_NOTE',false,'active',true),($6,$7,$8,null,null,false,'active',true)",[id(100),id(300),id(200),id(400),id(301),id(101),id(302),id(201)]);
  await q('insert into public.church_embed_settings(church_id) values($1)',[id(100)]);
  await as(0,'anon');assert.equal((await q("select public.website_embed_config('public-a','directory') result")).rows[0].result,null);const rows=(await q("select * from public.limited_public_directory('public-a')")).rows;assert.equal(rows.length,1);assert.deepEqual(Object.keys(rows[0]).sort(),['ministry','term','volunteer']);assert.equal(rows[0].volunteer,'José Example');assert.equal(rows[0].term,'2027-2028');assert.doesNotMatch(JSON.stringify(rows),/SECRET|NOTE|Other|Hidden/);
  await assert.rejects(()=>q('select * from public.public_directory_entries'),/permission denied/);await assert.rejects(()=>rpc('account_church_branding'),/permission denied/);
  assert.equal((await q("select * from public.limited_public_directory('unknown')")).rows.length,0);
  await as(1);assert.deepEqual(await rpc('account_church_branding'),{name:'Oak Valley Church',slug:'public-a'});
  await as(3);assert.deepEqual(await rpc('account_church_branding'),{name:'Another Church',slug:'public-b'});
  await db.exec('reset role');await q('update public.profiles set must_change_password=true where user_id=$1',[id(2)]);await as(2);assert.equal((await rpc('account_church_branding')).name,'Oak Valley Church');assert.equal((await q('select count(*)::int n from public.assignments')).rows[0].n,0);
  await db.exec('reset role');await q('update public.churches set public_directory_enabled=false where id=$1',[id(100)]);await as(0,'anon');assert.equal((await q("select * from public.limited_public_directory('public-a')")).rows.length,0);
 }finally{await db.close();}
});
test('public directory PDF supports accented names and only the three display fields',async()=>{
 const require=createRequire(import.meta.url),source=ts.transpileModule(await readFile(new URL('../../app/public-directory-pdf.ts',import.meta.url),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022,esModuleInterop:true}}).outputText,exports={};new Function('exports','require',source)(exports,require);
 const regular=new Uint8Array(await readFile(new URL('../../public/fonts/NotoSans-Regular.ttf',import.meta.url))),bold=new Uint8Array(await readFile(new URL('../../public/fonts/NotoSans-Bold.ttf',import.meta.url)));
 const rows=Array.from({length:24},(_,i)=>({ministry:'Children, Families and Community Welcome Ministry',volunteer:'José Example '+(i+1),term:'2027-2028',notes:'PRIVATE_NOTE_MUST_NOT_EXPORT',email:'SECRET_EMAIL@example.invalid'}));
 const bytes=await exports.createDirectoryPDF(rows,'Fictional Church',{regular,bold});const doc=await PDFDocument.load(bytes);assert.ok(doc.getPageCount()>=2);assert.equal(doc.getTitle(),'Fictional Church - Ministry directory');
 if(process.env.PUBLIC_DIRECTORY_PDF_SAMPLE)await writeFile(process.env.PUBLIC_DIRECTORY_PDF_SAMPLE,bytes);
});
