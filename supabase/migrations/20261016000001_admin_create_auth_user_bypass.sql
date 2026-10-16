-- Allows the create-admin-user edge function to directly insert an auth user
-- when GoTrue's email validator rejects syntactically valid addresses
-- (e.g. role prefixes like admin@, info@, support@).
-- Only callable by service_role; revoked from public and authenticated.

CREATE OR REPLACE FUNCTION public.admin_create_auth_user_bypass(
  p_user_id   uuid,
  p_email     text,
  p_password  text,
  p_full_name text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = auth, extensions, public
AS $$
BEGIN
  INSERT INTO auth.users (
    id,
    instance_id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    invited_at,
    confirmation_token,
    confirmation_sent_at,
    recovery_token,
    recovery_sent_at,
    email_change_token_new,
    email_change,
    email_change_sent_at,
    last_sign_in_at,
    raw_app_meta_data,
    raw_user_meta_data,
    is_super_admin,
    created_at,
    updated_at,
    phone,
    phone_confirmed_at,
    phone_change,
    phone_change_token,
    phone_change_sent_at,
    email_change_token_current,
    email_change_confirm_status,
    banned_until,
    reauthentication_token,
    reauthentication_sent_at,
    is_sso_user,
    deleted_at
  ) VALUES (
    p_user_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    p_email,
    crypt(p_password, gen_salt('bf', 10)),
    now(),    -- email_confirmed_at: mark as confirmed
    null,     -- invited_at
    '',       -- confirmation_token
    null,     -- confirmation_sent_at
    '',       -- recovery_token
    null,     -- recovery_sent_at
    '',       -- email_change_token_new
    '',       -- email_change
    null,     -- email_change_sent_at
    null,     -- last_sign_in_at
    '{"provider":"email","providers":["email"]}',
    jsonb_build_object('full_name', p_full_name),
    false,    -- is_super_admin
    now(),    -- created_at
    now(),    -- updated_at
    null,     -- phone
    null,     -- phone_confirmed_at
    '',       -- phone_change
    '',       -- phone_change_token
    null,     -- phone_change_sent_at
    '',       -- email_change_token_current
    0,        -- email_change_confirm_status
    null,     -- banned_until
    '',       -- reauthentication_token
    null,     -- reauthentication_sent_at
    false,    -- is_sso_user
    null      -- deleted_at
  );

  -- Create the matching identity row so signInWithPassword works
  INSERT INTO auth.identities (
    id,
    provider_id,
    user_id,
    identity_data,
    provider,
    last_sign_in_at,
    created_at,
    updated_at
  ) VALUES (
    gen_random_uuid(),
    p_email,
    p_user_id,
    jsonb_build_object('sub', p_user_id::text, 'email', p_email),
    'email',
    null,
    now(),
    now()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_create_auth_user_bypass(uuid, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_create_auth_user_bypass(uuid, text, text, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.admin_create_auth_user_bypass(uuid, text, text, text) TO service_role;
