# Research references — first review

Written 2026-09-17 from each project's public page (no code downloaded, nothing installed).
Verdicts are recommendations; none adds a dependency.

| Reference | What it is | Verdict for noevia |
|---|---|---|
| [Ramps](https://www.ramps.studio/) | Free web tool + JSON API: 11-step OKLCH ramps and WCAG-checked semantic tokens (light/dark) from one brand colour. No CLI or offline mode; licence not stated. | **Borrow the method, not the service.** Useful as a one-off cross-check of noevia's palette against `tests/theme-contrast`. Don't call its API at build or run time (external, unlicensed, online-only). If palettes are ever regenerated, do OKLCH ramps locally in a script. |
| [zoxilsi studio](https://github.com/zoxilsi/studio) | MIT Next.js/Three.js mesh-gradient editor; OKLab/LCH interpolation, grain post-pass. | **Reference only.** Two ideas relevant to `public/glass.js`: interpolate in OKLab to avoid muddy midpoints, and a subtle grain layer (noevia already dithers ±½ step). Consider OKLab interpolation if the light field's colour transitions look muddy on device; Three.js is far too heavy to adopt. |
| [appllama-skills](https://github.com/Appllama/appllama-skills) | MIT agent skills for Expo/React Native apps; the main skill needs the paid Appllama Pro MCP (one credit per call). Name/logo trademarked. | **Not now.** noevia has no native client and isn't React Native. The free, useful part is the practice: verify UI in a running simulator with motion, not static screenshots. That matches the existing mobile QA suites. Revisit only if an Expo client is started; the paid MCP would be the user's decision. |
| [Unsloth](https://github.com/unslothai/unsloth) | Fine-tuning/RL and local inference; Apache-2.0 core, AGPL-3.0 Studio UI; GGUF export; publishes dynamic GGUF quants. Claims NVIDIA/AMD/Intel/CPU support. | **Two separate answers.** (1) Unsloth's published GGUFs are a reasonable default source in Discover, but record them through qualification evidence like any other file, not as known-good. (2) Fine-tuning on DaServer is unlikely to be practical: the Arc A380 (6 GB, Vulkan in noevia's stack) is not a proven Unsloth target. Any spike should use a rented GPU and export a GGUF. Avoid the AGPL Studio inside noevia. |

Follow-ups, if wanted (none scheduled): an OKLCH palette cross-check script; an OKLab
blend experiment in `glass.js` checked on the iPhone and the Mac display; a "source" note for
Unsloth quants in Discover.
