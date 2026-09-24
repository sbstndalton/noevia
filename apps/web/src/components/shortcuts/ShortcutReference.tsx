import type { JSX } from 'react';
import { ShellIcon } from '../ShellIcon';
import { filterShortcuts, referenceShortcuts } from './shortcuts';
import { useAccountPreferences } from '../../user-preferences';
import { useT } from '../../i18n';
import type { MessageKey } from '../../i18n';

// The reference rows are built in English from the handler table; their text is looked up here.
const LABEL_KEYS: Record<string, MessageKey> = {
  'Search projects and chats': 'keyboard.action.search', 'New chat': 'keyboard.action.newChat', 'Open Settings': 'keyboard.action.settings',
  'Show keyboard shortcuts': 'keyboard.action.help', 'Show keyboard shortcuts (outside a text field)': 'keyboard.action.helpAnywhere',
  'Send a message': 'keyboard.action.send', 'New line in a message': 'keyboard.action.newline', 'Save an edited message and re-run': 'keyboard.action.saveEdit',
  'Cancel editing a message': 'keyboard.action.cancelEdit', 'Close a dialog, menu, search or Settings': 'keyboard.action.close', 'Move between menu items': 'keyboard.action.moveMenu',
};

/** The searchable list shared by the "?" overlay and Settings → Keyboard & input (#230). */
export function ShortcutReference({ apple, query, onQuery }: { apple: boolean; query: string; onQuery: (q: string) => void }): JSX.Element {
  const { sendKey } = useAccountPreferences();
  const t = useT();
  // Translated before filtering, so search matches what is on screen (the English group still matches).
  const rows = filterShortcuts(referenceShortcuts(apple, sendKey).map((r) => ({ ...r, label: LABEL_KEYS[r.label] ? t(LABEL_KEYS[r.label]) : r.label })), query);
  const groups = [...new Set(rows.map((r) => r.group))];
  return <div className="shortcut-reference">
    <div className="settings-search shortcut-search"><ShellIcon name="search" size={16}/><input aria-label={t('keyboard.searchShortcuts')} placeholder={t('keyboard.searchShortcuts')} value={query} onChange={(e) => onQuery(e.target.value)} /></div>
    {groups.map((g) => <section key={g} aria-label={t(`keyboard.group.${g}`)}>
      <h3 className="shortcut-group">{t(`keyboard.group.${g}`)}</h3>
      <dl className="shortcuts-list">{rows.filter((r) => r.group === g).map((r) => <div key={r.label}><dt>{r.label}</dt><dd><kbd>{r.keys}</kbd></dd></div>)}</dl>
    </section>)}
    {!rows.length && <p className="route-note" role="status">{t('keyboard.noMatch', { query })}</p>}
  </div>;
}
