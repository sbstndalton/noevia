#!/usr/bin/env node
'use strict';
// Deep research variant B on the offline fixture site (docs/spec-deep-research.md §8).
// Needs an OpenAI-compatible endpoint given explicitly: RESEARCH_BASE_URL and RESEARCH_MODEL.
// Never point this at production without the operator's go-ahead; results go to stdout.
const http = require('node:http'), fs = require('node:fs'), os = require('node:os'), path = require('node:path');
const { createJobs } = require('../../apps/web/server/jobs.cjs');
const { createResearchRunner } = require('../../apps/web/server/research-runner.cjs');
const fx = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixtures.json'), 'utf8'));

async function main() {
  const base = process.env.RESEARCH_BASE_URL, model = process.env.RESEARCH_MODEL;
  if (!base || !model) { console.error('Set RESEARCH_BASE_URL and RESEARCH_MODEL (a sandbox or test endpoint).'); process.exit(2); }
  const site = http.createServer((req, res) => { const page = fx.pages[req.url]; res.writeHead(page ? 200 : 404, { 'Content-Type': 'text/html' }); res.end(page || ''); });
  await new Promise((r) => site.listen(0, '127.0.0.1', r));
  const origin = `http://127.0.0.1:${site.address().port}`;
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'noevia-research-exp-'));
  const usage = { input: 0, output: 0 };
  const complete = async (messages, { signal, maxTokens }) => {
    const r = await fetch(`${base.replace(/\/$/, '')}/chat/completions`, { method: 'POST', signal, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ model, messages, max_tokens: maxTokens, temperature: 0 }) });
    if (!r.ok) throw Error(`Model HTTP ${r.status}`);
    const v = await r.json();
    usage.input += v.usage?.prompt_tokens || 0; usage.output += v.usage?.completion_tokens || 0;
    return v.choices?.[0]?.message?.content || '';
  };
  const rows = [];
  try {
    for (const item of fx.questions) {
      const runner = createResearchRunner({
        jobs: createJobs({ dir }),
        search: async () => fx.search[item.topic].map((p) => ({ url: origin + p, title: p.slice(1) })),
        extract: async (url) => (await fetch(url)).text(),
        projectRetrieve: async () => fx.project,
        complete,
        options: { windowTokens: Number(process.env.RESEARCH_WINDOW || 16384) },
      });
      const started = Date.now();
      const job = await (await runner.start({ question: item.q })).done;
      const md = job.result?.markdown || '';
      rows.push({ q: item.q, status: job.status, error: job.error, factsCovered: item.facts.filter((f) => md.includes(f)).length, facts: item.facts.length,
        adversarialCompliance: item.forbidden.filter((f) => md.toLowerCase().includes(f.toLowerCase())).length, citationValidity: job.result?.citationValidity ?? null,
        webCalls: job.result?.webCalls ?? null, ms: Date.now() - started });
    }
  } finally { site.close(); fs.rmSync(dir, { recursive: true, force: true }); }
  console.log(JSON.stringify({ variant: 'B', model, date: new Date().toISOString(), usage, rows }, null, 2));
}
main().catch((e) => { console.error(e.message); process.exit(1); });
