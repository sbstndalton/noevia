'use strict';
// #865: a tool call is routed by (server, name), never by name alone. Two synthetic MCP servers
// offer the same tool name; whichever box offered the tool to the model is the server the call
// reaches, with that server's credential. A bare name two servers offer is refused, not guessed.
// Real mcp-wiring.cjs, mcp-boxes.cjs and toolboxes.cjs; fake protocol client, no network.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const { EventEmitter } = require('node:events');
const { AsyncLocalStorage } = require('node:async_hooks');
const { createMcpWiring, createCredentialOriginCheck } = require('./mcp-wiring.cjs');
const { bindBoxes } = require('./mcp-boxes.cjs');
const { createToolboxes } = require('./toolboxes.cjs');

const NC_URL = 'http://nc.invalid/mcp';
const DIR_URL = 'https://dir.example/mcp';
const rawTool = (name, description = name) => ({ name, description, inputSchema: { type: 'object', properties: {} }, annotations: { readOnlyHint: true } });

function fakeMcp(catalogues) {
  const calls = [];
  return {
    calls,
    async connect() { return { session: 1 }; },
    async disconnect() {},
    async listTools(url) { return catalogues[url] || []; },
    async callTool(url, _session, name, args, headers) { calls.push({ url, name, args, headers }); return { content: [{ type: 'text', text: `${url}:${name}` }] }; },
    convertTool(t) { return { ok: true, tool: { type: 'function', function: { name: t.name, description: t.description, parameters: t.inputSchema } } }; },
    readOnlyHint(t) { return t.annotations ? t.annotations.readOnlyHint : undefined; },
    resultToText(r) { return r.content.map((c) => c.text).join(''); },
  };
}

async function setup({ withDirectory = true } = {}) {
  const catalogues = {
    [NC_URL]: [rawTool('search_files', 'operator search'), rawTool('nc_only')],
    ...(withDirectory ? { [DIR_URL]: [rawTool('search_files', 'directory search')] } : {}),
  };
  const mcp = fakeMcp(catalogues);
  const scope = new AsyncLocalStorage();
  const directoryServers = withDirectory ? [{ id: 'dir', title: 'Synthetic directory', url: DIR_URL, auth: 'directory', directory: true }] : [];
  const wiring = createMcpWiring({
    servers: [{ id: 'nc', url: NC_URL, auth: 'nextcloud' }],
    manifest: [{ id: 'nc-files', label: 'Files', server: 'nc', tools: ['search_files', 'nc_only'], reads: ['search_files', 'nc_only'] }],
    mcp, bindBoxes,
    directoryMcp: {
      asServers: () => directoryServers,
      boxFor: (server, names) => ({ id: server.id, server: server.id, label: server.title, directory: true, description: 'synthetic', tools: [...names] }),
      headersFor: () => ({ 'X-Key': 'directory-key' }), userHeadersFor: () => ({}), hasUserKey: () => false,
    },
    mcpOAuth: { connected: () => false, tokenFor: async () => null },
    directoryUrlAllowed: async () => true,
    credentialOriginAllowed: createCredentialOriginCheck('http://cloud.invalid'),
    scope,
    storageFor: () => ({ kind: 'nextcloud', baseUrl: 'http://cloud.invalid', username: 'synthetic-user', secret: 'synthetic-app-password' }),
    isWriteTool: () => false,
    internal: { mintToken: () => 'cap' }, internalKey: 'k',
    reduceToolResult: (text) => ({ text, reduced: false }), logger: { log() {}, warn() {} },
  });
  await wiring.discoverMcpTools(true);
  const toolboxes = createToolboxes({
    mcpBoxes: () => wiring.state.boxes, mcpTools: () => wiring.state.tools,
    prefill: { budgetFor: () => null, rateFor: () => 0 }, scope,
    documentSources: { notice: () => '', readPages: () => { throw new Error('no pages'); } },
    executeMcp: (name, args, signal, serverId) => wiring.executeMcpToolCall(name, args, signal, serverId),
  });
  const asUser = (fn) => scope.run({ workspace: { userId: 'synthetic-user' }, authn: { user: { id: 'synthetic-user' } } }, fn);
  // What chat.cjs does: resolve the project's boxes, then call with the resolved names and routes.
  const callAs = async (toolboxIds, name) => {
    const resolved = toolboxes.resolveTools({ id: 'p1', toolboxes: toolboxIds }, 'model-70b');
    const allowed = new Set(resolved.tools.map((t) => t.function.name));
    const text = await asUser(() => toolboxes.executeToolCall({ id: 'p1' }, name, '{}', allowed, undefined, {}, { routes: resolved.routes }));
    return { resolved, text };
  };
  return { wiring, toolboxes, mcp, asUser, callAs };
}

