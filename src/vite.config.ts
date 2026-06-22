import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  root: '.',
  envDir: '..',
  server: {
    port: 5173,
    open: false,
  },
  build: {
    outDir: '../dist/berean',
    emptyOutDir: true,
  },
});
