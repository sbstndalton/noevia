/** Shared "is this really focusable right now" check, and a way to defer a focus-return
 *  decision until the layout it depends on has settled.
 *
 *  #401 (reopened): a fallback that only checks `Node.isConnected` treats a control sitting
 *  inside a `display:none` ancestor (a collapsed nav drawer, a hidden tab panel) as usable —
 *  it is still "in the document" — but `.focus()` on an element with no layout box is a silent
 *  no-op, so focus falls through to `<body>` anyway. `isFocusable` closes that gap: connected,
 *  producing at least one client rect (which requires every ancestor to actually render), and
 *  not inside an `inert` region (inert elements can still have non-empty rects). */
export function isFocusable<
  T extends {
    isConnected: boolean;
    getClientRects(): ArrayLike<unknown>;
    closest?: (selectors: string) => unknown;
  },
>(el: T | null | undefined): el is T {
  if (!el || !el.isConnected) return false;
  if (el.getClientRects().length === 0) return false;
  if (typeof el.closest === 'function' && el.closest('[inert]')) return false;
  return true;
}

/** Returns the first candidate `isFocusable` accepts, or `null` if none are. Callers list
 *  candidates from most to least specific (e.g. the control that opened a panel, then a
 *  reasonable landmark, then a control guaranteed to exist in the view). */
export function pickFocusable<
  T extends {
    isConnected: boolean;
    getClientRects(): ArrayLike<unknown>;
    closest?: (selectors: string) => unknown;
  },
>(...candidates: Array<T | null | undefined>): T | null {
  for (const candidate of candidates) {
    if (isFocusable(candidate)) return candidate;
  }
  return null;
}

/** Runs `check` once the layout from the commit that is currently unmounting/closing has had a
 *  chance to settle — a frame after paint, so a class toggled in that same commit (a drawer
 *  collapsing, a panel's exit animation finishing) has taken visual effect before `check` reads
 *  `getClientRects()`. A hidden background tab never fires `requestAnimationFrame` — a known
 *  tester artifact, and a real one for anyone who closes a panel via a keyboard shortcut fired
 *  from a tab that lost visibility — so a short timer runs the same check as a fallback;
 *  whichever fires first wins and the other is a no-op. Returns a canceller. */
export function afterLayoutSettles(check: () => void, timeoutMs = 100): () => void {
  let done = false;
  const fire = () => {
    if (done) return;
    done = true;
    check();
  };
  const raf = typeof requestAnimationFrame === 'function' ? requestAnimationFrame(fire) : 0;
  const timer = setTimeout(fire, timeoutMs);
  return () => {
    done = true;
    if (raf && typeof cancelAnimationFrame === 'function') cancelAnimationFrame(raf);
    clearTimeout(timer);
  };
}
