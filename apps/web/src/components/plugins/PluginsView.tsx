import { useEffect, useRef, useState } from 'react';
import type { JSX } from 'react';
import { apiFetch, fetchProfile } from '../../api';
import { ShellIcon } from '../ShellIcon';
import { SegmentedControl } from '../SegmentedControl';
import { ConnectorsSettings } from '../connectors/ConnectorsSettings';
import { useT } from '../../i18n';
import type { Translate } from '../../i18n';
import '../../i18n/customise/index';

/** Customise's three destinations (#238). The old tab ids stay accepted so a saved link lands on
 *  the right one: 'connected' was Connectors, 'mcp' was the MCP directory that now lives in Plugins. */
export type CustomiseTab = 'skills' | 'connectors' | 'plugins';
export function customiseTab(value: string | null | undefined): CustomiseTab {
  if (value === 'skills') return 'skills';
  if (value === 'plugins' || value === 'mcp') return 'plugins';
  return 'connectors';
}
interface Item { why?: string; id: string; name: string; publisher: string; description: string; version: string; url: string; remote: boolean; installable?: boolean; notInstallable?: string; needsKey?: boolean; headers?: KeyHeader[] }
interface KeyHeader { name: string; required: boolean; secret: boolean; description: string; template: string | null }
interface ProjectSkill { file: string; name: string; description: string; version: string; content: string; status: 'review' | 'updated' | 'enabled' | 'disabled' | 'invalid'; error: string; missingTools: string[] }
interface Added { id: string; registryName: string; title: string; declaredHeaders?: KeyHeader[]; toolCount: number | null; tools?: { name: string; description: string }[]; toolsTruncated?: boolean; error: string | null; keyHeaders?: string[]; oauth?: boolean; personal?: boolean; redirectUri?: string; oauthClient?: { manual: boolean; clientId: string | null; hasSecret: boolean; redirectUri: string; issuer: string } | null }

/** "3 tools" / "1 tool" / "… tools" while the count is not yet known. */
const tools = (t: Translate, n: number | null | undefined) => (n == null ? t('customise.toolsUnknown') : t.plural('customise.toolsCount', n));

/** Open the sign-in in a new tab from inside the click (or the browser blocks it), then point it at the URL. */
async function signInTab(get: () => Promise<string | null>): Promise<boolean> {
  const tab = window.open('about:blank', '_blank');
  try { const url = await get(); if (tab && url) { tab.opener = null; tab.location.href = url; return true; } tab?.close(); return false; }
  catch (e) { tab?.close(); throw e; }
}

/** Customise (#238, formerly "Plugins"): Skills, Connectors and Plugins as three tabs. Connectors
 *  are accounts you link (Google Drive and friends); Plugins are MCP servers, installed first and
 *  then the public directory. The view id stays `plugins`, so saved places and links still resolve. */
export function PluginsView({ onStartChat, embedded = false, projects = [], onProjectsChanged, initialTab }: { onStartChat?: (prompt: string) => void; embedded?: boolean; projects?: { id: string; name: string }[]; onProjectsChanged?: () => void; initialTab?: string }): JSX.Element {
  const t = useT();
  const [tab, setTab] = useState<CustomiseTab>(() => customiseTab(initialTab));
  const [isAdmin, setIsAdmin] = useState(false);
  useEffect(() => { let live = true; fetchProfile().then((p) => { if (live) setIsAdmin(p.user.role === 'admin'); }).catch(() => undefined); return () => { live = false; }; }, []);
  const body = <div className="plugins-page">
    <header className="plugins-head">
      <h1>{t('customise.title')}</h1>
      <p>{t('customise.intro')}</p>
      <SegmentedControl label={t('customise.title')} value={tab} onChange={setTab} options={[['skills', t('customise.tab.skills')], ['connectors', t('customise.tab.connectors')], ['plugins', t('customise.tab.plugins')]]}/>
    </header>
    {tab === 'connectors'
      ? <div className="plugins-connected"><h2 className="plugins-subhead">{t('customise.connectedTitle')}</h2><ConnectorsSettings hideTitle isAdmin={isAdmin} onStartChat={onStartChat}/></div>
      : tab === 'plugins'
        ? <div className="plugins-connected"><h2 className="plugins-subhead">{t('customise.installedTitle')}</h2><SignInServers/><KeyServers/><p className="plugins-note">{t('customise.mcpNote')}{isAdmin ? '' : t('customise.mcpAdminNote')}</p><h2 className="plugins-subhead">{t('customise.library')}</h2><Directory key="mcp" kind="mcp" projects={projects} onProjectsChanged={onProjectsChanged} isAdmin={isAdmin}/></div>
        : <><p className="plugins-note">{t('customise.skillsNote')}</p><h2 className="plugins-subhead">{t('customise.library')}</h2><Directory key="skills" kind="skills" projects={projects} onProjectsChanged={onProjectsChanged} isAdmin={isAdmin}/></>}
  </div>;
  return embedded ? body : <main className="main plugins-view">{body}</main>;
}

