'use client';

import { useMemo, useState } from 'react';
import Link from 'next/link';
import { BadgeCheck, ChevronRight, Search } from 'lucide-react';

import { AdminFrame } from '../components/admin-frame';
import { guideGroups } from '../lib/guide-content';

/**
 * The full admin guide, for reading end to end.
 *
 * Same content as the Guide button in the top bar — both read
 * `app/lib/guide-content.ts`. Two copies of a guide disagree within a month,
 * and the one someone happens to open is then the wrong one.
 *
 * Everything is expanded by default here. This page is for someone learning the
 * portal or checking a procedure; making them click twenty times to read a
 * manual is the opposite of what a manual is for. The slide-over panel starts
 * collapsed, because there the reader already knows what they came for.
 */
export default function HelpPage() {
  const [query, setQuery] = useState('');

  const results = useMemo(() => {
    const needle = query.trim().toLowerCase();
    if (!needle) return guideGroups;

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

  const sectionCount = guideGroups.reduce(
    (total, group) => total + group.sections.length,
    0,
  );

  return (
    <AdminFrame
      title="Admin guide"
      subtitle="What every screen is for, how to use it, and what not to get wrong."
    >
      <section className="helpHero">
        <div>
          <span>ADMIN GUIDE</span>
          <h2>Run UDrive safely and correctly</h2>
          <p>
            {sectionCount} sections covering every screen in this portal. The
            same guide sits behind the <strong>Guide</strong> button in the top
            right of any page, so you never have to leave what you are doing to
            look something up.
          </p>
        </div>
        <BadgeCheck size={50} />
      </section>

      <section className="panel">
        <div className="guideSearch" style={{ margin: '16px 18px' }}>
          <Search size={15} />
          <input
            value={query}
            placeholder="Search the guide — refund, per km, verification, OTP…"
            onChange={(event) => setQuery(event.target.value)}
          />
        </div>
      </section>

      {results.length === 0 && (
        <section className="panel">
          <p className="guideEmpty">
            Nothing in the guide matches “{query}”. Try a shorter word.
          </p>
        </section>
      )}

      {results.map((group) => (
        <section className="panel" key={group.label}>
          <header className="panelHeader">
            <div>
              <h2>{group.label}</h2>
              <p>{group.blurb}</p>
            </div>
          </header>

          <div style={{ padding: '14px 18px 18px' }}>
            {group.sections.map((section) => (
              <details
                className="guideEntry"
                key={`${group.label}-${section.title}`}
                open
              >
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
                  {section.roles && (
                    <span className="guideRoles">{section.roles}</span>
                  )}
                  <Link href={section.path}>
                    Go to screen
                    <ChevronRight size={13} />
                  </Link>
                </div>
              </details>
            ))}
          </div>
        </section>
      ))}
    </AdminFrame>
  );
}
