# Show lazy-view loading and correct Diary DAV capabilities

Implemented for review; not merged or deployed. Issues: [#8](https://github.com/sbstndalton/noevia/issues/8), [#9](https://github.com/sbstndalton/noevia/issues/9).

Coding, Models, Projects, Diary, and Settings now show a shared visible `role="status"` fallback. Only the active destination announces; a pre-mounted hidden Diary stays silent. Settings uses the existing stage layout so its loading message remains visible while the underlying app is hidden. The existing rejected-import retry/reload path is retained.

Diary sharing copy now describes reads, saves, folders, move/rename, same-Diary copies, Trash-backed deletion/overwrite preservation, protected-file versions, and unsupported locking. It does not promise Finder or Windows compatibility.

Validation: 1,247 web tests pass; typecheck, production build, and design lint pass. `qa/lazy-views.cjs` covers deferred loading, hidden Diary silence, and rejection/reload. `qa/lazy-app.cjs` holds each of the five actual built chunks and verifies exactly one visible loading message, retained navigation, and replacement by the loaded view. Run with an existing Playwright installation via `PLAYWRIGHT_MODULE`.

Synthetic combined-UI QA checked Chat, Projects, Diary, Settings, Code preview and setup welcome at 375/768/1440 in both themes (36 combinations, no document overflow). This is bounded layout coverage, not every workflow. A live-resized project composer at effective 375 CSS pixels had identical geometry after reload. Native Brave 100%→90% reflowed immediately and looked the same after reload. The reported reload-only resize/zoom issue was not reproduced; pinch zoom and physical devices remain untested. In-app browser screenshot artifacts and a pre-existing 80% scale required actual CSS-width measurements; emulation was not counted as browser zoom.

No DAV implementation changes or live client interoperability tests were performed.
