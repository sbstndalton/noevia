# noevia · Polymetal themes

The visible brand, browser title, application metadata, setup copy, and passkey display name are now lowercase **noevia**. Existing storage paths, local preference keys, deployment names, URLs, and credentials are preserved for compatibility.

Polymetal Night is the default for new users; saved Day preferences remain respected. Both themes use the requested palette swatches in `tokens.css`. Inter is the UI/journaling font; JetBrains Mono is used for code, thought-process/context text and technical status. System fallbacks remain usable without external fonts.

The navigation rail uses the canvas color. The center workspace uses a surface card. The context inspector can be opened beside projects/chats to view the selected model, routing, project file names, and memory count; its configure button opens the existing model controls. Diary and coding retain their context panels.

## Contrast decisions

WCAG 2.2 requires 4.5:1 for normal AA text, 7:1 for AAA normal text, and 3:1 for relevant UI indicators. Source: https://www.w3.org/TR/WCAG22/

The exact Night `text-muted` swatch (#717D8A) is retained as a palette reference, but is not used for text: it does not reach 4.5:1 on #21252D. Semantic secondary text uses #A3ADBA. Night garnet remains #DC2626 for filled actions with white text. Text links, focus rings and small indicators use #FF919D. Day uses the requested #5A6572 and #881337 directly. Subtle borders are decorative; inputs use separate higher-contrast control borders.

Automated contrast tests check primary text at 7:1, secondary/accent/status text at 4.5:1, focus/control boundaries at 3:1, and white action text at 4.5:1 across canvas, surface and selected tints in both themes. Rendered checks covered project, diary, coding and settings surfaces. This verifies the checked color combinations, not every WCAG criterion or future content supplied by users.

Theme background/border/color changes transition over 200 ms. Reduced-motion preferences disable transitions and animations. Visible keyboard focus rings apply throughout the UI.
