// Contract v1: drive a REAL harness through noevia's own CodeHarness modules.
//
// The spike (2026-09-17) answered "can noevia's gate stop an agent's writes". This answers the
// question after it, the one spec §3 calls contract v1: **what does a real harness actually send
// down the wire**, and does noevia's mapping hold against it? Everything in `code-*.cjs` has so
// far been tested against a scripted fake agent, which proves the rules and nothing about
// reality — the `_meta` reader especially is guesswork about shapes nobody has observed.
//
// So this uses the production modules, unmodified: code-workspace (clone mode), code-acp (socket
// channel to the sandbox supervisor), code-harness (classification, approvals, containment, job
// events). Only the approval answer and the job store are stand-ins, and both are logged.
//
// Run from a cowork-web container on the sandbox's network. Nothing here touches production
// state: its own temp dir, its own jobs store, the throwaway `scratch` repository.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const SERVER = process.env.NOEVIA_SERVER || '/app/server';
const { createCodeWorkspaces } = require(`${SERVER}/code-workspace.cjs`);
const { createCodeHarness } = require(`${SERVER}/code-harness.cjs`);
const { createAcpTransport } = require(`${SERVER}/code-acp.cjs`);
const { createJobs } = require(`${SERVER}/jobs.cjs`);
const { ACTIONS } = require(`${SERVER}/code-actions.cjs`);

const ENDPOINT = process.env.CODE_HARNESS_ENDPOINT || 'code-sandbox:8030';
const REPO = process.env.REPO || '/workspaces/repos/scratch';
const TREES = process.env.CODE_WORKSPACE_ROOT || '/workspaces/trees';
const MODEL = process.env.MODEL || 'Qwen3.5-4B-Q5_K_M';
const ENGINE = process.env.MODEL_BASE || 'http://llama:8080/v1';
const CTX = Number(process.env.MODEL_CTX || 24576);
const BUDGET_MS = Number(process.env.LIMIT_MS || 900000);
const TASK = process.env.TASK ||
  'median() in median.js has two bugs: it sorts lexicographically and in place, and it does not ' +
  'average the middle two values of an even-length list. Fix median.js so that `node test.js` ' +
  'passes. Do not edit test.js.';

const out = {
  startedAt: new Date().toISOString(), model: MODEL, endpoint: ENDPOINT,
  // Everything the harness sent, so the mapping can be checked against reality rather than hope.
  updates: [], toolCalls: [], permissions: [], decisions: [], clientFs: [], jobEvents: [],
  meta: null, result: null, error: null, testBefore: null, testAfter: null, limitations: [],
};

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'contract-v1-'));
const jobs = createJobs({ dir });
const workspaces = createCodeWorkspaces({
  dir, treeRoot: TREES, owner: { uid: 1000, gid: 1000 },
  // The harness user must own its clone; this driver already runs as root in the web image.
});

/**
 * OpenCode is configured by a file in its working directory, not by anything ACP carries. The
 * spike established this and noevia's adapter has to own it: a harness whose effective
 * permission config we cannot pin is one we refuse to run (spec §3).
 */
function pinHarnessConfig(cwd) {
  const config = {
    $schema: 'https://opencode.ai/config.json',
    autoupdate: false,
    share: 'disabled',
    provider: {
      local: {
        npm: '@ai-sdk/openai-compatible',
        name: 'noevia engine',
        options: { baseURL: ENGINE, apiKey: 'none' },
        models: { [MODEL]: { name: MODEL, tool_call: true, limit: { context: CTX, output: 4096 } } },
      },
    },
    model: `local/${MODEL}`,
    small_model: `local/${MODEL}`,
    // The pinned gate: every edit, command and fetch has to ask.
    permission: { edit: 'ask', bash: 'ask', webfetch: 'ask' },
  };
  const file = path.join(cwd, 'opencode.json');
  fs.writeFileSync(file, JSON.stringify(config, null, 2));
  fs.chownSync(file, 1000, 1000);
  return file;
}

const runTest = (cwd) => {
  try {
    require('node:child_process').execFileSync('node', ['test.js'], { cwd, encoding: 'utf8', timeout: 60000 });
    return 'passes';
  } catch (e) { return `fails: ${String(e.stdout || '').trim() || String(e.message).split('\n')[0]}`.slice(0, 200); }
};

