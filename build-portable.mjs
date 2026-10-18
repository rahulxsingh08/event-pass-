import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { build } from 'esbuild';

await mkdir('work', { recursive: true });
await build({
  entryPoints: ['src/main.jsx'],
  bundle: true,
  minify: true,
  format: 'iife',
  target: ['es2020'],
  jsx: 'automatic',
  outfile: 'work/campuspass.js',
  define: {
    'import.meta.env.VITE_SUPABASE_URL': 'undefined',
    'import.meta.env.VITE_SUPABASE_ANON_KEY': 'undefined',
  },
});

const [js, css] = await Promise.all([
  readFile('work/campuspass.js', 'utf8'),
  readFile('work/campuspass.css', 'utf8'),
]);
const safeJs = js.replace(/<\/script/gi, '<\\/script');
const html = `<!doctype html>
<html lang="en"><head>
  <meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="theme-color" content="#f7f7f3">
  <meta name="description" content="CampusPass campus event booking prototype. Demo only; no real tickets or payments.">
  <title>CampusPass | Campus event booking demo</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;500;600;700&family=Manrope:wght@400;500;600;700;800&display=swap" rel="stylesheet">
  <style>${css}</style>
</head><body><div id="root"></div><script>${safeJs}</script></body></html>`;
await writeFile('portable.html', html, 'utf8');
console.log('Created portable.html. Open it directly in a browser for the local demo.');
