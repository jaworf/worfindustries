
// Local-only fictional fixture API. Real edge code and PostgreSQL run here;
// GoTrue login/email delivery are simulated, never connected to production.
import http from 'node:http';
import vm from 'node:vm';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
import {createStagingDatabase} from './staging-database.mjs';
const db=await createStagingDatabase();
const ids={owner:'40000000-0000-4000-8000-000000000001',applicant:'40000000-0000-4000-8000-000000000002'};
const churchA='50000000-0000-4000-8000-000000000001',churchB='50000000-0000-4000-8000-000000000002';
await db.query(`insert into public.churches(id,name,slug) values($1,'Fixture Church Alpha','fixture-alpha'),($2,'Fixture Church Beta','fixture-beta')`,[churchA,churchB]);
for(const [name,id] of Object.entries(ids))await db.query(`insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())`,[id,name+'@example.invalid']);
await db.query(`update public.profiles set church_id=$1,app_role='admin',is_platform_admin=true where user_id=$2`,[churchA,ids.owner]);
const uuidToken=id=>Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url')+'.'+Buffer.from(JSON.stringify({sub:id,exp:Math.floor(Date.now()/1000)+3600,iat:Math.floor(Date.now()/1000),role:'authenticated'})).toString('base64url')+'.fixture';
const identify=token=>{try{const id=JSON.parse(Buffer.from(token.split('.')[1],'base64url').toString()).sub;return Object.values(ids).includes(id)?{id,email:Object.keys(ids).find(k=>ids[k]===id)+'@example.invalid',email_confirmed_at:'2026-10-21T00:00:00Z',aud:'authenticated',role:'authenticated'}:null;}catch{return null;}};
function ident(value){if(!/^[a-z_]+$/.test(value))throw Error('Invalid fixture identifier');return '"'+value+'"';}
function query(table){let fields='*',filters=[],order=[],limit=1000,single=false,insert=null,opts={};
 const chain={select(f='*',o={}){fields=f;opts=o;return chain;},eq(k,v){filters.push([k,v]);return chain;},order(k,o={}){order.push([k,o.ascending!==false]);return chain;},limit(n){limit=n;return chain;},single(){single=true;return execute();},maybeSingle(){single=true;return execute();},insert(row){insert=row;return chain;},then(a,b){return execute().then(a,b);}};
 async function execute(){try{let sql,params=[];
  if(insert){const keys=Object.keys(insert);sql=`insert into public.${ident(table)}(${keys.map(ident).join(',')}) values(${keys.map((_,i)=>'$'+(i+1)).join(',')}) returning *`;params=Object.values(insert);}
  else{sql=`select ${opts.count?'count(*)::int as count':fields==='*'?'*':fields.split(',').map(ident).join(',')} from public.${ident(table)}`;
   if(filters.length){sql+=' where '+filters.map(([k,v],i)=>{params.push(v);return ident(k)+'=$'+(i+1);}).join(' and ');}
   if(order.length&&!opts.count)sql+=' order by '+order.map(([k,asc])=>ident(k)+(asc?' asc':' desc')).join(',');if(!opts.count)sql+=' limit '+Number(limit);
  }
  const result=await db.query(sql,params);return {data:opts.head?null:single?result.rows[0]??null:result.rows,count:opts.count?result.rows[0]?.count:null,error:null};
 }catch(e){return {data:null,error:{message:e.message,code:e.code}};}}
 return chain;
}
const service={auth:{admin:{getUserById:async id=>({data:{user:{id,email:Object.keys(ids).find(k=>ids[k]===id)+'@example.invalid',email_confirmed_at:'2026-10-21T00:00:00Z'}},error:null})},getUser:async token=>({data:{user:identify(token)},error:null})},from:query,rpc:async(name,args)=>{try{const values=Object.values(args);const result=await db.query(`select public.${ident(name)}(${Object.keys(args).map((k,i)=>ident(k)+'=> $'+(i+1)).join(',')}) as value`,values);return {data:result.rows[0]?.value,error:null};}catch(e){return {data:null,error:{message:e.message,code:e.code}};}}};
let serve;
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info, x-supabase-api-version','Access-Control-Allow-Methods':'GET, POST, OPTIONS'};
const context=vm.createContext({Request,Response,Headers,console,Deno:{env:{get:n=>n==='SUPABASE_URL'?'http://127.0.0.1:54321':'fixture-key'},serve:fn=>serve=fn}});
const source=ts.transpileModule(await readFile(new URL('../../supabase/functions/church-platform/index.ts',import.meta.url),'utf8'),{compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022}}).outputText;
const mod=new vm.SourceTextModule(source,{context});await mod.link(async spec=>spec.startsWith('jsr:')?new vm.SyntheticModule([],()=>{},{context}):spec.endsWith('/cors')?new vm.SyntheticModule(['corsHeaders'],function(){this.setExport('corsHeaders',cors);},{context}):new vm.SyntheticModule(['createClient'],function(){this.setExport('createClient',()=>service);},{context}));await mod.evaluate();
const server=http.createServer(async(req,res)=>{try{
 if(req.method==='OPTIONS'){res.writeHead(204,cors);res.end();return;}
 const chunks=[];for await(const chunk of req)chunks.push(chunk);const body=Buffer.concat(chunks).toString();
 if(req.url.startsWith('/auth/v1/token')){const input=JSON.parse(body);const name=input.email?.split('@')[0];const id=ids[name];if(!id||input.password!=='Fixture-password-123'){res.writeHead(400,{...cors,'Content-Type':'application/json'});res.end(JSON.stringify({msg:'Invalid fixture credentials'}));return;}
 const access_token=uuidToken(id);res.writeHead(200,{...cors,'Content-Type':'application/json'});res.end(JSON.stringify({access_token,refresh_token:'fixture-refresh',expires_in:3600,token_type:'bearer',user:identify(access_token)}));return;}
 if(req.url==='/auth/v1/logout'){res.writeHead(204,cors);res.end();return;}
 if(req.url==='/auth/v1/user'){res.writeHead(200,{...cors,'Content-Type':'application/json'});res.end(JSON.stringify(identify(req.headers.authorization?.replace(/^Bearer /,''))));return;}
 if(req.url==='/functions/v1/church-platform'){const response=await serve(new Request('http://127.0.0.1:54321'+req.url,{method:'POST',headers:req.headers,body}));res.writeHead(response.status,Object.fromEntries(response.headers));res.end(await response.text());return;}
 res.writeHead(404,cors);res.end('Fixture route unavailable');
 }catch(e){console.error(e);res.writeHead(500,cors);res.end('Fixture API error');}});
server.listen(54321,'127.0.0.1',()=>console.log('Fictional staging API: http://127.0.0.1:54321; users owner@example.invalid and applicant@example.invalid; fixed fixture password only.'));
for(const sig of ['SIGINT','SIGTERM'])process.on(sig,()=>server.close(async()=>{await db.close();process.exit(0);}));
