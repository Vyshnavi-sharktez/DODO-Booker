import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// Generates a 14-character cryptographically random temporary password.
// Uses a character set that avoids visually ambiguous characters (0/O, 1/l/I).
function generateTempPassword(): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789!@#";
  const bytes = crypto.getRandomValues(new Uint8Array(14));
  return Array.from(bytes, (b) => chars[b % chars.length]).join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

    // Verify the caller has a valid session
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "Unauthorized" }, 401);

    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const {
      data: { user: caller },
    } = await callerClient.auth.getUser();
    if (!caller) return json({ error: "Unauthorized" }, 401);

    // Service-role client for admin operations
    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    // Verify the caller is an active admin (prevents non-admins from calling this)
    const { data: callerAdmin } = await adminClient
      .from("admin_users")
      .select("id, is_super_admin, is_active")
      .eq("auth_user_id", caller.id)
      .eq("is_active", true)
      .maybeSingle();

    if (!callerAdmin) return json({ error: "Forbidden" }, 403);

    const body = await req.json();
    const {
      full_name,
      email,
      phone,
      address,
      latitude,
      longitude,
      role_id,
    } = body as {
      full_name: string;
      email: string;
      phone?: string;
      address?: string;
      latitude?: number;
      longitude?: number;
      role_id?: string;
    };

    if (!full_name?.trim() || !email?.trim()) {
      return json({ error: "full_name and email are required" }, 400);
    }

    const normalizedEmail = email.toLowerCase().trim();

    // Duplicate-email guard
    const { data: existing } = await adminClient
      .from("admin_users")
      .select("id")
      .eq("email", normalizedEmail)
      .maybeSingle();

    if (existing) {
      return json(
        { error: "An admin account with this email already exists" },
        409
      );
    }

    // Create the auth user directly with a generated temporary password.
    // Using createUser (not inviteUserByEmail) because:
    //   1. inviteUserByEmail requires SMTP to be configured.
    //   2. inviteUserByEmail applies stricter email validation in GoTrue v2.197+,
    //      rejecting role-prefixed addresses (admin@, info@, support@, etc.).
    //   3. createUser accepts any syntactically valid email.
    const tempPassword = generateTempPassword();
    const { data: authData, error: authError } =
      await adminClient.auth.admin.createUser({
        email: normalizedEmail,
        password: tempPassword,
        email_confirm: true,
        user_metadata: { full_name: full_name.trim() },
      });

    if (authError || !authData?.user) {
      return json(
        { error: authError?.message ?? "Failed to create auth account" },
        500
      );
    }

    const authUserId = authData.user.id;

    // Insert admin_users profile row
    const profileRow: Record<string, unknown> = {
      auth_user_id: authUserId,
      full_name: full_name.trim(),
      email: normalizedEmail,
      is_active: true,
      is_super_admin: false,
    };
    if (phone?.trim()) profileRow.phone = phone.trim();
    if (address?.trim()) profileRow.address = address.trim();
    if (latitude != null) profileRow.latitude = latitude;
    if (longitude != null) profileRow.longitude = longitude;

    const { data: adminRow, error: insertError } = await adminClient
      .from("admin_users")
      .insert(profileRow)
      .select("id")
      .single();

    if (insertError || !adminRow) {
      // Rollback: delete the auth user so no orphaned account is left
      await adminClient.auth.admin.deleteUser(authUserId);
      return json(
        { error: insertError?.message ?? "Failed to create admin profile" },
        500
      );
    }

    // Assign role if provided
    if (role_id) {
      const { error: roleError } = await adminClient
        .from("admin_user_roles")
        .insert({ admin_user_id: adminRow.id, role_id });

      if (roleError) {
        // Non-fatal: user is created; role can be assigned later
        console.warn("Role assignment failed:", roleError.message);
      }
    }

    return json({
      success: true,
      admin_user_id: adminRow.id,
      temp_password: tempPassword,
    });
  } catch (err) {
    console.error("create-admin-user error:", err);
    return json({ error: String(err) }, 500);
  }
});
