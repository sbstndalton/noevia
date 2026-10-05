import { useEffect, useState } from 'react';
import { fetchToolboxes } from './api';

/** The name to show for an MCP server id on the approval card (#887): a directory server's title,
 *  else the id the server reported. Looked up once from /api/toolboxes; until it answers (or if it
 *  cannot) the id itself is shown, so the card never waits on this. */
let titles: Map<string, string> | null = null;
let loadedAt = 0;
const FRESH_MS = 30_000; // an administrator can add a server while the page is open
let inflight: Promise<Map<string, string>> | null = null;

export function loadServerTitles(load: typeof fetchToolboxes = fetchToolboxes): Promise<Map<string, string>> {
  if (titles && Date.now() - loadedAt < FRESH_MS) return Promise.resolve(titles);
  inflight ||= load().then((r) => {
    const found = new Map<string, string>();
    for (const s of r.mcp?.servers || []) if (s.id && s.title) found.set(s.id, s.title);
    titles = found;
    loadedAt = Date.now();
    return found;
  }).finally(() => { inflight = null; });
  return inflight;
}

export function useServerLabel(id: string | undefined): string | undefined {
  const [label, setLabel] = useState<string | undefined>(() => (id ? titles?.get(id) || id : undefined));
  useEffect(() => {
    if (!id) { setLabel(undefined); return; }
    setLabel(titles?.get(id) || id);
    if (titles?.has(id) && Date.now() - loadedAt < FRESH_MS) return;
    let live = true;
    loadServerTitles().then((m) => { if (live) setLabel(m.get(id) || id); }).catch(() => undefined);
    return () => { live = false; };
  }, [id]);
  return label;
}
