import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Capacitor build — no Cloudflare Workers plugin, no PWA service worker.
// Service workers inside Capacitor's WKWebView can intercept Capacitor's own
// bridge requests and prevent the app from loading on first install. The PWA
// plugin is used only for the web/Cloudflare build (vite.config.ts).
export default defineConfig({
  plugins: [react()],
})
