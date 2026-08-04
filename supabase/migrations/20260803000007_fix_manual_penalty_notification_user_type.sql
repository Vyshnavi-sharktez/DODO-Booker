-- ─────────────────────────────────────────────────────────────────────────────
-- Fix: Ensure user_type = 'vendor' and user_id = p_vendor_id in admin_apply_manual_penalty()
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION admin_apply_manual_penalty(
  p_vendor_id   UUID,
  p_amount      NUMERIC,
  p_reason      TEXT,
  p_admin_id    UUID DEFAULT NULL
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_new_balance    NUMERIC;
  v_transaction_id UUID;
  v_trimmed_reason TEXT;
BEGIN
  v_trimmed_reason := TRIM(COALESCE(p_reason, ''));

  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Penalty amount must be positive';
  END IF;

  IF v_trimmed_reason = '' THEN
    RAISE EXCEPTION 'A valid reason is required for applying a manual penalty';
  END IF;

  UPDATE vendor_wallets
     SET available_balance = available_balance - p_amount,
         updated_at        = now()
   WHERE vendor_id = p_vendor_id
  RETURNING available_balance INTO v_new_balance;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Wallet not found for vendor %', p_vendor_id;
  END IF;

  INSERT INTO wallet_transactions (
    vendor_id, type, amount, balance_after,
    reference_type, description, created_by
  ) VALUES (
    p_vendor_id, 'penalty', p_amount, v_new_balance,
    'manual', v_trimmed_reason, p_admin_id
  )
  RETURNING id INTO v_transaction_id;

  -- Send vendor notification with user_type = 'vendor' and user_id = p_vendor_id
  INSERT INTO notifications (
    user_type, user_id, title, message, notification_type, entity_type, entity_id, is_read, created_at
  ) VALUES (
    'vendor',
    p_vendor_id,
    'Wallet Penalty Applied',
    'A penalty of ₹' || TRIM(TO_CHAR(p_amount, '999999990.00')) || ' was charged to your wallet. Reason: ' || v_trimmed_reason,
    'wallet_penalty',
    'vendor_wallet',
    v_transaction_id,
    false,
    now()
  );

  RETURN v_transaction_id;
END;
$$;
