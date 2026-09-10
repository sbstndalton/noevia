# Document and image understanding: findings and bounded proposal

2026-09-10, inspected against `5fd568c` on main. Trigger: the user's mmproj warning
on a photo and no-text-layer warning on financial PDFs. This is an investigation
and implementation proposal, **not an OCR release or a production diagnosis**.
No production access, private documents, diary prompts, or corpus changes.

## Source-completeness implementation follow-up — 2026-09-10

The bounded section 1 batch is implemented locally, not deployed. The remaining
sections below retain the original audit/proposal; this follow-up supersedes their
statements about the current source-completeness and binary-read behavior.

- S3 and WebDAV binary reads now preserve bytes and enforce the 25 MB limit while
  consuming the stream, including missing or misleading Content-Length headers.
  Over-limit streams are cancelled; existing auth, roots and redirect refusal stay.
- Local uploads, legacy `/documents` uploads and linked-folder refresh use one
  native-PDF contract. Original bytes and extracted pages are saved under the
  authenticated workspace's `project-documents/<hashed-project-id>/` directory.
  Remote files are not rewritten by extraction. Original downloads resolve the
  source through project membership; arbitrary hashes/paths are never accepted.
- Versions hash the original bytes and extractor version. Unchanged refreshes
  reuse on-disk extraction only within the same user/project. Current bytes and
  the last readable version are retained; superseded versions and removed sources
  are pruned when project source operations are idle. This is not unlimited history.
- The source stores ready/partial/failed state, physical page count/status,
  truncation, native item coordinates, hashes and separate indexing status. A
  failed replacement keeps old text explicitly marked stale; a new failure stays
  visible with no readable text. All affected refresh filenames are reported.
  Existing source rows display status and an original-PDF download action.
- Native extraction is page-aware, with page labels carried into RAG chunks.
  Image-bearing pages are conservatively `ocr-needed`, even with a digital header.
  This intentionally flags decorative images too: it is not image-region OCR or
  proof that text is missing. Blank pages remain blank. Password and parse failures
  have explicit messages. There is still no OCR engine or structured table parser.
- The compact project summary stays capped at 200,000 characters. A separate
  page store retains up to 300 pages / 2,000,000 characters, with 200,000 characters
  per page. Limits set partial/truncated status; page requests outside extracted
  coverage fail explicitly. These output limits are not a hard CPU/RAM/time sandbox
  for the native parser; worker isolation remains separate follow-up work.
- `read_project_file` now accepts `startPage`, `endPage` (at most 5 pages) and
  `offset`; responses include source/text versions, page status, and a continuation
  offset for the 8,000-character payload cap. The authenticated
  `/api/projects/:id/documents/pages?name=...&startPage=...` endpoint exposes the
  same contract. Default chat context remains bounded excerpts, with completeness
  notices; missing vector support is not a claim of full-document retrieval.
- Upload, refresh and remote deletion serialize per project. Detached folders and
  deleted projects are rechecked before refresh commits. Client config patches
  cannot forge or erase metadata or replace server-derived PDF text, but can remove
  a source. Original/page routes and caches are isolated by user and project.

Uploads now report storage success with a `document` result even when extraction
fails; inspect its state rather than treating HTTP 200 as readable content. This
keeps unreadable originals available and failures visible for later OCR/retry.
Existing source records are not silently backfilled from private storage: refresh
linked PDFs or re-upload local PDFs to obtain original bytes and page metadata.
Old local PDF text alone cannot reconstruct the original file.

Verification includes real authenticated routes with two synthetic users, mocked
storage/inference, cache and page-range fixtures, stale replacement/concurrent
refresh/deletion tests, and browser inspection of source rows at 375/768/1440 widths
in light/dark modes. Mobile row actions were corrected after visual QA exposed
clipped status text. No production, real diary or financial documents were used.

