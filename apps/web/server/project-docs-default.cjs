'use strict';
// #659: a project that holds uploaded files gets its Project documents toolbox, once.
//
// New projects start with `core` only (least privilege). Without the Project documents box, an
// edit request about an uploaded file had no project tool to go to, so an account with Google
// Drive connected got drive_update_file instead: a whole-file overwrite with no path on its
// card. The box is what edits a project's uploads in place, conditionally, and names the file on
// the approval card (#648), so a project that has uploads should have it.
//
// Why here, and stored, rather than computed at chat time or folded into Core:
//  - The project's `toolboxes` list is what the composer and the model popup show as ticked. A
//    box added only inside the chat loop would be sent while showing unticked.
//  - It is added the first time the project holds an upload (an upload, or a file synced into
//    the project's own upload folder), and a marker records that. Unticking it afterwards is a
//    choice this never overrides.
//  - A project without uploads (only attached folders, or nothing) keeps exactly what it had.
//    An empty toolbox list is a deliberate "no tools" and is left alone. Core stays the same
//    for every chat, and the box is only added where the server offers it (the internal MCP
//    server is configured), so nothing appears that could not run.
//  - Every write in the box still stops at the approval card, with all three actions.
const BOX = 'project-docs';

/** An upload: a file the project owns itself (a local upload, or one in its own upload folder),
 *  not one read from a folder the user attached. The same files the box can edit (#648). */
function hasUploads(project) {
  return (Array.isArray(project && project.files) ? project.files : [])
    .some((f) => f && (!f.source || (project.projectFolder && f.source === project.projectFolder)));
}

/**
 * Adds the Project documents box to `project.toolboxes` the first time the project holds an
 * upload. Mutates the project; the caller saves it. Returns true when the project changed.
 * @param {object} project
 * @param {{ offered: (id: string) => boolean, defaults: string[] }} options
 */
function applyProjectDocsDefault(project, { offered, defaults }) {
  if (!project || project.docsToolboxDefaulted === true || !hasUploads(project)) return false;
  if (!offered(BOX)) return false; // not offered on this server: decide again once it is
  const current = Array.isArray(project.toolboxes) ? project.toolboxes : [...defaults];
  if (!current.length) return false; // "no tools" was chosen on purpose
  project.docsToolboxDefaulted = true;
  if (!current.includes(BOX)) project.toolboxes = [...current, BOX];
  return true;
}

module.exports = { applyProjectDocsDefault, hasUploads, BOX };
