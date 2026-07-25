/** HTML entity-escape a value for safe insertion into HTML attributes or text content. */
export function escHtml(str) {
  if (str == null) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/**
 * Render seo_content as safe HTML paragraphs.
 * Splits on double newlines, escapes each paragraph, wraps in <p>.
 */
export function renderContent(str) {
  if (!str || str.trim() === '') return '';
  return str
    .split(/\n\n+/)
    .filter(p => p.trim())
    .map(p => `<p>${escHtml(p.trim())}</p>`)
    .join('\n      ');
}