function Directory({ kind, projects, onProjectsChanged, isAdmin }: { kind: 'mcp' | 'skills'; projects: { id: string; name: string }[]; onProjectsChanged?: () => void; isAdmin: boolean }): JSX.Element {
  const t = useT();
  const [added, setAdded] = useState<Added[]>([]);
  const [addedStatus, setAddedStatus] = useState<'loading' | 'ready' | 'error'>('loading');
  const [addedAttempt, setAddedAttempt] = useState(0);
  useEffect(() => {
    if (kind !== 'mcp' || !isAdmin) return;
    let live = true;
    setAddedStatus('loading');
    apiFetch('/api/admin/mcp-directory').then(async (r) => { if (!r.ok) throw new Error('Could not load added servers.'); return r.json(); })
      .then((d) => { if (live) { setAdded(d.servers || []); setAddedStatus('ready'); } })
      .catch(() => { if (live) setAddedStatus('error'); });
    return () => { live = false; };
  }, [kind, isAdmin, addedAttempt]);
  const [mode, setMode] = useState<'yours' | 'discover'>('yours');
  const [yourQuery, setYourQuery] = useState('');
  const [skillProject, setSkillProject] = useState(projects[0]?.id || '');
  useEffect(() => {
    if (kind === 'skills' && !projects.some((project) => project.id === skillProject)) {
      setSkillProject(projects[0]?.id || '');
    }
  }, [kind, projects, skillProject]);
  const [projectSkills, setProjectSkills] = useState<ProjectSkill[]>([]);
  const [skillsStatus, setSkillsStatus] = useState<'loading' | 'ready' | 'error'>('loading');
  const [skillsAttempt, setSkillsAttempt] = useState(0);
  useEffect(() => {
    if (kind !== 'skills' || !skillProject) return;
    let live = true; setSkillsStatus('loading');
    apiFetch(`/api/projects/${encodeURIComponent(skillProject)}/instruction-skills`)
      .then(async (r) => { const data = await r.json(); if (!r.ok || !Array.isArray(data.skills)) throw new Error(data.error || 'Could not load skills.'); return data.skills as ProjectSkill[]; })
      .then((skills) => { if (live) { setProjectSkills(skills); setSkillsStatus('ready'); } })
      .catch(() => { if (live) setSkillsStatus('error'); });
    return () => { live = false; };
  }, [kind, skillProject, skillsAttempt]);
  const [query, setQuery] = useState('');
  const [items, setItems] = useState<Item[] | null>(null);
  const [error, setError] = useState('');
  const [source, setSource] = useState<{ label: string; home: string } | null>(null);
  const [attempt, setAttempt] = useState(0);
  // noevia's curated starters (server/plugin-starters.json): a failure just hides the row.
  const [starters, setStarters] = useState<Item[]>([]);
  useEffect(() => {
    let live = true;
    apiFetch(`/api/plugins/directory?kind=${kind}&starters=1`).then((r) => (r.ok ? r.json() : null))
      .then((d) => { if (live) setStarters(d?.items ?? []); }).catch(() => undefined);
    return () => { live = false; };
  }, [kind]);
  useEffect(() => {
    if (mode === 'yours') return;
    let live = true;
    const timer = window.setTimeout(() => {
      setItems(null); setError('');
      apiFetch(`/api/plugins/directory?kind=${kind}&q=${encodeURIComponent(query.trim())}`)
        .then(async (r) => { const data = await r.json().catch(() => ({})); if (!live) return; setSource(data.source ?? null); if (!r.ok) throw new Error(data.error || 'The directory could not be reached.'); setItems(data.items); })
        .catch((e) => { if (live) { setError((e as Error).message); setItems([]); } });
    }, query ? 300 : 0);
    return () => { live = false; window.clearTimeout(timer); };
  }, [kind, mode, query, attempt]);
  const matchingSkills = [...projectSkills].filter((skill) => `${skill.name} ${skill.file} ${skill.description}`.toLocaleLowerCase().includes(yourQuery.trim().toLocaleLowerCase())).sort((a, b) => (a.name || a.file).localeCompare(b.name || b.file) || a.file.localeCompare(b.file));
  const matchingAdded = [...added].filter((a) => `${a.title} ${a.registryName}`.toLocaleLowerCase().includes(yourQuery.trim().toLocaleLowerCase())).sort((a, b) => a.title.localeCompare(b.title) || a.id.localeCompare(b.id));
  const card = (i: Item, starter = false) => <li key={(starter ? 'starter:' : '') + i.id} className="plugin-card surface">
        <span className="plugin-card-icon"><ShellIcon name={kind === 'mcp' ? 'server' : 'sparkles'} size={20}/></span>
        <span className="plugin-card-text">
          <b>{i.name}</b>
          {i.publisher && <small className="plugin-publisher">{i.publisher}{i.version && ` · v${i.version}`}{i.remote && ' · hosted'}</small>}
          {i.why && <small className="plugin-why">{i.why}</small>}
          {i.description && <small>{i.description}</small>}
        </span>
        <span className="plugin-card-actions">
          {i.url && <a className="btn btn-secondary btn-sm plugin-card-link" href={i.url} target="_blank" rel="noreferrer noopener" aria-label={`View ${i.name}`}>View</a>}
          {kind === 'skills' && <AddSkill skill={i} projects={projects} installedIn={(skillsStatus === 'ready' ? projectSkills : []).filter((s) => s.file === `${i.id}/SKILL.md`).map(() => skillProject)} onAdded={() => { setSkillsAttempt((n) => n + 1); onProjectsChanged?.(); }}/>}
          {kind === 'mcp' && isAdmin && <AddServer item={i} added={added.find((a) => a.registryName === i.id)} onChange={setAdded}/>}
        </span>
</li>;
  return <section className="plugins-directory" aria-label={kind === 'mcp' ? t('connectors.mcp.title') : t('customise.tab.skills')}>
    <SegmentedControl label={kind === 'mcp' ? t('customise.mcpInventory') : t('customise.skillInventory')} value={mode} onChange={setMode} options={[["yours", kind === 'mcp' ? t('customise.added') : t('customise.inProject')], ["discover", t('customise.discover')]]}/>
    {kind === 'skills' && mode === 'yours' ? <>
      <label className="plugins-project-picker">{t('customise.project')} <select value={skillProject} onChange={(e) => setSkillProject(e.target.value)}>{projects.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}</select></label>
      <div className="settings-search plugins-search"><ShellIcon name="search" size={16}/><input aria-label={t('customise.searchProjectSkillsAria')} placeholder={t('customise.searchSkillsPlaceholder')} value={yourQuery} onChange={(e) => setYourQuery(e.target.value)}/></div>
      <p className="plugins-note">{t('customise.skillsInstructionNote')}</p>
      {!skillProject ? <p className="plugins-note">{t('customise.createProjectHint')}</p>
        : skillsStatus === 'loading' ? <p className="plugins-note" role="status">{t('customise.loadingProjectSkills')}</p>
        : skillsStatus === 'error' ? <p className="route-note" role="alert">{t('customise.loadSkillsError')} <button className="btn btn-secondary btn-sm" onClick={() => setSkillsAttempt((n) => n + 1)}>{t('connectors.tryAgain')}</button></p>
        : matchingSkills.length ? <ul className="plugin-grid plugin-grid-installed">{matchingSkills.map((skill) => <li key={skill.file} className="plugin-card surface"><span className="plugin-card-text"><b>{skill.name || skill.file}</b><small className="plugin-publisher">{t('customise.skillStatusProjectFile')} · {skill.status === 'enabled' ? t('customise.skillStatusEnabled') : skill.status === 'review' || skill.status === 'updated' ? t('customise.skillStatusReviewRequired') : skill.status === 'invalid' ? t('customise.skillStatusNeedsCorrection') : t('customise.skillStatusDisabled')}</small><small>{skill.file}{skill.version ? ` · v${skill.version}` : ''}</small>{skill.description && <small>{skill.description}</small>}<details><summary>{t('customise.viewInstructionsSummary')}</summary><p>{t('customise.instructionsScopeNote')}</p>{skill.missingTools?.length > 0 && <p>{t('customise.requiresTools', { tools: skill.missingTools.join(', ') })}</p>}{skill.error && <p role="alert">{skill.error}</p>}<pre>{skill.content}</pre></details></span></li>)}</ul>
        : <p className="plugins-note" role="status">{yourQuery ? t('customise.noProjectSkillsMatch', { query: yourQuery }) : t('customise.noProjectSkills')}</p>}
    </> : kind === 'mcp' && mode === 'yours' ? <>
      <div className="settings-search plugins-search"><ShellIcon name="search" size={16}/><input aria-label={t('customise.searchAddedAria')} placeholder={t('customise.searchAddedPlaceholder')} value={yourQuery} onChange={(e) => setYourQuery(e.target.value)}/></div>
      <p className="plugins-note">{t('customise.addedServersNote')}</p>
      {!isAdmin ? <p className="plugins-note">{t('customise.adminManagesInventory')}</p>
        : addedStatus === 'loading' ? <p className="plugins-note" role="status">{t('customise.loadingAddedServers')}</p>
        : addedStatus === 'error' ? <p className="route-note" role="alert">{t('customise.loadAddedError')} <button className="btn btn-secondary btn-sm" onClick={() => setAddedAttempt((n) => n + 1)}>{t('connectors.tryAgain')}</button></p>
        : matchingAdded.length ? <ul className="plugin-grid">{matchingAdded.map((a) =>
          <li key={a.id} className="plugin-card surface">
            <span className="plugin-card-icon"><ShellIcon name="server" size={20}/></span>
            <span className="plugin-card-text"><b>{a.title}</b><small className="plugin-publisher">{a.registryName.startsWith('url:') ? t('customise.addedByUrl') : t('customise.publicRegistry')} · {a.error ? t('connectors.needsAttention') : t('customise.availableToolsCount', { count: tools(t, a.toolCount) })}</small><small>{a.registryName.startsWith('url:') ? a.registryName.slice(4) : a.registryName}</small>
              <details className="plugin-tool-detail"><summary>{a.tools?.length ? t('customise.availableToolsCount', { count: a.toolCount ?? a.tools.length }) : t('customise.availableTools')}</summary>
                {a.tools?.length ? <ul>{a.tools.map((tool) => <li key={tool.name}><b>{tool.name}</b>{tool.description && <span>{tool.description}</span>}</li>)}</ul> : <p>{a.error ? t('customise.toolsUnavailable') : t('customise.noToolsDiscovered')}</p>}
                {a.toolsTruncated && <p>{t('customise.toolsTruncated')}</p>}
                <p>{t('customise.projectMustSelect')}</p>
              </details></span>
            <span className="plugin-card-actions"><AddServer item={{ id: a.registryName, name: a.title, publisher: '', description: '', version: '', url: '', remote: true, installable: true, headers: a.declaredHeaders }} added={a} onChange={setAdded}/></span>
          </li>)}</ul>
        : <p className="plugins-note" role="status">{yourQuery ? t('customise.noAddedServersMatch', { query: yourQuery }) : t('customise.noAddedServers')}</p>}
    </> : <>
      <div className="settings-search plugins-search"><ShellIcon name="search" size={16}/><input aria-label={kind === 'mcp' ? t('customise.searchMcpPlaceholder') : t('customise.searchSkillsDiscoverPlaceholder')} placeholder={kind === 'mcp' ? t('customise.searchMcpPlaceholder') : t('customise.searchSkillsDiscoverPlaceholder')} value={query} onChange={(e) => setQuery(e.target.value)}/></div>
    <p className="plugins-note">{kind === 'mcp'
      ? (isAdmin ? t('customise.mcpDirectoryNoteAdmin') : t('customise.mcpDirectoryNoteMember'))
      : t('customise.skillsDirectoryNote')}
      {source && <> {t('customise.source')} <a href={source.home} target="_blank" rel="noreferrer noopener">{source.label}</a>.</>}</p>
    {error && <p className="route-note" role="alert">{error} <button className="btn btn-secondary btn-sm" onClick={() => setAttempt((n) => n + 1)}>{t('connectors.tryAgain')}</button></p>}
    {kind === 'mcp' && isAdmin && <AddByUrl onChange={setAdded}/>}
    {items === null ? <p className="plugins-note" aria-live="polite">{t('customise.loading')}</p> : !error && items.length === 0 ? <p className="plugins-note">{t('customise.noMatch', { query })}</p> : null}
    {!query && starters.length > 0 && <section className="plugins-starters" aria-label={t('customise.recommendedByNoevia')}>
      <h2 className="plugins-subhead">{t('customise.recommendedByNoevia')}</h2>
      <ul className="plugin-grid">{starters.map((i) => card(i, true))}</ul>
    </section>}
    {!query && starters.length > 0 && items && items.length > 0 && <h2 className="plugins-subhead">{kind === 'mcp' ? t('customise.allMcpServers') : t('customise.allSkills')}</h2>}
    <ul className="plugin-grid">
      {items?.map((i) => card(i))}
    </ul></>}
  </section>;
}

