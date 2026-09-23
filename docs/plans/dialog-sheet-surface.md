# Restore surfaces on native dialog panels

Issue: [#58](https://github.com/sbstndalton/noevia/issues/58). Baseline: `e19e5f619a987b4be3953ee7582d55ae164e1b1c`.

“Pull from your storage” (`StorageFileBrowser.tsx`) and “Choose a folder” (`FolderPicker.tsx`) use a native `<dialog>` that is itself the `.aero.dialog-sheet` panel. The broad reset in `overlays.css` removed its background, border, and shadow. The reset outranked the plain `.aero` surface in Liquid glass. Soft and Material 3 have stronger material-specific surface rules; the live transparent-dialog observation came from Liquid glass in release `aa5132b`.

The reset now matches only a native dialog with a direct `.dialog-sheet` child. Direct-panel dialogs keep their material surface and existing scrim. Wrapper dialogs, such as `ModelPopup`, retain a transparent outer dialog and a surfaced inner panel. No component behavior or copy changes are needed.

`qa/storage-accessibility.cjs` uses a synthetic storage API and mounts the real `StorageFileBrowser` and `FolderPicker` components. Its fixture loads the production stylesheet sequence, including `materials.css`, `material3.css`, and `phone.css`. A small wrapper dialog mirrors the production wrapper structure. The browser check covers surfaces, viewport bounds, horizontal overflow, focus on open, Escape and focus restoration at 375/768/1440 in Soft, Liquid glass, and Material 3, each in light and dark. Existing storage label, connection test, and failure checks continue to run. The fixture validates browser behavior with mocked storage, not physical touch keyboards or a live connection.
