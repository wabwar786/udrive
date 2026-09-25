'use client';

import { useCallback, useEffect, useState } from 'react';

import type { GuideLanguage } from './guide-content';

const STORAGE_KEY = 'udrive.guide.language';
const CHANGED = 'udrive-guide-language';

function isLanguage(value: unknown): value is GuideLanguage {
  return value === 'en' || value === 'ur';
}

/**
 * Which language the guide is being read in.
 *
 * Shared between the Guide slide-over and the Help page through localStorage
 * and a window event, so switching to English in one does not leave the other
 * in Roman Urdu. Both are open at once often enough — someone reads the full
 * guide on one screen and opens the panel on another — that two independent
 * switches would read as a bug.
 *
 * Roman Urdu is the default. The portal itself stays English.
 */
export function useGuideLanguage(): [GuideLanguage, (next: GuideLanguage) => void] {
  const [language, setLanguage] = useState<GuideLanguage>('ur');

  // After mount, not during render: reading localStorage while rendering makes
  // the server markup and the first client render disagree, and React then
  // throws the whole panel away and rebuilds it.
  useEffect(() => {
    try {
      const saved = window.localStorage.getItem(STORAGE_KEY);
      if (isLanguage(saved)) setLanguage(saved);
    } catch {
      // Blocked storage just means the default, which is a working guide.
    }

    // The new language travels on the event itself rather than being re-read
    // from storage. Where storage is blocked — a private window, a managed
    // browser — the write silently fails, and a listener that re-read storage
    // would find the old value and leave this switch behind: the Help page in
    // English with the panel still in Roman Urdu, which is the one thing the
    // shared state exists to prevent.
    const onChanged = (event: Event) => {
      const next = (event as CustomEvent<unknown>).detail;
      if (isLanguage(next)) setLanguage(next);
    };
    window.addEventListener(CHANGED, onChanged);
    return () => window.removeEventListener(CHANGED, onChanged);
  }, []);

  const choose = useCallback((next: GuideLanguage) => {
    setLanguage(next);
    try {
      window.localStorage.setItem(STORAGE_KEY, next);
    } catch {
      // Not remembered for next time; still applied everywhere on this page.
    }
    window.dispatchEvent(new CustomEvent(CHANGED, { detail: next }));
  }, []);

  return [language, choose];
}
