#!/usr/bin/env node
/**
 * Merges Flutter Customer Web build + SEO generator output into deploy-test/.
 *
 * Sources:
 *   customer_app/build/web/   — Flutter SPA (index.html + assets)
 *   scripts/generate-seo-pages/dist/s/          — static SEO HTML pages
 *   scripts/generate-seo-pages/dist/sitemap.xml
 *   scripts/generate-seo-pages/dist/robots.txt
 *
 * Output: deploy-test/  (gitignored, safe to delete/recreate at any time)
 *
 * Security: never reads or copies .env, node_modules, or credentials.
 * Scans the output for secret strings and aborts if any are found.
 *
 * Run: node scripts/merge.mjs
 */

import { readdir, copyFile, mkdir, rm, access, readFile } from 'fs/promises';
import { dirname, join, relative } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT        = join(__dirname, '..');
const FLUTTER_BUILD = join(ROOT, 'customer_app', 'build', 'web');
const SEO_DIST      = join(ROOT, 'scripts', 'generate-seo-pages', 'dist');
const DEPLOY_TEST   = join(ROOT, 'deploy-test');

// Strings that must never appear in the deployed output
const SECRET_PATTERNS = ['SUPABASE_SERVICE_ROLE_KEY', 'service_role'];

// File extensions to scan for secrets (skip binary/large files)
const SCANNABLE = /\.(html|xml|txt|json|js|css|dart)$/i;

async function pathExists(p) {
  try { await access(p); return true; } catch { return false; }
}

// Copy directory CONTENTS of src into dest (dest is created if needed).
// Concurrent at each level for speed.
async function copyDir(src, dest) {
  await mkdir(dest, { recursive: true });
  const entries = await readdir(src, { withFileTypes: true });
  await Promise.all(
    entries.map(entry => {
      const s = join(src, entry.name);
      const d = join(dest, entry.name);
      return entry.isDirectory() ? copyDir(s, d) : copyFile(s, d);
    }),
  );
}

// Recursively scan text files for secret strings.
async function scanForSecrets(dir) {
  const violations = [];
  async function scan(d) {
    const entries = await readdir(d, { withFileTypes: true });
    await Promise.all(
      entries.map(async entry => {
        const full = join(d, entry.name);
        if (entry.isDirectory()) return scan(full);
        if (!SCANNABLE.test(entry.name)) return;
        let content;
        try { content = await readFile(full, 'utf-8'); } catch { return; }
        for (const pat of SECRET_PATTERNS) {
          if (content.includes(pat)) violations.push({ file: full, pat });
        }
      }),
    );
  }
  await scan(dir);
  return violations;
}

async function main() {
  console.log('\nDODO — Merge Flutter + SEO → deploy-test/');
  console.log(`  Flutter : ${FLUTTER_BUILD}`);
  console.log(`  SEO dist: ${SEO_DIST}`);
  console.log(`  Output  : ${DEPLOY_TEST}\n`);

  // ── Validate sources ────────────────────────────────────────────────────────
  if (!await pathExists(FLUTTER_BUILD)) {
    console.error('[error] Flutter web build not found.');
    console.error('  Run: cd customer_app && flutter build web --base-href /');
    process.exit(1);
  }
  if (!await pathExists(join(SEO_DIST, 's'))) {
    console.error('[error] SEO pages not found (dist/s/ missing).');
    console.error('  Run: cd scripts/generate-seo-pages && node index.js');
    process.exit(1);
  }

  // ── Clean output dir ────────────────────────────────────────────────────────
  if (await pathExists(DEPLOY_TEST)) {
    process.stdout.write('  Cleaning deploy-test/...  ');
    await rm(DEPLOY_TEST, { recursive: true, force: true });
    console.log('done');
  }

  // ── 1. Flutter assets (index.html, flutter.js, assets/, icons/, manifest.json, …) ──
  process.stdout.write('  Copying Flutter build/web/ → deploy-test/... ');
  await copyDir(FLUTTER_BUILD, DEPLOY_TEST);
  console.log('ok');

  // ── 2. SEO pages: dist/s/ → deploy-test/s/ ─────────────────────────────────
  process.stdout.write('  Copying dist/s/ → deploy-test/s/...           ');
  await copyDir(join(SEO_DIST, 's'), join(DEPLOY_TEST, 's'));
  console.log('ok');

  // ── 3. sitemap.xml ──────────────────────────────────────────────────────────
  const sitemapSrc = join(SEO_DIST, 'sitemap.xml');
  if (await pathExists(sitemapSrc)) {
    await copyFile(sitemapSrc, join(DEPLOY_TEST, 'sitemap.xml'));
    console.log('  Copying sitemap.xml...                         ok');
  } else {
    console.warn('  [warn] dist/sitemap.xml not found — skipped');
  }

  // ── 4. robots.txt ──────────────────────────────────────────────────────────
  const robotsSrc = join(SEO_DIST, 'robots.txt');
  if (await pathExists(robotsSrc)) {
    await copyFile(robotsSrc, join(DEPLOY_TEST, 'robots.txt'));
    console.log('  Copying robots.txt...                          ok');
  } else {
    console.warn('  [warn] dist/robots.txt not found — skipped');
  }

  // ── 5. Security scan ────────────────────────────────────────────────────────
  process.stdout.write('\n  Scanning deploy-test/ for secrets...          ');
  const violations = await scanForSecrets(DEPLOY_TEST);
  if (violations.length > 0) {
    console.error('FAIL\n');
    console.error('[SECURITY] Secret pattern found in deploy-test/. Removing output and aborting.\n');
    violations.forEach(v =>
      console.error(`  "${v.pat}" in ${relative(DEPLOY_TEST, v.file)}`),
    );
    await rm(DEPLOY_TEST, { recursive: true, force: true });
    process.exit(1);
  }
  console.log('clean');

  // ── Summary ─────────────────────────────────────────────────────────────────
  console.log('\n── deploy-test/ ready ───────────────────────────────────────────');
  console.log('  Serve with SPA fallback (unmatched → index.html):');
  console.log('    npx serve deploy-test --single --listen 3000');
  console.log('');
  console.log('  Verify:');
  console.log('    http://localhost:3000/              → Flutter Customer App');
  console.log('    http://localhost:3000/s/.../        → Static SEO HTML');
  console.log('    http://localhost:3000/catalog/<id>  → Flutter SPA (not 404)');
  console.log('    http://localhost:3000/sitemap.xml');
  console.log('    http://localhost:3000/robots.txt');
  console.log('');
}

main().catch(e => {
  console.error('\nFatal:', e.message);
  process.exit(1);
});
