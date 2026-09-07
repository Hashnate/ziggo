import type { Metadata, Viewport } from 'next';
import { Outfit, DM_Sans } from 'next/font/google';
import SmoothScrollProvider from '@/components/SmoothScrollProvider';
import FilmGrain from '@/components/FilmGrain';
import CustomCursor from '@/components/CustomCursor';
import './globals.css';


const outfit = Outfit({
  subsets: ['latin'],
  weight: ['300', '400', '500', '600', '700', '800', '900'],
  variable: '--font-outfit',
  display: 'swap',
});

const dmSans = DM_Sans({
  subsets: ['latin'],
  weight: ['300', '400', '500', '600', '700'],
  variable: '--font-dm-sans',
  display: 'swap',
});

export const metadata: Metadata = {
  title: 'Ziggo Grand Launch — The VIP Reveal | Sri Lanka\'s Super App',
  description:
    'Join the exclusive nationwide grand launch of Ziggo. Sri Lanka\'s award-tier super-app for rides, food delivery, grocery, logistics, rental, and VIP events.',
  icons: {
    icon: '/logo-light.png',
  },
  openGraph: {
    title: 'Ziggo Grand Launch — Official VIP Ceremony',
    description: 'The super-app you\'ve been waiting for is here. Sri Lanka\'s all-in-one platform launches nationwide.',
    url: 'https://ziggo.app',
    siteName: 'Ziggo Launch',
    images: [
      {
        url: '/logo-light.png',
        width: 1200,
        height: 630,
        alt: 'Ziggo Grand Launch Ceremony',
      },
    ],
    locale: 'en_LK',
    type: 'website',
  },
};

export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
  maximumScale: 5,
  themeColor: '#030712',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html
      lang="en"
      className={`${outfit.variable} ${dmSans.variable} bg-[#030712] text-white min-h-screen selection:bg-blue-500 selection:text-white`}
      style={{ backgroundColor: '#030712' }}
    >
      <body className="bg-[#030712] text-white antialiased min-h-screen w-full m-0 p-0 overflow-x-hidden relative">
        <SmoothScrollProvider>
          {children}
        </SmoothScrollProvider>
        {/* Luxury Custom Magnetic Cursor */}
        <CustomCursor />
        {/* Subtle cinematic 35mm film grain overlay */}
        <FilmGrain />
      </body>

    </html>
  );
}

