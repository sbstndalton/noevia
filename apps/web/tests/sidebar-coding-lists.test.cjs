// #415: the Code-mode sidebar's "CODING PROJECTS"/"TASKS" sections were unconditionally the "not
// connected yet" stub even once #368 made the main Code panel real. CodingProjectList/
// CodingTaskList are the real-data lists Sidebar now switches to once access is confirmed —
// exported hook-free presentational components (the same shape CodingWorkspace.tsx's own
// CodeProjectPicker already is), loaded through Vite's SSR pipeline so JSX resolves exactly as in
// the app, following the pattern in coding-workspace-code-link.test.cjs.
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

async function withModule(name, fn) {
  const { createServer } = await import('vite');
  const server = await createServer({ configFile: false, root: path.resolve(__dirname, '..'), server: { middlewareMode: true }, appType: 'custom', plugins: [(await import('@vitejs/plugin-react')).default()] });
  global.window = { matchMedia: () => ({ matches: false, addEventListener() {}, removeEventListener() {} }), addEventListener() {}, removeEventListener() {} };
  global.document = { documentElement: { dataset: {}, lang: '' } };
  global.localStorage = { getItem: () => null, setItem() {}, removeItem() {} };
  global.navigator = { language: 'en-GB', languages: ['en-GB'] };
  try {
    const mod = await server.ssrLoadModule(name);
    const React = require('react');
    const { renderToStaticMarkup } = require('react-dom/server');
    return await fn(mod, React, renderToStaticMarkup);
  } finally {
    delete global.window; delete global.document; delete global.localStorage; delete global.navigator;
    await server.close();
  }
}

test('CodingProjectList lists real projects, one open button per project', () => withModule('/src/components/CodingSidebarLists.tsx', ({ CodingProjectList }, React, render) => {
  const html = render(React.createElement(CodingProjectList, {
    projects: [{ id: 'p1', name: 'Garden planner', icon: 'folder', color: 'default' }, { id: 'p2', name: 'Invoice bot', icon: 'folder', color: 'default' }],
    onOpen: () => {},
  }));
  assert.match(html, /Garden planner/);
  assert.match(html, /Invoice bot/);
  // The generic "not connected yet" stub language must not leak into the working path.
  assert.doesNotMatch(html, /not connected/);
  assert.doesNotMatch(html, /coming in a future update/);
}));

test('CodingTaskList names each task\'s project and its status, one open button per task', () => withModule('/src/components/CodingSidebarLists.tsx', ({ CodingTaskList }, React, render) => {
  const html = render(React.createElement(CodingTaskList, {
    tasks: [
      { id: 't1', projectId: 'p1', projectName: 'Garden planner', title: null, status: 'waiting_approval', stage: null, updatedAt: 1, approvalAction: null },
      { id: 't2', projectId: 'p2', projectName: 'Invoice bot', title: null, status: 'running', stage: null, updatedAt: 2, approvalAction: null },
    ],
    onOpen: () => {},
  }));
  assert.match(html, /Garden planner/);
  assert.match(html, /Needs decision/);
  assert.match(html, /Invoice bot/);
  assert.match(html, /Running/);
  assert.doesNotMatch(html, /will appear here/);
}));

test('an empty task list renders nothing — the caller shows the empty hint, not this component', () => withModule('/src/components/CodingSidebarLists.tsx', ({ CodingTaskList }, React, render) => {
  const html = render(React.createElement(CodingTaskList, { tasks: [], onOpen: () => {} }));
  assert.equal(html, '<ul class="coding-task-list"></ul>');
}));
