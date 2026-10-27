import {createStagingDatabase} from './staging-database.mjs';
import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const db=await createStagingDatabase();
try{
await db.exec(await readFile(new URL('./database-security.sql',import.meta.url),'utf8'));
console.log('PASS: existing database isolation, access, password, and account deletion tests');
await db.exec(await readFile(new URL('./multi-church-security.sql',import.meta.url),'utf8'));
console.log('PASS: approval, administrator delegation, support audit, RLS, and RPC restrictions');
assert.equal((await db.query(`select count(*)::int as n from public.church_applications`)).rows[0].n,0);
}finally{await db.close();}