/** Add one published skill to a chosen project. It arrives needing review, never enabled. */
function AddSkill({ skill, projects, installedIn = [], onAdded }: { skill: Item; projects: { id: string; name: string }[]; installedIn?: string[]; onAdded?: () => void }): JSX.Element {
  const t = useT();
  const [open, setOpen] = useState(false);
  const [project, setProject] = useState('');
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<{ text: string; error?: boolean } | null>(null);
  if (!projects.length) return <button className="btn btn-secondary btn-sm plugin-card-link" disabled title={t('customise.createProjectFirst')}>{t('customise.addToProject')}</button>;
  if (!open) return <span className="plugin-add">{installedIn.length > 0 && <small>{t('customise.inSelectedProject')}</small>}<button className="btn btn-secondary btn-sm plugin-card-link" aria-label={t('customise.addSkillAria', { name: skill.name })} onClick={() => { setOpen(true); setNote(null); }}>{t('customise.addToProject')}</button>{note && <small role={note.error ? 'alert' : 'status'} className={note.error ? 'plugin-add-error' : ''}>{note.text}</small>}</span>;
  const add = async () => {
    setBusy(true); setNote(null);
    try {
      const r = await apiFetch(`/api/projects/${encodeURIComponent(project)}/skills/install`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ skill: skill.id }) });
      const data = await r.json().catch(() => ({}));
      if (!r.ok) throw new Error(data.error || t('customise.couldNotAddSkill'));
      const name = projects.find((p) => p.id === project)?.name || t('customise.theProject');
      setNote({ text: t('customise.addedToProject', { project: name }) });
      setOpen(false); onAdded?.();
    } catch (e) { setNote({ text: (e as Error).message, error: true }); } finally { setBusy(false); }
  };
  return <span className="plugin-add">
    <select aria-label={`Project for ${skill.name}`} value={project} onChange={(e) => setProject(e.target.value)} disabled={busy}>
      <option value="">{t('customise.chooseProjectOption')}</option>
      {projects.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
    </select>
    <button className="btn btn-primary btn-sm" disabled={!project || busy} onClick={() => void add()}>{busy ? t('customise.adding') : t('customise.add')}</button>
    <button className="btn btn-ghost btn-sm" onClick={() => setOpen(false)} disabled={busy}>{t('common.cancel')}</button>
    {note && <small role={note.error ? 'alert' : 'status'} className={note.error ? 'plugin-add-error' : ''}>{note.text}</small>}
  </span>;
}

