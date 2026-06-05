import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  base: '/admin-react/',
  plugins: [react()],
  build: { outDir: 'dist', emptyOutDir: true },
})
