'use client';

import { useMemo, useState } from 'react';
import Link from 'next/link';
import { BadgeCheck, ChevronRight, Printer, Search } from 'lucide-react';

import { AdminFrame } from '../components/admin-frame';
import { LanguageSwitch } from '../components/guide-button';
import {
  customerGuideGroups,
  dailyChecklist,
  driverGuideGroups,
  guideGroups,
  haystack,
  say,
} from '../lib/guide-content';
import { useGuideLanguage } from '../lib/guide-language';

/**
 * The three guides, for reading end to end.
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
 *
 * Three audiences, one page. Support answers questions about the driver app and
 * the customer app far more often than about the portal, and the person
 * answering has the portal open, not a phone. Sending them to install the
 * driver app to look up what the boarding PIN is for is not an answer. The two
 * app guides use the same section shape, so the search, the language switch and
 * the print layout all work on them unchanged — and the mobile apps keep their
 * own shorter in-app help, which must agree with this and never differ.
 *
 * The daily checklist stays on the Admin tab only. It is an instruction about
 * the order to clear queues in, which means nothing to a driver.
 */

const TABS = [
  { key: 'admin', groups: guideGroups, en: 'Admin portal', ur: 'Admin portal' },
  { key: 'driver', groups: driverGuideGroups, en: 'Driver app', ur: 'Driver app' },
  { key: 'customer', groups: customerGuideGroups, en: 'Customer app', ur: 'Customer app' },
] as const;

type TabKey = (typeof TABS)[number]['key'];

const BLURB: Record<TabKey, { en: string; ur: string }> = {
  admin: {
    en: 'What every screen is for, how to use it, and what not to get wrong.',
    ur: 'Har screen kis kaam ki hai, kaise chalani hai, aur kya ghalat nahi karna.',
  },
  driver: {
    en: 'The driver app, screen by screen — for answering a driver on the phone.',
    ur: 'Driver app, screen ba screen — phone par driver ko jawab dene ke liye.',
  },
  customer: {
    en: 'The customer app, screen by screen — for answering a customer on the phone.',
    ur: 'Customer app, screen ba screen — phone par customer ko jawab dene ke liye.',
  },
};
export default function HelpPage() {
  const [query, setQuery] = useState('');
  const [tab, setTab] = useState<TabKey>('admin');
  const [language, setLanguage] = useGuideLanguage();
  const urdu = language === 'ur';

  const groups = useMemo(
    () => TABS.find((entry) => entry.key === tab)!.groups,
    [tab],
  );

  const results = useMemo(() => {
    const needle = query.trim().toLowerCase();
    if (!needle) return groups;

    return groups
      .map((group) => ({
        ...group,
        sections: group.sections.filter((section) =>
          haystack(section).includes(needle),
        ),
      }))
      .filter((group) => group.sections.length > 0);
  }, [query, groups]);

  const sectionCount = groups.reduce(
    (total, group) => total + group.sections.length,
    0,
  );

  return (
    <AdminFrame
      title="Guides"
      subtitle={urdu ? BLURB[tab].ur : BLURB[tab].en}
      actions={<LanguageSwitch value={language} onChange={setLanguage} />}
    >
      {/* The tab row, before everything else. Which guide you are reading has
          to be the first thing on the page and the first thing you can change —
          somebody who opens this while a driver waits on the phone should not
          have to scroll to find the driver guide. */}
      <section className="panel">
        <div className="buttonRow" style={{ padding: 16 }}>
          {TABS.map((entry) => (
            <button
              key={entry.key}
              className={entry.key === tab ? 'primaryButton' : 'secondaryButton'}
              onClick={() => {
                setTab(entry.key);
                setQuery('');
              }}
            >
              {urdu ? entry.ur : entry.en}
            </button>
          ))}
        </div>
      </section>

      <section className="helpHero">
        <div>
          {/* The tab's own name, not its blurb. The blurb is already the page
              subtitle, and set in capitals it ran to two lines of shouting. */}
          <span>
            {(urdu
              ? TABS.find((entry) => entry.key === tab)!.ur
              : TABS.find((entry) => entry.key === tab)!.en
            ).toUpperCase()}
          </span>
          <h2>
            {tab === 'admin'
              ? urdu
                ? 'UDrive sahi tareeqe se chalayein'
                : 'Run UDrive safely and correctly'
              : tab === 'driver'
                ? urdu
                  ? 'Driver ke sawal ka jawab'
                  : 'Answering a driver'
                : urdu
                  ? 'Customer ke sawal ka jawab'
                  : 'Answering a customer'}
          </h2>
          <p>
            {tab === 'admin'
              ? urdu
                ? `Is portal ki har screen ke liye ${sectionCount} hisse. Yehi guide har page par upar dayein “Guide” button ke peeche bhi mojood hai, taake apna kaam chhore baghair dekh sakein. Portal angrezi mein hai; guide Roman Urdu mein — upar se English par badal sakte hain.`
                : `${sectionCount} sections covering every screen in this portal. The same guide sits behind the Guide button in the top right of any page, so you never have to leave what you are doing to look something up.`
              : urdu
                ? `App ki har screen ke liye ${sectionCount} hisse, usi tarteeb mein jis mein app mein hain. Har hisse ke neeche likha hai ke woh screen app mein kahan hai, taake phone par baat karte huay bata sakein.`
                : `${sectionCount} sections covering the app, in the order the app presents them. Each one says where that screen lives, so you can say it down the phone.`}
          </p>
        </div>
        <BadgeCheck size={50} />
      </section>

      {/* The day, before the reference material. Someone who has just been
          given this portal needs an order to work in more than they need a
          description of screen twenty-nine. */}
      {tab === 'admin' && (
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
      )}

      <section className="panel helpSearchPanel">
        <div className="guideSearch" style={{ margin: '16px 18px' }}>
          <Search size={15} />
          <input
            value={query}
            placeholder={
              urdu
                ? 'Is guide mein dhoondein — refund, deposit, verification, OTP…'
                : 'Search this guide — refund, deposit, verification, OTP…'
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
        <section className="panel" key={`${tab}-${group.label}`}>
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
                key={`${tab}-${group.label}-${section.title}`}
                open
              >
                <summary>
                  <strong>{section.title}</strong>
                  <small>{say(section.purpose, language)}</small>
                </summary>

                <ol>
                  {section.steps.map((step, index) => (
                    <li key={`${section.title}-step-${index}`}>
                      {say(step, language)}
                    </li>
                  ))}
                </ol>

                {section.cautions && section.cautions.length > 0 && (
                  <ul className="guideCautions">
                    {section.cautions.map((caution, index) => (
                      <li key={`${section.title}-caution-${index}`}>
                        {say(caution, language)}
                      </li>
                    ))}
                  </ul>
                )}

                <div className="guideEntryFoot">
                  {section.roles && (
                    <span className="guideRoles">{say(section.roles, language)}</span>
                  )}
                  {/* The app guides have no portal route to open, so they name
                      where the screen is instead of offering a dead link. */}
                  {section.path ? (
                    <Link href={section.path}>
                      {urdu ? 'Screen kholein' : 'Go to screen'}
                      <ChevronRight size={13} />
                    </Link>
                  ) : (
                    section.where && (
                      <span className="guideRoles">{section.where}</span>
                    )
                  )}
                </div>
              </details>
            ))}
          </div>
        </section>
      ))}
    </AdminFrame>
  );
}
