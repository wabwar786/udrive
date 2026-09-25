'use client';

import { useMemo, useState } from 'react';
import Link from 'next/link';
import { BadgeCheck, ChevronRight, Printer, Search } from 'lucide-react';

import { AdminFrame } from '../components/admin-frame';
import { LanguageSwitch } from '../components/guide-button';
import {
  dailyChecklist,
  guideGroups,
  haystack,
  say,
} from '../lib/guide-content';
import { useGuideLanguage } from '../lib/guide-language';

/**
 * The full admin guide, for reading end to end.
 *
 * Same content as the Guide button in the top bar — both read
 * `app/lib/guide-content.ts`. Two copies of a guide disagree within a month,
 * and the one someone happens to open is then the wrong one. The printed copy
 * is this page through the browser's own print dialogue, for the same reason:
 * a PDF built separately is a third copy waiting to go stale.
 *
 * Everything is expanded by default here. This page is for someone learning
 * the portal or checking a procedure; making them click thirty-five times to
 * read a manual is the opposite of what a manual is for. The slide-over panel
 * starts collapsed, because there the reader already knows what they came for.
 *
 * The group headings are the sidebar headings, in the sidebar's order, so this
 * page can be read as a map of the menu rather than as a second structure to
 * learn.
 */
export default function HelpPage() {
  const [query, setQuery] = useState('');
  const [language, setLanguage] = useGuideLanguage();
  const urdu = language === 'ur';

  const results = useMemo(() => {
    const needle = query.trim().toLowerCase();
    if (!needle) return guideGroups;

    return guideGroups
      .map((group) => ({
        ...group,
        sections: group.sections.filter((section) =>
          haystack(section).includes(needle),
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
      actions={<LanguageSwitch value={language} onChange={setLanguage} />}
    >
      <section className="helpHero">
        <div>
          <span>ADMIN GUIDE</span>
          <h2>
            {urdu ? 'UDrive sahi tareeqe se chalayein' : 'Run UDrive safely and correctly'}
          </h2>
          <p>
            {urdu
              ? `Is portal ki har screen ke liye ${sectionCount} hisse. Yehi guide har page par upar dayein “Guide” button ke peeche bhi mojood hai, taake apna kaam chhore baghair dekh sakein. Portal angrezi mein hai; guide Roman Urdu mein — upar se English par badal sakte hain.`
              : `${sectionCount} sections covering every screen in this portal. The same guide sits behind the Guide button in the top right of any page, so you never have to leave what you are doing to look something up.`}
          </p>
        </div>
        <BadgeCheck size={50} />
      </section>

      {/* The day, before the reference material. Someone who has just been
          given this portal needs an order to work in more than they need a
          description of screen twenty-nine. */}
      <section className="panel helpDaily">
        <header className="panelHeader">
          <div>
            <h2>{urdu ? 'Rozana ka kaam, isi tarteeb mein' : 'The day, in this order'}</h2>
            <p>
              {urdu
                ? 'Log in karne ke baad in screens ko isi tarteeb se khali karein. Upar wali cheez hamesha neeche wali se pehle.'
                : 'Clear these queues in this order after logging in. Anything higher always comes before anything lower.'}
            </p>
          </div>
          <button className="secondaryButton helpPrintButton" onClick={() => window.print()}>
            <Printer size={15} /> {urdu ? 'Print / PDF' : 'Print / PDF'}
          </button>
        </header>

        <ol className="helpChecklist">
          {dailyChecklist.map((entry, index) => (
            <li key={entry.path + index}>
              <span className="helpChecklistStep">{index + 1}</span>
              <span>
                <Link href={entry.path}>{entry.title}</Link>
                <small>{say(entry.detail, language)}</small>
              </span>
            </li>
          ))}
        </ol>
      </section>

      <section className="panel helpSearchPanel">
        <div className="guideSearch" style={{ margin: '16px 18px' }}>
          <Search size={15} />
          <input
            value={query}
            placeholder={
              urdu
                ? 'Guide mein dhoondein — refund, per km, verification, OTP…'
                : 'Search the guide — refund, per km, verification, OTP…'
            }
            onChange={(event) => setQuery(event.target.value)}
          />
        </div>
      </section>

      {results.length === 0 && (
        <section className="panel">
          <p className="guideEmpty">
            {urdu
              ? `“${query}” se guide mein kuch nahi mila. Chhota lafz try karein.`
              : `Nothing in the guide matches “${query}”. Try a shorter word.`}
          </p>
        </section>
      )}

      {results.map((group) => (
        <section className="panel" key={group.label}>
          <header className="panelHeader">
            <div>
              <h2>{group.label}</h2>
              <p>{say(group.blurb, language)}</p>
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
                  <small>{say(section.purpose, language)}</small>
                </summary>

                <ol>
                  {section.steps.map((step, index) => (
                    <li key={`${section.path}-step-${index}`}>
                      {say(step, language)}
                    </li>
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
                  <Link href={section.path}>
                    {urdu ? 'Screen kholein' : 'Go to screen'}
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
