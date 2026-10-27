
import {PGlite} from '@electric-sql/pglite';
import {pgcrypto} from '@electric-sql/pglite/contrib/pgcrypto';
import {readFile,readdir} from 'node:fs/promises';
export async function createStagingDatabase(){
const db=new PGlite({extensions:{pgcrypto}});
await db.exec(`
 create role anon; create role authenticated; create role service_role bypassrls;
 create schema auth; create schema extensions; create schema vault; create schema cron;
 grant usage on schema auth,public to anon,authenticated,service_role;
 create schema storage;
 grant usage on schema storage to authenticated,service_role;
 create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
 create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text references storage.buckets(id),name text,unique(bucket_id,name));
 alter table storage.objects enable row level security;
 grant select,insert,update,delete on storage.objects to authenticated,service_role;
 create table auth.users(id uuid primary key,email text,encrypted_password text,raw_user_meta_data jsonb default '{}',email_confirmed_at timestamptz);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create function auth.role() returns text language sql stable as $$select current_setting('request.jwt.claim.role',true)$$;
 create table vault.decrypted_secrets(id uuid primary key,decrypted_secret text);
 create table cron.job(jobid bigint generated always as identity,jobname text,active boolean default true);
 create function cron.schedule(text,text,text) returns bigint language sql as $$insert into cron.job(jobname) values($1) returning jobid$$;
 create function cron.unschedule(bigint) returns boolean language sql as $$delete from cron.job where jobid=$1 returning true$$;
`);
const dir=new URL('../../supabase/migrations/',import.meta.url);
for(const name of (await readdir(dir)).filter(n=>n.endsWith('.sql')).sort()){
 let sql=await readFile(new URL(name,dir),'utf8');
 sql=sql.replace('create extension if not exists pg_cron with schema pg_catalog;','-- Scheduler is stubbed in the embedded test database.');
 try{await db.exec(sql);console.log('Applied',name);}catch(e){console.error('Migration failed:',name,e.message);throw e;}
}
return db;
}
