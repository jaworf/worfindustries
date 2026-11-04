import assert from 'node:assert/strict';
import test from 'node:test';
import vm from 'node:vm';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';

async function worker(fetcher = async () => new Response("null", {headers:{"Content-Type":"application/json"}})) {
  const code = ts.transpileModule(await readFile(new URL('../../worker/index.ts', import.meta.url), 'utf8'), {
    compilerOptions: {module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022},
  }).outputText;
  const context = vm.createContext({Request, Response, Headers, URL, AbortSignal, fetch:fetcher});
  const workerModule = new vm.SourceTextModule(code, {context});
  await workerModule.link(async specifier => {
    if (specifier.includes('app/embed/config')) {
      const helper = ts.transpileModule(await readFile(new URL('../../app/embed/config.ts', import.meta.url), 'utf8'), {compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022}}).outputText;
      const helperModule = new vm.SourceTextModule(helper,{context});
      await helperModule.link(()=>{throw new Error('Unexpected bootstrap dependency');});
      return helperModule;
    }
    if (specifier.endsWith('app-router-entry')) {
      return new vm.SyntheticModule(['default'], function () {
        this.setExport('default', {fetch: async () => new Response('directory')});
      }, {context});
    }
    return new vm.SyntheticModule(['handleImageOptimization', 'DEFAULT_DEVICE_SIZES', 'DEFAULT_IMAGE_SIZES'], function () {
      this.setExport('handleImageOptimization', () => new Response('image'));
      this.setExport('DEFAULT_DEVICE_SIZES', []);
      this.setExport('DEFAULT_IMAGE_SIZES', []);
    }, {context});
  });
  await workerModule.evaluate();
  return workerModule.namespace.default;
}

test('embed permits configured churches and rejects unsafe CSP inputs', async () => {
  const app = await worker();
  const response = await app.fetch(new Request('https://example.org/embed'), {
    EMBED_ALLOWED_ORIGINS: 'https://church.example, https://other.example https://bad.example/path http://unsafe.example https://*.wild.example *',
  }, {});
  assert.equal(response.headers.get('Content-Security-Policy'), "frame-ancestors 'self' https://church.example https://other.example");
});

test('custom embed origins do not permit framing authenticated routes', async () => {
  const app = await worker();
  const response = await app.fetch(new Request('https://example.org/admin'), {
    EMBED_ALLOWED_ORIGINS: 'https://church.example',
  }, {});
  assert.equal(response.headers.get('Content-Security-Policy'), "frame-ancestors 'self'");
});

test('church-scoped full app permits only its registered hosts',async()=>{
 const calls=[];
 const app=await worker(async(url,options)=>{calls.push(JSON.parse(options.body));return Response.json({name:'Church A',slug:'church-a',allowed_origins:['https://church-a.example','https://evil.example/path','*']});});
 const response=await app.fetch(new Request('https://example.org/embed/app/church-a'),{SUPABASE_URL:'https://db.example',SUPABASE_PUBLISHABLE_KEY:'test'},{});
 assert.equal(response.headers.get('Content-Security-Policy'),"frame-ancestors 'self' https://church-a.example");
 assert.match(response.headers.get('Cache-Control'),/no-store/);
 assert.deepEqual(calls,[{p_slug:'church-a',p_mode:'app'}]);
});
test('disabled, mismatched or failed church embeds fail closed',async()=>{
 for(const fixture of [null,{name:'Other',slug:'church-b',allowed_origins:['https://other.example']}]){
  const app=await worker(async()=>Response.json(fixture));
  const response=await app.fetch(new Request('https://example.org/embed/app/church-a'),{SUPABASE_URL:'https://db.example',SUPABASE_PUBLISHABLE_KEY:'test'},{});
  assert.equal(response.headers.get('Content-Security-Policy'),"frame-ancestors 'self'");
 }
 const app=await worker(async()=>{throw new Error('offline');});
 const response=await app.fetch(new Request('https://example.org/embed/app/church-a'),{SUPABASE_URL:'https://db.example',SUPABASE_PUBLISHABLE_KEY:'test'},{});
 assert.equal(response.headers.get('Content-Security-Policy'),"frame-ancestors 'self'");
});
