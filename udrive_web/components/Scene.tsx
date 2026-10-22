/**
 * A calm flat landscape used wherever a tour or hotel has no photo yet.
 * Deterministic per name, so the same place always gets the same picture.
 */
const PALETTES = [
  { sky: '#DCE8EE', sun: '#F4E3B5', far: '#9FB6C3', mid: '#5E8571', near: '#3F6B50', tree: '#2C4F3A', water: '#7FB0C4' },
  { sky: '#EFE6D6', sun: '#F2C98A', far: '#C2B39B', mid: '#8E9A6C', near: '#5F7746', tree: '#3E5530', water: '#9CB8B3' },
  { sky: '#E3ECE6', sun: '#F6E7C1', far: '#A9BFB4', mid: '#6E9479', near: '#47705A', tree: '#2F5240', water: '#6FA2A8' },
  { sky: '#E7EAF0', sun: '#F3DDB0', far: '#B4BCCB', mid: '#7F8FA3', near: '#5E7A62', tree: '#3B5444', water: '#8AAFC2' },
];

function hash(s: string) {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0;
  return h;
}

export function Scene({ seed, label }: { seed: string; label?: string }) {
  const h = hash(seed || 'udrive');
  const p = PALETTES[h % PALETTES.length];
  const lake = h % 3 === 0;
  const w = 600;
  const H = 360;
  const trees = Array.from({ length: 9 }, (_, i) => {
    const x = (i * 97 + (h % 50)) % w;
    const s = 0.7 + ((i * 37 + h) % 5) / 10;
    const y = H * (lake ? 0.76 : 0.86);
    return <path key={i} d={`M${x} ${y - 46 * s} L${x + 13 * s} ${y} H${x - 13 * s}Z`} fill={p.tree} />;
  });
  return (
    <svg viewBox={`0 0 ${w} ${H}`} preserveAspectRatio="xMidYMid slice" role="img" aria-label={label ?? 'Mountains of Azad Kashmir'}>
      <rect width={w} height={H} fill={p.sky} />
      {h % 2 === 0 && <circle cx={w * 0.78} cy={H * 0.22} r={H * 0.07} fill={p.sun} />}
      <path d={`M0 ${H * 0.55} L${w * 0.14} ${H * 0.3} L${w * 0.24} ${H * 0.4} L${w * 0.4} ${H * 0.16} L${w * 0.55} ${H * 0.38} L${w * 0.68} ${H * 0.24} L${w * 0.86} ${H * 0.42} L${w} ${H * 0.3} V${H} H0Z`} fill={p.far} />
      <path d={`M${w * 0.4} ${H * 0.16} L${w * 0.45} ${H * 0.23} L${w * 0.42} ${H * 0.25} L${w * 0.37} ${H * 0.21}Z M${w * 0.68} ${H * 0.24} L${w * 0.72} ${H * 0.29} L${w * 0.66} ${H * 0.27}Z`} fill="#fff" opacity=".85" />
      <path d={`M0 ${H * 0.66} L${w * 0.18} ${H * 0.46} L${w * 0.33} ${H * 0.6} L${w * 0.5} ${H * 0.44} L${w * 0.7} ${H * 0.62} L${w * 0.84} ${H * 0.5} L${w} ${H * 0.6} V${H} H0Z`} fill={p.mid} />
      <path d={`M0 ${H * 0.8} Q${w * 0.25} ${H * 0.68} ${w * 0.5} ${H * 0.76} T${w} ${H * 0.72} V${H} H0Z`} fill={p.near} />
      {lake && <path d={`M0 ${H * 0.78} Q${w * 0.3} ${H * 0.74} ${w * 0.55} ${H * 0.79} T${w} ${H * 0.77} V${H} H0Z`} fill={p.water} />}
      {trees}
    </svg>
  );
}

/** A real photo when there is one, otherwise the landscape. */
export function Picture({ src, alt, seed, eager }: { src: string | null; alt: string; seed: string; eager?: boolean }) {
  return src ? (
    // eslint-disable-next-line @next/next/no-img-element
    <img src={src} alt={alt} loading={eager ? 'eager' : 'lazy'} decoding="async" />
  ) : (
    <Scene seed={seed} label={alt} />
  );
}
