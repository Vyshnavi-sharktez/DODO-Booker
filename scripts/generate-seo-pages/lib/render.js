import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const TEMPLATES_DIR = join(__dirname, '..', 'templates');

const templateCache = new Map();

function loadTemplate(name) {
  if (!templateCache.has(name)) {
    templateCache.set(name, readFileSync(join(TEMPLATES_DIR, name), 'utf-8'));
  }
  return templateCache.get(name);
}

/**
 * Remove or keep a conditional block: <!-- IF:NAME --> ... <!-- /IF:NAME -->
 * When show=true: markers are removed, content kept.
 * When show=false: entire block including content is removed.
 */
function applyConditional(html, name, show) {
  const open = `<!-- IF:${name} -->`;
  const close = `<!-- /IF:${name} -->`;
  let result = html;
  let start;
  while ((start = result.indexOf(open)) !== -1) {
    const end = result.indexOf(close, start);
    if (end === -1) break;
    if (show) {
      result =
        result.slice(0, start) +
        result.slice(start + open.length, end) +
        result.slice(end + close.length);
    } else {
      result = result.slice(0, start) + result.slice(end + close.length);
    }
  }
  return result;
}

/**
 * Render a named template with the given tokens map.
 *
 * Token types:
 *   boolean  — controls a <!-- IF:KEY --> ... <!-- /IF:KEY --> block
 *   string   — replaces {{KEY}} placeholders (no additional escaping; callers
 *              must pre-escape values that go into HTML attributes/text)
 *
 * JSON-LD token (JSON_LD) is a pre-serialized string; do not escape it again.
 */
export function render(templateName, tokens) {
  let html = loadTemplate(templateName);

  // Apply boolean conditionals first (they modify structure)
  for (const [key, value] of Object.entries(tokens)) {
    if (typeof value === 'boolean') {
      html = applyConditional(html, key, value);
    }
  }

  // Replace string tokens
  for (const [key, value] of Object.entries(tokens)) {
    if (typeof value === 'string') {
      html = html.replaceAll(`{{${key}}}`, value);
    }
  }

  return html;
}
