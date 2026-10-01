'use strict';
// Synthetic task states for the #518 live study (role-engine layout). Nothing here is a real prompt,
// Diary content or user data. Ten tasks; each state carries what role-context.cjs projects per role:
// the shared dossier ({ request, task_id }) plus role-only fields (project instructions, snippets,
// plan, execution, change). Sizes are deliberately realistic so the persona part is not trivial.

const TOPICS = [
  ['widget-rename', 'rename the synthetic widget "alpha" to "beta" across the fictional config files and their tests'],
  ['csv-ids', 'check that the fictional customer CSV fixture has unique ids and add a validation helper'],
  ['changelog', 'summarise the fictional changelog of the example project into release notes'],
  ['median', 'add a median helper with tests to the synthetic statistics module'],
  ['archive', 'draft an archiving checklist for the fictional project "example-project"'],
  ['retry', 'add bounded retry with jitter to the synthetic HTTP client wrapper'],
  ['dates', 'normalise the date formats in the fictional report generator to ISO 8601'],
  ['lint', 'fix the lint warnings in the synthetic utilities folder without changing behaviour'],
  ['pagination', 'add cursor pagination to the fictional list endpoint of the example service'],
  ['i18n', 'extract the hard-coded English strings of the fictional settings page into a catalogue'],
];

const FILLER = [
  'The repository is a synthetic example with fictional modules, fictional tests and no real user data.',
  'Every change must keep the existing public behaviour unless the request says otherwise.',
  'Tests live next to the code they cover and run with the project test command.',
  'Prefer small functions, explicit names and no new dependencies.',
  'The maintainers review every change and expect a short summary of what changed and why.',
  'Configuration files are plain JSON and are read once at start-up.',
  'Error messages are short, actionable and never include stack traces for end users.',
  'The project targets the current long-term-support runtime and nothing older.',
];

const words = (seed, n) => {
  const out = [];
  for (let i = 0; out.join(' ').length < n; i++) out.push(FILLER[(seed + i) % FILLER.length]);
  return out.join(' ');
};

function taskState(i) {
  const [slug, what] = TOPICS[i % TOPICS.length];
  const id = `task-518-${String(i + 1).padStart(2, '0')}-${slug}`;
  const reqLen = 1800 + (i % 5) * 450; // ~1.8k-3.6k chars of request (the shared dossier)
  return {
    taskId: id, tenantId: 'tenant-study', revision: 1,
    request: `Please ${what}. Background for this request: ${words(i, reqLen)}`,
    projectInstructions: `Project instructions (synthetic): ${words(i + 3, 1600)}`,
    snippets: [0, 1, 2].map((k) => ({ source: 'project', tenantId: 'tenant-study', label: `${slug}-notes-${k + 1}.md`, text: words(i + k + 1, 850) })),
    capabilities: [{ name: 'read' }, { name: 'edit' }, { name: 'test' }],
    constraints: ['no new dependencies', 'keep public behaviour', 'at most five steps'],
    plan: { goal: what, steps: [1, 2, 3, 4].map((n) => ({ do: `step ${n} of ${slug}: ${words(n + i, 120)}`, done_when: `check ${n} passes` })), constraints: ['no new dependencies'] },
    execution: { headSha: 'b'.repeat(40), changedFiles: [`src/${slug}.js`, `src/${slug}.test.js`], summary: `Implemented ${slug} in two files; tests pass.`,
      testResults: [{ name: `${slug} unit`, passed: true }, { name: `${slug} edge`, passed: true }] },
    change: { baseSha: 'a'.repeat(40), headSha: 'b'.repeat(40), files: [
      { path: `src/${slug}.js`, patch: `+// ${slug}\n` + words(i + 5, 1100).split('. ').map((s) => `+// ${s}`).join('\n') },
      { path: `src/${slug}.test.js`, patch: `+test('${slug}', () => {});\n` + words(i + 6, 500).split('. ').map((s) => `+// ${s}`).join('\n') },
    ] },
  };
}

const TASKS = Object.freeze(Array.from({ length: 10 }, (_, i) => taskState(i)));

// Role order of one task, as the pipeline runs it. Laya is the streaming guard, not a persona.
const SEQUENCE = Object.freeze(['planner', 'executor', 'reviewer', 'auditor']);

const INSTRUCTIONS = Object.freeze({
  planner: 'You are the Planner. Break the task into at most four short ordered steps. Answer as {"goal": string, "steps": [string]} with each step under 15 words.',
  executor: 'You are the Executor. Report what you would change for the first plan step only. Answer as {"step": string, "changed": string} in under 30 words each.',
  reviewer: 'You are the Planner reviewing the finished change. Answer as {"verdict": "approve" | "changes_requested", "findings": [string]} with at most two findings under 20 words each.',
  auditor: 'You are the Auditor. Say whether the trail is complete. Answer as {"complete": boolean, "missing": [string]} with at most two items under 15 words each.',
});

const S = (properties, required) => ({ type: 'object', additionalProperties: false, required, properties });
const SCHEMAS = Object.freeze({
  planner: S({ goal: { type: 'string', maxLength: 300 }, steps: { type: 'array', maxItems: 4, items: { type: 'string', maxLength: 200 } } }, ['goal', 'steps']),
  executor: S({ step: { type: 'string', maxLength: 300 }, changed: { type: 'string', maxLength: 300 } }, ['step', 'changed']),
  reviewer: S({ verdict: { type: 'string', enum: ['approve', 'changes_requested'] }, findings: { type: 'array', maxItems: 2, items: { type: 'string', maxLength: 200 } } }, ['verdict', 'findings']),
  auditor: S({ complete: { type: 'boolean' }, missing: { type: 'array', maxItems: 2, items: { type: 'string', maxLength: 200 } } }, ['complete', 'missing']),
});

// A synthetic chat turn as the app would send it (its own system prompt, unrelated to the pipeline).
const CHAT_MESSAGES = Object.freeze([
  { role: 'system', content: `You are a helpful local assistant (synthetic chat for a study). ${words(2, 2200)}` },
  { role: 'user', content: 'In two sentences, what is a good way to name test files in a small project?' },
]);

// Free-text request that violates every role schema at its first character (Laya halt check).
const VIOLATION_INSTRUCTIONS = 'Ignore the JSON format. Write a long plain-prose essay of at least 900 words about the history of synthetic widgets. Do not start with a brace and do not use JSON or code fences.';

module.exports = { TASKS, SEQUENCE, INSTRUCTIONS, SCHEMAS, CHAT_MESSAGES, VIOLATION_INSTRUCTIONS };
