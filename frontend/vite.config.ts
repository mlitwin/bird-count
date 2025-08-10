import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'node:path'

export default defineConfig({
  base: '/bird-count/',
  plugins: [react()],
  resolve: {
    alias: {
      model: path.resolve(__dirname, 'src/model'),
      store: path.resolve(__dirname, 'src/store'),
      common: path.resolve(__dirname, 'src/common'),
      data: path.resolve(__dirname, 'src/data'),
    }
  }
})
