import assert from 'node:assert/strict';
import test from 'node:test';
import vm from 'node:vm';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';

async function worker() {
  const code = ts.transpileModule(await readFile(new URL('../../worker/index.ts', import.meta.url), 'utf8'), {
    compilerOptions: {module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022},
  }).outputText;
  const context = vm.createContext({Request, Response, Headers, URL});
  const workerModule = new vm.SourceTextModule(code, {context});
  await workerModule.link(async specifier => {
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
    EMBED_ALLOWED_ORIGINS: 'https://church.example, https://other.example https://bad.example/path http://unsafe.example *',
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
