// A bounded reflected highlight, not a page-wide animation or content effect.
(() => {
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  let frame = 0, target, x, y;
  document.addEventListener('pointermove', event => {
    const surface = event.target instanceof Element && event.target.closest('.app-mode-switch');
    if (!surface || reduced.matches) return;
    const rect = surface.getBoundingClientRect();
    target = surface; x = event.clientX - rect.left; y = event.clientY - rect.top;
    if (!frame) frame = requestAnimationFrame(() => {
      frame = 0;
      if (!target?.isConnected) return;
      target.style.setProperty('--glass-x', `${x}px`);
      target.style.setProperty('--glass-y', `${y}px`);
    });
  }, {passive:true});
})();
