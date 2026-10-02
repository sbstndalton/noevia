'use strict';
// The real backend: an OpenAI-compatible /v1/chat/completions endpoint. Built only by run.cjs after
// an explicit --approved-run id; tests inject `fetch` and never reach the network. It loads nothing
// by itself beyond what the engine does when a request names a model.
function createHttpBackend({ engineUrl, fetch = globalThis.fetch, timeoutMs = 120000, apiKey = process.env.FRAMING_EVAL_API_KEY || '' }) {
  const base = String(engineUrl || '').replace(/\/+$/, '').replace(/\/v1$/, '');
  if (!/^https?:\/\//.test(base)) throw Error('engine URL must be http(s)');
  return {
    async complete({ model, messages, tools, schema, signal }) {
      const body = { model, messages, stream: false, temperature: 0, max_tokens: 1200 };
      if (Array.isArray(tools) && tools.length) body.tools = tools.map((t) => ({ type: 'function', function: { name: t.name, description: t.description, parameters: t.parameters } }));
      if (schema) body.response_format = { type: 'json_schema', json_schema: { name: 'task_packet', strict: true, schema } };
      const timeout = AbortSignal.timeout(timeoutMs);
      const res = await fetch(`${base}/v1/chat/completions`, {
        method: 'POST', headers: { 'Content-Type': 'application/json', ...(apiKey ? { Authorization: `Bearer ${apiKey}` } : {}) },
        body: JSON.stringify(body), signal: signal ? AbortSignal.any([signal, timeout]) : timeout,
      });
      if (!res.ok) throw Error(`engine ${res.status}`);
      const message = (await res.json())?.choices?.[0]?.message;
      if (!message) throw Error('no message');
      const toolCalls = (message.tool_calls || []).map((c) => ({ name: c.function?.name, arguments: c.function?.arguments ?? '' }));
      return { text: typeof message.content === 'string' ? message.content : '', toolCalls };
    },
  };
}
module.exports = { createHttpBackend };
