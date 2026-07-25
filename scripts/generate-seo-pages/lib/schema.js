/**
 * Conservative JSON-LD structured data builders.
 *
 * Phase 2 uses only:
 *   Service       — for bookable leaf nodes (is_bookable=true, children_count=0)
 *   ItemList      — for category/sub-category nodes
 *   BreadcrumbList — always included alongside the primary type
 *
 * Excluded (no real data to support the claims):
 *   LocalBusiness   — DODO is a platform, not the local service provider
 *   AggregateRating — excluded until a verified reviews pipeline exists
 *   availability    — no real-time inventory data
 */

/** Build a Service schema object for a bookable leaf node. */
export function buildServiceSchema(node, canonicalUrl) {
  const service = {
    '@type': 'Service',
    name: node.name,
    url: canonicalUrl,
  };
  if (node.description) service.description = node.description;
  if (node.base_price != null) {
    service.offers = {
      '@type': 'Offer',
      priceCurrency: 'INR',
      price: String(node.base_price),
    };
  }
  return service;
}

/**
 * Build an ItemList schema object for a category/sub-category node.
 * eligibleChildren: array of { name, base_price, canonicalUrl } — only children
 * that also have their own /s/ pages (i.e., pass the eligibility rule).
 */
export function buildCategorySchema(node, eligibleChildren, canonicalUrl) {
  const list = {
    '@type': 'ItemList',
    name: node.name,
    url: canonicalUrl,
  };
  if (node.description) list.description = node.description;
  if (eligibleChildren.length > 0) {
    list.itemListElement = eligibleChildren.map((child, i) => ({
      '@type': 'ListItem',
      position: i + 1,
      name: child.name,
      url: child.canonicalUrl,
    }));
  }
  return list;
}

/**
 * Build a BreadcrumbList schema object.
 * breadcrumbs: [{ name, url, isLinked }]
 *
 * `item` is only emitted when isLinked is true, which the caller sets only when
 * the corresponding /s/ page was actually generated (or for Home which always
 * exists). This prevents the structured data from asserting URLs that return 404.
 * schema.org ListItem.item is optional; omitting it is valid and semantically
 * correct for unlinked hierarchy labels.
 */
export function buildBreadcrumbSchema(breadcrumbs) {
  return {
    '@type': 'BreadcrumbList',
    itemListElement: breadcrumbs.map((b, i) => {
      const entry = { '@type': 'ListItem', position: i + 1, name: b.name };
      if (b.isLinked) entry.item = b.url;
      return entry;
    }),
  };
}

/**
 * Serialize the @graph array to a JSON string safe for embedding in <script> tags.
 * Replaces </ with <\/ to prevent early </script> tag termination.
 */
export function buildGraphJson(primarySchema, breadcrumbSchema) {
  const raw = JSON.stringify(
    { '@context': 'https://schema.org', '@graph': [primarySchema, breadcrumbSchema] },
    null,
    2,
  );
  return raw.replace(/<\//g, '<\\/');
}

/**
 * Build a Service schema with areaServed for a location service page.
 * Uses GeoCircle to represent the service zone's geographic extent.
 *
 * Conservative choices:
 *   • No LocalBusiness — DODO is a platform, not the local provider.
 *   • No AggregateRating — no verified reviews pipeline.
 *   • provider omitted when brandName is absent.
 */
export function buildLocationServiceSchema(node, area, canonicalUrl, brandName) {
  const schema = {
    '@type': 'Service',
    name: `${node.name} in ${area.name}`,
    url: canonicalUrl,
    areaServed: {
      '@type': 'GeoCircle',
      geoMidpoint: {
        '@type': 'GeoCoordinates',
        latitude: Number(area.latitude),
        longitude: Number(area.longitude),
        name: `${area.name}, ${area.city}`,
      },
      geoRadius: String(Math.round(Number(area.radius_km) * 1000)),
    },
  };
  if (node.description) schema.description = node.description;
  if (brandName) schema.provider = { '@type': 'Organization', name: brandName };
  if (node.base_price != null) {
    schema.offers = {
      '@type': 'Offer',
      priceCurrency: 'INR',
      price: String(node.base_price),
    };
  }
  return schema;
}

/**
 * Build an ItemList schema for an area index page listing all configured services.
 */
export function buildLocationIndexSchema(area, indexedPages, areaIndexUrl) {
  return {
    '@type': 'ItemList',
    name: `Services in ${area.name}`,
    url: areaIndexUrl,
    description: `Home services available in ${area.name}, ${area.city}`,
    itemListElement: indexedPages.map((p, i) => ({
      '@type': 'ListItem',
      position: i + 1,
      name: p.node.name,
      url: p.pageUrl,
    })),
  };
}
