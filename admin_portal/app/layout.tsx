import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = { title: 'Udrive Operations', description: 'Tourism operations, safety and marketplace administration.' };
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) { return <html lang="en"><body>{children}</body></html>; }
