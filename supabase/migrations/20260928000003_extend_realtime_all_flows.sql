-- ─────────────────────────────────────────────────────────────────────────────
-- Extend Supabase Realtime publication to cover all remaining business flows.
--
-- Flows covered by this migration:
--   • Refunds        (refund_requests, refund_status_history, refund_messages)
--   • Vendor wallet  (vendor_wallets, wallet_transactions)
--   • Settlements    (vendor_settlements, vendor_settlement_bookings)
--   • Warranty       (service_warranties)
--   • Loyalty        (loyalty_transactions, customer_loyalty)
--   • Vendor docs    (vendor_documents)
--   • Customers      (customers — admin panel customer list auto-refresh)
--   • AMC plans      (amc_plans — vendor app plan browsing)
--
-- All blocks are idempotent: they check pg_publication_tables before adding,
-- so re-running this migration is safe.
-- ─────────────────────────────────────────────────────────────────────────────

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND tablename='refund_requests') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE refund_requests;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND tablename='refund_status_history') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE refund_status_history;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND tablename='refund_messages') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE refund_messages;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND tablename='vendor_wallets') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE vendor_wallets;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND tablename='wallet_transactions') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE wallet_transactions;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND tablename='vendor_settlements') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE vendor_settlements;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND tablename='vendor_settlement_bookings') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE vendor_settlement_bookings;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND tablename='service_warranties') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE service_warranties;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND tablename='loyalty_transactions') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE loyalty_transactions;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND tablename='customer_loyalty') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE customer_loyalty;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND tablename='vendor_documents') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE vendor_documents;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND tablename='customers') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE customers;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND tablename='amc_plans') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE amc_plans;
  END IF;
END $$;
