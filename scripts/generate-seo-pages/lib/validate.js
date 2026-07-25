/**
 * SEO page output validator.
 *
 * Reads generated HTML files from dist/s/ and checks each for:
 *
 * ERRORS (fatal — cause non-zero exit, last_generation_at NOT updated):
 *   - Missing <html> or <body> elements
 *   - Missing or empty <title> tag
 *   - Missing or empty meta description
 *   - Missing canonical link
 *   - Unresolved {{TOKEN}} template placeholders
 *   - Missing JSON-LD structured data block
 *   - Invalid (non-parseable) JSON in a JSON-LD block
 *
 * WARNINGS (reported but do not block generation):
 *   - Title > 60 characters
 *   - Meta description > 160 characters
 *   - No robots meta tag
 *
 * Exports:
 *   validateGenerated(distDir) → ValidationReport
 *   printValidationSummary(report)
 */

import { readdir, readFile } from 'fs/promises';
import { join, relative } from 'path';

// ── File discovery ─────────────────────────────────────────────────────────────

async function findHtmlFiles(dir) {
  const files = [];
  let entries;
  try {
    entries = await readdir(dir, { withFileTypes: true });
  } catch {
    return files; // directory doesn't exist — no generated pages
  }
  for (const entry of entries) {
    const fullPath = join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...await findHtmlFiles(fullPath));
    } else if (entry.name.endsWith('.html')) {
      files.push(fullPath);
    }
  }
  return files;
}

// ── Per-page validation ────────────────────────────────────────────────────────

function validatePageHtml(html) {
  const errors = [];
  const warnings = [];

  // Structural integrity
  if (!/<html[\s>]/i.test(html)) errors.push('Missing <html> element');
  if (!/<body[\s>]/i.test(html)) errors.push('Missing <body> element');

  // Title
  const titleMatch = html.match(/<title[^>]*>([^<]*)<\/title>/i);
  if (!titleMatch || !titleMatch[1].trim()) {
    errors.push('Missing or empty <title> tag');
  } else {
    const len = titleMatch[1].trim().length;
    if (len > 60) warnings.push(`Title ${len} chars — recommended ≤ 60`);
  }

  // Meta description
  const descMatch =
    html.match(/<meta\s+name=["']description["']\s+content=["']([^"']*)["']/i) ||
    html.match(/<meta\s+content=["']([^"']*)["']\s+name=["']description["']/i);
  if (!descMatch || !descMatch[1].trim()) {
    errors.push('Missing or empty meta description');
  } else {
    const len = descMatch[1].trim().length;
    if (len > 160) warnings.push(`Meta description ${len} chars — recommended ≤ 160`);
  }

  // Canonical URL
  const hasCanonical =
    /<link\s[^>]*rel=["']canonical["'][^>]*href=["'][^"']+["']/i.test(html) ||
    /<link\s[^>]*href=["'][^"']+["'][^>]*rel=["']canonical["']/i.test(html);
  if (!hasCanonical) errors.push('Missing canonical link tag');

  // Unresolved template tokens — any {{UPPER_CASE}} remaining after render
  const unresolvedTokens = html.match(/\{\{[A-Z_]+\}\}/g);
  if (unresolvedTokens) {
    errors.push(`Unresolved template tokens: ${[...new Set(unresolvedTokens)].join(', ')}`);
  }

  // JSON-LD: must be present and each block must be valid JSON
  const ldBlocks = [...html.matchAll(
    /<script\s+type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi,
  )];
  if (ldBlocks.length === 0) {
    errors.push('Missing JSON-LD structured data block');
  } else {
    for (let i = 0; i < ldBlocks.length; i++) {
      try {
        JSON.parse(ldBlocks[i][1].trim());
      } catch (e) {
        errors.push(`Invalid JSON-LD (block ${i + 1}): ${e.message.slice(0, 100)}`);
      }
    }
  }

  // Robots meta — warning only; some pages intentionally omit it
  if (!/<meta\s+name=["']robots["']/i.test(html)) {
    warnings.push('No robots meta tag');
  }

  return { errors, warnings };
}

// ── Public API ─────────────────────────────────────────────────────────────────

/**
 * Validate all generated SEO HTML pages under distDir/s/.
 *
 * @param {string} distDir - Absolute path to the dist directory.
 * @returns {Promise<ValidationReport>}
 */
export async function validateGenerated(distDir) {
  const seoDir = join(distDir, 's');
  const htmlFiles = await findHtmlFiles(seoDir);

  const results = [];
  for (const file of htmlFiles) {
    const html = await readFile(file, 'utf-8');
    const relPath = relative(distDir, file);
    const { errors, warnings } = validatePageHtml(html);
    results.push({ path: relPath, errors, warnings });
  }

  const errorCount = results.reduce((s, r) => s + r.errors.length, 0);
  const warningCount = results.reduce((s, r) => s + r.warnings.length, 0);

  return {
    pageCount: results.length,
    errorCount,
    warningCount,
    results,
    validatedAt: new Date().toISOString(),
  };
}

/**
 * Print a concise validation summary to the console.
 * Errors go to stderr; warnings go to stderr with [warn] prefix; pass goes to stdout.
 *
 * @param {ValidationReport} report
 */
export function printValidationSummary(report) {
  console.log('\n── SEO Validation ───────────────────────────────────────');
  console.log(`  Pages validated : ${report.pageCount}`);
  console.log(`  Errors          : ${report.errorCount}`);
  console.log(`  Warnings        : ${report.warningCount}`);

  const failures = report.results.filter(r => r.errors.length > 0);
  if (failures.length > 0) {
    console.error('\n  Fatal errors:');
    for (const f of failures) {
      console.error(`    ${f.path}`);
      for (const e of f.errors) console.error(`      [error] ${e}`);
    }
  }

  const warned = report.results.filter(r => r.warnings.length > 0);
  if (warned.length > 0) {
    console.warn('\n  Warnings:');
    for (const w of warned) {
      for (const msg of w.warnings) console.warn(`    [warn] ${w.path}: ${msg}`);
    }
  }

  if (report.errorCount === 0) {
    console.log('\n  ✓ Validation passed\n');
  } else {
    console.error('\n  ✗ Validation FAILED — last_generation_at will NOT be updated\n');
  }
}
