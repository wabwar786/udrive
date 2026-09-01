'use client';

import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { BookOpen, ChevronRight, Search, X } from 'lucide-react';

import { guideGroups, type GuideSection } from '../lib/guide-content';

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

  // Escape closes it. A panel that covers the screen and can only be dismissed
  // by finding a small × is a trap.
  useEffect(() => {
    if (!open) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setOpen(false);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open]);

  const results = useMemo(() => {
    const needle = query.trim().toLowerCase();
    if (!needle) return guideGroups;

    // Searches the steps and cautions too, not just titles. Someone looking for
    // help types the problem ("refund", "per km"), not the heading it sits
    // under.
    return guideGroups
      .map((group) => ({
        ...group,
        sections: group.sections.filter((section) =>
          [
            section.title,
            section.purpose,
            ...section.steps,
            ...(section.cautions ?? []),
          ]
            .join(' ')
            .toLowerCase()
            .includes(needle),
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

      {open && (
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
                <small>What each screen is for, and how to use it safely.</small>
              </div>
              <button className="iconButton" onClick={() => setOpen(false)}>
                <X />
              </button>
            </header>

            <div className="guideSearch">
              <Search size={15} />
              <input
                autoFocus
                value={query}
                placeholder="Search the guide — refund, per km, verification…"
                onChange={(event) => setQuery(event.target.value)}
              />
            </div>

            <div className="guideBody">
              {results.length === 0 && (
                <p className="guideEmpty">
                  Nothing in the guide matches “{query}”. Try a shorter word, or
                  open the full guide.
                </p>
              )}

              {results.map((group) => (
                <section key={group.label} className="guideGroup">
                  <h3>{group.label}</h3>
                  <p className="guideGroupBlurb">{group.blurb}</p>
                  {group.sections.map((section) => (
                    <GuideEntry
                      key={`${group.label}-${section.title}`}
                      section={section}
                      expanded={query.trim().length > 0}
                      onNavigate={() => setOpen(false)}
                    />
                  ))}
                </section>
              ))}
            </div>

            <footer className="guidePanelFoot">
              <Link href="/help" onClick={() => setOpen(false)}>
                Open the full guide
                <ChevronRight size={14} />
              </Link>
            </footer>
          </aside>
        </div>
      )}
    </>
  );
}

function GuideEntry({
  section,
  expanded,
  onNavigate,
}: {
  section: GuideSection;
  expanded: boolean;
  onNavigate: () => void;
}) {
  return (
    // Open by default while searching: a list of collapsed headings is a poor
    // answer to a search, since the matched words are inside them.
    <details className="guideEntry" open={expanded}>
      <summary>
        <strong>{section.title}</strong>
        <small>{section.purpose}</small>
      </summary>

      <ol>
        {section.steps.map((step) => (
          <li key={step}>{step}</li>
        ))}
      </ol>

      {section.cautions && section.cautions.length > 0 && (
        <ul className="guideCautions">
          {section.cautions.map((caution) => (
            <li key={caution}>{caution}</li>
          ))}
        </ul>
      )}

      <div className="guideEntryFoot">
        {section.roles && <span className="guideRoles">{section.roles}</span>}
        <Link href={section.path} onClick={onNavigate}>
          Go to screen
          <ChevronRight size={13} />
        </Link>
      </div>
    </details>
  );
}
