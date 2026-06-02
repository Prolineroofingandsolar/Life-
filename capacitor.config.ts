import type { CapacitorConfig } from '@capacitor/cli'

const config: CapacitorConfig = {
  appId: 'uk.co.prolineroofingandsolar.life',
  appName: 'Life',
  webDir: 'dist',
  ios: {
    // 'always' means the web content is always inset by safe-area amounts.
    // Combined with viewport-fit=cover in index.html this gives us full-bleed
    // layout while env(safe-area-inset-*) CSS variables still work correctly.
    contentInset: 'always',
    // Disable native WKWebView bounce scrolling. The app manages all scrolling
    // in a React-controlled <main> element; double-bounce looks broken and
    // fights our overscroll-behavior: none setting.
    scrollEnabled: false,
  },
}

export default config
