'use client';

import { useEffect, useMemo, useState } from 'react';
import { createPortal } from 'react-dom';
import Link from 'next/link';
import { BookOpen, ChevronRight, Search, X } from 'lucide-react';

import {
  guideGroups,
  haystack,
  say,
  type GuideLanguage,
  type GuideSection,
} from '../lib/guide-content';
import { useGuideLanguage } from '../lib/guide-language';

/**
 * The Guide button in the top bar, and the panel it opens.
 *
 * A slide-over rather than a separate page, because the guide is read *while*
 * doing the thing it describes. Sending someone to another route means losing
 * the half-filled form they were stuck on, which is exactly when they went
 * looking for help.
 *
 * The full guide still lives at /help for reading end to end; this is the same
 * content, reachable without leaving the screen.
 */
export function GuideButton() {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const [language, setLanguage] = useGuideLanguage();
  const [mounted, setMounted] = useState(false);

  useEffect(() => setMounted(true), []);

  // Escape closes it. A panel that covers the screen and can only be dismissed
  // by finding a small × is a trap. The page behind is frozen at the same
  // time, so a scroll aimed at the guide does not silently move the form the
  // reader is in the middle of.
  useEffect(() => {
    if (!open) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setOpen(false);
    };
    window.addEventListener('keydown', onKey);
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => {
      window.removeEventListener('keydown', onKey);
      document.body.style.overflow = previousOverflow;
    };
  }, [open]);

  const results = useMemo(() => {
    const needle = query.trim().toLowerCase();
    if (!needle) return guideGroups;

    // Searches both languages, and the steps and cautions as well as the
    // titles. Someone looking for help types the problem — "refund", "per km",
    // "wapsi" — not the heading it sits under, and searching only the language
    // on screen would hide a screen from someone who typed its English name.
    return guideGroups
      .map((group) => ({
        ...group,
        sections: group.sections.filter((section) =>
          haystack(section).includes(needle),
        ),
      }))
      .filter((group) => group.sections.length > 0);
  }, [query]);

  return (
    <>
      <button
        className="guideTrigger"
        onClick={() => setOpen(true)}
        title="Open the admin guide"
      >
        <BookOpen size={16} />
        <span>Guide</span>
      </button>

      {/*
        Rendered into <body> rather than here.

        The button sits inside the top bar, and the top bar has a
        backdrop-filter. A backdrop-filter makes its element the containing
        block for every fixed-position descendant, so `position: fixed;
        inset: 0` on the overlay was resolving against a 72-pixel-tall strip
        instead of the viewport: the guide opened as a clipped band across the
        top of the page with its body collapsed to nothing. A portal takes it
        out of that subtree, and the same CSS then means what it says.
      */}
      {open && mounted && createPortal(
        <div className="guideOverlay" role="dialog" aria-label="Admin guide">
          <button
            className="guideScrim"
            aria-label="Close guide"
            onClick={() => setOpen(false)}
          />
          <aside className="guidePanel">
            <header className="guidePanelHead">
              <div>
                <strong>Admin guide</strong>
                <small>
                  {language === 'ur'
                    ? 'Har screen kis kaam ki hai, aur usay mehfooz tareeqe se kaise chalana hai.'
                    : 'What each screen is for, and how to use it safely.'}
                </small>
              </div>
              <div className="guideHeadTools">
                <LanguageSwitch value={language} onChange={setLanguage} />
                <button className="iconButton" onClick={() => setOpen(false)}>
                  <X />
                </button>
              </div>
            </header>

            <div className="guideSearch">
              <Search size={15} />
              <input
                autoFocus
                value={query}
                placeholder={
                  language === 'ur'
                    ? 'Guide mein dhoondein — refund, per km, verification…'
                    : 'Search the guide — refund, per km, verification…'
                }
                onChange={(event) => setQuery(event.target.value)}
              />
            </div>

            <div className="guideBody">
              {results.length === 0 && (
                <p className="guideEmpty">
                  {language === 'ur'
                    ? `“${query}” se guide mein kuch nahi mila. Chhota lafz try karein, ya poori guide kholein.`
                    : `Nothing in the guide matches “${query}”. Try a shorter word, or open the full guide.`}
                </p>
              )}

              {results.map((group) => (
                <section key={group.label} className="guideGroup">
                  <h3>{group.label}</h3>
                  <p className="guideGroupBlurb">{say(group.blurb, language)}</p>
                  {group.sections.map((section) => (
                    // The query is part of the key so each keystroke remounts
                    // the entries. <details open> is uncontrolled: once the
                    // reader collapses one by hand, React sees no prop change
                    // on the next keystroke and never re-opens it, leaving a
                    // search result whose matched words are hidden. Remounting
                    // is the cheap fix at thirty-nine entries.
                    <GuideEntry
                      key={`${group.label}-${section.title}-${query.trim()}`}
                      section={section}
                      language={language}
                      expanded={query.trim().length > 0}
                      onNavigate={() => setOpen(false)}
                    />
                  ))}
                </section>
              ))}
            </div>

            <footer className="guidePanelFoot">
              <Link href="/help" onClick={() => setOpen(false)}>
                {language === 'ur' ? 'Poori guide kholein' : 'Open the full guide'}
                <ChevronRight size={14} />
              </Link>
            </footer>
          </aside>
        </div>,
        document.body,
      )}
    </>
  );
}

/**
 * Roman / English.
 *
 * Labelled in each language's own words rather than with flags: a flag names a
 * country, and neither of these is a country.
 */
export function LanguageSwitch({
  value,
  onChange,
}: {
  value: GuideLanguage;
  onChange: (next: GuideLanguage) => void;
}) {
  return (
    <div className="helpLanguageSwitch" role="group" aria-label="Guide language">
      <button
        type="button"
        className={value === 'ur' ? 'active' : ''}
        onClick={() => onChange('ur')}
      >
        Roman
      </button>
      <button
        type="button"
        className={value === 'en' ? 'active' : ''}
        onClick={() => onChange('en')}
      >
        English
      </button>
    </div>
  );
}

function GuideEntry({
  section,
  language,
  expanded,
  onNavigate,
}: {
  section: GuideSection;
  language: GuideLanguage;
  expanded: boolean;
  onNavigate: () => void;
}) {
  return (
    // Open by default while searching: a list of collapsed headings is a poor
    // answer to a search, since the matched words are inside them.
    <details className="guideEntry" open={expanded}>
      <summary>
        <strong>{section.title}</strong>
        <small>{say(section.purpose, language)}</small>
      </summary>

      <ol>
        {section.steps.map((step, index) => (
          <li key={`${section.path}-step-${index}`}>{say(step, language)}</li>
        ))}
      </ol>

      {section.cautions && section.cautions.length > 0 && (
        <ul className="guideCautions">
          {section.cautions.map((caution, index) => (
            <li key={`${section.path}-caution-${index}`}>
              {say(caution, language)}
            </li>
          ))}
        </ul>
      )}

      <div className="guideEntryFoot">
        {section.roles && (
          <span className="guideRoles">{say(section.roles, language)}</span>
        )}
        <Link href={section.path} onClick={onNavigate}>
          {language === 'ur' ? 'Screen kholein' : 'Go to screen'}
          <ChevronRight size={13} />
        </Link>
      </div>
    </details>
  );
}
