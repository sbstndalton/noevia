'use strict';
// Attributable model evidence import (#266): alongside a model download, fetch permitted
// public model-card metadata (license, task, benchmark claims as published by the source)
// for the exact repository the artifact came from, and record it as external evidence —
// separate from the local benchmark/calibration evidence in evidence.cjs. This never blocks
// or gates the download itself: every caller here is best-effort and swallows its own errors.
//
// Trust boundary: the source host is a fixed allow-list entry (Hugging Face), never a
// user-supplied URL. The repository name is validated before it is interpolated into the
// URL. The response is treated as untrusted text: every field is stripped of markup/control
// characters and capped in length before it is stored or rendered. Requests use the shared
// fetchJson helper (timeout + response-size cap) and never follow a redirect.

const evidenceLib = require('./evidence.cjs');

const ALLOWED_HOSTS = new Set(['huggingface.co']);
const CHECKPOINT_RE = /^[\w.-]+\/[\w.-]+(?::[\w.-]+)?$/;
const MAX_FIELD = 2000;
const MAX_LIST = 8;

// Strip HTML/markup and control characters, collapse whitespace, and cap length. Model-card
// text is untrusted third-party content; it is stored and later rendered as plain text, so it
// must never carry tags or unbounded size into the evidence log or the UI.
function sanitizeText(value, maxLen = MAX_FIELD) {
  if (value == null) return null;
  const text = String(value)
    .replace(/<[^>]*>/g, ' ')
    // eslint-disable-next-line no-control-regex
    .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
  if (!text) return null;
  return text.length > maxLen ? `${text.slice(0, maxLen)}…` : text;
}

// The download checkpoint is `org/repo` or `org/repo:quant`; the model card lives at the
// repo, not the quantization tag.
function repoFromCheckpoint(checkpoint) {
  if (!CHECKPOINT_RE.test(String(checkpoint || ''))) return null;
  return String(checkpoint).split(':')[0];
}

function cardUrl(repo) {
  return `https://huggingface.co/api/models/${repo.split('/').map(encodeURIComponent).join('/')}`;
}

function hostAllowed(rawUrl) {
  try {
    const u = new URL(rawUrl);
    return u.protocol === 'https:' && ALLOWED_HOSTS.has(u.hostname.toLowerCase());
  } catch {
    return false;
  }
}

// Public model-card fields worth recording, matched against the standard HF card schema
// (huggingface.co/docs/hub/model-cards). Every string is sanitised and capped; the eval
// section is capped to a handful of entries to keep one card bounded.
function normalizeCard(repo, body) {
  if (!body || typeof body !== 'object') return null;
  const cardData = body.cardData && typeof body.cardData === 'object' ? body.cardData : {};
  const revision = /^[a-f0-9]{6,64}$/i.test(String(body.sha || '')) ? body.sha : null;
  const license = sanitizeText(cardData.license || body.license, 100);
  const tags = Array.isArray(body.tags) ? body.tags.filter((t) => typeof t === 'string').slice(0, MAX_LIST).map((t) => sanitizeText(t, 60)) : [];
  const modelIndex = Array.isArray(cardData['model-index']) ? cardData['model-index'] : [];
  const evaluationClaims = [];
  for (const entry of modelIndex.slice(0, 3)) {
    for (const result of (Array.isArray(entry?.results) ? entry.results : []).slice(0, MAX_LIST)) {
      if (evaluationClaims.length >= MAX_LIST) break;
      const metrics = Array.isArray(result?.metrics) ? result.metrics : [];
      for (const metric of metrics.slice(0, 3)) {
        evaluationClaims.push({
          task: sanitizeText(result?.task?.type || result?.task?.name, 120),
          dataset: sanitizeText(result?.dataset?.name, 120),
          metric: sanitizeText(metric?.type || metric?.name, 60),
          value: typeof metric?.value === 'number' || typeof metric?.value === 'string' ? sanitizeText(metric.value, 40) : null,
        });
      }
    }
  }
  return {
    repo,
    revision,
    license,
    pipelineTag: sanitizeText(body.pipeline_tag, 80),
    libraryName: sanitizeText(body.library_name, 80),
    tags,
    evaluationClaims,
    cardExcerpt: sanitizeText(cardData.model_summary || cardData.summary || body.description, 1200),
  };
}

