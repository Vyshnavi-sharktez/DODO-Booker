-- ─────────────────────────────────────────────────────────────────────────────
-- Vendor Service Requests
-- Vendors submit new-service proposals; admin reviews, approves, or rejects.
-- ─────────────────────────────────────────────────────────────────────────────

-- Storage bucket for request images (public read, vendor-scoped write)
INSERT INTO storage.buckets (id, name, public)
VALUES ('vendor-requests', 'vendor-requests', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "vsr_vendor_upload" ON storage.objects;
CREATE POLICY "vsr_vendor_upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'vendor-requests'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "vsr_public_read" ON storage.objects;
CREATE POLICY "vsr_public_read" ON storage.objects
  FOR SELECT TO public
  USING (bucket_id = 'vendor-requests');

-- ── Table ─────────────────────────────────────────────────────────────────────

CREATE TABLE vendor_service_requests (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor_id        UUID NOT NULL REFERENCES vendors(id) ON DELETE CASCADE,
  service_name     TEXT NOT NULL,
  description      TEXT,
  price            NUMERIC(10,2),
  image_url        TEXT,
  status           TEXT NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending', 'approved', 'rejected')),
  rejection_reason TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- updated_at auto-stamp
CREATE OR REPLACE FUNCTION fn_vsr_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

CREATE TRIGGER trg_vsr_updated_at
  BEFORE UPDATE ON vendor_service_requests
  FOR EACH ROW EXECUTE FUNCTION fn_vsr_set_updated_at();

-- ── RLS ───────────────────────────────────────────────────────────────────────

ALTER TABLE vendor_service_requests ENABLE ROW LEVEL SECURITY;

-- Vendors: insert own requests
CREATE POLICY "vsr_vendor_insert" ON vendor_service_requests
  FOR INSERT TO authenticated
  WITH CHECK (vendor_id = auth.uid());

-- Vendors + admins: select (vendors see own; admins see all)
CREATE POLICY "vsr_select" ON vendor_service_requests
  FOR SELECT TO authenticated
  USING (
    vendor_id = auth.uid()
    OR EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid())
  );

-- Admins only: update (status + rejection_reason)
CREATE POLICY "vsr_admin_update" ON vendor_service_requests
  FOR UPDATE TO authenticated
  USING (EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid()));

-- ── Admin notification trigger (AFTER INSERT) ─────────────────────────────────

CREATE OR REPLACE FUNCTION fn_notify_admin_vendor_service_request()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_vendor_name TEXT;
BEGIN
  SELECT COALESCE(NULLIF(TRIM(business_name), ''), 'A vendor')
  INTO v_vendor_name
  FROM vendors WHERE id = NEW.vendor_id;

  INSERT INTO notifications (
    user_type, user_id,
    title, message,
    notification_type, entity_type, entity_id,
    is_read, created_at
  ) VALUES (
    'admin', NULL,
    'New Service Request',
    COALESCE(v_vendor_name, 'A vendor') || ' requested a new service: "' || NEW.service_name || '".',
    'vendor_service_request', 'vendor_service_request', NEW.id,
    FALSE, NOW()
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_admin_vendor_service_request ON vendor_service_requests;
CREATE TRIGGER trg_notify_admin_vendor_service_request
  AFTER INSERT ON vendor_service_requests
  FOR EACH ROW EXECUTE FUNCTION fn_notify_admin_vendor_service_request();

-- ── Vendor notification trigger (AFTER UPDATE — status change only) ───────────

CREATE OR REPLACE FUNCTION fn_notify_vendor_service_request_status()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  IF OLD.status = NEW.status THEN RETURN NEW; END IF;

  IF NEW.status = 'approved' THEN
    INSERT INTO notifications (
      user_type, user_id,
      title, message,
      notification_type, entity_type, entity_id,
      is_read, created_at
    ) VALUES (
      'vendor', NEW.vendor_id,
      'Service Request Approved',
      'Your request for "' || NEW.service_name || '" has been approved.',
      'vendor_service_request', 'vendor_service_request', NEW.id,
      FALSE, NOW()
    );
  ELSIF NEW.status = 'rejected' THEN
    INSERT INTO notifications (
      user_type, user_id,
      title, message,
      notification_type, entity_type, entity_id,
      is_read, created_at
    ) VALUES (
      'vendor', NEW.vendor_id,
      'Service Request Not Approved',
      'Your request for "' || NEW.service_name || '" was not approved.'
        || CASE
             WHEN NEW.rejection_reason IS NOT NULL
              AND TRIM(NEW.rejection_reason) <> ''
             THEN ' Reason: ' || TRIM(NEW.rejection_reason)
             ELSE ''
           END,
      'vendor_service_request', 'vendor_service_request', NEW.id,
      FALSE, NOW()
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_vendor_service_request_status ON vendor_service_requests;
CREATE TRIGGER trg_notify_vendor_service_request_status
  AFTER UPDATE ON vendor_service_requests
  FOR EACH ROW EXECUTE FUNCTION fn_notify_vendor_service_request_status();
