'use client';

import { useEffect, useRef, useState } from 'react';

import { Art } from './Art';

export type Slide = {
  src: string | null; name: string; district: string; season?: string;
  /** Photo credit (Wikimedia Commons licence condition). */
  credit?: { author: string; license: string; pageUrl: string | null } | null;
  /** Weather there right now. */
  wx?: { temp: number; code: number } | null;
};

const kindOf = (code: number) => (code >= 95 || (code >= 51 && code <= 67) || (code >= 80 && code <= 82) ? 'rain' : (code >= 71 && code <= 77) || code === 85 || code === 86 ? 'snow' : '');

/** Falling snow or rain over the picture when that is the weather there now. CSS only, still for reduced motion. */
function Fall({ kind }: { kind: string }) {
  if (!kind) return null;
  const n = kind === 'snow' ? 70 : 90;
  return (
    <div className={`fall ${kind}`} aria-hidden="true">
      {Array.from({ length: n }, (_, k) => {
        const x = (k * 137.5) % 100, d = 4 + ((k * 7) % 6), delay = -((k * 13) % 90) / 10, size = kind === 'snow' ? 2 + (k % 4) : 1;
        return <i key={k} style={{ left: `${x}%`, width: size, height: kind === 'snow' ? size : 14 + (k % 6) * 2, animationDuration: `${kind === 'snow' ? d : d / 6}s`, animationDelay: `${delay}s`, opacity: 0.35 + (k % 5) * 0.12 }} />;
      })}
    </div>
  );
}

/**
 * Full-bleed hero pictures: slow zoom, cross-fade every 5 seconds.
 * - Pauses on hover and while the tab is hidden.
 * - Still for people who ask for reduced motion.
 * - Only the current and next photo are downloaded.
 * Renders the background layer and the caption card (with progress bars and
 * thumbnails) as two parts, so the page can place the card where it wants.
 */
export function useSlides(count: number) {
  const [i, setI] = useState(0);
  const [seen, setSeen] = useState(() => new Set([0, 1]));
  const paused = useRef(false);
  useEffect(() => {
    if (count < 2) return;
    if (window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) return;
    const t = window.setInterval(() => {
      if (paused.current || document.hidden) return;
      setI((x) => { const n = (x + 1) % count; setSeen((s) => new Set([...s, n, (n + 1) % count])); return n; });
    }, 5000);
    return () => window.clearInterval(t);
  }, [count]);
  const go = (k: number) => { setI(k); setSeen((s) => new Set([...s, k, (k + 1) % count])); };
  return { i, seen, go, paused };
}

export function HeroBackground({ slides, i, seen }: { slides: Slide[]; i: number; seen: Set<number> }) {
  return (
    <div className="h3bg" aria-roledescription="carousel" aria-label="Places in Azad Kashmir">
      {slides.map((s, k) => (
        <figure key={`${s.name}${k}`} className={k === i ? 'on' : ''} aria-hidden={k !== i}>
          {s.src && seen.has(k)
            // eslint-disable-next-line @next/next/no-img-element
            ? <img src={s.src} alt={`${s.name}${s.district ? `, ${s.district}` : ''} — Azad Kashmir`} loading={k === 0 ? 'eager' : 'lazy'} decoding="async" fetchPriority={k === 0 ? 'high' : 'low'} referrerPolicy="no-referrer" />
            : <Art seed={s.name} label={s.name} w={1600} h={900} palette={['dawn', 'alpine', 'day', 'dusk', 'night', 'day'][k % 6]} lake={k % 2 === 0} />}
        </figure>
      ))}
      <Fall kind={slides[i]?.wx ? kindOf(slides[i].wx!.code) : ''} />
      {slides[i]?.credit && (
        <div className="credit">
          Photo: {slides[i].credit!.pageUrl ? <a href={slides[i].credit!.pageUrl!} target="_blank" rel="noopener noreferrer nofollow">{slides[i].credit!.author}</a> : slides[i].credit!.author}
          {slides[i].credit!.license ? ` · ${slides[i].credit!.license}` : ''}{slides[i].credit!.pageUrl ? ' · Wikimedia Commons' : ''}
        </div>
      )}
    </div>
  );
}

export function HeroCaption({ slides, i, go }: { slides: Slide[]; i: number; go: (k: number) => void }) {
  const s = slides[i];
  if (!s) return null;
  return (
    <div className="slideCard" aria-live="polite">
      <div className="n">{String(i + 1).padStart(2, '0')} / {String(slides.length).padStart(2, '0')} · NOW SHOWING</div>
      <b>{s.name}</b>
      <span>{[s.district, !s.wx && s.season ? `best ${s.season}` : ''].filter(Boolean).join(' · ')}</span>
      {s.wx && <span className="wxchip">{kindOf(s.wx.code) === 'snow' ? '❄' : kindOf(s.wx.code) === 'rain' ? '☂' : '☀'} {Math.round(s.wx.temp)}° {kindOf(s.wx.code) === 'snow' ? 'snowing now' : kindOf(s.wx.code) === 'rain' ? 'raining now' : 'now'}</span>}
      {slides.length > 1 && (
        <>
          <div className="bars">{slides.map((_, k) => <i key={k} className={k < i ? 'done' : k === i ? 'on' : ''} />)}</div>
          <div className="thumbs3" role="tablist" aria-label="Choose picture">
            {slides.map((x, k) => (
              <button key={k} role="tab" aria-selected={k === i} aria-label={x.name} className={k === i ? 'on' : ''} onClick={() => go(k)}>
                {/* eslint-disable-next-line @next/next/no-img-element */}
                {x.src ? <img src={x.src} alt="" loading="lazy" referrerPolicy="no-referrer" /> : <Art seed={x.name} w={160} h={110} palette={['dawn', 'alpine', 'day', 'dusk', 'night', 'day'][k % 6]} lake={k % 2 === 0} />}
              </button>
            ))}
          </div>
        </>
      )}
    </div>
  );
}