Verified after implementation: **238 web tests** (15 added to the 223-test audit
baseline), typecheck and build pass; **155 diary tests pass, 3 skipped**, with
two dependency deprecation warnings. `git diff --check` passes.

Next: benchmark the optional OCR worker on synthetic scans and mixed pages;
projector repair and real vision accuracy still need separate host verification.
No OCR dependencies, job framework, diary-write changes or sidebar redesign landed.

## What the reported errors establish

The photo message comes from `server/vision.cjs`: a failed image probe whose
response mentions `mmproj` or `projector`. It identifies a server configuration
failure; it does not prove which file is absent, which model was selected, or
whether a projector already on disk was loaded. The older backlog records both a
missing Qwen projector and an E2B projector that existed but was not being loaded.
Those historical observations were not rechecked here.

The PDF message comes from `server/documents.cjs`: extraction yielded no text
anywhere in the document. A scan is the likely explanation, but a blank PDF can
also produce this result. The message does not establish that every uploaded PDF
failed. `App.tsx` displays only the first skipped reason and always appends
“Previous copies were kept.” The sync route actually keeps a previous source only
when one exists. A newly failed file contributes no readable source.

## Reproduced findings

All fixtures are generated from invented account IDs, dates, and amounts under
`apps/web/server/fixtures/documents/`. Tests invoke the real extractor and actual
upload/sync/chat handler code with mocked storage, providers and tools.

| Finding | Evidence and consequence |
| --- | --- |
| Text PDFs work | `text.pdf`: one page; dates, 42.15, -7.20 and total 34.95 survive extraction. Table columns flatten into text; this is not structured table recognition. |
| Scans fail explicitly | `scanned.pdf`: HTTP-style extraction error 422, no OCR. The visible statement exists only as pixels. |
| Mixed PDFs silently lose content | `mixed-pages.pdf`: two pages reported, but only the digital first page is returned. `mixed-page.pdf`: just the 40-character digital header is returned, omitting the scanned statement below it. Both report `truncated: false`. |
| Page attribution disappears | `extractText(..., {mergePages:true})` merges pages; stored sources keep only name/content/source. There is no page provenance for downstream chunks or citations. |
| Long documents look more complete than they are | `long.pdf`: 110 pages, extraction capped at 200,000 characters. `/upload` and `/sources/sync` discard the truncation/page metadata. The older `/documents` endpoint returns it but does not persist it. The cap is applied after whole-document extraction, not as a parser resource limit. |
| Upload is not readability | Remote `/upload` writes original bytes before extraction; subsequent sync may fail. Local `/upload` extracts first and stores text only, losing the original PDF. Legacy `/documents` also stores only text. |
| Refresh can serve stale text | A failed replacement retains old extracted content although remote bytes already contain the replacement. A new failed source has no old content to retain. There is no persistent stale/failed version status. |
| Refresh repeats parsing | Two unchanged syncs extract the same document twice. RAG indexing skips unchanged text, but extraction has no source hash/version cache. |
| S3 binary corruption is separate from OCR | `storage-client.cjs:s3Read` decodes as UTF-8 text, then `readBinaryFile` rebuilds bytes as binary. A mocked non-UTF8 payload changes bytes and bypasses the binary cap on this branch. WebDAV caps after buffering the full body. |
| Retrieval has a separate completeness limit | With the optional index unavailable, large files supply only their first 24,000 characters. The synthetic tail marker is absent while the source name remains listed. The read tool also caps output. Successful ingest is not proof that a whole statement reached the model. |
| Photo failure routing works | Mocked missing-projector response emits the warning, omits image bytes from the answering request and tells the model not to guess. Direct vision sends both attached fixture images. Configured vision sends a description to the answering model; failure falls back to direct vision or an explicit warning. |
| Probe success is not accuracy | The probe checks HTTP success for a 1-pixel input with a 1-token budget. A server silently ignoring images can pass. Negative cache lasts 30 seconds; positive cache lasts 5 minutes. |
| Missing image assets are silent | If all listed asset files are missing on disk, the handler logs warnings but emits no user-facing image warning. |