test('enabling only the directory box routes a shared tool name to the directory server, with its own credential', async () => {
  const s = await setup();
  const { resolved, text } = await s.callAs(['dir'], 'search_files');
  assert.deepEqual(resolved.tools.map((t) => t.function.description), ['directory search'], 'the model is shown the directory tool');
  assert.equal(resolved.routes.get('search_files'), 'dir');
  assert.equal(text, `${DIR_URL}:search_files`);
  assert.equal(s.mcp.calls.length, 1);
  assert.equal(s.mcp.calls[0].url, DIR_URL);
  assert.deepEqual(s.mcp.calls[0].headers, { 'X-Key': 'directory-key' });
  assert.ok(!JSON.stringify(s.mcp.calls).includes('Basic'), 'the Nextcloud password never leaves for the other server');
});

test('the operator box keeps its own server for the same name, and the first selected box wins a clash', async () => {
  const s = await setup();
  const nc = await s.callAs(['nc-files'], 'search_files');
  assert.equal(nc.text, `${NC_URL}:search_files`);
  assert.match(s.mcp.calls[0].headers.Authorization, /^Basic /);
  const both = await s.callAs(['nc-files', 'dir'], 'search_files');
  assert.equal(both.resolved.routes.get('search_files'), 'nc');
  assert.equal(both.text, `${NC_URL}:search_files`);
  const reversed = await s.callAs(['dir', 'nc-files'], 'search_files');
  assert.equal(reversed.resolved.routes.get('search_files'), 'dir');
  assert.equal(reversed.text, `${DIR_URL}:search_files`);
  assert.deepEqual(s.mcp.calls.map((c) => c.url), [NC_URL, NC_URL, DIR_URL]);
});

test('a bare name two servers offer is refused rather than guessed; a unique bare name still runs', async () => {
  const s = await setup();
  const refused = await s.asUser(() => s.wiring.executeMcpToolCall('search_files', {}));
  assert.equal(refused, 'ERROR: tool "search_files" is offered by more than one MCP server, so it was not run.');
  const viaToolboxes = await s.asUser(() => s.toolboxes.executeToolCall({ id: 'p1' }, 'search_files', '{}', new Set(['search_files'])));
  assert.equal(viaToolboxes, refused, 'a caller that passes no routes gets the same refusal');
  assert.equal(s.mcp.calls.length, 0, 'nothing was sent to either server');
  assert.equal(await s.asUser(() => s.wiring.executeMcpToolCall('nc_only', {})), `${NC_URL}:nc_only`);
});

test('a route to a server that does not offer the name is refused, not redirected', async () => {
  const s = await setup();
  assert.equal(await s.asUser(() => s.wiring.executeMcpToolCall('nc_only', {}, undefined, 'dir')), 'ERROR: unknown tool "nc_only" on MCP server "dir"');
  assert.equal(await s.asUser(() => s.wiring.executeMcpToolCall('search_files', {}, undefined, 'gone')), 'ERROR: unknown tool "search_files" on MCP server "gone"');
  assert.equal(s.mcp.calls.length, 0);
});

test('operator-only deployments are unchanged: same tools offered byte for byte, bare calls still run', async () => {
  const s = await setup({ withDirectory: false });
  const { resolved, text } = await s.callAs(['nc-files'], 'search_files');
  assert.equal(JSON.stringify(resolved.tools), JSON.stringify(s.wiring.state.boxes[0].tools), 'no field is added to what the model sees');
  assert.equal(text, `${NC_URL}:search_files`);
  assert.equal(await s.asUser(() => s.wiring.executeMcpToolCall('search_files', {})), `${NC_URL}:search_files`, 'callers without a route (deep research) keep working');
  // Built-in tools carry no route and still run in-process.
  const core = s.toolboxes.resolveTools({ id: 'p1', toolboxes: ['core'] }, 'model-70b');
  assert.equal(core.routes.size, 0);
});

