
import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
import {renderToStaticMarkup} from 'react-dom/server';
import {createElement} from 'react';
const context=vm.createContext({console,URL});const cache=new Map();
async function load(url){
 if(cache.has(url.href))return cache.get(url.href);
 const code=ts.transpileModule(await readFile(url,'utf8'),{compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022,jsx:ts.JsxEmit.ReactJSX}}).outputText;
 const compiledModule=new vm.SourceTextModule(code,{context,identifier:url.href});cache.set(url.href,compiledModule);
 await compiledModule.link(async spec=>{if(spec.startsWith('.'))return load(new URL(spec.endsWith('admin-shared')?spec+'.ts':spec.endsWith('section-heading')?spec+'.tsx':spec,url));const ns=await import(spec);return new vm.SyntheticModule(Object.keys(ns),function(){for(const key of Object.keys(ns))this.setExport(key,ns[key]);},{context});});
 await compiledModule.evaluate();return compiledModule;
}
const {ChurchReport,reportAssignments}= (await load(new URL('../../app/admin/church-branding.tsx',import.meta.url))).namespace;
const profile={church_id:'church-a',churches:{name:'Independent Test Church'}};
const base={status:'active',ministry_is_active:true,end_date:null,vote_date:null,role_name:'Welcome',sub_role_name:null,person_name:'Fixture Volunteer',is_public:true,note_is_public:false,notes:'Private pastoral note',email:'private@example.invalid'};
function render(assignments){const markup=renderToStaticMarkup(createElement(ChurchReport,{supabase:{},profile,assignments}));const encoded=markup.match(/srcDoc="([\s\S]*?)"/i)?.[1];assert.ok(encoded);return encoded.replace(/&quot;/g,'"').replace(/&#x27;/g,"'").replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&amp;/g,'&');}
test('web report uses its own church and current public assignments',()=>{
 const html=render([base,{...base,person_name:'Private Person',is_public:false},{...base,person_name:'Archived Person',status:'archived'}]);
 assert.ok(html.includes('Independent Test Church'));assert.ok(html.includes('Fixture Volunteer'));assert.ok(!html.includes('Private Person'));assert.ok(!html.includes('Archived Person'));assert.ok(!html.includes('Pasco Riverview'));assert.ok(!html.includes('/embed'));
});
test('web report excludes contact data and unapproved notes',()=>{const html=render([base]);assert.ok(!html.includes('private@example.invalid'));assert.ok(!html.includes('Private pastoral note'));});
test('web report escapes user-controlled names and approved notes',()=>{const html=render([{...base,person_name:'<script>alert(1)</script>',note_is_public:true,notes:'<img src=x onerror=alert(1)>'}]);assert.ok(!html.includes('<script>'));assert.ok(html.includes('&lt;script&gt;'));assert.ok(html.includes('&lt;img'));});

test('report shortcuts keep church data scoped and distinguish votes and term windows',()=>{
 const rows=[{...base,person_name:'Awaiting',requires_vote:true,end_date:'2027-01-01'}, {...base,person_name:'Voted',requires_vote:true,vote_date:'2026-10-01',end_date:'2028-01-01'}, {...base,person_name:'Other Ministry',role_name:'Music',end_date:null}];
 assert.deepEqual(Array.from(reportAssignments(rows,'awaiting','','',new Date('2026-10-21T12:00:00')),x=>x.person_name),['Awaiting']);
 assert.deepEqual(Array.from(reportAssignments(rows,'ending','','',new Date('2026-10-21T12:00:00')),x=>x.person_name),['Awaiting']);
 assert.equal(reportAssignments(rows,'directory','Music').length,1);
 assert.equal(reportAssignments(rows,'directory','','Private pastoral note').length,0);
});
test('report workflow exposes named report and ministry choices with print after preview controls',()=>{
 const html=renderToStaticMarkup(createElement(ChurchReport,{supabase:{},profile,assignments:[base]}));
 for(const text of ['Awaiting church vote','Terms ending in six months','All ministries','Reset Filters','Print / Save PDF','1 assignment included']) assert.ok(html.includes(text));
});

test('reports use ministry section headings without repeated ministry cells',()=>{
 const rows=[{...base,role_name:'Welcome',person_name:'Z Team',leadership_rank:100,last_name:'Team'}, {...base,role_name:'Welcome',person_name:'A Leader',leadership_rank:10,last_name:'Leader'}, {...base,role_name:'Music & Worship',person_name:'B Music'}];
 for(const selected of [rows,reportAssignments(rows,'directory','Welcome')]){
  const html=render(selected);
  assert.ok(!html.includes('<th>Ministry</th>'));
  assert.ok(!html.includes('<td>Welcome</td>'));
  assert.equal((html.match(/<h2>Welcome<\/h2>/g)||[]).length,1);
  assert.ok(html.indexOf('A Leader')<html.indexOf('Z Team'));
  assert.ok(html.includes('display:table-header-group'));
 }
 const html=render(rows);
 assert.ok(html.includes('<h2>Music &amp; Worship</h2>'));
 assert.equal((html.match(/class="ministry-report"/g)||[]).length,2);
});
