'use strict';
// What may leave the server through an EXTERNAL provider (#447).
//
// An external provider is one the server marks as sending chats to a third-party service on a
// person's own account: today only "Sign in with ChatGPT" rows (kind chatgpt-oauth, or a row the
// server flagged external:true; neither can be set through POST /api/providers). Custom
// OpenAI-compatible endpoints keep their existing behaviour.
//
// The rules, enforced in code by chat.cjs rather than by instructions to the model:
//   1. Diary text never goes to an external provider. The Diary space itself always talks to the
//      Diary sidecar; Diary extras (the preparation step that runs on a chat model, with the Diary
//      message as its prompt) are refused on an external provider.
//   2. Private tools are not offered through an external provider: the `diary` toolbox would read
//      the private journal into a request bound for a third party.
//   3. Project images are not attached automatically (spec-document-understanding: "Do not
//      automatically send sources to a new cloud provider").
// Every write still goes through the approval card; nothing here widens what a chat may do.

const PRIVATE_TOOLBOXES = new Set(['diary']);

function isExternalProvider(provider) {
  return !!provider && (provider.kind === 'chatgpt-oauth' || provider.external === true);
}

/** Why this request may not use this provider, or null. */
function egressRefusal({ provider, spaceId, projectId, diaryProjectId }) {
  if (!isExternalProvider(provider)) return null;
  if ((typeof spaceId === 'string' && spaceId.startsWith('diary')) || (diaryProjectId && projectId === diaryProjectId)) {
    return `Diary text is never sent to an external provider (${provider.label || 'ChatGPT'}). Choose a local model for Diary attachments and tools.`;
  }
  return null;
}

/** Removes private toolboxes from the selection, in place; returns the ids removed. */
function stripPrivateToolboxes(selected, provider) {
  if (!isExternalProvider(provider)) return [];
  const removed = [];
  for (let k = selected.length - 1; k >= 0; k--) if (PRIVATE_TOOLBOXES.has(selected[k])) removed.unshift(...selected.splice(k, 1));
  return removed;
}

module.exports = { PRIVATE_TOOLBOXES, isExternalProvider, egressRefusal, stripPrivateToolboxes };
