/**
 * Phase 4 — Location SEO page generator.
 *
 * Generates two types of static pages under /s/location/:
 *
 *   /s/location/{area-slug}/{canonical-node-path}/index.html
 *     — Location service page: "{Service} in {Area}"
 *       Self-canonical. Carries areaServed structured data.
 *       noindex pages are generated (so existing links don't 404) but
 *       carry <meta name="robots" content="noindex, follow"> and are
 *       excluded from the sitemap.
 *
 *   /s/location/{area-slug}/index.html
 *     — Area index page: "Services in {Area}"
 *       Lists all non-noindex service pages for that area.
 *       Only generated when the area has at least one indexed page.
 *
 * URL prefix /s/location/ is protected by a collision guard: if any existing
 * catalog SEO page already uses a path starting with "location/", the generator
 * aborts to prevent overwriting.
 *
 * Serviceability limitation (clearly reported in logs):
 *   catalog_node_location_restrictions signals where a node is BLOCKED, not where
 *   it is available. We check node-scoped blocks as a safety guard, but cannot
 *   positively assert availability from the absence of a restriction row. Explicit
 *   admin curation in location_node_seo is the publishing gate.
 */

import { mkdir, writeFile } from 'fs/promises';
import { join } from 'path';

import { fetchLocationData, fetchAncestors } from './data.js';
import { buildPath } from './path.js';
import {
  buildLocationServiceSchema,
  buildLocationIndexSchema,
  buildBreadcrumbSchema,
  buildGraphJson,
} from './schema.js';
import { render } from './render.js';
import { escHtml, renderContent } from './escape.js';

// ── Breadcrumb HTML ────────────────────────────────────────────────────────────

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

// ── Service card HTML for index pages ─────────────────────────────────────────

function buildServiceCard(page) {
  const priceHtml = page.node.base_price != null
    ? `\n        <p class="price">From &#8377;${escHtml(String(page.node.base_price))}</p>`
    : '';
  return `<a href="${escHtml(page.pageUrl)}" class="service-card">\n        <h2>${escHtml(page.node.name)}</h2>${priceHtml}\n      </a>`;
}

// ── Title resolution ───────────────────────────────────────────────────────────

function resolveTitle(seoTitle, area, global) {
  const template = global?.title_template?.trim();
  const pageTitle = seoTitle || `${area.name} Services`;
  if (template && template.includes('{page_title}')) {
    return template.replace('{page_title}', pageTitle);
  }
  return pageTitle;
}

// ── Main export ────────────────────────────────────────────────────────────────

/**
 * Generate all location SEO pages.
 *
 * @param {object} opts
 * @param {string} opts.domain — production domain (no trailing slash)
 * @param {string} opts.distDir — absolute path to dist/
 * @param {object|null} opts.global — seo_global_settings row or null
 * @param {Map<string,string>} opts.ancestorCache — shared ancestor cache from main index
 * @param {Set<string>} opts.existingCatalogUrlPaths — set of urlPaths already generated
 *   by the catalog phase, used for the collision guard and breadcrumb link resolution
 * @returns {{ generatedUrls: string[], sitemapUrls: string[] }}
 *   generatedUrls: all pages generated (includes noindex)
 *   sitemapUrls: pages to include in sitemap (excludes noindex)
 */
