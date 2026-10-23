/**
 * Atmospheric layered landscape (mist, glow, aerial perspective) used when a
 * place has no photo yet. Built only from numbers — no outside text goes into
 * the SVG — and deterministic per seed, so server and browser draw the same.
 */
type Pal = { sky: string[]; sun: string; ridges: string[]; mist: string; water: [string, string]; tree: string };
const PAL: Record<string, Pal> = {
  day: { sky: ['#5FA8D3', '#9FD0E8', '#DCEFF5', '#F4FAFB'], sun: '#FFFDF2', ridges: ['#B8D3DE', '#86AFBF', '#5E8C86', '#3F6E5A', '#24493A'], mist: '#EAF4F6', water: ['#8CC3D4', '#2E6A73'], tree: '#173828' },
  dawn: { sky: ['#2B3A67', '#8E6C9E', '#F2A97E', '#FCE3B8'], sun: '#FFE7B0', ridges: ['#C9A7B9', '#9E7E9C', '#6E5A80', '#463D62', '#25233F'], mist: '#F7D6C4', water: ['#E7B9A4', '#5E5079'], tree: '#1B1A30' },
  dusk: { sky: ['#1A2240', '#5A3A62', '#D9684A', '#F7B46A'], sun: '#FFD38A', ridges: ['#B9806E', '#8A5A60', '#5C3E55', '#38283F', '#1C1628'], mist: '#F3B48A', water: ['#E58E62', '#3B2A44'], tree: '#120E1C' },
  alpine: { sky: ['#24466F', '#4F85B4', '#A9CFE6', '#EAF4FA'], sun: '#FFFFFF', ridges: ['#E6EEF4', '#B5C9D8', '#7F9DB2', '#4D6E7E', '#2A4A45'], mist: '#F2F7FA', water: ['#7DB4CF', '#244C5C'], tree: '#14302A' },
  night: { sky: ['#060A1C', '#121C3E', '#2A3768', '#4A5B8E'], sun: '#F3F0DC', ridges: ['#5A6A97', '#435280', '#2F3B63', '#1E2747', '#0E1428'], mist: '#7C8BB8', water: ['#3B4B7C', '#0A1024'], tree: '#060914' },
};
const NAMES = Object.keys(PAL);
/** Palettes in a pleasing order, for rows of pictures side by side. */
export const PALETTES = ['alpine', 'day', 'dusk', 'dawn', 'night', 'day'];

function hash(s: string) { let h = 2166136261; for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619) >>> 0; return h; }
function rnd(seed: number) { let s = seed >>> 0 || 1; return () => ((s = (Math.imul(s, 1664525) + 1013904223) >>> 0) / 4294967296); }
const f = (n: number) => Math.round(n * 10) / 10;