// identityHash scoped to the artifact only (spec-agent-execution keys evidence to full
// runtime identity for benchmark evidence; a public model card describes the weights, not
// the serving configuration, so it must stay attributed to the same record across a preset
// or context-window change and only change when the artifact itself does).
function artifactIdentityHash(artifact) {
  return evidenceLib.identityHash({ artifact });
}

// Fetches and normalizes one model's external evidence. Never throws: every failure mode
// (bad checkpoint, disallowed host, offline, oversized/invalid response) resolves to
// { ok:false, reason }, so a caller wiring this into "download finished" cannot let a
// metadata failure block or fail the download.
async function fetchModelCardEvidence({ checkpoint, artifact, fetchJson, now = () => Date.now() }) {
  const repo = repoFromCheckpoint(checkpoint);
  if (!repo) return { ok: false, reason: 'invalid checkpoint' };
  if (!artifact) return { ok: false, reason: 'artifact not available' };
  const url = cardUrl(repo);
  if (!hostAllowed(url)) return { ok: false, reason: 'source host not allowed' };
  let response;
  try {
    response = await fetchJson(url, { redirect: 'error' }, 15000, 1024 * 1024);
  } catch {
    return { ok: false, reason: 'fetch failed' };
  }
  if (!response || !response.ok) return { ok: false, reason: `source responded ${response?.status ?? 'error'}` };
  if (response.body?.private) return { ok: false, reason: 'source repository is private' };
  const value = normalizeCard(repo, response.body);
  if (!value) return { ok: false, reason: 'unrecognized source response' };
  return {
    ok: true,
    record: {
      category: 'external_model_card',
      result: 'reported',
      identityHash: artifactIdentityHash(artifact),
      value,
      suite: { name: 'huggingface-model-card', version: 1 },
      source: 'external',
      provenance: { sourceUrl: url, retrievedAt: now() },
      // Surfaced verbatim next to the record: this is a source's own claim, never a local
      // measurement, and must never be presented as verified.
      limitations: ['unverified, from source: published by the model repository, not measured locally'],
    },
  };
}

// Records the evidence via the shared append-only store (evidence.cjs), deduped by the
// artifact-scoped identity: a refetch of the same artifact with unchanged card data appends
// nothing; a changed card (or a new artifact under the same model name) appends a new record.
async function importModelEvidence({ model, checkpoint, artifact, fetchJson, store, now }) {
  const fetched = await fetchModelCardEvidence({ checkpoint, artifact, fetchJson, now });
  if (!fetched.ok || !store) return fetched;
  const entry = store.appendIfChanged({ model, identityHash: fetched.record.identityHash, ...fetched.record });
  return { ok: true, record: entry };
}

// State for one model's external evidence against its current artifact. Unlike
// evidence.cjs's derive() (scoped to the full runtime identity: build, preset, context),
// external evidence is scoped to the artifact alone, so a preset or context-window change
// must not turn a reported card 'stale'.
function deriveExternal(records, { model, artifactHash }) {
  const mine = (records || []).filter((r) => r.model === model && r.category === 'external_model_card');
  if (!artifactHash) return { state: 'unavailable', record: mine.at(-1) || null };
  const matching = mine.filter((r) => r.identityHash === artifactHash);
  const newest = matching.at(-1);
  if (newest) return { state: 'reported', record: newest };
  const older = mine.at(-1);
  if (older) return { state: 'stale', record: older };
  return { state: 'unverified', record: null };
}

module.exports = {
  sanitizeText,
  repoFromCheckpoint,
  cardUrl,
  hostAllowed,
  normalizeCard,
  artifactIdentityHash,
  fetchModelCardEvidence,
  importModelEvidence,
  deriveExternal,
  ALLOWED_HOSTS,
};
