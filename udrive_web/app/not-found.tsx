import Link from 'next/link';

export default function NotFound() {
  return (
    <div className="wrap" style={{ padding: '80px 0' }}>
      <h1 style={{ fontSize: 36 }}>Page not found</h1>
      <p className="muted">The page may have moved, or the tour has already left.</p>
      <Link className="btn dark" href="/">Go to home</Link>
    </div>
  );
}
