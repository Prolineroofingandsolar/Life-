/** @type {import('tailwindcss').Config} */
export default {
  darkMode: 'class',
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {
      colors: {
        bg: 'rgb(var(--bg) / <alpha-value>)',
        grouped: 'rgb(var(--bg-grouped) / <alpha-value>)',
        surface: 'rgb(var(--surface) / <alpha-value>)',
        surface2: 'rgb(var(--surface-2) / <alpha-value>)',
        label: 'rgb(var(--label) / <alpha-value>)',
        label2: 'rgb(var(--label-2) / <alpha-value>)',
        label3: 'rgb(var(--label-3) / <alpha-value>)',
        separator: 'rgb(var(--separator) / <alpha-value>)',
        fill: 'rgb(var(--fill) / <alpha-value>)',
        accent: 'rgb(var(--accent) / <alpha-value>)',
        accentPress: 'rgb(var(--accent-press) / <alpha-value>)',
        gradientEnd: 'rgb(var(--gradient-end) / <alpha-value>)',
        hydrate: '#32ade6',
        nourish: '#ff9f0a',
        move: '#30d158',
        danger: '#ff453a',
      },
      fontFamily: {
        sans: ['-apple-system', 'BlinkMacSystemFont', 'SF Pro Text', 'Segoe UI', 'Roboto', 'sans-serif'],
      },
      fontSize: {
        largetitle: ['34px', { lineHeight: '41px', letterSpacing: '-0.4px', fontWeight: '700' }],
        title1:    ['28px', { lineHeight: '34px', letterSpacing: '-0.3px', fontWeight: '700' }],
        title2:    ['22px', { lineHeight: '28px', letterSpacing: '-0.3px', fontWeight: '700' }],
        title3:    ['20px', { lineHeight: '25px', letterSpacing: '-0.2px', fontWeight: '600' }],
        headline:  ['17px', { lineHeight: '22px', letterSpacing: '-0.2px', fontWeight: '600' }],
        body:      ['17px', { lineHeight: '22px', letterSpacing: '-0.2px' }],
        callout:   ['16px', { lineHeight: '21px', letterSpacing: '-0.2px' }],
        subhead:   ['15px', { lineHeight: '20px', letterSpacing: '-0.1px' }],
        footnote:  ['13px', { lineHeight: '18px' }],
        caption:   ['12px', { lineHeight: '16px' }],
      },
      borderRadius: {
        ios:   '10px',
        card:  '14px',
        xl2:   '20px',
        sheet: '24px',
      },
      boxShadow: {
        card:      'var(--shadow-card)',
        sheet:     '0 -2px 24px rgb(0 0 0 / 0.18)',
        glow:      '0 0 28px rgb(var(--accent) / 0.38)',
        'glow-sm': '0 0 16px rgb(var(--accent) / 0.25)',
        'glow-lg': '0 0 48px rgb(var(--accent) / 0.45)',
      },
      maxWidth: {
        app: '30rem',
      },
      animation: {
        'glow-breathe': 'glow-breathe 2.4s ease-in-out infinite',
      },
      keyframes: {
        'glow-breathe': {
          '0%, 100%': { boxShadow: '0 0 18px rgb(var(--accent) / 0.30)' },
          '50%':       { boxShadow: '0 0 38px rgb(var(--accent) / 0.60)' },
        },
      },
    },
  },
  plugins: [],
}