const harness = createCodeHarness({
  jobs, workspaces,
  log: (entry) => out.jobEvents.push(entry),
  // Answer the way a person watching the card would for this task: allow what it needs inside
  // its own workspace, refuse anything that reaches further. Recorded either way.
  askApproval: async (request) => {
    out.permissions.push({
      action: request.action, kind: request.kind, title: String(request.title || '').slice(0, 160),
      command: String(request.command || '').slice(0, 300), paths: request.paths,
      reason: request.reason, hasDiff: !!request.diff,
      argumentKeys: request.arguments && typeof request.arguments === 'object' ? Object.keys(request.arguments) : null,
    });
    const allowed = [ACTIONS.EDIT, ACTIONS.EXECUTE].includes(request.action);
    out.decisions.push({ action: request.action, decision: allowed ? 'approve' : 'deny' });
    return allowed ? 'approve' : 'deny';
  },
});

const connect = createAcpTransport({ endpoint: ENDPOINT, log: (e) => out.jobEvents.push(e) });

const started = await harness.start({
  projectId: 'contract-v1', repoPath: REPO, prompt: TASK, model: MODEL,
  capabilities: [ACTIONS.READ, ACTIONS.EDIT, ACTIONS.EXECUTE],
  harness: 'opencode', sandboxKind: 'sandbox',
  connect: async (options) => {
    // Written before the agent starts, because it is what the agent reads at startup.
    out.harnessConfig = pinHarnessConfig(options.cwd);
    out.testBefore = runTest(options.cwd);
    const agent = await connect(options);
    const seen = options.handlers.sessionUpdate;
    options.handlers.sessionUpdate = (update) => {
      const kind = update?.sessionUpdate || update?.type;
      out.updates.push(kind);
      // The whole payload for the kinds whose shape noevia has to read. Guessing at field names
      // is what contract v1 exists to stop.
      if (kind === 'usage_update' || kind === 'available_commands_update') {
        out.rawUpdates = out.rawUpdates || [];
        out.rawUpdates.push(JSON.parse(JSON.stringify(update)).sessionUpdate === kind
          ? JSON.parse(JSON.stringify(update)) : update);
      }
      if (kind === 'tool_call' || kind === 'tool_call_update') {
        out.toolCalls.push({
          kind: update.kind ?? null, status: update.status ?? null,
          title: String(update.title || '').slice(0, 160),
          // What the `_meta` reader is actually looking at, in the real thing.
          metaKeys: update._meta && typeof update._meta === 'object' ? Object.keys(update._meta) : null,
          contentTypes: Array.isArray(update.content) ? [...new Set(update.content.map((c) => c?.type))] : null,
          rawInputKeys: update.rawInput && typeof update.rawInput === 'object' ? Object.keys(update.rawInput) : null,
        });
      }
      return seen(update);
    };
    for (const name of ['readTextFile', 'writeTextFile']) {
      const real = options.handlers[name];
      options.handlers[name] = async (params) => {
        out.clientFs.push({ call: name, path: params?.path });
        return real(params);
      };
    }
    return agent;
  },
});
out.taskId = started.taskId;
out.branch = started.branch;
out.workspace = started.workspace;

const deadline = Date.now() + BUDGET_MS;
const TERMINAL = ['completed', 'failed', 'cancelled', 'interrupted'];
while (!TERMINAL.includes(jobs.get(started.taskId)?.status) && Date.now() < deadline) {
  await new Promise((r) => setTimeout(r, 1000));
}
const job = jobs.get(started.taskId);
if (!TERMINAL.includes(job?.status)) { harness.cancel(started.taskId); out.error = 'budget exhausted'; }

// The workspace is released by now, so read the result off the branch in the source repository.
out.status = job?.status ?? null;
out.result = job?.result ?? null;
out.meta = job?.result?.meta ?? null;
out.error = out.error || job?.error || null;
try {
  const { execFileSync } = require('node:child_process');
  const git = (...args) => execFileSync('git', args, { cwd: REPO, encoding: 'utf8' }).trim();
  out.branchLog = git('log', '--oneline', '-3', started.branch);
  out.branchDiff = git('diff', '--stat', `main..${started.branch}`);
  const check = fs.mkdtempSync(path.join(os.tmpdir(), 'verify-'));
  execFileSync('git', ['clone', '--quiet', '--shared', '-b', started.branch, REPO, check]);
  out.testAfter = runTest(check);
  out.testUnchanged = git('diff', '--name-only', `main..${started.branch}`).split('\n').every((f) => f !== 'test.js');
  fs.rmSync(check, { recursive: true, force: true });
} catch (e) { out.verifyError = String(e.message).slice(0, 300); }

out.finishedAt = new Date().toISOString();
console.log(JSON.stringify(out, null, 2));
