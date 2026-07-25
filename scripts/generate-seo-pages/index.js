import 'dotenv/config';
import { mkdir, writeFile } from 'fs/promises';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

import { fetchGlobalSettings, fetchEligibleNodes, fetchAncestors, fetchChildren, updateLastGenerationAt } from './lib/data.js';
import { validateGenerated, printValidationSummary } from './lib/validate.js';
import { buildPath } from './lib/path.js';
import { buildServiceSchema, buildCategorySchema, buildBreadcrumbSchema, buildGraphJson } from './lib/schema.js';
import { render } from './lib/render.js';
import { escHtml, renderContent } from './lib/escape.js';
import { generateLocationPages } from './lib/location.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DIST_DIR = join(__dirname, 'dist');

// ── Env validation ─────────────────────────────────────────────────────────────

function validate() {
  const missing = ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', 'PRODUCTION_DOMAIN']
    .filter(k => !process.env[k]);
  if (missing.length > 0) {
    console.error(`\nMissing required environment variables:\n  ${missing.join('\n  ')}`);
    console.error('\nCopy .env.example to .env and fill in the values.\n');
    process.exit(1);
  }
}

// ── Ancestor cache — avoids duplicate RPC calls for shared/child nodes ─────────

const ancestorCache = new Map();
async function getAncestors(nodeId) {
  if (!ancestorCache.has(nodeId)) {
    ancestorCache.set(nodeId, await fetchAncestors(nodeId));
  }
  return ancestorCache.get(nodeId);
}

// ── Title resolution ───────────────────────────────────────────────────────────

function resolveTitle(seoTitle, global) {
  const template = global?.title_template?.trim();
  if (template && template.includes('{page_title}')) {
    return template.replace('{page_title}', seoTitle);
  }
  // No template: use seo_title verbatim. Admins include brand in seo_title
  // directly, or configure title_template for automatic brand appending.
  // The brand_name fallback caused double-branding when seo_title already
  // contained the brand name.
  return seoTitle;
}

// ── Breadcrumb HTML nav ────────────────────────────────────────────────────────

function buildBreadcrumbNav(breadcrumbs) {
  return breadcrumbs
    .map((b, i) => {
      const isLast = i === breadcrumbs.length - 1;
      if (isLast) return `<span aria-current="page">${escHtml(b.name)}</span>`;
      if (b.isLinked) return `<a href="${escHtml(b.url)}">${escHtml(b.name)}</a><span>›</span>`;
      return `<span>${escHtml(b.name)}</span><span>›</span>`;
    })
    .join('');
}

// ── Children card list HTML (category template) ────────────────────────────────

function buildChildrenList(children) {
  return children
    .map(c => {
      const priceHtml = c.base_price != null
        ? `\n        <p class="price">From &#8377;${escHtml(String(c.base_price))}</p>`
        : '';
      return `<a href="${escHtml(c.canonicalUrl)}" class="service-card">\n        <h2>${escHtml(c.name)}</h2>${priceHtml}\n      </a>`;
    })
    .join('\n      ');
}

// ── sitemap.xml ────────────────────────────────────────────────────────────────

/**
 * Build sitemap.xml.
 * entries: [{ url, priority }] — catalog pages use 0.7; location area index 0.65; location service 0.6.
 */
