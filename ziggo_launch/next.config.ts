import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  images: {
    formats: ['image/avif', 'image/webp'],
  },
  // Hide the "N" dev indicator badge in the bottom-left corner
  devIndicators: false,
  async rewrites() {
    return [
      {
        source: '/launch',
        destination: '/',
      },
      {
        source: '/Launch',
        destination: '/',
      },
      {
        source: '/LAUNCH',
        destination: '/',
      },
    ];
  },
};

export default nextConfig;
