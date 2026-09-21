'use strict';
// A mock llama-server for runner tests: plain HTTP, canned responses, no model. FAKE_MODE:
//   ok (default)   valid readouts        exit   dies during startup
//   slow           each completion waits FAKE_DELAY_MS         format   '**' at the answer position
const http = require('node:http'), fs = require('node:fs');
const port = Number(process.argv[process.argv.indexOf('--port') + 1]);
const mode = process.env.FAKE_MODE || 'ok', delay = Number(process.env.FAKE_DELAY_MS || 400);
if (process.env.FAKE_PIDFILE) fs.writeFileSync(process.env.FAKE_PIDFILE, String(process.pid));
if (process.argv.includes('--version')) { process.stderr.write('version: fake (build 0)\n'); process.exit(0); }
if (mode === 'exit') process.exit(3);
const L = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
http.createServer((req, res) => {
  let body = ''; req.on('data', (c) => (body += c)); req.on('end', () => {
    const b = body ? JSON.parse(body) : {};
    const send = (o) => { res.setHeader('content-type', 'application/json'); res.end(JSON.stringify(o)); };
    if (req.url === '/health') return send({ status: 'ok' });
    if (req.url === '/props') return send({ model_path: '/fake.gguf', build_info: 'fake-build', default_generation_settings: { n_ctx: 8192 } });
    if (req.url === '/tokenize') { const t = b.content.trim(); return send({ tokens: [{ id: 100 + L.indexOf(t) * 2 + (b.content.startsWith(' ') ? 1 : 0), piece: b.content }] }); }
    if (req.url === '/apply-template') return send({ prompt: 'P' });
    const reply = () => (b.logit_bias
      ? send({ completion_probabilities: [{ top_probs: b.logit_bias.map(([id], i) => ({ id, token: 'x', prob: i === 0 ? 0.6 : 0.4 / (b.logit_bias.length - 1) })) }] })
      : send({ completion_probabilities: [{ top_logprobs: mode === 'format' ? [{ id: 2, token: '**', logprob: -0.01 }] : [{ id: 100, token: 'A', logprob: -0.2 }, { id: 102, token: 'B', logprob: -2 }] }], timings: { prompt_n: 12, prompt_ms: 5 } }));
    if (mode === 'slow') setTimeout(reply, delay); else reply();
  });
}).listen(port, '127.0.0.1');