Additional static findings: linked-folder sync ignores image extensions, so uploaded
image assets and folder-linked photos are not equivalent. Image uploads accept
PNG/JPEG/WebP/GIF metadata (8 MB, 12 images); there is no dimension/decode validation.
Every available project image is attached, irrespective of the question. The
vision description pass has a shared 900-token ceiling for all images and no
`finish_reason` check. Its cache includes user/project/model/asset IDs/question,
but not credential changes, content hashes, or an expiry. These are follow-up
scope, not claims of measured failures on the user's photo.

## Proposed implementation order

### 1. Make source completeness explicit, without an OCR dependency

Unify upload and folder refresh around one document result contract. Preserve
original bytes in per-user/per-project storage for local uploads too. Keep remote
originals untouched; derived text must never overwrite them. Use immutable source
versions, based on byte hash plus extractor version, with metadata such as:

- source ID, owning user/project, original name/path, byte hash and size;
- extraction state: `queued`, `processing`, `ready`, `partial`, or `failed`;
- page count, per-page text/method/status, extracted character count, truncation;
- error code/message, missing/skipped pages and last successful version;
- indexing state separately from extraction state.

An unchanged source may reuse its derived version within the same tenant/project.
A changed source must not inherit a “ready” badge from its old text. Retain the old
version on failure, explicitly mark it stale, and disclose that fact to both the
user and model when using it. Missing new sources should appear as failed rows.
Return all failed filenames/reasons. Do not infer previous copies from a generic
error. Preserve server ownership of folder-derived files and existing deletion
ownership checks; clients must not round-trip server text back into the server.

Extract page-by-page with physical page numbers, preserving blank pages and
separating native text from OCR. A page with text plus a substantial image cannot
be considered fully read solely because it has a digital header. Initially flag
suspected scanned content as partial/OCR-needed; do not pretend text/image
heuristics establish completeness. Preserve line/column positions where possible,
and carry page/source/version references through RAG chunks and read tools.
Expose truncation and retrieval availability; allow bounded page/range reads so
questions about a statement's last page are not limited to its first 24k chars.

Fix and test binary byte preservation and bounded reads for S3/WebDAV before
blaming their failures on OCR. Keep this correctness batch separate from changing
the OCR runtime. No sidebar redesign is needed: source rows and existing warnings
can expose these states.

### 2. Add a bounded local OCR worker, after fixture benchmarking

Recommended candidate: an isolated, optional OCRmyPDF/Tesseract worker producing a
derived PDF, then page-aware extraction through the existing PDF parser. This is
an architecture recommendation, not an installed dependency or final engine choice.
The worker should receive only the selected source bytes, not a user's storage
credentials or the whole corpus. No network access is needed for processing after
images/language packs are provisioned. Never use the diary service as the worker.

| Candidate | Fit and tradeoff |
| --- | --- |
| OCRmyPDF + Tesseract | Best first candidate for document-centric OCR and searchable derived PDFs. Offers rotation/deskew and controls for existing text. Larger Python/native runtime; measure memory, latency, language and table accuracy before selecting. |
| Renderer + direct Tesseract | Greater control over per-page image limits and OCR output; more application code for rendering, mixed content, orientation and page association. A viable alternative if only derived text is wanted. |
| Existing vision model | Keep for photo interpretation and supplementary visual questions. The current 900-token description cannot serve as faithful bulk statement extraction. Requires a working projector and measured accuracy; could contend with interactive chat resources. |

