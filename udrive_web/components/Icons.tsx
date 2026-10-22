const P = { width: 26, height: 26, viewBox: '0 0 24 24', 'aria-hidden': true } as const;
export const TourIcon = () => (<svg {...P}><path d="M3 19l6-10 4 6 3-4 5 8z" /><circle cx="17" cy="6" r="1.8" /></svg>);
export const HotelIcon = () => (<svg {...P}><path d="M3 19V6M3 14h18v5M21 19v-3a3 3 0 0 0-3-3h-7v1" /><circle cx="7" cy="10.5" r="1.7" /></svg>);
export const CarIcon = () => (<svg {...P}><path d="M3 16v-3l2-1 2.5-4h9L19 12l2 1v3" /><circle cx="7.5" cy="16.5" r="1.8" /><circle cx="16.5" cy="16.5" r="1.8" /></svg>);
export const KeyIcon = () => (<svg {...P}><circle cx="8" cy="12" r="4" /><path d="M12 12h9M18 12v3M21 12v2" /></svg>);
export const PlayIcon = () => (
  <svg width="22" height="24" viewBox="0 0 22 24" aria-hidden="true"><path d="M1 1l12 11L1 23z" fill="#0B1B33" /><path d="M13 12l4-4 4 2.3c1.2.7 1.2 2.7 0 3.4L17 16z" fill="#7DA700" /></svg>
);
