DROP VIEW IF EXISTS catalog_nodes_view;

CREATE VIEW catalog_nodes_view AS
SELECT
    n.id,
    n.parent_id,
    n.legacy_id,
    n.legacy_type,
    n.name,
    n.slug,
    n.description,
    n.image_url,
    n.icon_key,
    n.sort_order,
    n.is_active,
    n.is_bookable,
    n.base_price,
    n.estimated_duration,
    n.minimum_order_amount,
    n.created_at,
    n.updated_at,
    (
        SELECT COUNT(*)::INTEGER
        FROM catalog_nodes c
        WHERE c.parent_id = n.id
          AND c.is_active = TRUE
    ) AS children_count,
    p.name AS parent_name,
    p.slug AS parent_slug
FROM catalog_nodes n
LEFT JOIN catalog_nodes p
ON p.id = n.parent_id;