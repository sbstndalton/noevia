# 10. Complexity-reduction analysis

**H2:** one generic decision primitive can replace brittle, application-specific orchestration.
Doc 2 has the full inventory. This document says what could go, what could not, and the realistic
net change.

## 10.1 What could be deleted if the matching purpose wins its benchmark

| Code | Lines today | After | Net |
|---|---|---|---|
| `auto-router.cjs`: heuristics, two classifier prompts, verdict parsing, the 512-token budget, the 400-retry path | 94 | an options list + ~10-line wrapper; the heuristic kept as fallback (moved, ~25 lines) | **−60** |
| `chat-skill-routing.cjs`: cosine, threshold, margin | 48 | wrapper over `rank`/`choice` | **−30** |
| `chat-tool-routing.cjs` + `tool-router.cjs`: cosine ranking, threshold, top-k | 109 | the `requires` closure, collision and cap checks stay (policy); the ranking goes to `rank` | **−45** |
| `toolboxes.cjs` `toolCapFor`: parameter count parsed from the file name | ~10 | the capability database (doc 12) gives the measured tool accuracy per config; the hard ceiling stays | **−8** |
| `rag.cjs` fixed top-6 / 0.3 cut-off | ~10 | retrieve k = 24 → `rankContext` → adaptive cut; the fallback stays | ±0 (a behaviour change, not a deletion) |
| Diary `pipeline.py` `classify` generate-and-parse | ~20 | `noul` decision (later; the Diary is out of scope for now) | **−12** |
| **Total removable** | | | **≈ −155 lines, 3 classifier prompts, ~12 thresholds, 8 regexes** |

Added:
- the decision layer: primitive, validation, fallback chain, calibration, shadow logging and 4–5
  backends, estimated 450–600 lines plus tests;
- the capability database: ~250 lines;
- the checkpoint and switching machinery (docs 5, 6, 12): ~600–900 lines.

## 10.2 The honest conclusion

- **H2 as literally stated ("replace hundreds of lines of fuzzy logic") is not supported by this
  codebase.** noevia's fuzzy code is already small (about 300 replaceable lines), injected and
  fail-open. Net line count will **go up**, not down.
- The real simplification is **structural**:
  1. **One mechanism instead of five.** Today there are five decision styles:
     - regex/length heuristics;
     - generate-and-parse classification (twice, in two languages);
     - cosine plus threshold (three copies);
     - a file-name parse;
     - fixed cut-offs.
     They become one primitive with one validation rule, one fallback rule, one log format and one
     calibration method.
  2. **New decisions cost a wrapper, not a subsystem.** Output evaluation, loop control, context
     utility, residency and mid-task switching would otherwise each need their own bespoke
     heuristics, prompts and thresholds, which is exactly the brittle growth H2 worries about.
     Measure H2 as *avoided* complexity:
     - the decision count noevia gains, against the new thresholds and prompts it did **not**
       have to write;
     - plus the thresholds retired.
  3. **Every threshold becomes data.** Hand-tuned constants (0.35, 0.5, 0.03, 0.3, 6, 12/24, 600
     chars) become calibration fits and capability-database evidence that update themselves.
- Metric to report for H2:
  - `branches + thresholds + prompts` in decision code, before and after, per purpose;
  - the number of decision purposes supported per 100 lines of decision code.

## 10.3 What must not be simplified away

Everything listed in doc 2 as deterministic:
- `code-actions.cjs`, even though it looks like a classifier;
- the tool token budget;
- context-fit arithmetic;
- step and budget caps;
- the approval flow.

Moving any of these behind a model would trade a reviewable rule for an unreviewable probability.
