export function BrandMark({ size = 44, className = '' }: { size?: number; className?: string }) {
  return (
    <img
      src="/branding/udrive-icon-v3.png?v=20260730b"
      alt="Udrive"
      width={size}
      height={size}
      className={className}
      style={{ width: size, height: size, objectFit: 'contain', display: 'block' }}
    />
  );
}

export function BrandWordmark({
  height = 44,
  className = '',
}: {
  height?: number;
  className?: string;
}) {
  return (
    <img
      src="/branding/udrive-wordmark-v3.png?v=20260730b"
      alt="Udrive — Your Ride, Our Priority"
      className={className}
      width={Math.round(height * 2.85)}
      height={height}
      style={{ height, width: 'auto', maxWidth: '100%', objectFit: 'contain', display: 'block' }}
    />
  );
}
