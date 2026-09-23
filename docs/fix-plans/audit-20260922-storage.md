# Fix storage test settings, labels, and browser dialog

Implemented for review; not merged or deployed. Issues: [#5](https://github.com/sbstndalton/noevia/issues/5), [#6](https://github.com/sbstndalton/noevia/issues/6), [#7](https://github.com/sbstndalton/noevia/issues/7).

Storage controls now have persistent visible labels and stable associations, with saved-secret guidance in help text. Test sends edited fields with `useSavedSecret`; the server reads only the signed-in account's secret and requires the same origin and storage kind before applying the existing outbound approval policy. Edited WebDAV paths/folders and S3 endpoint paths/buckets/access keys are tested rather than silently using the old connection. The legacy `useSaved` API remains compatible.

The storage browser uses a named native modal dialog with initial focus, Tab/Shift+Tab wrapping, Escape and backdrop dismissal, trigger-focus restoration, and announced load/read errors.

Validation: 1,250 web tests pass; typecheck, production build, and design lint pass. Route tests capture WebDAV headers, verify the S3 signature, assert tenant lookup and cross-origin/type rejection, and confirm no secret in the response or saved-setting mutation. `PLAYWRIGHT_MODULE=/path/to/playwright node apps/web/qa/storage-accessibility.cjs` tests actual components with mocked APIs: all three storage types, edited Test payload, focus wrapping/restoration, Escape, errors, and 375/768/1440 light/dark layouts. Manual synthetic-app checks covered the storage form and project import dialog.

Limits: no real storage connection, corpus, or production mutation. Physical devices and assistive-technology speech were not tested.
