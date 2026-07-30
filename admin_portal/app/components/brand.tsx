export function BrandMark({ size = 44, className = '' }: { size?: number; className?: string }) {
  return (
    <img
      src="/branding/udrive-icon.png"
      alt="Udrive"
      width={size}
      height={size}
      className={className}
      style={{ width: size, height: size, objectFit: 'contain' }}
    />
  );
}

export function BrandWordmark({
  height = 34,
  darkBackground = false,
  className = '',
}: {
  height?: number;
  darkBackground?: boolean;
  className?: string;
}) {
  return (
    <span
      className={className}
      style={
        darkBackground
          ? {
              display: 'inline-flex',
              alignItems: 'center',
              background: '#fff',
              borderRadius: 16,
              padding: '7px 10px',
            }
          : undefined
      }
    >
      <img
        src="/branding/udrive-wordmark.png"
        alt="Udrive"
        width={Math.round(height * 5.7)}
        height={height}
        style={{ height, width: 'auto', objectFit: 'contain', display: 'block' }}
      />
    </span>
  );
}
