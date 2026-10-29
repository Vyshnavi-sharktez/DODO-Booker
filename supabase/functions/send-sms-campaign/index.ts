import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";

// ── CORS ───────────────────────────────────────────────────────────────────────

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// ── Phone normalisation ────────────────────────────────────────────────────────
// auth.users.phone is E.164 with leading + (e.g. +919876543210).
// MSG91 Flow API requires the number WITHOUT the + prefix.
function normalisePhone(raw: string): string | null {
  const stripped = raw.startsWith("+") ? raw.slice(1) : raw;
  // 7–15 digits (TRAI: Indian numbers are 10 digits + country code = 12)
  if (!/^\d{7,15}$/.test(stripped)) return null;
  return stripped;
}

// ── MSG91 Flow API ─────────────────────────────────────────────────────────────
// Uses /api/v5/flow for template-based promotional/transactional SMS.
// This is completely separate from /api/v5/otp used by the send-sms Edge Function.
//
// sent_count reflects messages submitted to MSG91, NOT confirmed delivery to handsets.
// MSG91 accepts the batch and queues delivery; actual delivery depends on DLT registration,
// DND status, network, and operator. Reported as "submitted" not "delivered".

async function sendMsg91FlowBatch(
  apiKey: string,
  flowTemplateId: string,
  normalisedPhones: string[],
): Promise<{ submitted: number; failed: number; errors: string[] }> {
  const recipients = normalisedPhones.map((p) => ({ mobiles: p }));

  let res: Response;
  try {
    res = await fetch("https://api.msg91.com/api/v5/flow", {
      method: "POST",
      redirect: "error",
      headers: {
        "authkey": apiKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        template_id: flowTemplateId,
        short_url: "0",
        realTimeResponse: "1",
        recipients,
      }),
    });
  } catch (e) {
    const msg = (e as Error).message ?? "network error";
    return {
      submitted: 0,
      failed: normalisedPhones.length,
      errors: [`Network error: ${msg}`],
    };
  }

  const resText = await res.text().catch(() => "");
  let resJson: Record<string, unknown> | null = null;
  try { resJson = JSON.parse(resText); } catch { /* non-JSON body */ }

  if (!res.ok) {
    return {
      submitted: 0,
      failed: normalisedPhones.length,
      errors: [`MSG91 HTTP ${res.status}: ${resText.slice(0, 300)}`],
    };
  }

  if (resJson?.type === "error") {
    const errMsg = String(resJson.message ?? "unknown");
    return {
      submitted: 0,
      failed: normalisedPhones.length,
      errors: [`MSG91 rejected batch: ${errMsg}`],
    };
  }

  // Batch accepted by MSG91 provider
  return { submitted: normalisedPhones.length, failed: 0, errors: [] };
}

const BATCH_SIZE = 500;

