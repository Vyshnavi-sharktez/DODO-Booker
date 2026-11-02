DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND tablename = 'vendor_settlements'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE vendor_settlements;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND tablename = 'vendor_settlement_bookings'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE vendor_settlement_bookings;
  END IF;
END $$;
