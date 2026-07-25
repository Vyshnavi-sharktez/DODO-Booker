import { createClient } from '@supabase/supabase-js';

let _client = null;

function getClient() {
  if (!_client) {
    _client = createClient(
      process.env.SUPABASE_URL,
      process.env.SUPABASE_SERVICE_ROLE_KEY,
      { auth: { persistSession: false } },
    );
  }
  return _client;
}

/**
 * Update last_generation_at on the seo_global_settings singleton row.
 *
 * Uses UPDATE (not UPSERT) so only last_generation_at is written — all other
 * columns are left unchanged. The fn_seo_global_settings_updated_at trigger
 * detects this and does NOT bump updated_at, keeping staleness comparisons
 * accurate.
 *
 * If the row does not exist yet (admin has not saved Global SEO settings),
 * this is a no-op and a warning is logged — the timestamp will be stored
 * once global settings are saved and the generator is re-run.
 */
export async function updateLastGenerationAt() {
  const now = new Date().toISOString();
  const { error } = await getClient()
    .from('seo_global_settings')
    .update({ last_generation_at: now })
    .eq('id', 'global');
  if (error) throw new Error(`updateLastGenerationAt: ${error.message}`);
}

/** Fetch the singleton global SEO settings row, or null if not yet configured. */
export async function fetchGlobalSettings() {
  const { data, error } = await getClient()
    .from('seo_global_settings')
    .select('*')
    .eq('id', 'global')
    .maybeSingle();
  if (error) throw new Error(`fetchGlobalSettings: ${error.message}`);
  return data;
}

/**
 * Fetch all SEO-eligible catalog nodes.
 *
 * Eligibility rule (from revised Phase 2 plan):
 *   1. catalog_node_seo row exists with non-empty seo_title (admin has explicitly configured it)
 *   2. catalog_node_seo.noindex = false
 *   3. catalog_nodes.is_active = true
 *
 * Uses two queries to avoid PostgREST view-join limitations:
 *   Q1 — catalog_node_seo with eligibility filters → eligible node_ids + seo data
 *   Q2 — catalog_nodes_view for node details (children_count, is_root_node, etc.)
 */
export async function fetchEligibleNodes() {
  const { data: seoRows, error: seoError } = await getClient()
    .from('catalog_node_seo')
    .select('node_id, seo_title, seo_description, og_title, og_description, og_image_url, seo_content')
    .eq('noindex', false)
    .not('seo_title', 'is', null)
    .neq('seo_title', '');
  if (seoError) throw new Error(`fetchEligibleNodes (seo): ${seoError.message}`);
  if (!seoRows || seoRows.length === 0) return [];

  // Post-filter: trim check (guards against whitespace-only titles)
  const validSeoRows = seoRows.filter(r => r.seo_title.trim() !== '');
  if (validSeoRows.length === 0) return [];

  const eligibleIds = validSeoRows.map(r => r.node_id);
  const seoByNodeId = Object.fromEntries(validSeoRows.map(r => [r.node_id, r]));

  const { data: nodes, error: nodeError } = await getClient()
    .from('catalog_nodes_view')
    .select('id, name, slug, description, is_bookable, base_price, children_count, is_root_node')
    .eq('is_active', true)
    .in('id', eligibleIds);
  if (nodeError) throw new Error(`fetchEligibleNodes (nodes): ${nodeError.message}`);

  return (nodes || []).map(n => {
    const seo = seoByNodeId[n.id] ?? {};
    return {
      id: n.id,
      name: n.name,
      slug: n.slug,
      description: n.description ?? null,
      is_bookable: n.is_bookable,
      base_price: n.base_price ?? null,
      children_count: n.children_count ?? 0,
      is_root_node: n.is_root_node,
      seo_title: seo.seo_title ?? null,
      seo_description: seo.seo_description ?? null,
      og_title: seo.og_title ?? null,
      og_description: seo.og_description ?? null,
      og_image_url: seo.og_image_url ?? null,
      seo_content: seo.seo_content ?? null,
    };
  });
}

/**
 * Fetch the canonical ancestor path for a node.
 * Returns rows ordered by depth DESC: root first (highest depth), node last (depth 0).
 * Each row: { id, name, slug, depth }
 */
export async function fetchAncestors(nodeId) {
  const { data, error } = await getClient()
    .rpc('catalog_node_ancestors', { p_node_id: nodeId });
  if (error) throw new Error(`fetchAncestors(${nodeId}): ${error.message}`);
  return data ?? [];
}

