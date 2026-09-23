# Lazy loading and Diary DAV copy implementation plan

Issues: [#8](https://github.com/sbstndalton/noevia/issues/8), [#9](https://github.com/sbstndalton/noevia/issues/9)

## Scope

Provide visible, announced loading feedback for lazy application views and correct Diary sharing copy to describe implemented DAV methods without promising unverified client interoperability.

## Implementation

1. Add a shared, layout-stable lazy-view fallback with concise `role="status"` text. Use it for Coding, Models, Projects, Diary, and Settings while retaining the current rejected-import reload path.
2. Ensure hidden pre-mounted views do not announce loading when they are not the active destination.
3. Rewrite Diary sharing help text around implemented capabilities: listing, reads, conditional saves, folder creation, move/rename, copy within supported bounds, and Trash-backed delete. State that locking is unsupported and that client/file-manager compatibility is bounded by tested interoperability.

## Verification

- Delay each dynamic import and assert the active view shows one status while the main layout stays present; exercise the existing load-failure recovery.
- Review copy against the DAV `Allow` construction and operation handlers. A focused text assertion may prevent reintroducing the retired method claims; no implementation-mirroring test is needed for copy alone.
- Run `npm test`, `npm run typecheck`, and `npm run build` from `apps/web`.

## Risks

The Diary view is pre-mounted, so an unconditional live region could announce during unrelated work. Loading UI must not create focus jumps. Capability copy must distinguish protocol methods from universal Finder/Windows support.
