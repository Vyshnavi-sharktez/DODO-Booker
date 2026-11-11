-- Gate customer-visible vendor listings on active subscription permissions.
--
-- InstaHelp discovery: respects instahelp_subscription_enabled + allow_instahelp.
-- Vendor Catalog discovery: requires allow_vendor_catalog on active subscription.
--
-- Changes:
--   1. Add allow_vendor_catalog permission to existing subscription plans
--   2. Fix get_instahelp_vendors_by_location
--   3. Fix get_vcs_categories
--   4. Fix get_vcs_vendors
--   5. Fix get_vcs_vendor_service_names
--   6. Fix search_vendor_custom_services

-- ── 1. Seed allow_vendor_catalog into existing plans ─────────────────────────
-- Plans with allow_custom_price=true get allow_vendor_catalog=true; others false.

UPDATE public.subscription_plans
SET permissions = permissions || jsonb_build_object('allow_vendor_catalog', true)
WHERE (permissions->>'allow_custom_price')::BOOLEAN = TRUE;

UPDATE public.subscription_plans
SET permissions = permissions || jsonb_build_object('allow_vendor_catalog', false)
WHERE permissions->>'allow_vendor_catalog' IS NULL;

-- ── 2. get_instahelp_vendors_by_location ─────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_instahelp_vendors_by_location(
  p_lat FLOAT8,
  p_lng FLOAT8
)
RETURNS TABLE (
  id                UUID,
  business_name     TEXT,
  profile_image_url TEXT,
  is_online         BOOLEAN,
  rating            NUMERIC,
  service_count     BIGINT,
  min_service_price NUMERIC,
  city              TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    v.id,
    v.business_name,
    v.profile_image_url,
    v.is_online,
    v.rating::NUMERIC,
    COUNT(DISTINCT vsr.id)      AS service_count,
    MIN(vsr.price)::NUMERIC     AS min_service_price,
    v.city
  FROM public.vendors v
  LEFT JOIN public.vendor_serving_area_assignments vsaa
         ON vsaa.vendor_id = v.id
  LEFT JOIN public.service_availability_areas saa
         ON saa.id = vsaa.serving_area_id
        AND saa.is_active = TRUE
  LEFT JOIN public.vendor_service_requests vsr
         ON vsr.vendor_id = v.id
        AND vsr.status = 'approved'
        AND vsr.is_active = TRUE
  WHERE v.is_active = TRUE
    AND (
      vsaa.vendor_id IS NULL
      OR (
        (2.0 * 6371.0 * asin(sqrt(
          power(sin(radians((saa.latitude  - p_lat) / 2.0)), 2) +
          cos(radians(p_lat)) * cos(radians(saa.latitude)) *
          power(sin(radians((saa.longitude - p_lng) / 2.0)), 2)
        ))) <= saa.radius_km
      )
    )
    -- Subscription gate: skip if module is off; otherwise require allow_instahelp
    AND (
      COALESCE(
        (SELECT setting_value FROM public.settings
         WHERE setting_key = 'instahelp_subscription_enabled'), 'false'
      ) <> 'true'
      OR EXISTS (
        SELECT 1
        FROM public.vendor_subscriptions vs
        JOIN public.subscription_plans sp ON sp.id = vs.plan_id
        WHERE vs.vendor_id       = v.id
          AND vs.catalog_node_id IS NULL
          AND vs.status          = 'active'
          AND vs.expiry_date     > NOW() - (
            COALESCE(
              NULLIF(TRIM(COALESCE(
                (SELECT setting_value FROM public.settings
                 WHERE setting_key = 'instahelp_subscription_grace_period_days'), '0'
              )), ''), '0'
            )::INT || ' days'
          )::INTERVAL
          AND (sp.permissions->>'allow_instahelp')::BOOLEAN = TRUE
      )
    )
  GROUP BY v.id, v.business_name, v.profile_image_url, v.is_online, v.rating, v.city
  ORDER BY v.is_online DESC NULLS LAST, v.rating DESC NULLS LAST, v.business_name;
$$;

GRANT EXECUTE ON FUNCTION public.get_instahelp_vendors_by_location(FLOAT8, FLOAT8)
  TO anon, authenticated;

-- ── 3. get_vcs_categories ─────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_vcs_categories()
RETURNS TABLE (
  id           UUID,
  name         TEXT,
  slug         TEXT,
  icon_key     TEXT,
  image_url    TEXT,
  sort_order   INTEGER,
  vendor_count BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    vc.id,
    vc.name,
    NULL::TEXT  AS slug,
    NULL::TEXT  AS icon_key,
    vc.icon_url AS image_url,
    0::INTEGER  AS sort_order,
    COUNT(DISTINCT vsr.vendor_id) AS vendor_count
  FROM public.vendor_categories vc
  JOIN public.vendor_service_requests vsr ON vsr.vendor_category_id = vc.id
  JOIN public.vendors v                   ON v.id = vsr.vendor_id
  WHERE vsr.request_type = 'new_service'
    AND vsr.status       = 'completed'
    AND vsr.is_active    = true
    AND v.is_active      = true
    AND EXISTS (
      SELECT 1
      FROM public.vendor_subscriptions vs
      JOIN public.subscription_plans sp ON sp.id = vs.plan_id
      WHERE vs.vendor_id       = v.id
        AND vs.catalog_node_id IS NULL
        AND vs.status          = 'active'
        AND vs.expiry_date     > NOW()
        AND (sp.permissions->>'allow_vendor_catalog')::BOOLEAN = TRUE
    )
  GROUP BY vc.id, vc.name, vc.icon_url
  HAVING COUNT(DISTINCT vsr.vendor_id) > 0
  ORDER BY vendor_count DESC, vc.name ASC;
$$;

GRANT EXECUTE ON FUNCTION public.get_vcs_categories() TO anon, authenticated;

-- ── 4. get_vcs_vendors ────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.get_vcs_vendors(UUID, FLOAT8, FLOAT8);

CREATE FUNCTION public.get_vcs_vendors(
  p_category_id UUID   DEFAULT NULL,
  p_lat         FLOAT8 DEFAULT NULL,
  p_lng         FLOAT8 DEFAULT NULL
)
RETURNS TABLE (
  id                UUID,
  business_name     TEXT,
  rating            NUMERIC,
  profile_image_url TEXT,
  is_online         BOOLEAN,
  service_count     BIGINT,
  city              TEXT,
  total_reviews     BIGINT,
  min_service_price NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    v.id,
    v.business_name,
    v.rating::NUMERIC                 AS rating,
    v.profile_image_url,
    v.is_online,
    COUNT(DISTINCT vsr.id)            AS service_count,
    v.city,
    (
      SELECT COALESCE(SUM(r.review_count), 0)
      FROM   public.vendor_service_requests r
      WHERE  r.vendor_id    = v.id
        AND  r.request_type = 'new_service'
        AND  r.status       = 'completed'
        AND  r.is_active    = true
    )::BIGINT                         AS total_reviews,
    MIN(vsr.active_price)             AS min_service_price
  FROM public.vendors v
  JOIN public.vendor_service_requests vsr ON vsr.vendor_id = v.id
  WHERE (p_category_id IS NULL OR vsr.vendor_category_id = p_category_id)
    AND vsr.request_type   = 'new_service'
    AND vsr.status         = 'completed'
    AND vsr.is_active      = true
    AND v.is_active        = true
    AND EXISTS (
      SELECT 1
      FROM public.vendor_subscriptions vs
      JOIN public.subscription_plans sp ON sp.id = vs.plan_id
      WHERE vs.vendor_id       = v.id
        AND vs.catalog_node_id IS NULL
        AND vs.status          = 'active'
        AND vs.expiry_date     > NOW()
        AND (sp.permissions->>'allow_vendor_catalog')::BOOLEAN = TRUE
    )
    AND (
      p_lat IS NULL
      OR p_lng IS NULL
      OR EXISTS (
        SELECT 1
        FROM   public.vendor_serving_area_assignments vsaa
        JOIN   public.vendor_serving_areas vsa ON vsa.id = vsaa.serving_area_id
        WHERE  vsaa.vendor_id = v.id
          AND  vsa.is_active  = true
          AND  (
            2.0 * 6371.0 * asin(sqrt(
              power(sin(radians((vsa.latitude  - p_lat) / 2.0)), 2) +
              cos(radians(p_lat)) * cos(radians(vsa.latitude)) *
              power(sin(radians((vsa.longitude - p_lng) / 2.0)), 2)
            ))
          ) <= vsa.radius_km
      )
    )
  GROUP BY v.id, v.business_name, v.rating, v.profile_image_url, v.is_online, v.city
  ORDER BY v.rating DESC NULLS LAST, v.business_name ASC;
$$;

GRANT EXECUTE ON FUNCTION public.get_vcs_vendors(UUID, FLOAT8, FLOAT8) TO anon, authenticated;

-- ── 5. get_vcs_vendor_service_names ──────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_vcs_vendor_service_names(p_category_id UUID)
RETURNS TABLE (
  vendor_id    UUID,
  service_name TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT DISTINCT
    vsr.vendor_id,
    vsr.service_name
  FROM public.vendor_service_requests vsr
  JOIN public.vendors v ON v.id = vsr.vendor_id
  WHERE vsr.vendor_category_id = p_category_id
    AND vsr.request_type       = 'new_service'
    AND vsr.status             = 'completed'
    AND vsr.is_active          = true
    AND v.is_active            = true
    AND EXISTS (
      SELECT 1
      FROM public.vendor_subscriptions vs
      JOIN public.subscription_plans sp ON sp.id = vs.plan_id
      WHERE vs.vendor_id       = v.id
        AND vs.catalog_node_id IS NULL
        AND vs.status          = 'active'
        AND vs.expiry_date     > NOW()
        AND (sp.permissions->>'allow_vendor_catalog')::BOOLEAN = TRUE
    )
  ORDER BY vsr.service_name;
$$;

GRANT EXECUTE ON FUNCTION public.get_vcs_vendor_service_names(UUID) TO anon, authenticated;

-- ── 6. search_vendor_custom_services ─────────────────────────────────────────

DROP FUNCTION IF EXISTS public.search_vendor_custom_services(TEXT);

CREATE FUNCTION public.search_vendor_custom_services(p_query TEXT)
RETURNS TABLE (
  id                 UUID,
  service_name       TEXT,
  description        TEXT,
  price              NUMERIC,
  active_price       NUMERIC,
  discount_type      TEXT,
  discount_value     NUMERIC,
  image_url          TEXT,
  vendor_id          UUID,
  vendor_name        TEXT,
  rating             NUMERIC,
  review_count       INTEGER,
  included_items     JSONB,
  excluded_items     JSONB,
  before_after_pairs JSONB,
  vendor_category_id UUID,
  pricing_type       TEXT,
  price_per_minute   NUMERIC,
  duration_minutes   INTEGER
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    vsr.id,
    vsr.service_name,
    vsr.description,
    vsr.price,
    vsr.active_price,
    vsr.discount_type,
    vsr.discount_value,
    vsr.image_url,
    vsr.vendor_id,
    v.business_name      AS vendor_name,
    vsr.rating,
    vsr.review_count,
    vsr.included_items,
    vsr.excluded_items,
    vsr.before_after_pairs,
    vsr.vendor_category_id,
    vsr.pricing_type,
    vsr.price_per_minute,
    vsr.duration_minutes
  FROM public.vendor_service_requests vsr
  JOIN public.vendors v ON v.id = vsr.vendor_id
  WHERE vsr.request_type = 'new_service'
    AND vsr.status       = 'completed'
    AND vsr.is_active    = true
    AND v.is_active      = true
    AND EXISTS (
      SELECT 1
      FROM public.vendor_subscriptions vs
      JOIN public.subscription_plans sp ON sp.id = vs.plan_id
      WHERE vs.vendor_id       = v.id
        AND vs.catalog_node_id IS NULL
        AND vs.status          = 'active'
        AND vs.expiry_date     > NOW()
        AND (sp.permissions->>'allow_vendor_catalog')::BOOLEAN = TRUE
    )
    AND (
      vsr.service_name   ILIKE '%' || p_query || '%'
      OR vsr.description ILIKE '%' || p_query || '%'
    )
  ORDER BY vsr.service_name
  LIMIT 50;
$$;

GRANT EXECUTE ON FUNCTION public.search_vendor_custom_services(TEXT) TO anon, authenticated;
