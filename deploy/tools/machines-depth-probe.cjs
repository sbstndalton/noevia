'use strict';
// One probe in a fresh process: node probe-one.cjs <context> <depth> [leaf]
// Prints JSON {ctx, depth, ok, status, name, writes, err}. Contexts exercise the reference route and
// bare String(JSON.parse()) at different stack bases. Run with the production Node and flags.
const path = require('node:path');
const core = process.env.CORE || '/core';
const [ctx, depthArg, leafArg = '"x"'] = process.argv.slice(2);
const depth = Number(depthArg);
const nest = (n, leaf) => '['.repeat(n) + leaf + ']'.repeat(n);
const out = (o) => { process.stdout.write(JSON.stringify({ node: process.version, v8: process.versions.v8, execArgv: process.execArgv, ctx, depth, leaf: leafArg, ...o }) + '\n'); };
const { createInferenceMachines } = require(core + '/tests/reference/inference-machines.node.cjs');
const { createInferenceMachineRoutes, PATH } = require(core + '/tests/reference/inference-machines-route.node.cjs');
const comma = (n) => { let s = '"x"'; for (let i = 0; i < n; i++) s = `["p",${s},"q"]`; return s; };
const shaped = (n) => (process.env.SHAPE === 'comma' ? comma(n) : nest(n, leafArg));
const raw = '{"action":"add","name":' + shaped(depth) + ',"address":"192.168.1.2"}';

function makeRoute(readJson, sink, rows) {
  const machines = createInferenceMachines({ store: { get: k => rows.get(k), set: (k, v) => rows.set(k, v) }, audit() {}, log() {} });
  return createInferenceMachineRoutes({ json: (_, status, body) => { sink.result = { status, name: body.machine?.name, error: body.error }; }, readJson, machines, health: {} });
}
const callRoute = (route) => route({ method: 'POST' }, { setHeader() {} }, { path: PATH, authn: { user: { id: 'synthetic', role: 'admin' } }, url: new URL('http://local' + PATH) });

async function viaRoute() {
  const rows = new Map(); const sink = {};
  const route = makeRoute(async () => JSON.parse(raw), sink, rows);
  await callRoute(route);
  out({ ok: sink.result?.status === 201, ...sink.result, writes: rows.size });
}
async function viaHttp(warm) {
  const http = require('node:http');
  const rows = new Map(); let sink = {};
  const { readJson } = require(core + '/server/http.cjs');
  const machines = createInferenceMachines({ store: { get: k => rows.get(k), set: (k, v) => rows.set(k, v) }, audit() {}, log() {} });
  const route = createInferenceMachineRoutes({ json: (res, status, body) => { sink = { status, name: body.machine?.name, error: body.error, body: status === 500 ? body : undefined }; res.statusCode = status; res.end(JSON.stringify(body)); }, readJson, machines, health: {} });
  const server = http.createServer((req, res) => { route(req, res, { path: PATH, authn: { user: { id: 'synthetic', role: 'admin' } }, url: new URL('http://local' + PATH) }).catch((e) => { sink = { status: 500, error: 'unhandled ' + e.constructor.name }; res.statusCode = 500; res.end('{}'); }); });
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  const post = (body) => new Promise((resolve, reject) => { const rq = http.request({ port: server.address().port, host: '127.0.0.1', method: 'POST', path: PATH, headers: { 'content-type': 'application/json', 'content-length': Buffer.byteLength(body) } }, (res) => { res.resume(); res.on('end', resolve); }); rq.on('error', reject); rq.end(body); });
  if (warm) for (let i = 0; i < 3000; i++) await post(JSON.stringify({ action: 'add', name: 'n' + i, address: 'not an address' }));
  rows.clear(); sink = {};
  await post(raw);
  out({ ok: sink.status === 201, ...sink, writes: rows.size, warm });
  server.close();
}
function bare(how) {
  const text = shaped(depth);
  const run = () => { try { const s = String(JSON.parse(text)); out({ ok: true, name: s }); } catch (e) { out({ ok: false, err: e.constructor.name }); } };
  if (how === 'top') run();
  else if (how === 'timer') setTimeout(run, 0);
  else if (how === 'micro') queueMicrotask(run);
  else if (how === 'async') (async () => { await null; run(); })();
}
(async () => {
  if (ctx === 'route') await viaRoute();
  else if (ctx === 'http-cold') await viaHttp(false);
  else if (ctx === 'http-warm') await viaHttp(true);
  else if (ctx.startsWith('bare-')) bare(ctx.slice(5));
  else throw new Error('ctx');
})().catch(e => { out({ ok: false, err: 'harness ' + e.constructor.name + ' ' + String(e.message).slice(0, 100) }); });
