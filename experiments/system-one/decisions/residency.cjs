'use strict';
// Residency feasibility v2 (docs/research/system-one/13 §13.10). Replaces v1's "model file size ≤
// currently free memory", which cannot express a swap and treats file size as memory.
//
// A candidate is one of:
//   'coexist'    fits alongside every model resident now
//   'after_swap' fits only after an authorised checkpoint + unload of the swappable resident(s)
//   'no_fit'     does not fit under the configured limits even after that
//   'unknown'    a required measurement is missing; never loaded on an estimate
//
// Deployment-specific numbers (limits, reserved services, measured footprints) come from a host
// profile, never from noevia-wide constants. File size is not treated as resident or reclaimable
// memory: resident footprints must be measured (weights + KV/context + runtime overhead), and a
// load has its own transient peak.

/**
 * @typedef {{ limitGB: number|null,       // model runtime cap from the host profile (e.g. an engine memory limit); null = none
 *   hostAvailableGB: number|null,          // measured available host memory now (after reserved services); null = not measured
 *   resident: { id: string, residentGB: number|null, pinned: boolean }[] }} HostState
 *   // pinned: may not be unloaded by a swap (e.g. the class-A RAG reranker)
 * @typedef {{ id: string, residentGB: number|null,   // measured steady footprint at the planned context size (weights + KV + runtime)
 *   loadPeakGB: number|null }} Candidate               // measured extra transient memory while loading
 */
function feasibility(c, host, { swappable = [] } = {}) {
  if (c.residentGB == null || c.loadPeakGB == null) return { fit: 'unknown', reason: 'candidate footprint not measured' };
  if (host.hostAvailableGB == null) return { fit: 'unknown', reason: 'host memory not measured' };
  if (host.resident.some((r) => r.residentGB == null)) return { fit: 'unknown', reason: 'a resident model footprint is not measured' };
  const need = c.residentGB + c.loadPeakGB;
  const models = host.resident.reduce((a, r) => a + r.residentGB, 0);
  const fits = (freed) => (host.limitGB == null || models - freed + need <= host.limitGB) && need <= host.hostAvailableGB + freed;
  if (fits(0)) return { fit: 'coexist', need };
  // Only models named swappable (the current System-Two at a safe checkpoint), never pinned ones.
  // What is reclaimed is their MEASURED resident footprint, not their file size.
  const reclaim = host.resident.filter((r) => !r.pinned && swappable.includes(r.id)).reduce((a, r) => a + r.residentGB, 0);
  if (reclaim > 0 && fits(reclaim)) return { fit: 'after_swap', need, reclaim };
  return { fit: 'no_fit', need, reclaim };
}

module.exports = { feasibility };