OCRmyPDF's skip mode skips an entire page when it already has text; that alone
will not repair the synthetic digital-header-plus-scan case. Redo mode can OCR
additional image text while retaining visible text. Force mode rasterizes all
content and changes document properties, so it should not be the default. Test
both mixed fixtures before choosing options. See the official
[processing-mode documentation](https://ocrmypdf.readthedocs.io/en/stable/advanced.html).

Do not use OCRmyPDF's text sidecar as the complete result of a mixed document: it
omits text on pages that did not undergo OCR. Re-extract the derived PDF and check
page coverage. OCR language packs must match the documents; English is only a
candidate default. See the official
[cookbook](https://ocrmypdf.readthedocs.io/en/stable/cookbook.html).

Tesseract documents limitations on tables without additional layout analysis.
For financial statements, validate exact signs, decimal separators, dates and
row/column association—not just whether any text appeared. Do not claim a general
accounting-table import feature. See its
[quality guidance](https://tesseract-ocr.github.io/tessdoc/ImproveQuality.html).

Provisional bounds for the benchmark: keep 25 MB ingress; one job at a time;
50 OCR pages/job; render at 300 DPI capped at 12 megapixels/page; 60 seconds/page,
10 minutes/job; 1 GiB worker memory and temporary-output quota of 512 MiB/job.
These are proposed starting limits, not proven safe operating values. Fail visibly
on limits rather than silently skipping pages. Revisit after measuring peak RSS,
scratch usage, per-page latency and chat contention on the target host. Longer
files need explicit partial/rejected state and configurable limits, not an
unbounded HTTP request. Jobs require cancellation, restart recovery, bounded
per-user queues, and stale-result checks before committing a derived version.

This task did not inspect host resources or benchmark OCR: the local QA runtime
has PDF tooling, but no Tesseract executable was found on PATH. No engine or model
was installed. CPU/RAM/disk headroom, inference backend/version, language needs,
and acceptable document latency remain open measurements.

### 3. Repair and verify photo inference separately

Before any deployment change, inspect the installed Lemonade version, selected
model, model registration, matching projector file, and actual loader arguments.
A file on disk is insufficient evidence that the backend loaded it. Current
Lemonade documentation supports explicit main/mmproj checkpoint registration;
verify syntax against the installed version rather than applying current commands
blindly. See [custom model configuration](https://lemonade-server.ai/docs/guide/configuration/custom-models/).

Then use a synthetic image with a known marker, amount, and colored shapes to test
actual perception, not merely HTTP acceptance. Exercise direct answering and the
configured vision role. Keep the current warned text-only fallback. Missing assets,
partial descriptions, timeouts and multiple images must be reported per image;
image-only PDFs must enter document OCR explicitly rather than being mistaken for
ordinary image assets. Add decoded dimension checks and image/content-version cache
keys. Do not automatically send sources to a new cloud provider. A configured
provider may already be remote; make the selected destination clear.

## Acceptance matrix for implementation

Observed means executed locally with synthetic fixtures/mocks. “Pending” is a
required future acceptance check, not a passing result from this audit.

| Fixture/scenario | Audit observation | Required implementation result |
| --- | --- | --- |
| Digital statement table | Text values preserved | Same dates/signs/amounts, page citations; no OCR degradation. |
| Pure scan | Explicit 422 | OCR recovers INV-2042 and total 34.95 with page provenance, or explicit failure. |
| Digital page + scanned page | Only page 1 extracted | Both page markers and text present; missing page never looks ready. |
| Digital header + scan on same page | Only header extracted | Header and scan recovered once; no duplicated text. |
| Blank page | Not yet fixture-tested | Distinguish blank from OCR failure; retain physical page numbering. |
| Encrypted / malformed | Explicit extractor failures | Stable errors, no password guessing or partial ready state. |
| >25 MB upload | Rejected before extraction | Same across local/remote/refresh with bounded network reads. |
| Long text PDF | 110 pages, 200k cap; metadata dropped | Visible truncation and bounded page access, never “fully read.” |
| Refresh unchanged | Parses twice | Reuse versioned extraction; changing bytes invalidates it. |
| Failed replacement / new failure | Old text retained / no new text | Separate stale and failed rows; old version disclosed to chat. |
| Local / remote originals | Text only / bytes preserved | Original bytes recoverable without overwriting remote files. |
| S3 binary / size cap | Corruption / bypass reproduced | Byte-identical payload and enforced cap. |
| Missing vector index | Large source tail absent | Explicit retrieval state; requested page/range available. |
| Two image sources | Both routed in mock | Per-image attribution and no cross-image amount mixing. |
| mmproj failure / description failure | Warned fallback works | Preserve behavior; real fixture recognition after configuration repair. |
| Missing asset | No user warning | Name the unavailable image; do not imply it was inspected. |
| Photos / screenshots / rotated or blurry scans | Screenshot-like PNG routed; accuracy not measured | Fixture-based legibility/rotation tests; unreadable content explicitly unknown. |
| Complex tables / mixed languages | Not benchmarked | Exact cell values/associations or explicit limitation; selected language packs. |
| Worker timeout / cancellation / restart | Pending; no worker exists | No stale job commits, no silent omissions, bounded resources. |
| Two users/projects | Existing ownership lookup mocked | Full route tests prevent reads, jobs, caches and indexes crossing owners. |

## Verification

`npm test`: 223 passing (15 added); `npm run typecheck` and `npm run build`:
passing. Diary `.venv/bin/python -m pytest tests/ -q`: 155 passing, 3 skipped,
two dependency deprecation warnings. No runtime implementation changed.

## Reproduction and next task

Run from `apps/web`:

```sh
node --test server/documents.test.cjs server/vision-routing.test.cjs server/vision.test.cjs
npm test
npm run typecheck
npm run build
```

The `audit:` tests intentionally document current defects; change those assertions
alongside their fixes. They are not the desired acceptance contract. The generator
needs ReportLab, Pillow and pypdf only to regenerate committed synthetic fixtures;
no runtime dependency was added. Representative text and mixed-page PDFs were
rendered and visually inspected. Real provider output, browser interaction, live
storage and vector-search quality were not evaluated; mocks establish code paths,
not OCR or vision accuracy.

Original recommendation (now completed by the follow-up above): section 1's
source completeness/binary-read batch before choosing or installing OCR. Photo projector
repair remains a separate operator task. Onboarding and diary navigation remain
open; the user's explicit request selected this investigation first, not the whole
roadmap.


## Implemented OCR and image follow-up (2026-09-10)

The implementation uses direct Poppler rendering plus Tesseract 5, rather than
OCRmyPDF: each image-bearing page is rendered in full so a digital header cannot
hide a scanned body. Native text remains alongside a labelled OCR transcription;
this can repeat header text but does not replace native values with OCR guesses.
Original PDFs are immutable. No derived PDF or global text cache is produced.
The private worker has no storage credentials, persistent volume, host port, or
external network. Debian packages supply Poppler, Tesseract, English and German
language data; no application framework was added.

The tested worker bounds are 25 MB, 50 selected pages, longest image edge 3500 px
(at most 12.25 MP), 60 seconds per render/OCR subprocess, ten minutes per document,
one concurrent job, 1 GiB RAM, 512 MiB tmpfs. Busy/failed work stays incomplete and
refresh retries it; successful results are reused only inside the same workspace
and project. In-memory browser polling jobs are capped at two active and sixteen
retained per workspace; completed polling results expire after fifteen minutes.
A restart loses polling status, not saved originals/results; refresh/re-upload
retries. There is no durable automatic resume queue. Native parsing is still in
the web process. These are explicit limits, not claims of arbitrary PDF support.

The real worker recovered invoice INV-2042, date/amount associations, refund -7.20,
and total 34.95 from all three scanned/mixed fixtures. The image inference test
recovered the same values after registering Qwen's matching mmproj. Missing image
bytes are now visible, length-limited descriptions fall back, and the description
cache is credential/content scoped and expires. A 2xx capability probe alone is
still not proof of perception; deployment verification uses actual image content.
