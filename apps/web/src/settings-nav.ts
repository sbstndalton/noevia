// Return-target bookkeeping for the Settings shell (#304, #305).
//
// The app renders a handful of views (Models & routing, Customise/plugins, Archived chats,
// Diary) that Settings can launch as a detour from wherever the user actually was. If those
// detours were allowed to become "the place Settings returns you to", closing Settings from
// one of them just re-shows the same detour — the back/close loop reported in #304. Keeping
// this bookkeeping in a small pure module makes it unit-testable without mounting React.

export interface NavState<V> {
  /** The last view that was NOT a Settings-launched detour: where Settings' close/back lands. */
  returnView: V;
  /** The Settings section the current view was launched from, if any (null once you are back
   *  on a normal view). Used to re-open Settings at the right page rather than the last one. */
  cameFromSettings: string | null;
}

export function initialNavState<V>(view: V): NavState<V> {
  return { returnView: view, cameFromSettings: null };
}

/** Call this whenever the app's main view changes. `fromSettingsSection`, when set, means the
 *  new view is a Settings-launched detour (e.g. Models & routing) — the return target is left
 *  untouched so it keeps pointing at the real chat/project view underneath. Any other view
 *  (including a Settings-launched detour reached from elsewhere) becomes the new return target. */
export function nextNavState<V>(
  state: NavState<V>,
  nextView: V,
  opts: { fromSettingsSection?: string | null } = {},
): NavState<V> {
  const fromSettings = opts.fromSettingsSection ?? null;
  if (fromSettings) return { returnView: state.returnView, cameFromSettings: fromSettings };
  return { returnView: nextView, cameFromSettings: null };
}

/** What Settings' X / Escape / top-level back should hand the app back to, and the nav state to
 *  carry forward afterward (the detour is forgotten, so a second close never re-opens it). */
export function resolveSettingsClose<V>(state: NavState<V>): { view: V; next: NavState<V> } {
  return { view: state.returnView, next: { returnView: state.returnView, cameFromSettings: null } };
}
