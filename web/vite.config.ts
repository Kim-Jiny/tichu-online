import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Served from https://tichu.jiny.shop/play/ in production so the WebSocket is
// same-origin (no CORS work, and the profile-photo upload endpoint stays
// reachable). Dev runs at http://localhost:5173/play/ against a local server.
export default defineConfig({
  base: '/play/',
  plugins: [react()],
  server: {
    port: 5173,
    strictPort: false,
  },
  build: {
    outDir: 'dist',
    sourcemap: true,
  },
});
