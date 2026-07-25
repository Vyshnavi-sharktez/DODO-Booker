/**
 * Build URL path and breadcrumb data from catalog_node_ancestors() output.
 *
 * ancestors: rows ordered by depth DESC — root at highest depth, node at depth 0.
 * The ordering matches what catalog_node_ancestors() returns and gives us
 * root → ... → node in the natural reading order for URLs and breadcrumbs.
 *
 * Multi-parent nodes: only the canonical parent path is used here.
 * catalog_node_ancestors() already follows the canonical parent (sort_order ASC,
 * created_at ASC) so no additional logic is needed.
 */
export function buildPath(ancestors, domain) {
  // ancestors is already root-first (depth DESC), so slugs join in the correct order
  const segments = ancestors.map(a => a.slug);
  const urlPath = segments.join('/');
  const canonicalUrl = `${domain}/s/${urlPath}/`;

  // Breadcrumbs: Home + each ancestor in root-to-node order
  const breadcrumbs = [{ name: 'Home', url: `${domain}/` }];
  let cumulativePath = '';
  for (const ancestor of ancestors) {
    cumulativePath = cumulativePath
      ? `${cumulativePath}/${ancestor.slug}`
      : ancestor.slug;
    breadcrumbs.push({
      name: ancestor.name,
      url: `${domain}/s/${cumulativePath}/`,
    });
  }

  return { urlPath, canonicalUrl, breadcrumbs };
}