/**
 * Fetch active children of a parent node.
 * Returns SETOF catalog_nodes_view — ordered by sort_order ASC, name ASC.
 */
export async function fetchChildren(parentId) {
  const { data, error } = await getClient()
    .rpc('get_catalog_node_children', { p_parent_id: parentId });
  if (error) throw new Error(`fetchChildren(${parentId}): ${error.message}`);
  return data ?? [];
}

/**
 * Fetch all data needed for location SEO page generation.
 *
 * Returns:
 *   { areaMap: { [areaId]: area }, entries: LocationEntry[] }
 *
 * Each LocationEntry has:
 *   { id, area, node, seoTitle, seoDescription, ogTitle, ogDescription,
 *     ogImageUrl, seoContent, noindex, isNodeBlocked }
 *
 * isNodeBlocked: true when catalog_node_location_restrictions has a node-scoped
 * (relationship_id IS NULL) entry for this node+area pair. The generator skips
 * such entries with a warning — publishing a "book here" page for a service that
 * is explicitly blocked in that area would be misleading.
 *
 * Limitation: This only catches node-scoped (global) blocks. Relationship-scoped
 * restrictions and partial-overlap zones are not checked. Explicit admin curation
 * remains the primary publishing gate.
 */
export async function fetchLocationData() {
  // Q1: location_node_seo rows with a non-empty seo_title
  const { data: lnsRows, error: lnsError } = await getClient()
    .from('location_node_seo')
    .select('id, area_id, node_id, seo_title, seo_description, og_title, og_description, og_image_url, seo_content, noindex')
    .not('seo_title', 'is', null)
    .neq('seo_title', '');
  if (lnsError) throw new Error(`fetchLocationData (lns): ${lnsError.message}`);
  if (!lnsRows || lnsRows.length === 0) return { areaMap: {}, entries: [] };

  const validRows = lnsRows.filter(r => r.seo_title.trim() !== '');
  if (validRows.length === 0) return { areaMap: {}, entries: [] };

  // Q2: relevant active areas (must have a slug — migration ensures this)
  const areaIds = [...new Set(validRows.map(r => r.area_id))];
  const { data: areas, error: areaError } = await getClient()
    .from('service_availability_areas')
    .select('id, name, city, slug, latitude, longitude, radius_km')
    .in('id', areaIds)
    .eq('is_active', true);
  if (areaError) throw new Error(`fetchLocationData (areas): ${areaError.message}`);

  const areaMap = Object.fromEntries((areas || []).map(a => [a.id, a]));

  // Q3: relevant active catalog nodes
  const nodeIds = [...new Set(validRows.map(r => r.node_id))];
  const { data: nodes, error: nodeError } = await getClient()
    .from('catalog_nodes_view')
    .select('id, name, slug, description, is_bookable, base_price, is_active')
    .in('id', nodeIds)
    .eq('is_active', true);
  if (nodeError) throw new Error(`fetchLocationData (nodes): ${nodeError.message}`);

  const nodeMap = Object.fromEntries((nodes || []).map(n => [n.id, n]));

  // Q4: node-scoped blocks (relationship_id IS NULL) for these node+area pairs.
  // Only checks node-scoped entries: these represent a global block for that node
  // in that area regardless of catalog path, making the restriction unambiguous.
  const { data: restrictions, error: rError } = await getClient()
    .from('catalog_node_location_restrictions')
    .select('node_id, area_id')
    .in('node_id', nodeIds)
    .in('area_id', areaIds)
    .is('relationship_id', null);
  if (rError) throw new Error(`fetchLocationData (restrictions): ${rError.message}`);

  const blockedSet = new Set((restrictions || []).map(r => `${r.node_id}:${r.area_id}`));

  // Assemble entries, dropping rows where area or node is missing/inactive
  const entries = validRows
    .filter(r => areaMap[r.area_id] && nodeMap[r.node_id])
    .map(r => ({
      id: r.id,
      area: areaMap[r.area_id],
      node: nodeMap[r.node_id],
      seoTitle: r.seo_title.trim(),
      seoDescription: r.seo_description ?? null,
      ogTitle: r.og_title ?? null,
      ogDescription: r.og_description ?? null,
      ogImageUrl: r.og_image_url ?? null,
      seoContent: r.seo_content ?? null,
      noindex: r.noindex,
      isNodeBlocked: blockedSet.has(`${r.node_id}:${r.area_id}`),
    }));

  return { areaMap, entries };
}