/** Administrators add or remove a hosted server from the registry. The server re-reads its URL from
 *  the registry, checks it is public, and makes sure it answers before saving. This admin-only
 *  key/OAuth management flow is not yet translated (#293 gap); it is reached only from Plugins, by
 *  administrators, after the Directory and SignInServers/KeyServers strings above. */
function AddServer({ item, added, onChange }: { item: Item; added?: Added; onChange: (servers: Added[]) => void }): JSX.Element | null {
  const t = useT();
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<{ text: string; error?: boolean } | null>(null);
  // The key form: shown before adding a server that needs one, or to change a key later.
  const [form, setForm] = useState(false);
  const [values, setValues] = useState<Record<string, string>>({});
  const [keyMode, setKeyMode] = useState<'shared' | 'personal'>('personal');
  const fields = item.headers || [];
  // A sign-in service that needs a hand-registered app: where to register, and the app's ID/secret.
  const [appForm, setAppForm] = useState<{ issuer?: string; redirectUri?: string } | null>(null);
  const [clientId, setClientId] = useState('');
  const [clientSecret, setClientSecret] = useState('');
  const saveApp = (id: string) => void signInTab(async () => {
    setBusy(true); setNote(null);
    try {
      const r = await apiFetch(`/api/admin/mcp-directory/${encodeURIComponent(id)}/oauth-client`, { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ clientId, clientSecret }) });
      const d = await r.json().catch(() => ({}));
      if (!r.ok) { setNote({ text: d.error || 'The app was not accepted.', error: true }); return null; }
      onChange(d.servers || []); setAppForm(null); setClientSecret('');
      setNote({ text: 'Finish signing in in the new tab.' }); pollAdded();
      return d.signIn;
    } finally { setBusy(false); }
  }).catch((e) => setNote({ text: (e as Error).message, error: true }));
  const call = async (method: 'POST' | 'DELETE' | 'PUT') => {
    setBusy(true); setNote(null);
    try {
      // A personal server's key is the admin's own, changed like anyone else's.
      const url = method === 'POST' ? '/api/admin/mcp-directory' : method === 'PUT' ? (added?.personal ? `/api/mcp-keys/${encodeURIComponent(added!.id)}` : `/api/admin/mcp-directory/${encodeURIComponent(added!.id)}/keys`) : `/api/admin/mcp-directory/${encodeURIComponent(added!.id)}`;
      const payload = method === 'POST' ? { registryName: item.id, headers: values, keyMode } : method === 'PUT' ? { headers: values } : undefined;
      let data: any = {};
      let status = 0;
      const send = async () => { const r = await apiFetch(url, { method, headers: { 'Content-Type': 'application/json' }, body: payload ? JSON.stringify(payload) : undefined }); status = r.status; data = await r.json().catch(() => ({})); if (!r.ok) throw new Error(data.error || 'That did not work.'); return data.signIn || null; };
      // Adding may turn out to need a sign-in; the tab has to open inside this click.
      if (method === 'POST' && !fields.length) await signInTab(send); else await send();
      if (status === 202 && data.needsClient) { onChange(data.servers || []); setAppForm({ issuer: data.issuer, redirectUri: data.redirectUri }); return; }
      if (status === 202) { onChange(data.servers || []); setNote({ text: 'Finish signing in in the new tab. The server’s tools appear here once you have.' }); pollAdded(); return; }
      onChange(data.servers || []); setForm(false); setValues({});
      setNote({ text: method === 'POST' ? `Added with ${tools(t, data.server?.toolCount ?? 0)}. Choose it under a project’s Tools to use it.` : method === 'PUT' ? 'Key updated.' : 'Removed.' });
    } catch (e) { setNote({ text: (e as Error).message, error: true }); } finally { setBusy(false); }
  };
  // After an OAuth add, wait for the admin's sign-in to land and the tools to be listed.
  const pollAdded = () => {
    let n = 0;
    const timer = window.setInterval(async () => {
      n++;
      const d = await apiFetch('/api/admin/mcp-directory').then((r) => r.json()).catch(() => null);
      const me = d?.servers?.find((x: Added) => x.registryName === item.id);
      if (d?.servers) onChange(d.servers);
      if ((me && me.toolCount) || n > 60) { window.clearInterval(timer); if (me?.toolCount) setNote({ text: `Signed in. ${tools(t, me.toolCount)} available; choose it under a project’s Tools. Everyone else signs in with their own account from Plugins → Connected.` }); }
    }, 3000);
  };
  const msg = note && <small role={note.error ? 'alert' : 'status'} className={note.error ? 'plugin-add-error' : ''}>{note.text}</small>;
  const keyForm = (submitLabel: string, method: 'POST' | 'PUT') => <form className="plugin-key-form" onSubmit={(e) => { e.preventDefault(); void call(method); }}>
    {fields.map((h) => <label key={h.name}>
      <span>{h.name}{h.required ? '' : ' (optional)'}</span>
      {h.description && <small>{h.description}</small>}
      <input type={h.secret ? 'password' : 'text'} autoComplete="off" spellCheck={false} required={h.required}
        placeholder={h.template ? h.template.replace(/\{([^}]+)\}/, '$1') : ''} value={values[h.name] || ''}
        onChange={(e) => setValues((v) => ({ ...v, [h.name]: e.target.value }))}/>
    </label>)}
    {method === 'POST' && <fieldset className="plugin-key-mode"><legend>Who uses this key</legend>
      <label><input type="radio" name={`mode-${item.id}`} checked={keyMode === 'personal'} onChange={() => setKeyMode('personal')}/> Each person uses their own key <small>(yours is used to list the tools; others add theirs in Plugins → Connected)</small></label>
      <label><input type="radio" name={`mode-${item.id}`} checked={keyMode === 'shared'} onChange={() => setKeyMode('shared')}/> Everyone uses this key</label>
    </fieldset>}
    <small className="plugin-key-note">Stored encrypted on this server and sent only to this MCP server. {method === 'POST' ? (keyMode === 'shared' ? 'Everyone who uses its toolbox uses this key.' : 'Only you use this key.') : added?.personal ? 'This is your own key.' : 'Everyone who uses its toolbox uses this key.'}</small>
    <span className="plugin-key-actions"><button className="btn btn-primary btn-sm" disabled={busy}>{busy ? t('common.checking') : submitLabel}</button><button type="button" className="btn btn-ghost btn-sm" disabled={busy} onClick={() => { setForm(false); setValues({}); }}>{t('common.cancel')}</button></span>
  </form>;
  const appFormView = (id: string) => appForm && <form className="plugin-key-form" onSubmit={(e) => { e.preventDefault(); saveApp(id); }}>
    <small className="plugin-key-note">This service does not let apps register themselves. Register an app{appForm.issuer ? <> with <b>{appForm.issuer}</b></> : null} (in its developer or OAuth settings) and give it this return address:</small>
    <span className="plugin-copy"><code>{appForm.redirectUri}</code><button type="button" className="btn btn-ghost btn-sm" onClick={() => void navigator.clipboard?.writeText(appForm.redirectUri || '')}>Copy</button></span>
    <label><span>Client ID</span><input autoComplete="off" spellCheck={false} required value={clientId} onChange={(e) => setClientId(e.target.value)}/></label>
    <label><span>Client secret (if the service gave one)</span><input type="password" autoComplete="off" spellCheck={false} value={clientSecret} onChange={(e) => setClientSecret(e.target.value)}/></label>
    <small className="plugin-key-note">Stored encrypted and never shown again. Changing the app later signs everyone out of this server.</small>
    <span className="plugin-key-actions"><button className="btn btn-primary btn-sm" disabled={busy || !clientId.trim()}>{busy ? t('common.checking') : 'Save and sign in'}</button><button type="button" className="btn btn-ghost btn-sm" disabled={busy} onClick={() => setAppForm(null)}>{t('common.cancel')}</button></span>
  </form>;
  if (added) return <span className="plugin-add">
    <span className="badge ok">{added.error ? (added.oauth ? 'Waiting for sign-in' : 'Not answering') : `Added · ${tools(t, added.toolCount)}`}</span>
    {added.keyHeaders?.length ? <span className="badge count">Shared key set</span> : null}
    {added.personal && <span className="badge count">Each person adds a key</span>}
    {added.oauth && <span className="badge count">Each person signs in</span>}
    {added.oauth && added.oauthClient?.manual && <span className="badge count">App: {added.oauthClient.clientId}</span>}
    {added.oauth && !appForm && (!added.oauthClient || added.oauthClient.manual) && <button className="btn btn-ghost btn-sm" disabled={busy} onClick={() => { setClientId(added.oauthClient?.clientId || ''); setAppForm({ issuer: added.oauthClient?.issuer, redirectUri: added.redirectUri }); }}>{added.oauthClient ? 'App settings' : 'Set up app'}</button>}
    {appFormView(added.id)}
    {added.oauth && added.oauthClient && added.error && <button className="btn btn-secondary btn-sm" disabled={busy} onClick={() => void signInTab(async () => { const r = await apiFetch(`/api/mcp-oauth/${encodeURIComponent(added.id)}/connect`, { method: 'POST' }); const d = await r.json(); if (!r.ok) { setNote({ text: d.error || 'Could not start sign-in.', error: true }); return null; } pollAdded(); return d.signIn; })}>Sign in</button>}
    {fields.length > 0 && !form && <button className="btn btn-ghost btn-sm" disabled={busy} aria-label={`Change key for ${item.name}`} onClick={() => setForm(true)}>Change key</button>}
    <button className="btn btn-ghost btn-sm" disabled={busy} aria-label={`Remove ${item.name}`} onClick={() => void call('DELETE')}>{busy && !form ? 'Removing…' : 'Remove'}</button>
    {form && keyForm('Save key', 'PUT')}{msg}
  </span>;
  if (!item.installable) return <span className="plugin-add"><small>{item.notInstallable || 'Cannot be added'}</small></span>;
  if (form) return <span className="plugin-add">{keyForm('Add', 'POST')}{msg}</span>;
  return <span className="plugin-add">
    {item.needsKey && <span className="badge count">Needs a key</span>}
    <button className="btn btn-secondary btn-sm plugin-card-link" disabled={busy} aria-label={`Add ${item.name} to noevia`} onClick={() => (fields.length ? setForm(true) : void call('POST'))}>{busy ? t('common.checking') : 'Add'}</button>{msg}
  </span>;
}

