'use client';

import { useEffect, useState } from 'react';

import { api, img } from '@/lib/api';
import { API_URL } from '@/lib/config';
import type { Ad } from '@/lib/types';
import { Scene } from './Scene';

/** An admin-filled ad place. Shows nothing when the slot is empty. */
export function AdSlot({ slot, variant = 'wide', initial }: { slot: string; variant?: 'wide' | 'side'; initial?: Ad[] }) {
  const [ads, setAds] = useState<Ad[]>(initial ?? []);
  useEffect(() => {
    api<Ad[]>(`/api/v1/web/ads/${slot}`).then(setAds).catch(() => undefined);
  }, [slot]);

  const ad = ads[0];
  if (!ad) return null;
  const picture = img(ad.imageUrl);
  const click = () => {
    if (API_URL) navigator.sendBeacon?.(`${API_URL}/api/v1/web/ads/${ad.id}/click`);
  };
  const Link = ({ children, className }: { children: React.ReactNode; className: string }) =>
    ad.linkUrl ? (
      <a className={className} href={ad.linkUrl} target="_blank" rel="sponsored noopener noreferrer" onClick={click}>{children}</a>
    ) : (
      <span className={className}>{children}</span>
    );

  if (variant === 'side') {
    return (
      <Link className="sideAd">
        <div className="img">{picture ? <img src={picture} alt="" loading="lazy" /> : <Scene seed={ad.title} label="" />}</div>
        <div><b>{ad.title}</b><p>{ad.body}</p></div>
        <span className="lbl">Ad</span>
      </Link>
    );
  }

  return (
    <aside className="ad" aria-label="Advertisement">
      <div className="img">{picture ? <img src={picture} alt="" loading="lazy" /> : <Scene seed={ad.title} label="" />}</div>
      <div><h3>{ad.title}</h3><p>{ad.body}</p></div>
      {ad.linkUrl ? (
        <a className="btn ghost" href={ad.linkUrl} target="_blank" rel="sponsored noopener noreferrer" onClick={click}>{ad.ctaLabel}</a>
      ) : <span />}
      <span className="lbl">Ad</span>
    </aside>
  );
}
