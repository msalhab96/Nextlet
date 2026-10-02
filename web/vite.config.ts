import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    // In development the API runs separately (npm run dev in ../server).
    proxy: { '/api': 'http://localhost:3000' },
  },
  build: {
    target: 'es2022',
  },
});
