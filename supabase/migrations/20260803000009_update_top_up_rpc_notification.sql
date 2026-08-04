-- ─────────────────────────────────────────────────────────────────────────────
-- Update admin_top_up_vendor_wallet() RPC to ensure vendor_wallets exists and send notification
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION admin_top_up_vendor_wallet(
  p_vendor_id   UUID,
  p_amount      NUMERIC,
  p_description TEXT  DEFAULT NULL,
  p_admin_id    UUID  DEFAULT NULL
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_new_balance    NUMERIC;
  v_transaction_id UUID;
  v_desc           TEXT;
BEGIN
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Top-up amount must be positive';
  END IF;

  v_desc := COALESCE(NULLIF(TRIM(p_description), ''), 'Wallet Top-Up');

  -- Ensure vendor_wallets row exists
  INSERT INTO vendor_wallets (vendor_id, available_balance)
  VALUES (p_vendor_id, 0)
  ON CONFLICT (vendor_id) DO NOTHING;

  UPDATE vendor_wallets
     SET available_balance = available_balance + p_amount,
         updated_at        = now()
   WHERE vendor_id = p_vendor_id
  RETURNING available_balance INTO v_new_balance;

  INSERT INTO wallet_transactions (
    vendor_id, type, amount, balance_after,
    reference_type, description, created_by
  ) VALUES (
    p_vendor_id, 'top_up', p_amount, v_new_balance,
    'manual', v_desc, p_admin_id
  )
  RETURNING id INTO v_transaction_id;

  -- Send vendor notification for wallet top-up
  INSERT INTO notifications (
    user_type, user_id, title, message, notification_type, entity_type, entity_id, is_read, created_at
  ) VALUES (
    'vendor',
    p_vendor_id,
    'Wallet Top-Up Successful',
    'Your wallet has been credited with ₹' || TRIM(TO_CHAR(p_amount, '999999990.00')) || '. New balance: ₹' || TRIM(TO_CHAR(v_new_balance, '999999990.00')) || '.',
    'wallet_alert',
    'vendor_wallet',
    v_transaction_id,
    false,
    now()
  );

  RETURN v_transaction_id;
END;
$$;
