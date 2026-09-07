import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'Launch Control — Ziggo Admin',
  robots: { index: false, follow: false },
};

export default function LaunchControlLayout({ children }: { children: React.ReactNode }) {
  return <>{children}</>;
}
