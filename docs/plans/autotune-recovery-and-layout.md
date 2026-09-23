# Auto-tune recovery and layout plan

Issue: [#72](https://github.com/sbstndalton/noevia/issues/72). Baseline: `5004b50`.

The full tuner must wait for the router to report every model exactly `unloaded` before each profile write. The wait will be bounded, cancellation-aware during normal tuning, and usable during rollback even after cancellation. A timeout will identify the model and final state. The manager's strict guard and preset revision checks remain in place. Context calibration uses the same safe boundary before its profile writes.

Quality failures will identify the failed probe and whether the response was missing, truncated, rejected upstream, or mismatched, without persisting model output. The smoke-test acceptance criteria remain unchanged.

The Auto Tune panel will show current status, progress, confirmation and recovery controls first. Queued models and phases will be compact disclosures; active and failed details remain visible. Existing result and log details remain available.

Verification: add delayed and never-completing unload fixtures, cancellation/rollback coverage, and quality diagnostic cases. Run the full web unit suite, typecheck, build, design lint, and synthetic browser checks at phone and desktop sizes in both themes. Do not run production inference or touch Diary data.
