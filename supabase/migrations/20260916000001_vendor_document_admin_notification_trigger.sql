-- Admin notification trigger for vendor document upload and replacement.
--
-- Fires when:
--   INSERT on vendor_documents  → vendor submitted a new document
--   UPDATE on vendor_documents  → vendor replaced an existing document
--                                 (detected by document_url change)
--
-- entity_type = 'vendor_document'
-- entity_id   = vendor_id  (allows direct navigation to /vendors/:vendorId?tab=1)
--
-- Duplicate prevention: if an unread notification already exists for the same
-- vendor's documents, a new one is not created.  Once the admin opens (reads)
-- the notification a fresh one can be generated on the next upload.

CREATE OR REPLACE FUNCTION fn_notify_admin_vendor_document()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_vendor_name TEXT;
  v_doc_label   TEXT;
  v_action      TEXT;
  v_title       TEXT;
BEGIN
  -- On UPDATE, only notify when the actual file was replaced (URL changed).
  -- This prevents triggering when admin changes verification_status only.
  IF TG_OP = 'UPDATE' AND OLD.document_url IS NOT DISTINCT FROM NEW.document_url THEN
    RETURN NEW;
  END IF;

  -- Fetch the vendor's business name for a readable message.
  SELECT COALESCE(NULLIF(TRIM(business_name), ''), NULLIF(TRIM(phone), ''), 'A vendor')
  INTO   v_vendor_name
  FROM   vendors
  WHERE  id = NEW.vendor_id;
  v_vendor_name := COALESCE(v_vendor_name, 'A vendor');

  -- Determine a human-readable document label.
  -- The SELECT is wrapped in a nested block so that a missing document_types
  -- table (migration not yet applied) never aborts the parent transaction.
  IF NEW.document_type = 'other' AND NEW.custom_document_name IS NOT NULL AND TRIM(NEW.custom_document_name) <> '' THEN
    v_doc_label := TRIM(NEW.custom_document_name);
  ELSE
    BEGIN
      SELECT COALESCE(NULLIF(TRIM(label), ''), NEW.document_type)
      INTO   v_doc_label
      FROM   document_types
      WHERE  id = NEW.document_type;
    EXCEPTION WHEN undefined_table THEN
      v_doc_label := NULL;
    END;
    v_doc_label := COALESCE(v_doc_label, NEW.document_type);
  END IF;

  v_action := CASE WHEN TG_OP = 'INSERT' THEN 'submitted' ELSE 'replaced' END;
  v_title  := CASE WHEN TG_OP = 'INSERT' THEN 'Document Submitted' ELSE 'Document Replaced' END;

  -- Deduplication: skip if there is already an unread notification for this
  -- vendor's documents (one pending review signal per vendor at a time).
  IF EXISTS (
    SELECT 1 FROM notifications
    WHERE  user_type         = 'admin'
      AND  notification_type = 'vendor_document_submitted'
      AND  entity_type       = 'vendor_document'
      AND  entity_id         = NEW.vendor_id
      AND  is_read           = FALSE
  ) THEN
    RETURN NEW;
  END IF;

  INSERT INTO notifications (
    user_type, user_id,
    title, message,
    notification_type, entity_type, entity_id,
    is_read, created_at
  ) VALUES (
    'admin', NULL,
    v_title,
    v_vendor_name || ' has ' || v_action || ' ' || v_doc_label || ' for review.',
    'vendor_document_submitted',
    'vendor_document',
    NEW.vendor_id,
    FALSE,
    NOW()
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_admin_vendor_document ON vendor_documents;
CREATE TRIGGER trg_notify_admin_vendor_document
  AFTER INSERT OR UPDATE ON vendor_documents
  FOR EACH ROW
  EXECUTE FUNCTION fn_notify_admin_vendor_document();