export async function generateLocationPages({
  domain,
  distDir,
  global,
  ancestorCache,
  existingCatalogUrlPaths,
}) {
  // ── Fetch data ─────────────────────────────────────────────────────────────
  const { areaMap, entries } = await fetchLocationData();

  if (entries.length === 0) {
    console.log('  [location] No configured location pages found.');
    console.log('  [location] Add area × service SEO configs in the Admin Panel → SEO → Location Pages.\n');
    return { generatedUrls: [], sitemapUrls: [] };
  }

  console.log(`  [location] Found ${entries.length} configured location page(s)\n`);

  // ── Collision guard ────────────────────────────────────────────────────────
  // If any catalog node happens to have the slug "location" at the root level,
  // the path "location/..." would collide with our /s/location/ prefix.
  // Abort rather than silently overwrite an existing page.
  const collisions = [...existingCatalogUrlPaths].filter(p => p === 'location' || p.startsWith('location/'));
  if (collisions.length > 0) {
    console.error(`\n  [FATAL] /s/location/ URL prefix collision detected.`);
    console.error(`  Existing catalog pages conflict with the location page namespace:`);
    collisions.forEach(p => console.error(`    /s/${p}/`));
    console.error(`  Rename the conflicting catalog node slug(s) before re-running.\n`);
    throw new Error('Location page URL prefix collision with existing catalog pages');
  }

  // ── Per-entry ancestor cache helper ───────────────────────────────────────
  async function getAncestors(nodeId) {
    if (!ancestorCache.has(nodeId)) {
      ancestorCache.set(nodeId, await fetchAncestors(nodeId));
    }
    return ancestorCache.get(nodeId);
  }

  // ── Generate service pages ─────────────────────────────────────────────────
  const allGenerated = [];  // { area, node, pageUrl, noindex } — for area index and sitemap
  let skipped = 0;

  for (const entry of entries) {
    const { area, node, noindex, isNodeBlocked } = entry;

    // Safety check: skip if this node is explicitly blocked in this area
    if (isNodeBlocked) {
      console.warn(
        `  [skip] "${node.name}" in "${area.name}" — ` +
        `node has a node-scoped location restriction for this area. ` +
        `Remove the restriction in Admin → Service Availability → Restrictions, ` +
        `or remove this location SEO config.`,
      );
      skipped++;
      continue;
    }

    try {
      // Build canonical node path using shared ancestor cache
      const ancestors = await getAncestors(node.id);
      if (ancestors.length === 0) {
        console.warn(`  [skip] "${node.name}" in "${area.name}" — node has no ancestors (orphaned?)`);
        skipped++;
        continue;
      }

      const { urlPath: nodeUrlPath, breadcrumbs: rawNodeCrumbs } = buildPath(ancestors, domain);

      // Location page URL: /s/location/{area-slug}/{canonical-node-path}/
      const locationUrlPath = `location/${area.slug}/${nodeUrlPath}`;
      const canonicalUrl = `${domain}/s/${locationUrlPath}/`;
      const areaIndexUrl = `${domain}/s/location/${area.slug}/`;

      // Breadcrumbs: Home › {Area} › {Catalog ancestors...} › {Service}
      // The area links to its index page (always generated when it has indexed pages).
      // Intermediate catalog ancestors link only when their /s/ page was generated this run.
      const breadcrumbs = [
        { name: 'Home', url: `${domain}/`, isLinked: true },
        { name: area.name, url: areaIndexUrl, isLinked: true },
        // rawNodeCrumbs[0] is Home (skip), rest are catalog ancestors including the node itself
        ...rawNodeCrumbs.slice(1).map((b, i) => ({
          ...b,
          isLinked: i < rawNodeCrumbs.length - 2
            ? existingCatalogUrlPaths.has(b.url.replace(`${domain}/s/`, '').replace(/\/$/, ''))
            : false,
        })),
      ];

      // Metadata
      const h1 = `${node.name} in ${area.name}`;
      const titleBase = entry.seoTitle;
      const title = resolveTitle(titleBase, area, global);
      const metaDesc = entry.seoDescription || node.description || `Book ${node.name} in ${area.name}, ${area.city}.`;
      const ogTitle = entry.ogTitle || titleBase || h1;
      const ogDesc = entry.ogDescription || entry.seoDescription || metaDesc;
      const ogImage = entry.ogImageUrl || global?.default_og_image_url || null;

      // Structured data
      const primarySchema = buildLocationServiceSchema(node, area, canonicalUrl, global?.brand_name ?? null);
      const breadcrumbSchema = buildBreadcrumbSchema(breadcrumbs);
      const jsonLd = buildGraphJson(primarySchema, breadcrumbSchema);

      // Template tokens
      const tokens = {
        TITLE: escHtml(title),
        META_DESCRIPTION: escHtml(metaDesc),
        CANONICAL_URL: escHtml(canonicalUrl),
        ROBOTS: noindex ? 'noindex, follow' : 'index, follow',
        OG_TITLE: escHtml(ogTitle),
        OG_DESCRIPTION: escHtml(ogDesc),
        OG_IMAGE: escHtml(ogImage ?? ''),
        HAS_OG_IMAGE: ogImage != null,
        H1: escHtml(h1),
        BODY_DESCRIPTION: escHtml(node.description ?? ''),
        HAS_DESCRIPTION: node.description != null && node.description.trim() !== '',
        HAS_AREA_FACTS: true,
        AREA_NAME: escHtml(area.name),
        AREA_CITY: escHtml(area.city),
        PRICE: node.base_price != null ? escHtml(String(node.base_price)) : '',
        HAS_PRICE: node.base_price != null,
        SEO_CONTENT: renderContent(entry.seoContent),
        HAS_SEO_CONTENT: entry.seoContent != null && entry.seoContent.trim() !== '',
        BREADCRUMB_NAV: buildBreadcrumbNav(breadcrumbs),
        JSON_LD: jsonLd,
        CTA_URL: `/catalog/${node.id}`,
        CTA_TEXT: `Book Now in ${area.name}`,
      };

      const html = render('location-service.html', tokens);
      const outDir = join(distDir, 's', 'location', area.slug, ...nodeUrlPath.split('/'));
      await mkdir(outDir, { recursive: true });
      await writeFile(join(outDir, 'index.html'), html, 'utf-8');

      allGenerated.push({ area, node, pageUrl: canonicalUrl, noindex });

      const noindexMark = noindex ? ' [noindex]' : '';
      console.log(`  [ok]  /s/${locationUrlPath}/${noindexMark}`);
    } catch (e) {
      console.error(`  [err] "${node.name}" in "${area.name}": ${e.message}`);
      skipped++;
    }
  }

  // ── Generate area index pages ──────────────────────────────────────────────
  // One index per area that has at least one non-noindex page.

  const indexedByArea = new Map();
  for (const p of allGenerated.filter(p => !p.noindex)) {
    const areaId = p.area.id;
    if (!indexedByArea.has(areaId)) indexedByArea.set(areaId, { area: p.area, pages: [] });
    indexedByArea.get(areaId).pages.push(p);
  }

  const areaIndexUrls = [];

  for (const { area, pages } of indexedByArea.values()) {
    try {
      const areaIndexUrl = `${domain}/s/location/${area.slug}/`;
      const areaIndexUrlPath = `location/${area.slug}`;

      const breadcrumbs = [
        { name: 'Home', url: `${domain}/`, isLinked: true },
        { name: area.name, url: areaIndexUrl, isLinked: false },
      ];

      const h1 = `Services in ${area.name}`;
      const metaDesc = `Find and book home services in ${area.name}, ${area.city}. Compare services and prices.`;
      const titleBase = `Services in ${area.name}`;
      const title = resolveTitle(titleBase, area, global);

      const primarySchema = buildLocationIndexSchema(area, pages, areaIndexUrl);
      const breadcrumbSchema = buildBreadcrumbSchema(breadcrumbs);
      const jsonLd = buildGraphJson(primarySchema, breadcrumbSchema);

      const servicesList = pages.map(p => buildServiceCard(p)).join('\n      ');

      const tokens = {
        TITLE: escHtml(title),
        META_DESCRIPTION: escHtml(metaDesc),
        CANONICAL_URL: escHtml(areaIndexUrl),
        OG_TITLE: escHtml(h1),
        OG_DESCRIPTION: escHtml(metaDesc),
        H1: escHtml(h1),
        AREA_META: escHtml(`Covering ${area.name}, ${area.city} (${area.radius_km} km radius)`),
        BREADCRUMB_NAV: buildBreadcrumbNav(breadcrumbs),
        JSON_LD: jsonLd,
        SERVICES_LIST: servicesList,
        HAS_SERVICES: pages.length > 0,
      };

      const html = render('location-index.html', tokens);
      const outDir = join(distDir, 's', 'location', area.slug);
      await mkdir(outDir, { recursive: true });
      await writeFile(join(outDir, 'index.html'), html, 'utf-8');

      areaIndexUrls.push(areaIndexUrl);
      console.log(`  [ok]  /s/${areaIndexUrlPath}/  (area index, ${pages.length} service(s))`);
    } catch (e) {
      console.error(`  [err] Area index "${area.name}": ${e.message}`);
    }
  }

  if (skipped > 0) {
    console.log(`\n  [location] ${skipped} entry(s) skipped — see warnings above.`);
  }

  // ── Build URL lists for sitemap integration ────────────────────────────────
  const sitemapUrls = [
    ...areaIndexUrls,
    ...allGenerated.filter(p => !p.noindex).map(p => p.pageUrl),
  ];
  const allGeneratedUrls = [
    ...areaIndexUrls,
    ...allGenerated.map(p => p.pageUrl),
  ];

  return { generatedUrls: allGeneratedUrls, sitemapUrls };
}
