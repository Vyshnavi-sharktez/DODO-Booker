#!/usr/bin/env node
/**
 * Local test server for deploy-test/ — mirrors the production routing contract:
 *
 *   1. Try the exact file path (e.g. /flutter.js, /sitemap.xml, /robots.txt)
 *   2. Try the path + /index.html (e.g. /s/path/to/dir/ → .../dir/index.html)
 *   3. SPA fallback → deploy-test/index.html (covers /catalog/**, /booking, etc.)
 *
 * This correctly routes:
 *   /                     → deploy-test/index.html          (Flutter SPA home)
 *   /s/category/service/  → deploy-test/s/.../index.html   (SEO page)
 *   /sitemap.xml          → deploy-test/sitemap.xml
 *   /robots.txt           → deploy-test/robots.txt
 *   /catalog/{uuid}       → deploy-test/index.html          (Flutter SPA, GoRouter)
 *   /flutter.js, /assets/ → Flutter static assets
 *
 * No npm dependencies. Run: node scripts/test-server.mjs
 */

import { createServer } from 'http';
import { readFile, stat } from 'fs/promises';
import { join, extname, dirname } from 'path';
import { fileURLToPath } from 'url';

const PORT   = 3000;
const SERVE_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', 'deploy-test');
const SPA_INDEX  = join(SERVE_ROOT, 'index.html');

// MIME types covering Flutter web assets + SEO files
const MIME = {
  '.html':        'text/html; charset=utf-8',
  '.js':          'application/javascript',
  '.mjs':         'application/javascript',
  '.json':        'application/json',
  '.wasm':        'application/wasm',
  '.css':         'text/css',
  '.png':         'image/png',
  '.jpg':         'image/jpeg',
  '.jpeg':        'image/jpeg',
  '.gif':         'image/gif',
  '.webp':        'image/webp',
  '.svg':         'image/svg+xml',
  '.ico':         'image/x-icon',
  '.txt':         'text/plain; charset=utf-8',
  '.xml':         'application/xml; charset=utf-8',
  '.woff':        'font/woff',
  '.woff2':       'font/woff2',
  '.ttf':         'font/ttf',
  '.map':         'application/json',
  '.webmanifest': 'application/manifest+json',
};

function mimeFor(filePath) {
  return MIME[extname(filePath).toLowerCase()] ?? 'application/octet-stream';
}

// Returns file Buffer if path is a real file, null otherwise.
async function tryFile(filePath) {
  try {
    const s = await stat(filePath);
    if (s.isFile()) return await readFile(filePath);
  } catch { /* not found or not a file */ }
  return null;
}

const server = createServer(async (req, res) => {
  const rawPath = req.url.split('?')[0];
  let urlPath;
  try { urlPath = decodeURIComponent(rawPath); } catch { urlPath = rawPath; }

  // Build filesystem path segments, stripping leading slash and empty parts
  const segments = urlPath.split('/').filter(Boolean);
  const fsBase = join(SERVE_ROOT, ...segments);

  // Candidate files, in priority order:
  //   1. Exact match:              deploy-test/flutter.js, deploy-test/sitemap.xml, etc.
  //   2. Directory index:          deploy-test/s/.../dir/index.html
  const candidates = [fsBase, join(fsBase, 'index.html')];

  for (const candidate of candidates) {
    const content = await tryFile(candidate);
    if (content !== null) {
      const mime = mimeFor(candidate);
      res.writeHead(200, {
        'Content-Type':  mime,
        'Cache-Control': mime.startsWith('text/html') ? 'no-cache' : 'public, max-age=60',
      });
      res.end(content);
      const label = candidate.endsWith('index.html') && segments.length > 0
        ? '(dir/index.html)'
        : '(file)';
      console.log(`  200  ${urlPath}  ${label}`);
      return;
    }
  }

  // SPA fallback: serve Flutter index.html so GoRouter can handle the route
  try {
    const indexContent = await readFile(SPA_INDEX);
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-cache' });
    res.end(indexContent);
    console.log(`  200  ${urlPath}  (→ Flutter SPA)`);
  } catch (e) {
    res.writeHead(500);
    res.end('deploy-test/index.html not found. Run: node scripts/merge.mjs');
    console.error(`  500  ${urlPath}  (index.html missing: ${e.message})`);
  }
});

server.on('error', e => {
  if (e.code === 'EADDRINUSE') {
    console.error(`\n[error] Port ${PORT} is already in use.`);
    console.error('  Stop the other process or change the PORT in this script.');
  } else {
    console.error('\n[error]', e.message);
  }
  process.exit(1);
});

server.listen(PORT, () => {
  console.log(`\nDODO Local Test Server`);
  console.log(`  URL     : http://localhost:${PORT}`);
  console.log(`  Serving : ${SERVE_ROOT}`);
  console.log(`\n  Routing contract:`);
  console.log(`    /s/**           → SEO static HTML (dir/index.html)`);
  console.log(`    /sitemap.xml    → served directly`);
  console.log(`    /robots.txt     → served directly`);
  console.log(`    /catalog/**     → Flutter SPA (index.html fallback)`);
  console.log(`    /**             → Flutter SPA (index.html fallback)`);
  console.log(`\n  Press Ctrl+C to stop.\n`);
});