function buildSitemap(entries) {
  const today = new Date().toISOString().slice(0, 10);
  const items = entries
    .map(({ url, priority }) =>
      `  <url>\n    <loc>${escHtml(url)}</loc>\n    <lastmod>${today}</lastmod>\n    <changefreq>weekly</changefreq>\n    <priority>${priority}</priority>\n  </url>`,
    )
    .join('\n');
  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${items}\n</urlset>`;
}

// ── robots.txt ─────────────────────────────────────────────────────────────────

function buildRobotsTxt(domain) {
  return [
    'User-agent: *',
    'Disallow: /catalog/',
    'Disallow: /booking',
    'Disallow: /cart',
    'Disallow: /checkout',
    'Disallow: /profile',
    'Disallow: /my-bookings',
    'Disallow: /address',
    'Disallow: /login',
    'Disallow: /otp',
    'Allow: /s/',
    `Sitemap: ${domain}/sitemap.xml`,
  ].join('\n');
}

// ── Main ───────────────────────────────────────────────────────────────────────

async function main() {
  validate();
  const domain = process.env.PRODUCTION_DOMAIN.replace(/\/$/, '');

  console.log('\nDODO SEO Generator');
  console.log(`  Domain : ${domain}`);
  console.log(`  Dist   : ${DIST_DIR}\n`);

  // 1. Global settings
  let global = null;
  try {
    global = await fetchGlobalSettings();
    if (!global) console.warn('  [warn] No global SEO settings configured — brand name and title template will be absent.');
  } catch (e) {
    console.warn(`  [warn] Could not fetch global settings: ${e.message}`);
  }

  // 2. Eligible nodes
  console.log('Fetching eligible nodes...');
  const nodes = await fetchEligibleNodes();
  console.log(`  Found ${nodes.length} eligible node(s)\n`);

  if (nodes.length === 0) {
    console.log('Nothing to generate.');
    console.log('Configure SEO titles for catalog nodes in the Admin Panel first.\n');
    return;
  }

  const eligibleIds = new Set(nodes.map(n => n.id));

  // Pre-compute the complete set of canonical URLs that will be generated this run.
  // Ancestor cache is populated here so the main loop below hits no extra RPCs.
  const willGenerateUrls = new Set();
  for (const node of nodes) {
    const ancestors = await getAncestors(node.id);
    if (ancestors.length > 0) {
      const { canonicalUrl } = buildPath(ancestors, domain);
      willGenerateUrls.add(canonicalUrl);
    }
  }

  const catalogUrls = [];
  let skipped = 0;

  // 3. Generate one page per eligible node
  for (const node of nodes) {
    try {
      // Ancestor path
      const ancestors = await getAncestors(node.id);
      if (ancestors.length === 0) {
        console.warn(`  [skip] "${node.name}" — no ancestors returned (orphaned node?)`);
        skipped++;
        continue;
      }
      const { urlPath, canonicalUrl, breadcrumbs: rawBreadcrumbs } = buildPath(ancestors, domain);

      // Mark each crumb: Home (index 0) is always linked; intermediate ancestors
      // are linked only when their own /s/ page was generated this run; the
      // current page is always in willGenerateUrls so it gets isLinked:true too
      // (used by JSON-LD item but not by the HTML nav which renders it as aria-current).
      const breadcrumbs = rawBreadcrumbs.map((b, i) => ({
        ...b,
        isLinked: i === 0 || willGenerateUrls.has(b.url),
      }));

      // Metadata resolution
      const title = resolveTitle(node.seo_title, global);
      const metaDesc = node.seo_description || node.description || '';
      const ogTitle = node.og_title || node.seo_title;
      const ogDesc = node.og_description || node.seo_description || node.description || '';
      const ogImage = node.og_image_url || global?.default_og_image_url || null;

      // Classify node type
      const isServiceNode = node.is_bookable === true && node.children_count === 0;

      // Structured data
      let primarySchema;
      let eligibleChildrenForSchema = [];

      if (isServiceNode) {
        primarySchema = buildServiceSchema(node, canonicalUrl);
      } else {
        if (node.children_count > 0) {
          const rawChildren = await fetchChildren(node.id);
          // Only include children that also have their own /s/ pages
          const eligibleRaw = rawChildren.filter(c => eligibleIds.has(c.id));
          eligibleChildrenForSchema = await Promise.all(
            eligibleRaw.map(async c => {
              const childAncestors = await getAncestors(c.id);
              const { canonicalUrl: childUrl } = buildPath(childAncestors, domain);
              return { name: c.name, base_price: c.base_price ?? null, canonicalUrl: childUrl };
            }),
          );
        }
        primarySchema = buildCategorySchema(node, eligibleChildrenForSchema, canonicalUrl);
      }

      const breadcrumbSchema = buildBreadcrumbSchema(breadcrumbs);
      const jsonLd = buildGraphJson(primarySchema, breadcrumbSchema);

      // Template tokens
      const tokens = {
        TITLE: escHtml(title),
        META_DESCRIPTION: escHtml(metaDesc),
        CANONICAL_URL: escHtml(canonicalUrl),
        OG_TITLE: escHtml(ogTitle),
        OG_DESCRIPTION: escHtml(ogDesc),
        OG_IMAGE: escHtml(ogImage ?? ''),
        HAS_OG_IMAGE: ogImage != null,
        H1: escHtml(node.name),
        BODY_DESCRIPTION: escHtml(node.description ?? ''),
        HAS_DESCRIPTION: node.description != null && node.description.trim() !== '',
        SEO_CONTENT: renderContent(node.seo_content),
        HAS_SEO_CONTENT: node.seo_content != null && node.seo_content.trim() !== '',
        BREADCRUMB_NAV: buildBreadcrumbNav(breadcrumbs),
        JSON_LD: jsonLd,
        CTA_URL: `/catalog/${node.id}`,
        CTA_TEXT: isServiceNode ? 'Book Now' : 'View Services',
        // service.html only
        PRICE: node.base_price != null ? escHtml(String(node.base_price)) : '',
        HAS_PRICE: isServiceNode && node.base_price != null,
        // category.html only
        CHILDREN_LIST: eligibleChildrenForSchema.length > 0
          ? buildChildrenList(eligibleChildrenForSchema)
          : '',
        HAS_CHILDREN: eligibleChildrenForSchema.length > 0,
      };

      const html = render(isServiceNode ? 'service.html' : 'category.html', tokens);

      // Write file
      const outDir = join(DIST_DIR, 's', ...urlPath.split('/'));
      await mkdir(outDir, { recursive: true });
      await writeFile(join(outDir, 'index.html'), html, 'utf-8');

      catalogUrls.push(canonicalUrl);
      console.log(`  [ok]  /s/${urlPath}/`);
    } catch (e) {
      console.error(`  [err] "${node.name}" (${node.id}): ${e.message}`);
      skipped++;
    }
  }

  // 4. Location SEO pages (Phase 4)
  console.log('\nGenerating location SEO pages...');
  const existingCatalogUrlPaths = new Set(
    [...willGenerateUrls].map(u => u.replace(`${domain}/s/`, '').replace(/\/$/, '')),
  );
  let locationSitemapUrls = [];
  try {
    const locationResult = await generateLocationPages({
      domain,
      distDir: DIST_DIR,
      global,
      ancestorCache,
      existingCatalogUrlPaths,
    });
    locationSitemapUrls = locationResult.sitemapUrls;
  } catch (e) {
    if (e.message.includes('collision')) {
      process.exit(1);
    }
    console.error(`  [err] Location page generation failed: ${e.message}`);
  }

  // 5. Sitemap and robots.txt
  // Catalog pages: priority 0.7; location area index: 0.65; location service: 0.6
  const locationIndexPrefix = `${domain}/s/location/`;
  const allSitemapEntries = [
    ...catalogUrls.map(url => ({ url, priority: '0.7' })),
    ...locationSitemapUrls.map(url => ({
      url,
      priority: url.split('/').filter(Boolean).length <= 4 ? '0.65' : '0.6',
    })),
  ];

  if (allSitemapEntries.length > 0) {
    await mkdir(DIST_DIR, { recursive: true });
    await writeFile(join(DIST_DIR, 'sitemap.xml'), buildSitemap(allSitemapEntries), 'utf-8');
    await writeFile(join(DIST_DIR, 'robots.txt'), buildRobotsTxt(domain), 'utf-8');
  }

  // 6. Summary
  const totalGenerated = catalogUrls.length + locationSitemapUrls.length;
  console.log('\n── Summary ──────────────────────────────────────────────');
  console.log(`  Catalog pages   : ${catalogUrls.length}`);
  console.log(`  Location pages  : ${locationSitemapUrls.length} (indexed)`);
  if (skipped > 0) console.log(`  Skipped         : ${skipped} (see errors above)`);
  console.log(`  Dist dir        : ${DIST_DIR}`);
  if (totalGenerated > 0) {
    const firstLocal = (catalogUrls[0] ?? locationSitemapUrls[0]).replace(domain, 'http://localhost:3000');
    console.log('\n── To verify locally ────────────────────────────────────');
    console.log('  npx serve dist/');
    console.log(`  Open: ${firstLocal}`);
  }

  // 7. Validate generated output
  // Run even if some pages were skipped — validate what was produced.
  // last_generation_at is only updated after validation passes.
  if (totalGenerated === 0) {
    console.log('\n  No pages generated — skipping validation and timestamp update.\n');
    return;
  }

  console.log('\nValidating generated SEO output...');
  const validationReport = await validateGenerated(DIST_DIR);
  await writeFile(
    join(DIST_DIR, 'seo-validation-report.json'),
    JSON.stringify(validationReport, null, 2),
    'utf-8',
  );
  printValidationSummary(validationReport);

  if (validationReport.errorCount > 0) {
    console.error(
      `Generation completed with ${validationReport.errorCount} validation error(s).\n` +
      'Fix the errors above and regenerate.\n' +
      'last_generation_at has NOT been updated.',
    );
    process.exit(1);
  }

  // 8. Record successful generation timestamp (only after validation passes)
  try {
    await updateLastGenerationAt();
    console.log('  last_generation_at recorded.\n');
  } catch (e) {
    // Non-fatal: timestamp not stored, but pages are valid
    console.warn(`  [warn] Could not update last_generation_at: ${e.message}`);
    console.warn('         Ensure Global SEO settings are saved in the Admin Panel.\n');
  }
}

main().catch(e => {
  console.error('\nFatal:', e.message);
  process.exit(1);
});