/** Plugins → Connected: MCP servers that need each person's own sign-in. */
function SignInServers(): JSX.Element | null {
  const t = useT();
  const [servers, setServers] = useState<{ id: string; title: string; connected: boolean; needsReauth?: boolean }[]>([]);
  const [note, setNote] = useState<{ text: string; error?: boolean } | null>(null);
  const load = () => apiFetch('/api/mcp-oauth/servers').then((r) => r.json()).then((d) => setServers(d.servers || [])).catch(() => undefined);
  useEffect(() => { void load(); }, []);
  if (!servers.length) return null;
  const connect = (id: string) => void signInTab(async () => {
    const r = await apiFetch(`/api/mcp-oauth/${encodeURIComponent(id)}/connect`, { method: 'POST' }); const d = await r.json().catch(() => ({}));
    if (!r.ok) { setNote({ text: d.error || t('customise.couldNotStartSignIn'), error: true }); return null; }
    setNote({ text: t('customise.finishSigningIn') });
    let n = 0; const timer = window.setInterval(async () => {
      n++;
      const d = await apiFetch('/api/mcp-oauth/servers').then((r) => r.json()).catch(() => null);
      if (d?.servers) setServers(d.servers);
      if (d?.servers?.find((x: { id: string; connected: boolean }) => x.id === id)?.connected) { window.clearInterval(timer); setNote({ text: t('customise.signedIn') + '.' }); }
      else if (n > 60) window.clearInterval(timer);
    }, 3000);
    return d.signIn;
  }).catch((e) => setNote({ text: (e as Error).message, error: true }));
  const disconnect = async (id: string) => { await apiFetch(`/api/mcp-oauth/${encodeURIComponent(id)}`, { method: 'DELETE' }); setNote({ text: t('customise.disconnected') }); void load(); };
  return <section className="sign-in-servers" aria-label={t('customise.signInServersTitle')}>
    <h2>{t('customise.signInServersTitle')}</h2>
    <p className="plugins-note">{t('customise.signInServersNote')}</p>
    <ul className="plugin-grid">
      {servers.map((s) => <li key={s.id} className="plugin-card surface">
        <span className="plugin-card-icon"><ShellIcon name="server" size={20}/></span>
        <span className="plugin-card-text"><b>{s.title}</b><small>{s.connected ? t('customise.signedIn') : s.needsReauth ? t('customise.signInAgain') : t('customise.notSignedIn')}</small></span>
        <span className="plugin-card-actions">{s.connected
          ? <button className="btn btn-ghost btn-sm" aria-label={t('customise.disconnectAria', { name: s.title })} onClick={() => void disconnect(s.id)}>{t('connectors.disconnect')}</button>
          : <button className="btn btn-secondary btn-sm" aria-label={t('customise.signInAria', { name: s.title })} onClick={() => connect(s.id)}>{t('customise.signIn')}</button>}</span>
      </li>)}
    </ul>
    {note && <small role={note.error ? 'alert' : 'status'} className={note.error ? 'plugin-add-error' : ''}>{note.text}</small>}
  </section>;
}

