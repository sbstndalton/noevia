# Third-party notices

## scratchhax/model-loader

`apps/web/server/gguf-meta.cjs` and `apps/web/server/llamacpp-autoconfig.cjs` adapt the
GGUF metadata reader and KV-cache/projector sizing from
[scratchhax/model-loader](https://github.com/scratchhax/model-loader) at commit
`e11a6ec307fa405144678930d507046163369b46`, under the MIT License. The full source is
folded into `services/model-manager` (see its `UPSTREAM.md`); noevia's changes are in git
history after the import commit:

```
MIT License

Copyright (c) 2026 scratchhax

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## nikdelvin/liquid-glass (MIT)

`apps/web/public/lens.js` adapts the displacement-map technique from
https://github.com/nikdelvin/liquid-glass, Copyright (c) 2025 Nikita Stadnik, MIT.
Full text: `apps/web/public/liquid-glass-LICENSE.txt`.

## Impeccable (Apache-2.0)

`.claude/skills/impeccable/` is the Impeccable agent skill v4.3.1 from
https://github.com/pbakaus/impeccable, Apache License 2.0 (`.claude/skills/impeccable/LICENSE`).
Development tooling only; not part of the shipped image.
