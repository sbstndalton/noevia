// The React side of the interface language (#231). The locale is the account preference
// (user-preferences.ts), so every component using useT() re-renders when it is saved, in this tab
// or after the account record loads. `t()` is for code outside React (a class boundary, a toast).
import { useEffect, useMemo, useState } from 'react';
import { PREFERENCES_CHANGED, currentPreferences, useAccountPreferences } from '../user-preferences';
import { resolveInterfaceLocale, translate, translatePlural } from './core';
import type { MessageKey, Params } from './core';

export type { MessageKey, Params };
export type Translate = ((key: MessageKey, params?: Params) => string) & { plural: (key: string, count: number, params?: Params) => string; locale: string };

const browserLanguages = (): readonly string[] => (typeof navigator === 'undefined' ? [] : navigator.languages?.length ? navigator.languages : [navigator.language]);

/** The locale the interface is shown in right now. */
export function interfaceLocale(preference = currentPreferences().locale): string {
  return resolveInterfaceLocale(preference, browserLanguages());
}

function bind(locale: string): Translate {
  const fn = ((key: MessageKey, params?: Params) => translate(locale, key, params)) as Translate;
  fn.plural = (key, count, params) => translatePlural(locale, key, count, params);
  fn.locale = locale;
  return fn;
}

/** Outside React: the current locale, read at call time. */
export function t(key: MessageKey, params?: Params): string { return translate(interfaceLocale(), key, params); }

/** Inside React: a translator that changes identity when the locale does. */
export function useT(): Translate {
  const { locale: preference } = useAccountPreferences();
  const [, setTick] = useState(0);
  // 'system' follows the browser, which can change its language while the page is open.
  useEffect(() => {
    const again = () => setTick((n) => n + 1);
    window.addEventListener('languagechange', again);
    return () => window.removeEventListener('languagechange', again);
  }, []);
  const locale = interfaceLocale(preference);
  return useMemo(() => bind(locale), [locale]);
}

/** Keeps <html lang> on the interface locale, so screen readers, hyphenation and spellcheck
 *  follow it. Called once at start-up. */
export function startInterfaceLanguage(): void {
  if (typeof document === 'undefined') return;
  const apply = () => { document.documentElement.lang = interfaceLocale(); };
  apply();
  window.addEventListener(PREFERENCES_CHANGED, apply);
  window.addEventListener('languagechange', apply);
}

/** The composer's send hint in the interface language, with the platform's key names. */
export function sendHintText(t: Translate, sendKey: 'enter' | 'mod-enter', apple: boolean): string {
  return sendKey === 'enter'
    ? t('composer.hintEnter', { newline: apple ? '⇧Enter' : 'Shift+Enter' })
    : t('composer.hintMod', { mod: apple ? '⌘' : 'Ctrl+' });
}