/** Plugins → Connected: servers where each person adds their own key. */
function KeyServers(): JSX.Element | null {
  const t = useT();
  const [servers, setServers] = useState<{ id: string; title: string; headers: KeyHeader[]; hasKey: boolean }[]>([]);
  const [open, setOpen] = useState<string | null>(null);
  const [values, setValues] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<{ text: string; error?: boolean } | null>(null);
  const load = () => apiFetch('/api/mcp-keys/servers').then((r) => r.json()).then((d) => setServers(d.servers || [])).catch(() => undefined);
  useEffect(() => { void load(); }, []);
  if (!servers.length) return null;
  const save = async (id: string) => {
    setBusy(true); setNote(null);
    try {
      const r = await apiFetch(`/api/mcp-keys/${encodeURIComponent(id)}`, { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ headers: values }) });
      const d = await r.json().catch(() => ({}));
      if (!r.ok) throw new Error(d.error || t('customise.keyNotAccepted'));
      setOpen(null); setValues({}); setNote({ text: t('customise.keySaved') }); void load();
    } catch (e) { setNote({ text: (e as Error).message, error: true }); } finally { setBusy(false); }
  };
  const remove = async (id: string) => { await apiFetch(`/api/mcp-keys/${encodeURIComponent(id)}`, { method: 'DELETE' }); setNote({ text: t('customise.keyRemoved') }); void load(); };
  return <section className="sign-in-servers" aria-label={t('customise.keyServersTitle')}>
    <h2>{t('customise.keyServersTitle')}</h2>
    <p className="plugins-note">{t('customise.keyServersNote')}</p>
    <ul className="plugin-grid">
      {servers.map((s) => <li key={s.id} className="plugin-card surface">
        <span className="plugin-card-icon"><ShellIcon name="server" size={20}/></span>
        <span className="plugin-card-text"><b>{s.title}</b><small>{s.hasKey ? t('customise.yourKeySet') : t('customise.noKeyYet')}</small></span>
        <span className="plugin-card-actions">
          {open !== s.id && <span className="plugin-add">
            <button className="btn btn-secondary btn-sm" aria-label={s.hasKey ? t('customise.changeYourKeyAria', { name: s.title }) : t('customise.addYourKeyAria', { name: s.title })} onClick={() => { setOpen(s.id); setValues({}); setNote(null); }}>{s.hasKey ? t('customise.changeKey') : t('customise.addKey')}</button>
            {s.hasKey && <button className="btn btn-ghost btn-sm" aria-label={t('customise.removeYourKeyAria', { name: s.title })} onClick={() => void remove(s.id)}>{t('customise.removeKey')}</button>}
          </span>}
          {open === s.id && <form className="plugin-key-form" onSubmit={(e) => { e.preventDefault(); void save(s.id); }}>
            {s.headers.map((h) => <label key={h.name}><span>{h.name}{h.required ? '' : ' (optional)'}</span>{h.description && <small>{h.description}</small>}
              <input type={h.secret ? 'password' : 'text'} autoComplete="off" spellCheck={false} required={h.required} placeholder={h.template ? h.template.replace(/\{([^}]+)\}/, '$1') : ''}
                value={values[h.name] || ''} onChange={(e) => setValues((v) => ({ ...v, [h.name]: e.target.value }))}/></label>)}
            <span className="plugin-key-actions"><button className="btn btn-primary btn-sm" disabled={busy}>{busy ? t('common.checking') : t('customise.saveKey')}</button><button type="button" className="btn btn-ghost btn-sm" disabled={busy} onClick={() => setOpen(null)}>{t('common.cancel')}</button></span>
          </form>}
        </span>
      </li>)}
    </ul>
    {note && <small role={note.error ? 'alert' : 'status'} className={note.error ? 'plugin-add-error' : ''}>{note.text}</small>}
  </section>;
}

