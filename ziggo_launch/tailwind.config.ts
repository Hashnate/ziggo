import type { Config } from 'tailwindcss';

const config: Config = {
  content: [
    './app/**/*.{js,ts,jsx,tsx,mdx}',
    './components/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      colors: {
        brand: {
          DEFAULT: '#1E3A8A',
          dark: '#131C3D',
          light: '#3B82F6',
          bright: '#60A5FA',
          glow: '#93C5FD',
        },
        gold: {
          DEFAULT: '#C9A961',
          light: '#E5C97E',
          deep: '#A88840',
        },
        navy: {
          DEFAULT: '#131C3D',
          deep: '#0A0F1F',
        },
      },
      fontFamily: {
        display: ['Outfit', 'system-ui', 'sans-serif'],
        body: ['DM Sans', 'Inter', 'system-ui', 'sans-serif'],
      },
      backgroundImage: {
        'grad-brand': 'linear-gradient(135deg, #1E3A8A 0%, #131C3D 100%)',
        'grad-bright': 'linear-gradient(135deg, #3B82F6 0%, #1E3A8A 100%)',
        'grad-gold': 'linear-gradient(135deg, #E5C97E 0%, #C9A961 50%, #A88840 100%)',
        'hero-mesh': `
          radial-gradient(ellipse at 20% 20%, rgba(59,130,246,0.45) 0%, transparent 55%),
          radial-gradient(ellipse at 80% 10%, rgba(96,165,250,0.30) 0%, transparent 50%),
          radial-gradient(ellipse at 50% 85%, rgba(30,58,138,0.55) 0%, transparent 60%),
          radial-gradient(ellipse at 90% 70%, rgba(201,169,97,0.15) 0%, transparent 40%)
        `,
      },
      keyframes: {
        'float': {
          '0%, 100%': { transform: 'translateY(0px)' },
          '50%': { transform: 'translateY(-20px)' },
        },
        'float-slow': {
          '0%, 100%': { transform: 'translateY(0px) translateX(0px)' },
          '33%': { transform: 'translateY(-15px) translateX(8px)' },
          '66%': { transform: 'translateY(-8px) translateX(-5px)' },
        },
        'pulse-glow': {
          '0%, 100%': { opacity: '0.4', transform: 'scale(1)' },
          '50%': { opacity: '0.7', transform: 'scale(1.08)' },
        },
        'digit-in': {
          '0%': { transform: 'translateY(-100%)', opacity: '0' },
          '100%': { transform: 'translateY(0)', opacity: '1' },
        },
        'shimmer': {
          '0%': { backgroundPosition: '-400px 0' },
          '100%': { backgroundPosition: '400px 0' },
        },
        'fade-up': {
          '0%': { opacity: '0', transform: 'translateY(24px)' },
          '100%': { opacity: '1', transform: 'translateY(0)' },
        },
        'scale-pop': {
          '0%': { transform: 'scale(0.9)', opacity: '0' },
          '60%': { transform: 'scale(1.04)' },
          '100%': { transform: 'scale(1)', opacity: '1' },
        },
      },
      animation: {
        'float': 'float 6s ease-in-out infinite',
        'float-slow': 'float-slow 9s ease-in-out infinite',
        'pulse-glow': 'pulse-glow 4s ease-in-out infinite',
        'digit-in': 'digit-in 0.3s cubic-bezier(0.34, 1.56, 0.64, 1)',
        'fade-up': 'fade-up 0.6s cubic-bezier(0.34, 1.56, 0.64, 1) both',
        'scale-pop': 'scale-pop 0.5s cubic-bezier(0.34, 1.56, 0.64, 1) both',
      },
      boxShadow: {
        'brand': '0 16px 40px -10px rgba(30, 58, 138, 0.5)',
        'brand-sm': '0 8px 24px -6px rgba(30, 58, 138, 0.35)',
        'gold': '0 8px 24px -6px rgba(201, 169, 97, 0.4)',
        'glass': '0 8px 32px rgba(0, 0, 0, 0.3), inset 0 1px 0 rgba(255,255,255,0.15)',
      },
    },
  },
  plugins: [],
};

export default config;
