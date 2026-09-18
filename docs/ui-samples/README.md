# UI overhaul — release 1 sample screens

`foundation.html` renders three screens with the real `tokens.css`, `materials.css` and
`lens.js`, so what is approved here is what ships. Open it in Chrome (the refraction lens is
Chromium-only; other browsers show the blur-and-rim fallback):

- `foundation.html?screen=settings&theme=light` (or `dark`)
- `foundation.html?screen=project&theme=light`
- `foundation.html?screen=connectors&theme=light`

Data on these screens is synthetic. Layouts preview releases 2–5; release 1 ships only the
palette, tokens and materials. Rebuild after editing `foundation.src.html`:
`node docs/ui-samples/build.cjs <lucide-static icon-nodes.json>`.
