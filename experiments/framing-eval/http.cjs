'use strict';
// The real backend: an OpenAI-compatible /v1/chat/completions endpoint, local or a remote API over
// https. Built only by run.cjs after an explicit --approved-run id; tests inject `fetch` and `sleep` and
// never reach the network. The API key comes from FRAMING_EVAL_API_KEY and is only ever sent as the
// Authorization header; it is scrubbed from every error message and is never part of the stats.
const RETRY_MAX = 3;
const DEFAULT_MAX_CALLS = 60;

class CallCapError extends Error {
  constructor(max) { super(`--max-calls cap of ${max} reached; the run is aborted`); this.name = 'CallCapError'; this.fatal = true; }
}

function baseUrl(engineUrl) {
  const base = String(engineUrl || '').replace(/\/+$/, '').replace(/\/v1$/, '');
  if (!/^https?:\/\//.test(base)) throw Error('engine URL must be http(s)');
  return base;
}
const scrubber = (apiKey) => (s) => { const t = String(s ?? ''); return apiKey ? t.split(apiKey).join('[redacted]') : t; };
const defaultSleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** GET <engine>/v1/models: read-only, no inference. Returns the model ids, sorted. */
async function listModels({ engineUrl, fetch = globalThis.fetch, timeoutMs = 30000, apiKey = process.env.FRAMING_EVAL_API_KEY || '' }) {
  const scrub = scrubber(apiKey);
  const base = baseUrl(engineUrl);
  let res;
  try { res = await fetch(`${base}/v1/models`, { method: 'GET', headers: { ...(apiKey ? { Authorization: `Bearer ${apiKey}` } : {}) }, signal: AbortSignal.timeout(timeoutMs) }); } catch (e) { throw Error(scrub(`models request failed: ${e?.message || e}`)); }
  if (!res.ok) throw Error(`engine ${res.status}`);
  const data = (await res.json())?.data;
  if (!Array.isArray(data)) throw Error('no model list in the response');
  return data.map((m) => m?.id).filter((id) => typeof id === 'string').sort();
}

function createHttpBackend({ engineUrl, fetch = globalThis.fetch, timeoutMs = 120000, apiKey = process.env.FRAMING_EVAL_API_KEY || '', maxCalls = DEFAULT_MAX_CALLS, sleep = defaultSleep }) {
  const base = baseUrl(engineUrl);
  const scrub = scrubber(apiKey);
  const stats = { calls: 0, retries: 0, promptTokens: 0, completionTokens: 0, totalTokens: 0, callsWithoutUsage: 0 };
  async function post(body, signal) {
    for (let attempt = 0; ; attempt++) {
      if (stats.calls >= maxCalls) throw new CallCapError(maxCalls);
      stats.calls++;
      const timeout = AbortSignal.timeout(timeoutMs);
      let res;
      try {
        res = await fetch(`${base}/v1/chat/completions`, {
          method: 'POST', headers: { 'Content-Type': 'application/json', ...(apiKey ? { Authorization: `Bearer ${apiKey}` } : {}) },
          body: JSON.stringify(body), signal: signal ? AbortSignal.any([signal, timeout]) : timeout,
        });
      } catch (e) { throw Error(scrub(`engine request failed: ${e?.message || e}`)); }
      if (res.ok) return res;
      const retryable = res.status === 429 || (res.status >= 500 && res.status <= 599);
      if (!retryable || attempt >= RETRY_MAX) throw Error(`engine ${res.status}`);
      stats.retries++;
      const after = Number(res.headers?.get?.('retry-after'));
      await sleep(Number.isFinite(after) && after > 0 ? Math.min(after * 1000, 30000) : 1000 * 2 ** attempt);
    }
  }
  return {
    stats: () => ({ ...stats }),
    async complete({ model, messages, tools, schema, signal }) {
      const body = { model, messages, stream: false, temperature: 0, max_tokens: 1200 };
      if (Array.isArray(tools) && tools.length) body.tools = tools.map((t) => ({ type: 'function', function: { name: t.name, description: t.description, parameters: t.parameters } }));
      if (schema) body.response_format = { type: 'json_schema', json_schema: { name: 'task_packet', strict: true, schema } };
      const payload = await (await post(body, signal)).json();
      const u = payload?.usage;
      if (u && typeof u === 'object') {
        const p = Number(u.prompt_tokens) || 0, c = Number(u.completion_tokens) || 0;
        stats.promptTokens += p; stats.completionTokens += c; stats.totalTokens += Number(u.total_tokens) || p + c;
      } else stats.callsWithoutUsage++;
      const message = payload?.choices?.[0]?.message;
      if (!message) throw Error('no message');
      const toolCalls = (message.tool_calls || []).map((c) => ({ name: c.function?.name, arguments: c.function?.arguments ?? '' }));
      return { text: typeof message.content === 'string' ? message.content : '', toolCalls };
    },
  };
}
module.exports = { createHttpBackend, listModels, CallCapError, RETRY_MAX, DEFAULT_MAX_CALLS };