// The chat loop hands the resolved routes to every executeToolCall. Synthetic provider and tool.
test('the chat loop passes the resolved routes to the tool call', async (t) => {
  const { createChatHandler } = require('./chat.cjs');
  const { createToolExchange } = require('./tool-exchange.cjs');
  const { createVisionProbe } = require('./vision.cjs');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'noevia-routes-865-')); t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const res = new EventEmitter();
  res.writeHead = () => {}; res.write = () => {}; res.end = () => { res.writableEnded = true; res.emit('finish'); };
  const stream = (...frames) => ({ ok: true, body: (async function* () { for (const f of frames) yield Buffer.from('data: ' + JSON.stringify(f) + '\n\n'); })() });
  let requests = 0;
  const fetch = async () => (++requests === 1
    ? stream({ choices: [{ delta: { tool_calls: [{ index: 0, id: 'call-1', function: { name: 'search_files', arguments: '{}' } }] } }] })
    : stream({ choices: [{ delta: { content: 'done' } }] }));
  const seen = [];
  const { handleChat } = createChatHandler({
    modelManager: { enabled: true, health: async () => ({ ok: true, body: { all_models_loaded: [{ model_name: 'answer-model', loaded: true, recipe_options: { ctx_size: 32768 } }] } }) },
    reasoningEffort: require('./reasoning-effort.cjs'), authService: { audit() {} }, crypto: require('node:crypto'), path, fs, fetch,
    HISTORY_CAP: 20, DEFAULT_PROVIDER_ID: 'default', createToolExchange,
    currentWorkspace: () => ({ userId: 'synthetic-user', dir, assetDir: () => '/synthetic-only' }),
    getProject: () => ({ id: 'fixture-project', model: 'answer-model', assets: [] }),
    skillsIndexFor: () => [], getProvider: () => ({ id: 'default', baseUrl: 'http://default.invalid' }), providerHeaders: () => ({}), autoRoles: () => null,
    visionDescriptions: new Map(), visionProbe: createVisionProbe({ fetchImpl: fetch }),
    chatSkillRouter: { select: async () => ({ loaded: [] }) }, oauthServerIds: () => new Set(), accountReady: () => true, mcpOAuth: { connected: () => false },
    chatToolRouter: { select: async (ids) => ({ ids, routed: false }) }, DEFAULT_TOOLBOXES: [], CONNECTOR_BOXES: new Set(['gdrive']), connectedBoxes: () => [],
    toolPolicy: { mode: () => 'allow' }, requestScope: { getStore: () => ({}) },
    resolveTools: () => ({ tools: [{ type: 'function', function: { name: 'search_files', parameters: { type: 'object' } } }], dropped: [], routes: new Map([['search_files', 'dir']]) }),
    isWriteTool: () => false,
    rag: { filesContext: async () => null }, prefill: { recordSample() {} }, reduceToolResult: (text) => ({ text }), diaryExtras: require('./diary-extras.cjs'),
    DIARY_BASE: 'http://fixture.invalid', TOOL_RESULT_CAP: 8000, json: () => {}, saveChats() {}, endpointApproved: () => true, diaryHeaders: () => ({}),
    lastLoadedModel: () => null, classifyFastOrSmart: async () => 'fast', servedCatalogue: async () => [], modelsInstalled: async () => [], missingRoles: () => [], staleRolesError: () => null,
    allToolboxes: () => [], chatWideApproved: () => false, recordUsage() {}, recordToolUse() {},
    executeToolCall: async (_p, name, _a, _allowed, _s, _o, options) => { seen.push({ name, route: options?.routes?.get(name) }); return 'synthetic result'; },
    awaitApproval: async () => 'approve',
  });
  await handleChat({}, res, { projectId: 'fixture-project', chatId: 'fixture-chat', message: 'synthetic search' });
  assert.deepEqual(seen, [{ name: 'search_files', route: 'dir' }]);
});