// ── Main handler ──────────────────────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

  // ── 1. Authenticate caller (admin JWT) ────────────────────────────────────────
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader) return json({ error: "Unauthorized" }, 401);

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: { user }, error: authErr } = await userClient.auth.getUser();
  if (authErr || !user) return json({ error: "Unauthorized" }, 401);

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });
  const { data: callerAdmin } = await adminClient
    .from("admin_users")
    .select("id")
    .eq("auth_user_id", user.id)
    .eq("is_active", true)
    .maybeSingle();
  if (!callerAdmin) return json({ error: "Forbidden" }, 403);

  // ── 2. Parse request ──────────────────────────────────────────────────────────
  let body: { campaign_id?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const { campaign_id } = body;
  if (!campaign_id) return json({ error: "campaign_id is required" }, 400);

  // ── 3. Atomically claim the campaign ─────────────────────────────────────────
  // UPDATE … WHERE status = 'draft' is atomic: if two concurrent calls race,
  // only one will match the WHERE clause and return a row.
  // The second call will find no rows and return a 409.
  const { data: claimed, error: claimErr } = await adminClient
    .from("campaigns")
    .update({
      status: "sending",
      updated_at: new Date().toISOString(),
    })
    .eq("id", campaign_id)
    .eq("status", "draft")
    .select("id, name, channel, template_id, is_test_mode, targeting_type, targeting_value")
    .maybeSingle();

  if (claimErr) {
    return json(
      { error: `Failed to claim campaign: ${claimErr.message}` },
      500,
    );
  }

  if (!claimed) {
    const { data: existing } = await adminClient
      .from("campaigns")
      .select("status")
      .eq("id", campaign_id)
      .maybeSingle();

    if (!existing) return json({ error: "Campaign not found" }, 404);

    return json(
      {
        error: `Campaign is in '${existing.status}' state and cannot be sent. ` +
          `Only 'draft' campaigns can be sent. ` +
          (existing.status === "failed"
            ? "Use 'Reset to Draft' to retry a failed campaign."
            : existing.status === "sending"
            ? "Another send is already in progress."
            : ""),
      },
      409,
    );
  }

  if (claimed.channel !== "sms") {
    // Wrong function — reset and reject
    await adminClient
      .from("campaigns")
      .update({ status: "draft", updated_at: new Date().toISOString() })
      .eq("id", campaign_id);
    return json(
      { error: "This function handles SMS campaigns only" },
      400,
    );
  }

  // Helper: mark campaign failed and return an error response
  const failCampaign = async (reason: string, partialSent = 0, partialFailed = 0) => {
    await adminClient.from("campaigns").update({
      status: "failed",
      sent_count: partialSent,
      failed_count: partialFailed,
      failure_summary: [{ error: reason }],
      updated_at: new Date().toISOString(),
    }).eq("id", campaign_id);
    return json({ error: reason }, 500);
  };

  // ── 4. Load MSG91 provider config ─────────────────────────────────────────────
  const { data: smsCfg } = await adminClient
    .from("sms_provider_configs")
    .select("is_enabled, extra_config")
    .eq("provider", "msg91")
    .eq("is_enabled", true)
    .maybeSingle();

  if (!smsCfg) {
    return await failCampaign(
      "MSG91 provider is not enabled. Enable it in SMS / OTP Configuration.",
    );
  }

  // ── 5. Load API key from Vault ────────────────────────────────────────────────
  const { data: apiKey, error: secretErr } = await adminClient.rpc(
    "get_sms_secret_value",
    { p_provider: "msg91", p_secret_name: "api_key" },
  );
  if (secretErr || !apiKey) {
    return await failCampaign("MSG91 API key is not configured in Vault.");
  }

  // ── 6. Resolve recipient phone numbers (service_role RPC) ─────────────────────
  // _get_campaign_phones handles test vs live mode internally.
  // In test mode it returns only the configured test_phone.
  // In live mode it applies targeting and opt-out exclusion.
  // Phone numbers never touch the browser.
  const { data: rawPhones, error: phonesErr } = await adminClient.rpc(
    "_get_campaign_phones",
    { p_campaign_id: campaign_id },
  );
  if (phonesErr) {
    return await failCampaign(
      `Failed to resolve recipients: ${phonesErr.message}`,
    );
  }

  const phones: string[] = rawPhones ?? [];
  if (phones.length === 0) {
    await adminClient.from("campaigns").update({
      status: "sent",
      recipient_count: 0,
      sent_count: 0,
      failed_count: 0,
      failure_summary: [{ warning: "No eligible recipients found for this campaign and audience." }],
      sent_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    }).eq("id", campaign_id);
    return json({
      success: true,
      is_test_mode: claimed.is_test_mode,
      recipient_count: 0,
      sent_count: 0,
      failed_count: 0,
      message: "No eligible recipients found.",
    });
  }

  // ── 7. Normalise and validate phone numbers ───────────────────────────────────
  const normalised: string[] = [];
  let invalidCount = 0;
  for (const p of phones) {
    const n = normalisePhone(p);
    if (n) {
      normalised.push(n);
    } else {
      invalidCount++;
    }
  }

  // ── 8. Send in batches ────────────────────────────────────────────────────────
  let totalSubmitted = 0;
  let totalFailed = invalidCount;
  const errorSummary: string[] = [];

  if (invalidCount > 0) {
    errorSummary.push(`${invalidCount} invalid phone number(s) skipped (not E.164 format)`);
  }

  try {
    for (let i = 0; i < normalised.length; i += BATCH_SIZE) {
      const batch = normalised.slice(i, i + BATCH_SIZE);
      const result = await sendMsg91FlowBatch(
        apiKey as string,
        claimed.template_id,
        batch,
      );
      totalSubmitted += result.submitted;
      totalFailed += result.failed;
      // Cap errors per batch to avoid huge payloads in failure_summary
      if (result.errors.length > 0) {
        errorSummary.push(...result.errors.slice(0, 3));
      }
    }
  } catch (e) {
    // Unexpected mid-send error — save partial results so admin can see what was sent
    const errMsg = (e as Error).message ?? "unexpected error";
    errorSummary.push(`Unexpected error during send: ${errMsg}`);
    await adminClient.from("campaigns").update({
      status: "failed",
      recipient_count: phones.length,
      sent_count: totalSubmitted,
      failed_count: totalFailed + (normalised.length - totalSubmitted - totalFailed),
      failure_summary: errorSummary.slice(0, 20).map((e) => ({ error: e })),
      sent_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    }).eq("id", campaign_id);
    return json(
      {
        error: `Campaign failed mid-send: ${errMsg}`,
        sent_count: totalSubmitted,
        failed_count: totalFailed,
        note: "Partial delivery may have occurred. Use 'Reset to Draft' only if you are certain no messages were delivered.",
      },
      500,
    );
  }

  // ── 9. Finalise ───────────────────────────────────────────────────────────────
  // A campaign is 'sent' if at least one message was submitted.
  // If nothing was submitted (all failed), mark 'failed'.
  const finalStatus = totalSubmitted > 0 ? "sent" : "failed";
  const failureSummaryJson = errorSummary.length > 0
    ? errorSummary.slice(0, 20).map((e) => ({ error: e }))
    : null;

  await adminClient.from("campaigns").update({
    status: finalStatus,
    recipient_count: phones.length,
    sent_count: totalSubmitted,
    failed_count: totalFailed,
    failure_summary: failureSummaryJson,
    sent_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  }).eq("id", campaign_id);

  return json({
    success: finalStatus === "sent",
    is_test_mode: claimed.is_test_mode,
    recipient_count: phones.length,
    sent_count: totalSubmitted,
    failed_count: totalFailed,
    // Important: this is submission status, not delivery confirmation.
    // MSG91 queues delivery; actual receipt depends on DLT registration,
    // DND status, and operator routing.
    note: "sent_count = messages submitted to MSG91 for delivery, not confirmed received by recipients",
  });
});
