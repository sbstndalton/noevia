'use strict';
// Synthetic fixtures for the persona-swap KV-cache study (issue #518). Nothing here is a real
// prompt, Diary content or user data. Personas are deliberately short role sketches; the shared
// prefix stands in for the stable system/tool/context block every role would share.

const PERSONAS = Object.freeze({
  planner: 'Persona Planner: you break a synthetic task into at most five ordered steps, name the artifact each step yields, and never execute a step yourself.',
  executor: 'Persona Executor: you carry out one already-approved synthetic step at a time inside the sandbox and report exactly what changed, nothing more.',
  laya: 'Persona Laya (System 1 guard): you check a synthetic result against its stated acceptance criteria and answer with pass or fail plus one line of evidence.',
  auditor: 'Persona Auditor: you read the whole synthetic trail, list anything left incomplete, and say whether the trail is ready to hand back to the user.',
});
const ROLES = Object.freeze(Object.keys(PERSONAS));

const TASKS = Object.freeze([
  'Task: rename the synthetic widget "alpha" to "beta" across three fictional config files.',
  'Task: summarise a fictional two-paragraph changelog into one sentence.',
  'Task: check that a fictional CSV of five rows has unique ids in the first column.',
  'Task: draft a fictional checklist for archiving a project called "example-project".',
]);

// Role switches exercised in one repetition. Every role appears, then roles are revisited so slot
// restore of a previously seen persona can be compared with a fresh persona.
const SEQUENCE = Object.freeze(['planner', 'executor', 'laya', 'auditor', 'planner', 'laya', 'executor', 'auditor']);

const PREFIX_SENTENCES = [
  'Shared context: the workspace is a synthetic project with fictional files, and no real user data is present.',
  'Shared rules: answer briefly, cite only the fictional material given, and never invent tool results.',
  'Shared vocabulary: an artifact is a named output, a step is one unit of work, and a trail is the ordered list of steps.',
  'Shared limits: at most five steps per plan, one sentence of evidence per check, and no network access of any kind.',
];

// Deterministic stable prefix of `paragraphs` paragraphs (about 25 tokens each on typical tokenizers).
function sharedPrefix(paragraphs) {
  const out = [];
  for (let i = 0; i < paragraphs; i++) out.push(`[${i + 1}] ${PREFIX_SENTENCES[i % PREFIX_SENTENCES.length]}`);
  return out.join('\n');
}

module.exports = { PERSONAS, ROLES, TASKS, SEQUENCE, sharedPrefix };
