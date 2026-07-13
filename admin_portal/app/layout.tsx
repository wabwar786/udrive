import type { Metadata } from 'next';
import './globals.css';
export const metadata: Metadata = { title: 'UDrive Admin', description: 'UDrive tourism and ride operations portal' };
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) { return <html lang="en"><body>{children}</body></html>; }