/** Administrators add any MCP server by its address, with an optional sign-in header. Not yet
 *  translated (#293 gap): admin-only, reached from the Plugins tab's Library section. */
function AddByUrl({ onChange }: { onChange: (servers: Added[]) => void }): JSX.Element {
  const t = useT();
  const [open, setOpen] = useState(false);
  const [form, setForm] = useState({ title: '', url: '', headerName: '', headerValue: '', keyMode: 'personal' as 'personal' | 'shared' });
  const [busy, setBusy] = useState(false);
  const [review, setReview] = useState(false);
  const [preview, setPreview] = useState<{ requiresSignIn: boolean; toolCount: number | null; tools: { name: string; description: string }[]; toolsTruncated: boolean; previewToken: string } | null>(null);
  const revision = useRef(0);
  const resetReview = () => { revision.current++; setReview(false); setPreview(null); };
  const [note, setNote] = useState<{ text: string; error?: boolean } | null>(null);
  const set = (k: keyof typeof form) => (e: { target: { value: string } }) => { resetReview(); setForm((f) => ({ ...f, [k]: e.target.value })); };
  const check = async () => {
    const current = revision.current;
    setBusy(true); setNote(null);
    try {
      const r = await apiFetch('/api/admin/mcp-directory/custom/preview', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(form) });
      const data = await r.json().catch(() => ({}));
      if (current !== revision.current) return;
      if (!r.ok) throw new Error(data.error || 'Could not preview this server.');
      setPreview(data); setReview(true);
    } catch (e) { if (current === revision.current) setNote({ text: (e as Error).message, error: true }); }
    finally { setBusy(false); }
  };
  const submit = () => void signInTab(async () => {
    setBusy(true); setNote(null);
    try {
      const r = await apiFetch('/api/admin/mcp-directory/custom', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ ...form, previewToken: preview?.previewToken }) });
      const d = await r.json().catch(() => ({}));
      if (!r.ok) { if (r.status === 409) resetReview(); setNote({ text: d.error || 'That did not work.', error: true }); return null; }
      onChange(d.servers || []);
      if (d.signIn) { setNote({ text: 'Sign in with this server in the new tab. Its tools will be discovered after sign-in; review the available tools before selecting its toolbox in a project.' }); return d.signIn; }
      if (d.needsClient) { setNote({ text: 'This server needs an app registered by hand. Use “Set up app” on its card below.', error: true }); setOpen(false); return null; }
      setNote({ text: `Connected. noevia discovered ${tools(t, d.server?.toolCount ?? 0)}. Review its toolbox before selecting it in a project; each tool call still asks for approval.` });
      setOpen(false); resetReview(); setForm({ title: '', url: '', headerName: '', headerValue: '', keyMode: 'personal' });
      return null;
    } finally { setBusy(false); }
  }).catch((e) => setNote({ text: (e as Error).message, error: true }));
  if (!open) return <p className="plugins-note"><button className="btn btn-secondary btn-sm" onClick={() => { setOpen(true); setNote(null); }}>{t('customise.addServerByUrl')}</button>{note && <> <span role={note.error ? 'alert' : 'status'} className={note.error ? 'plugin-add-error' : ''}>{note.text}</span></>}</p>;
  return <form className="plugin-key-form plugin-url-form" onSubmit={(e) => { e.preventDefault(); if (busy) return; if (review && preview) submit(); else void check(); }}>
    <fieldset className="plugin-url-fields" disabled={busy}>
    <label><span>Name</span><input required value={form.title} onChange={set('title')} placeholder="What this server is"/></label>
    <label><span>Address</span><input required type="url" inputMode="url" autoComplete="off" spellCheck={false} value={form.url} onChange={set('url')} placeholder="https://example.com/mcp"/></label>
    <label><span>Sign-in header (optional)</span><input autoComplete="off" spellCheck={false} value={form.headerName} onChange={set('headerName')} placeholder="Authorization"/></label>
    {form.headerName && <label><span>Its value</span><input type="password" autoComplete="off" value={form.headerValue} onChange={set('headerValue')} placeholder="Bearer …"/></label>}
    {form.headerName && <fieldset className="plugin-key-mode"><legend>Who uses this key</legend>
      <label><input type="radio" name="url-mode" checked={form.keyMode === 'personal'} onChange={() => { resetReview(); setForm((f) => ({ ...f, keyMode: 'personal' })); }}/> Each person uses their own key</label>
      <label><input type="radio" name="url-mode" checked={form.keyMode === 'shared'} onChange={() => { resetReview(); setForm((f) => ({ ...f, keyMode: 'shared' })); }}/> Everyone uses this key</label>
    </fieldset>}
    </fieldset>
    {review ? <div className="plugin-url-review" role="group" aria-label="Review server access">
      <b>Review before connecting</b>
      <p><strong>Server:</strong> {form.title} · <span className="plugin-url-address">{form.url}</span></p>
      <p><strong>Data access:</strong> Requests to this external server can send conversation context and tool arguments when its toolbox is selected.</p>
      {preview?.requiresSignIn ? <p>The server requires sign-in. Tool details are unavailable until sign-in completes.</p> : <><p><strong>Discovered tools:</strong> {preview?.toolCount ?? 0}{preview?.toolsTruncated ? ' (first 40 shown)' : ''}</p><ul className="plugin-preview-tools">{preview?.tools.map((tool) => <li key={tool.name}><strong>{tool.name}</strong>{tool.description && <span>{tool.description}</span>}</li>)}</ul></>}
      <p><strong>Credential:</strong> {form.headerName ? `${form.headerName} header; ${form.keyMode === 'shared' ? 'shared with everyone who uses this toolbox' : 'used only for your requests'}.` : 'No header supplied. The server may ask you to sign in.'}</p>
      <p><strong>Control:</strong> A project must select the toolbox. Tools may change later; every call still asks for approval.</p>
    </div> : <small className="plugin-key-note">Preview checks the public HTTPS address and asks the server for its tools without saving it. Review the destination and discovered tools before connecting.</small>}
    <span className="plugin-key-actions"><button className="btn btn-primary btn-sm" disabled={busy}>{busy ? (review ? 'Connecting…' : t('common.checking')) : review ? 'Connect reviewed server' : 'Preview tools'}</button><button type="button" className="btn btn-ghost btn-sm" disabled={busy} onClick={() => { setOpen(false); resetReview(); }}>{t('common.cancel')}</button></span>
    {note && <small role={note.error ? 'alert' : 'status'} className={note.error ? 'plugin-add-error' : ''}>{note.text}</small>}
  </form>;
}