export function artSvg(seedText: string, w = 1600, h = 900, opts: { palette?: string; lake?: boolean; trees?: number } = {}) {
  const seed = hash(seedText || 'udrive');
  const r = rnd(seed);
  const pal = opts.palette && PAL[opts.palette] ? opts.palette : NAMES[seed % NAMES.length];
  const p = PAL[pal];
  const lake = opts.lake ?? seed % 3 === 0;
  const sunX = 0.55 + r() * 0.3, sunY = 0.26 + r() * 0.12;
  const id = `a${seed.toString(36)}`;
  const horizon = h * (lake ? 0.66 : 0.74);
  let defs = `<linearGradient id="${id}s" x1="0" y1="0" x2="0" y2="1">${p.sky.map((c, i) => `<stop offset="${i / (p.sky.length - 1)}" stop-color="${c}"/>`).join('')}</linearGradient>`
    + `<radialGradient id="${id}g" cx="${f(sunX)}" cy="${f(sunY)}" r="0.55"><stop offset="0" stop-color="${p.sun}" stop-opacity=".95"/><stop offset=".12" stop-color="${p.sun}" stop-opacity=".55"/><stop offset=".5" stop-color="${p.sun}" stop-opacity=".08"/><stop offset="1" stop-color="${p.sun}" stop-opacity="0"/></radialGradient>`
    + `<linearGradient id="${id}m" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${p.mist}" stop-opacity="0"/><stop offset=".5" stop-color="${p.mist}" stop-opacity=".9"/><stop offset="1" stop-color="${p.mist}" stop-opacity="0"/></linearGradient>`
    + `<linearGradient id="${id}w" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${p.water[0]}"/><stop offset="1" stop-color="${p.water[1]}"/></linearGradient>`;
  p.ridges.forEach((c, i) => { defs += `<linearGradient id="${id}r${i}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${c}"/><stop offset="1" stop-color="${p.ridges[Math.min(i + 1, 4)]}"/></linearGradient>`; });
  let body = `<rect width="${w}" height="${h}" fill="url(#${id}s)"/><rect width="${w}" height="${h}" fill="url(#${id}g)"/>`;
  if (pal === 'night') for (let k = 0; k < 90; k++) body += `<circle cx="${f(r() * w)}" cy="${f(r() * h * 0.5)}" r="${f(r() * 1.4 + 0.3)}" fill="#fff" opacity="${f(r() * 0.8 + 0.2)}"/>`;
  body += `<circle cx="${f(sunX * w)}" cy="${f(sunY * h)}" r="${f(h * 0.05)}" fill="${p.sun}" opacity=".95"/>`;
  for (let i = 0; i < 4; i++) {
    const base = h * (0.40 + i * 0.085), amp = h * (0.30 - i * 0.05) * (i >= 2 ? 0.5 : 1), seg = 6 + i * 3;
    const pts: [number, number][] = [];
    for (let k = 0; k <= seg; k++) {
      const x = Math.max(0, Math.min(w, ((k + (r() - 0.5) * 0.5) / seg) * w));
      const y = k % 2 === 1 ? base - amp * (0.55 + r() * 0.6) : base - amp * (0.05 + r() * 0.25);
      pts.push([x, Math.min(y, horizon)]);
    }
    let d = `M0 ${h} L0 ${f(pts[0][1])}`;
    for (let k = 1; k < pts.length; k++) {
      const [x0, y0] = pts[k - 1], [x1, y1] = pts[k];
      if (i < 2) for (let j = 1; j <= 4; j++) { const t = j / 4; const jit = j < 4 ? (r() - 0.5) * amp * 0.12 : 0; d += ` L${f(x0 + (x1 - x0) * t)} ${f(y0 + (y1 - y0) * t + jit)}`; }
      else d += ` C${f(x0 + (x1 - x0) * 0.4)} ${f(y0)} ${f(x0 + (x1 - x0) * 0.6)} ${f(y1)} ${f(x1)} ${f(y1)}`;
    }
    d += ` L${w} ${h}Z`;
    body += `<path d="${d}" fill="url(#${id}r${i})"/>`;
    if (i < 2 && pal !== 'dusk') pts.forEach(([x, y], k) => {
      if (k % 2 === 1 && y < base - amp * 0.75) { const s = amp * 0.16; body += `<path d="M${f(x)} ${f(y)} L${f(x + s)} ${f(y + s * 1.1)} L${f(x + s * 0.45)} ${f(y + s * 0.85)} L${f(x + s * 0.1)} ${f(y + s * 1.25)} L${f(x - s * 0.35)} ${f(y + s * 0.9)} L${f(x - s)} ${f(y + s * 1.1)}Z" fill="#fff" opacity="${i ? 0.6 : 0.85}"/>`; }
    });
    body += `<rect x="0" y="${f(base - amp * 0.15)}" width="${w}" height="${f(h * 0.14)}" fill="url(#${id}m)" opacity="${f(0.6 - i * 0.1)}"/>`;
  }
  if (lake) {
    body += `<rect x="0" y="${f(horizon)}" width="${w}" height="${f(h - horizon)}" fill="url(#${id}w)"/>`;
    for (let k = 0; k < 12; k++) body += `<rect x="${f(r() * w)}" y="${f(horizon + (h - horizon) * r())}" width="${f(40 + r() * 160)}" height="1.5" fill="#fff" opacity="${f(0.15 + r() * 0.3)}"/>`;
  }
  const fy = lake ? horizon + 4 : h * 0.86;
  let trees = '';
  for (let k = 0; k < (opts.trees ?? 46); k++) {
    const x = r() * w, s = 0.6 + r() * 1.3, th = h * 0.09 * s, tw = th * 0.32, y = fy + r() * h * 0.03;
    trees += `<path d="M${f(x)} ${f(y - th)} L${f(x + tw * 0.55)} ${f(y - th * 0.55)} L${f(x + tw * 0.3)} ${f(y - th * 0.55)} L${f(x + tw)} ${f(y)} L${f(x - tw)} ${f(y)} L${f(x - tw * 0.3)} ${f(y - th * 0.55)} L${f(x - tw * 0.55)} ${f(y - th * 0.55)}Z" fill="${p.tree}"/>`;
  }
  if (!lake) body += `<path d="M0 ${f(fy)} Q${f(w * 0.3)} ${f(fy - h * 0.03)} ${f(w * 0.6)} ${f(fy + h * 0.01)} T${w} ${f(fy - h * 0.02)} V${h} H0Z" fill="${p.tree}"/>`;
  body += trees;
  if (lake) body += `<g transform="translate(0 ${f(2 * horizon + 8)}) scale(1 -1)" opacity=".22">${trees}</g>`;
  return `<svg viewBox="0 0 ${w} ${h}" preserveAspectRatio="xMidYMid slice" xmlns="http://www.w3.org/2000/svg" aria-hidden="true"><defs>${defs}</defs>${body}</svg>`;
}

/** The landscape as an element. `label` becomes the accessible name. */
export function Art({ seed, label, w, h, palette, lake, className }: { seed: string; label?: string; w?: number; h?: number; palette?: string; lake?: boolean; className?: string }) {
  return <div className={`art ${className ?? ''}`} role="img" aria-label={label ?? 'Mountains of Azad Kashmir'} dangerouslySetInnerHTML={{ __html: artSvg(seed, w, h, { palette, lake }) }} />;
}

/** A real photo when there is one, otherwise the landscape. */
export function Photo({ src, alt, seed, eager, w, h, palette, lake }: { src: string | null; alt: string; seed: string; eager?: boolean; w?: number; h?: number; palette?: string; lake?: boolean }) {
  // eslint-disable-next-line @next/next/no-img-element
  return src ? <img src={src} alt={alt} loading={eager ? 'eager' : 'lazy'} decoding="async" referrerPolicy="no-referrer" /> : <Art seed={seed} label={alt} w={w} h={h} palette={palette} lake={lake} />;
}
