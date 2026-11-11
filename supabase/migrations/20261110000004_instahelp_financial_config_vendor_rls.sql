-- Allow vendors to manage the financial config for their own InstaHelp modes.
-- The join through instahelp_modes confirms ownership (m.vendor_id = v.id).

CREATE POLICY "instahelp_fc_vendor_write"
  ON public.instahelp_financial_config
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.instahelp_modes m
      JOIN public.vendors v ON v.auth_user_id = auth.uid()
      WHERE m.id = instahelp_financial_config.mode_id
        AND m.vendor_id = v.id
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.instahelp_modes m
      JOIN public.vendors v ON v.auth_user_id = auth.uid()
      WHERE m.id = instahelp_financial_config.mode_id
        AND m.vendor_id = v.id
    )
  );
