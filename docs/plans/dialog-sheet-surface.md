# Dialogs that are themselves the sheet render with no surface

Status: plan only; implementation pending. Found in live testing on release `aa5132b`, 2026-09-23 (Liquid glass material, dark).

## What happens

Two native dialogs render with a transparent background and no border, so their title, folder list and buttons float over the blurred page:

- **Pull from your storage** (`StorageFileBrowser.tsx`, `<dialog class="modal-card aero dialog-sheet">`). This is a regression from #15, which moved it to a native dialog. It shipped in `aa5132b`.
- **Choose a folder** (`FolderPicker.tsx`, `<dialog class="folder-picker aero dialog-sheet">`), used by Sources → Link folder. Broken since UI overhaul release 3 (`4e32b22`).

Measured in the live page: `getComputedStyle(dialog).backgroundColor === 'rgba(0, 0, 0, 0)'`, `backgroundImage: none`, `border: 0`.

## Cause

`styles/overlays.css:66`:

```css
dialog.dialog-sheet, dialog:has(> .dialog-sheet) { border: 0; padding: 0; background: none; box-shadow: none; }
```

The rule is right for dialogs that are only the backdrop around an inner `.dialog-sheet` panel (the `:has(> .dialog-sheet)` case). But `dialog.dialog-sheet` also matches dialogs that **are** the panel. Its specificity (0,1,1) beats the `.aero` surface rules (0,1,0) in `materials.css` and `material3.css`, so the panel's own surface, border and blur are wiped. `dialog.aero.dialog-sheet` (line 81) sets size and padding but no surface.

## Fix

- Limit the reset to backdrop-only dialogs, e.g. `dialog:has(> .dialog-sheet)`, and let `dialog.aero.dialog-sheet` keep the material's `.aero` surface. Alternatively restate the surface on `dialog.aero.dialog-sheet` for each material. The first is smaller and matches the comment on line 79 ("a dialog that is itself the frame").
- Check all three materials (Soft, Liquid glass, Material 3) in light and dark at 375/768/1440, for both dialogs plus one wrapper-style dialog (e.g. `EditProjectModal`) to confirm it's unchanged.
- Add a QA assertion: an open `dialog.aero.dialog-sheet` has a non-transparent background or a backdrop filter. `qa/storage-accessibility.cjs` from #15 is the natural place; it passed because it checks focus and labels, not the surface.
