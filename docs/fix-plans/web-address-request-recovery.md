# Recover Web address settings after a request fails

Issue: [#44](https://github.com/sbstndalton/noevia/issues/44). Audited on main `aa5132bfabf30361b4b69f9debf9440c2597d350`.

When the browser's GET for Web address settings rejects, the screen stays on `Loading…`. When its save POST rejects, `Checking…` remains disabled. The shared API client passes native fetch errors through, and this component currently handles only HTTP responses.

Implementation plan:

1. Keep request recovery within `WebAddressSettings.tsx`. Make a rejected initial load visible through an accessible alert and a retry control in the existing settings panel. A successful retry should populate the current address and clear that error.
2. Finish every save attempt by releasing the busy control, including network and response-read failures. Show an actionable error while retaining the admin's entered address. Preserve the existing server error, unreachable/“Save anyway”, and success behavior.
3. Guard asynchronous results so an older load/save response cannot replace a newer retry or update an unmounted view. Keep current form semantics, keyboard behavior, and layout.
4. Add a synthetic browser regression that rejects GET and POST, then succeeds on retry. Verify the alert, enabled controls, retained value, and eventual success at representative mobile and desktop widths in light and dark themes. Run web tests, typecheck, build, and design lint.

No change to the backend address policy, passkey logic, or shared API behavior is planned. Tests use synthetic loopback fixtures only.
