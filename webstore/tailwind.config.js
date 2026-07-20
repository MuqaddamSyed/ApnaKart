/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        brand: '#FF4500',
        'brand-dark': '#E03E00',
        'brand-tint': '#FFF0EA',
        ink: '#1C1C1E',
        'ink-soft': '#5D5F5F',
        muted: '#8E8E93',
        surface: '#F8F8F8',
        card: '#FFFFFF',
        'surface-2': '#F0EDEF',
        success: '#0B8A45',
        'success-tint': '#E7F8EE',
        glass: 'rgba(255,255,255,0.72)',
        'border-subtle': 'rgba(0,0,0,0.06)',
        danger: '#BA1A1A',
      },
      fontFamily: {
        sans: ['"Hanken Grotesk"', 'system-ui', '-apple-system', 'sans-serif'],
      },
      borderRadius: {
        xl2: '1rem',
        xl3: '1.5rem',
      },
      boxShadow: {
        ios: '0px 4px 20px rgba(0,0,0,0.05)',
        'ios-lg': '0px 8px 30px rgba(0,0,0,0.08)',
      },
      maxWidth: { app: '1080px' },
    },
  },
  plugins: [],
};
