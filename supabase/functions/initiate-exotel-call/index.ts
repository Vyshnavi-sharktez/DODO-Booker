import { createClient } from "npm:@supabase/supabase-js@^2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const ALLOWED_VENDOR_STATUSES = ["accepted", "en_route", "in_progress"];
const ALLOWED_CUSTOMER_STATUSES = ["accepted", "en_route", "in_progress"];

// Exotel status → our DB status
const EXOTEL_STATUS_MAP: Record<string, string> = {
  initiated: "initiated",
  ringing: "ringing",
  answered: "connected",
  "in-progress": "connected",
  completed: "ended",
  busy: "failed",
  failed: "failed",
  "no-answer": "missed",
  canceled: "missed",
};

function normalisePhone(phone: string | null | undefined): string | null {
  if (!phone) return null;
  const cleaned = phone.replace(/\s/g, "");
  // Accept E.164 (starts with +) or plain digits
  if (/^\+\d{7,15}$/.test(cleaned)) return cleaned;
  if (/^\d{7,15}$/.test(cleaned)) return `+${cleaned}`;
  return null;
}

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

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return json({ error: "Missing authorization" }, 401);
  }

  const serviceClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });

  // Verify JWT and get user
  const userClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
    global: { headers: { Authorization: authHeader } },
  });

  const {
    data: { user },
    error: authError,
  } = await userClient.auth.getUser();
  if (authError || !user) {
    return json({ error: "Unauthorized" }, 401);
  }

  const body = await req.json().catch(() => ({}));
  const bookingId: string | undefined = body.booking_id;
  const callerRole: string = body.caller_role ?? "vendor";

  if (!bookingId) {
    return json({ error: "booking_id is required" }, 400);
  }

  // ── Load call provider config ─────────────────────────────────────────────
  const { data: config, error: configError } = await serviceClient
    .from("call_provider_configs")
    .select("is_enabled, account_sid, exophone, record_calls, call_timeout_seconds")
    .eq("provider", "exotel")
    .single();

  if (configError || !config) {
    return json({ error: "Call provider not configured" }, 503);
  }
  if (!config.is_enabled) {
    return json({ error: "Calling is currently disabled" }, 503);
  }
  if (!config.account_sid || !config.exophone) {
    return json({ error: "Exotel account_sid and exophone must be configured" }, 503);
  }

  // ── Load Exotel secrets ───────────────────────────────────────────────────
  const { data: apiKey, error: keyError } = await serviceClient.rpc(
    "get_call_secret_value",
    { p_provider: "exotel", p_secret_name: "api_key" }
  );
  const { data: apiToken, error: tokenError } = await serviceClient.rpc(
    "get_call_secret_value",
    { p_provider: "exotel", p_secret_name: "api_token" }
  );

  if (keyError || tokenError || !apiKey || !apiToken) {
    return json({ error: "Exotel API credentials not configured" }, 503);
  }

  // Load webhook token so the StatusCallback URL is authenticated.
  // If not yet configured, the call is still placed but callbacks will be
  // rejected by exotel-webhook until the token is set via the admin UI.
  const { data: webhookToken } = await serviceClient.rpc(
    "get_call_secret_value",
    { p_provider: "exotel", p_secret_name: "webhook_token" }
  );
  if (!webhookToken) {
    console.warn(
      "initiate-exotel-call: webhook_token not configured — " +
      "StatusCallback will not be authenticated until the token is set."
    );
  }

  // ── Resolve caller identity and booking eligibility ───────────────────────
  let callerAuthUserId = user.id;
  let callerDbId: string | null = null;
  let calleeDbId: string | null = null;
  let callerPhone: string | null = null;
  let calleePhone: string | null = null;

  // Load booking
  const { data: booking, error: bookingError } = await serviceClient
    .from("bookings")
    .select("id, status, vendor_id, customer_id")
    .eq("id", bookingId)
    .single();

  if (bookingError || !booking) {
    return json({ error: "Booking not found" }, 404);
  }

  if (callerRole === "vendor") {
    // Find vendor record
    const { data: vendor } = await serviceClient
      .from("vendors")
      .select("id")
      .eq("auth_user_id", callerAuthUserId)
      .single();

    if (!vendor) {
      return json({ error: "Vendor record not found" }, 403);
    }
    if (vendor.id !== booking.vendor_id) {
      return json({ error: "You are not assigned to this booking" }, 403);
    }
    if (!ALLOWED_VENDOR_STATUSES.includes(booking.status)) {
      return json(
        {
          error:
            "Calling is only available after you accept the booking. Current status: " +
            booking.status,
        },
        422
      );
    }

    callerDbId = vendor.id;

    // Vendor phone from auth.users
    const { data: vendorAuthUser } = await serviceClient.auth.admin.getUserById(
      callerAuthUserId
    );
    callerPhone = normalisePhone(vendorAuthUser?.user?.phone);

    // Customer phone via customer record
    const { data: customer } = await serviceClient
      .from("customers")
      .select("id, auth_user_id")
      .eq("id", booking.customer_id)
      .single();

    if (customer?.auth_user_id) {
      const { data: custAuthUser } =
        await serviceClient.auth.admin.getUserById(customer.auth_user_id);
      calleePhone = normalisePhone(custAuthUser?.user?.phone);
      calleeDbId = customer.id;
    }
  } else if (callerRole === "customer") {
    // Find customer record
    const { data: customer } = await serviceClient
      .from("customers")
      .select("id")
      .eq("auth_user_id", callerAuthUserId)
      .single();

    if (!customer) {
      return json({ error: "Customer record not found" }, 403);
    }
    if (customer.id !== booking.customer_id) {
      return json({ error: "This booking does not belong to you" }, 403);
    }
    if (!ALLOWED_CUSTOMER_STATUSES.includes(booking.status)) {
      return json(
        {
          error:
            "Calling is only available for accepted or in-progress bookings. Current status: " +
            booking.status,
        },
        422
      );
    }

    callerDbId = customer.id;

    // Customer phone
    const { data: custAuthUser } = await serviceClient.auth.admin.getUserById(
      callerAuthUserId
    );
    callerPhone = normalisePhone(custAuthUser?.user?.phone);

    // Vendor phone
    if (booking.vendor_id) {
      const { data: vendor } = await serviceClient
        .from("vendors")
        .select("id, auth_user_id")
        .eq("id", booking.vendor_id)
        .single();

      if (vendor?.auth_user_id) {
        const { data: vendorAuthUser } =
          await serviceClient.auth.admin.getUserById(vendor.auth_user_id);
        calleePhone = normalisePhone(vendorAuthUser?.user?.phone);
        calleeDbId = vendor.id;
      }
    }
  } else {
    return json({ error: "Invalid caller_role" }, 400);
  }

  if (!callerPhone) {
    return json({ error: "Your account does not have a verified phone number" }, 422);
  }
  if (!calleePhone) {
    return json({ error: "The other party does not have a verified phone number" }, 422);
  }

  // ── Create call_session record (initiated state) ──────────────────────────
  const { data: sessionRow, error: sessionInsertError } = await serviceClient
    .from("call_sessions")
    .insert({
      booking_id: bookingId,
      caller_id: callerDbId,
      callee_id: calleeDbId,
      caller_role: callerRole,
      virtual_number: config.exophone,
      status: "initiated",
      initiated_at: new Date().toISOString(),
    })
    .select()
    .single();

  if (sessionInsertError || !sessionRow) {
    console.error("Failed to create call_session:", sessionInsertError);
    return json({ error: "Failed to create call session" }, 500);
  }

  const sessionId: string = sessionRow.id;

  // ── Call Exotel Connect API ───────────────────────────────────────────────
  // Webhook URL so Exotel can update our call session on status changes.
  // The token query parameter authenticates the callback against the vault secret.
  const baseWebhookUrl = `${SUPABASE_URL}/functions/v1/exotel-webhook`;
  const webhookUrl = webhookToken
    ? `${baseWebhookUrl}?token=${encodeURIComponent(webhookToken as string)}`
    : baseWebhookUrl;

  const exotelUrl = `https://api.exotel.com/v1/Accounts/${config.account_sid}/Calls/connect.json`;
  const credentials = btoa(`${apiKey}:${apiToken}`);

  const formData = new URLSearchParams();
  formData.set("From", callerPhone);
  formData.set("To", calleePhone);
  formData.set("CallerId", config.exophone);
  formData.set("TimeOut", String(config.call_timeout_seconds ?? 30));
  formData.set("TimeLimit", "3600");
  if (config.record_calls) {
    formData.set("Record", "true");
    formData.set("RecordingChannels", "dual");
  }
  formData.set("StatusCallback", webhookUrl);
  formData.set("StatusCallbackMethod", "POST");
  // Pass session ID so webhook can correlate
  formData.set("CustomField", sessionId);

  let exotelCallSid: string | null = null;

  try {
    const exotelRes = await fetch(exotelUrl, {
      method: "POST",
      headers: {
        Authorization: `Basic ${credentials}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: formData.toString(),
    });

    const exotelBody = await exotelRes.json().catch(() => ({}));

    if (!exotelRes.ok) {
      console.error("Exotel API error:", exotelRes.status, exotelBody);
      // Mark session failed
      await serviceClient
        .from("call_sessions")
        .update({ status: "failed", ended_at: new Date().toISOString() })
        .eq("id", sessionId);

      return json({ error: "Exotel call initiation failed", details: exotelBody }, 502);
    }

    exotelCallSid = exotelBody?.Call?.Sid ?? null;

    // Update session with Exotel call SID
    if (exotelCallSid) {
      await serviceClient
        .from("call_sessions")
        .update({ exotel_call_sid: exotelCallSid, status: "ringing" })
        .eq("id", sessionId);
    }
  } catch (err) {
    console.error("Exotel fetch error:", err);
    await serviceClient
      .from("call_sessions")
      .update({ status: "failed", ended_at: new Date().toISOString() })
      .eq("id", sessionId);
    return json({ error: "Failed to reach Exotel API" }, 502);
  }

  return json(
    {
      session_id: sessionId,
      exotel_call_sid: exotelCallSid,
      virtual_number: config.exophone,
      note: "Exotel will call your registered phone number. Answer it to connect to the other party.",
    },
    200
  );
});
