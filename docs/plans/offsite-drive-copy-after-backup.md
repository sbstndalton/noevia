# Off-site backups are never copied to Google Drive after the scheduled backup

Status: plan only; implementation pending. Found in live testing on release `aa5132b`, 2026-09-23.

## What happens

Settings → Backups on the live site says "The last copy to Drive is more than two days old (9/18/2026)", while the nightly backup itself ran on 9/23 at 02:14 UTC (115 files). The live status file agrees: `lastBackup.at` is 2026-09-23, and `mirror.at` is still 2026-09-18 with state `ok`. So the encrypted snapshots reach the `/offsite` folder every night, but not Google Drive.

## Cause

`apps/web/server/offsite-service.cjs`, `runNow`:

```js
runNow: () => exclusive('backup', async (b) => {
  …
  Promise.resolve().then(() => { if (!busy) return copyToDrive(); }).catch(() => {});
  return saved;
}),
```

The `.then` callback is a microtask that runs before `exclusive()`'s `finally { busy = '' }`, because `await work(...)` resumes a tick later. So `busy` is still `'backup'`, and the copy is skipped after every backup, both scheduled and "Back up now". The only paths that still copy are "Copy to Drive now", connecting Google, and turning the Drive copy back on. That's why the last copy is from 9/18.

Reproduced against the real module with fakes (`backupFactory`, `driveFactory`; no network, no live data): after `runNow()` plus 200 ms, the fake `drive.mirror` has been called **0** times. After `copyNow()` it's 1.

## Fix

- Start the copy after `exclusive` has released `busy`. For example, have `runNow` await `exclusive(...)` and then call `copyToDrive()` without awaiting it, or queue it with `setImmediate`/`setTimeout(0)` and check `busy` there.
- Keep the intent: a slow upload must never hold the page or the backup's response.
- Add a unit test with the same fakes: after `runNow()` the mirror is called once. Also check it isn't called when `driveCopy` is off or Drive isn't connected.
- After deploying, confirm on the live site that the next nightly run updates `mirror.at`. An admin can press "Copy to Drive now" once to bring the off-site copy current right away.

## Not affected

Local encrypted snapshots, retention, restore tests and the connection itself are fine. Only the Drive mirror is stale.
