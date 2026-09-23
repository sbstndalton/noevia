# Storage UI and test-contract implementation plan

Issues: [#5](https://github.com/sbstndalton/noevia/issues/5), [#6](https://github.com/sbstndalton/noevia/issues/6), [#7](https://github.com/sbstndalton/noevia/issues/7)

## Scope

Give storage fields persistent labels, test edited non-secret values with the saved secret, and make the project storage browser a complete accessible dialog.

## Implementation

1. Refactor `StoragePicker` fields into labelled controls with stable ids. Keep configured-secret guidance as help text rather than using it as the field name.
2. Define an explicit storage-test request shape. When `useSavedSecret` is requested, merge only the stored secret into the submitted edited connection on the server. Never return or log it. Apply validation and outbound-origin approval to the merged target.
3. Preserve the existing full-saved-connection test mode only if another caller needs it; use distinct names so the two contracts cannot be confused.
4. Upgrade `StorageFileBrowser` to a labelled modal dialog with initial focus, focus containment, Escape close, trigger-focus restoration, and announced async errors. Prefer a shared dialog primitive if it already satisfies these behaviors.

## Verification

- Component tests query each Nextcloud, WebDAV, and S3 field by persistent label after values are entered.
- Route tests prove edited WebDAV endpoint/folder and S3 endpoint/bucket are tested with the saved secret, and that the secret never appears in a response.
- Dialog tests cover role/name, initial and returned focus, Tab containment, Escape, and an alert on browse/read failure.
- Run `npm test`, `npm run typecheck`, and `npm run build` from `apps/web`.

## Risks

The merge contract must prevent clients from selecting another account's credentials or bypassing SSRF checks. Secret-preservation behavior during Save is separate and must remain unchanged. Focus restoration needs stable trigger ownership across both project entry points.
