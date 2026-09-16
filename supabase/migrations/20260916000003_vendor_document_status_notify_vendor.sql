-- Vendor notification when admin approves or rejects a document.
--
-- Fires: AFTER UPDATE OF verification_status on vendor_documents
--        only when the status actually changes to 'approved' or 'rejected'.
--
-- notification_type : 'document_approved' | 'document_rejected'
-- entity_type       : 'vendor_document'
-- entity_id         : vendor_documents.id  (specific document record)
-- user_type         : 'vendor'
-- user_id           : vendor_documents.vendor_id
--
-- Duplicate prevention: skips if an unread notification for the same
-- document + same status already exists.

CREATE OR REPLACE FUNCTION fn_notify_vendor_document_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_doc_label  TEXT;
  v_notif_type TEXT;
  v_title      TEXT;
  v_message    TEXT;
BEGIN
  -- Only act when the status column actually changed.
  IF OLD.verification_status IS NOT DISTINCT FROM NEW.verification_status THEN
    RETURN NEW;
  END IF;

  -- Only notify on terminal admin decisions.
  IF NEW.verification_status NOT IN ('approved', 'rejected') THEN
    RETURN NEW;
  END IF;

  v_notif_type := CASE NEW.verification_status
                    WHEN 'approved' THEN 'document_approved'
                    ELSE                 'document_rejected'
                  END;

  v_title := CASE NEW.verification_status
               WHEN 'approved' THEN 'Document Approved'
               ELSE                 'Document Rejected'
             END;

  -- Determine a human-readable label (resilient if document_types is absent).
  IF NEW.document_type = 'other'
     AND NEW.custom_document_name IS NOT NULL
     AND TRIM(NEW.custom_document_name) <> ''
  THEN
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

  v_message := CASE NEW.verification_status
                 WHEN 'approved'
                   THEN 'Your ' || v_doc_label || ' has been approved.'
                 ELSE
                   'Your ' || v_doc_label || ' has been rejected. Please upload a new copy.'
               END;

  -- Deduplication: skip if the vendor already has an unread notification for
  -- the exact same document + same status decision.
  IF EXISTS (
    SELECT 1 FROM notifications
    WHERE  user_type         = 'vendor'
      AND  user_id           = NEW.vendor_id
      AND  notification_type = v_notif_type
      AND  entity_type       = 'vendor_document'
      AND  entity_id         = NEW.id
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
    'vendor', NEW.vendor_id,
    v_title, v_message,
    v_notif_type,
    'vendor_document', NEW.id,
    FALSE, NOW()
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_vendor_document_status ON vendor_documents;
CREATE TRIGGER trg_notify_vendor_document_status
  AFTER UPDATE OF verification_status ON vendor_documents
  FOR EACH ROW
  EXECUTE FUNCTION fn_notify_vendor_document_status();
