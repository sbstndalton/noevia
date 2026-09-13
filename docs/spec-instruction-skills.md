# Reusable instruction skills — implemented v1

User-selected scope (2026-09-10): reusable instructions using existing approved
tools. No executable packages, dependency installers, shell hooks or new agent
framework. The lifecycle is implemented; the release record below states deployment status.

## Existing building blocks

Before this change, `index.cjs` parsed simple frontmatter from project source text with
`parseSkillFrontmatter`, lists name/description/version via `skillsIndexFor`, and
uses the existing `read_project_file` tool to load full content. Project
instructions are a separate field. `rag.filesContext` included the same
source files, so the index is not actually the only route for full skill text to
enter context. The index also omits the filename when a display name exists,
although the loading tool requires an exact filename. These are concrete gaps to
fix before adding another storage or execution system.

## Scope and lifecycle

Use project-owned Markdown source files as the initial canonical records. A user
creates or uploads a file, reviews its instructions, and explicitly enables it for
that project. Show name, description, exact filename and version. Enable/disable
and remove operate only within the owning project; copying to another project is
explicit. A future personal library may reference these records, but is not
required for v1. No cross-user skill store or automatic external import.

A small metadata subset is sufficient: non-empty scalar name and description,
optional scalar version. State that this is a restricted frontmatter format, not
full YAML compatibility. Bound metadata to 2 KiB, descriptions to 500 characters,
and the enabled index to a finite count/token budget. Reject malformed or duplicate
metadata explicitly. File content remains ordinary Markdown; no scripts execute.

Separate skill selection from ordinary sources. Skill files must not enter RAG
or whole-file fallback as instructions merely because they were uploaded. Enabled
skills enter a bounded metadata index; bodies are loaded through read_project_file
when requested. Disabled skills cannot re-enter through the ordinary source path.
Existing recognized files need a visible compatibility migration/review state,
not silent enabling or silent loss of current behavior.

Updates replace source content through the existing upload/editor path. Preserve
an enabled file's stable identity; show its changed version/content before the
next use. Removal clears selection. No background remote updates. Hash/version
pins should make a single exchange consistent if a skill changes mid-stream.

## Instructions and permissions

A skill is a task aid, never permission to use an unselected toolbox or bypass a
write decision. Project instructions and the current user request remain visible;
conflicts should be surfaced, not silently resolved by loading another file.
Tool selection stays in the existing + menu. Optional requirements can name
existing toolbox ids as informational metadata; the server does not enable them.
Missing tools produce a clear explanation and a manual choice to configure them.

A read_project_file result must remain reference text rather than acquire higher
instruction authority. Network/file sources may contain prompt injection. All
write calls still pass through the existing server allowlist and Allow once /
Decline / Allow for this chat gate. No skill can grant enduring approval.

## Representative workflow: weekly project review

A project-owned `weekly-review.md` skill instructs the model to:
1. Read the selected project notes and list decisions, unresolved questions and
   next actions, citing the source names actually read.
2. Mark missing dates or incomplete sources rather than inventing activity.
3. Draft a concise review in chat.
4. If the user requests saving and the existing notes toolbox is selected,
   propose one note creation with full content through the normal write gate.
5. On Decline, keep the draft in chat and report that no note was written.

This workflow uses existing file reads and an already integrated notes tool. It
needs no new executable capability. A model failing to load the skill must not be
reported as successful execution; show a truthful “loaded” event only when the
file tool actually returns it. Loading does not prove every instruction was followed.

## Implementation sequence and acceptance

1. Extract/test the existing parser and index. Include exact filenames, validate
   bounds and distinguish malformed candidate files from ordinary sources.
2. Add stable per-project enablement metadata and a small inspect/toggle surface
   in Sources. Define compatibility behavior for existing frontmatter files before
   shipping; no reset of unrelated projects or source content.
3. Enforce source/RAG exclusion and exchange-version consistency. Keep file reads
   within existing context limits, and make truncation explicit.
4. Add loaded-skill transcript evidence using existing tool events. Test the
   weekly-review workflow with synthetic sources and mocked notes tools.

Acceptance: tenant/project isolation, enable/disable/remove/update, exact-name
loading, metadata/body limits, RAG failure paths, missing toolbox, malformed files,
reload persistence, and all three approval decisions. Verify a disabled skill is
absent from both index and fallback context. Test provider failure and interrupted
loads without extra writes. Synthetic data only; Diary companion remains unchanged.


Implementation follow-up: the existing index now includes exact filenames and
bounded, escaped metadata. This closes the filename/index-size gap only; explicit
selection, migration and source/RAG exclusion were subsequently implemented as recorded below.

## Implementation evidence — 2026-09-12

Implemented project-owned review/enable/disable and content-hash re-review on
updates, exact filenames, metadata validation, source/RAG exclusion (including
stale vector hits), bounded paginated reads, missing-tool explanations and
server-side tenant isolation. Existing recognized files require visible review.
Selections persist; removed files lose selections. Mid-exchange updates or
disabling block subsequent reads; already loaded context cannot be revoked.
No new permissions or executable packages are introduced.

349 web tests, typecheck/build and real synthetic HTTP lifecycle/context checks
pass. Browser review covered enable/disable, updated versions, persistence,
keyboard focus and 375/768/1440 widths in both themes. Existing three-decision
approval regressions pass. Deployed as `095d308`; all three services healthy, 301 Linux server checks pass, public assets match.
