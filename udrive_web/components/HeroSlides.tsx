'use client';

import { useEffect, useRef, useState } from 'react';

import { Scene } from './Scene';

export type Slide = { src: string | null; name: string; district: string };

/**
 * Hero pictures that cross-fade every 5 seconds.
 * - Pauses while the pointer is over it, or the tab is hidden.
 * - No movement at all for people who ask for reduced motion.
 * - Only the current and next photo are downloaded; the rest load in turn.
 */
export function HeroSlides({ slides }: { slides: Slide[] }) {
  const list = slides.length ? slides : [{ src: null, name: 'Azad Kashmir', district: '' }];
  const [i, setI] = useState(0);
  const [seen, setSeen] = useState(() => new Set([0, 1]));
  const paused = useRef(false);

  useEffect(() => {
    if (list.length < 2) return;
    if (window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) return;
    const t = window.setInterval(() => {
      if (paused.current || document.hidden) return;
      setI((x) => {
        const n = (x + 1) % list.length;
        setSeen((s) => new Set([...s, n, (n + 1) % list.length]));
        return n;
      });
    }, 5000);
    return () => window.clearInterval(t);
  }, [list.length]);

  return (
    <div className="slides" onMouseEnter={() => (paused.current = true)} onMouseLeave={() => (paused.current = false)}
      aria-roledescription="carousel" aria-label="Places in Azad Kashmir">
      {list.map((s, k) => (
        <figure key={`${s.name}${k}`} className={k === i ? 'on' : ''} aria-hidden={k !== i}>
          {s.src && seen.has(k)
            // eslint-disable-next-line @next/next/no-img-element
            ? <img src={s.src} alt={`${s.name}${s.district ? `, ${s.district}` : ''} — Azad Kashmir`} loading={k === 0 ? 'eager' : 'lazy'} decoding="async" fetchPriority={k === 0 ? 'high' : 'low'} referrerPolicy="no-referrer" />
            : <Scene seed={s.name} label={s.name} />}
          <figcaption>{s.name}{s.district ? ` · ${s.district}` : ''}</figcaption>
        </figure>
      ))}
      {list.length > 1 && (
        <div className="dots" role="tablist" aria-label="Choose picture">
          {list.map((s, k) => (
            <button key={k} role="tab" aria-selected={k === i} aria-label={s.name} className={k === i ? 'on' : ''}
              onClick={() => { setI(k); setSeen((x) => new Set([...x, k, (k + 1) % list.length])); }} />
          ))}
        </div>
      )}
    </div>
  );
}
