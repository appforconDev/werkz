import { defineConfig } from 'astro/config';
import tailwindcss from '@tailwindcss/vite';

// werkz.app — static-first (CLAUDE.md stack rule). Checkout via Stripe
// hosted checkout (P3).
export default defineConfig({
  vite: {
    plugins: [tailwindcss()],
  },
});
