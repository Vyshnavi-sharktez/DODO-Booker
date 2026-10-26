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

// ── SSRF prevention ───────────────────────────────────────────────────────────

function isBlockedHostname(hostname: string): boolean {
  const h = hostname.toLowerCase().replace(/^\[|\]$/g, "");
  if (h === "localhost" || h === "::1" || h === "0.0.0.0") return true;
  if (h === "169.254.169.254" || h === "metadata.google.internal") return true;
  const m = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(h);
  if (m) {
    const [a, b] = m.slice(1).map(Number);
    if (a === 127 || a === 10 || a === 0 || a >= 240) return true;
    if (a === 172 && b >= 16 && b <= 31) return true;
    if (a === 192 && b === 168) return true;
    if (a === 169 && b === 254) return true;
    if (a === 100 && b >= 64 && b <= 127) return true;
  }
  if (h.startsWith("fc") || h.startsWith("fd")) return true;
  if (/^fe[89ab]/i.test(h)) return true;
  return false;
}

function validateUrl(rawUrl: string): string | null {
  let u: URL;
  try { u = new URL(rawUrl); } catch { return "Invalid URL format"; }
  if (u.protocol !== "https:") return "Only HTTPS URLs are allowed";
  if (isBlockedHostname(u.hostname)) return "URL hostname is not allowed (private/reserved address)";
  return null;
}

// ── Provider send logic (mirrors send-sms adapters) ──────────────────────────

async function sendViaMSG91(
  apiUrl: string,
  apiKey: string,
  extra: Record<string, string>,
  phone: string,
  otp: string,
): Promise<Response> {
  const mobile = phone.startsWith("+") ? phone.slice(1) : phone;
  const templateId = extra.template_id ?? "";
  if (!templateId) throw new Error("MSG91 template_id is not configured in extra settings");

  const payload: Record<string, string> = { template_id: templateId, mobile, otp };
  const senderId = (extra.sender_id ?? "").trim();
  if (senderId) payload.sender = senderId;

  return await fetch(apiUrl, {
    method: "POST",
    redirect: "error",
    headers: { "authkey": apiKey, "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
}

async function sendViaGenericHttp(
  apiUrl: string,
  apiKey: string,
  extra: Record<string, string>,
  phone: string,
  otp: string,
): Promise<Response> {
  const mobile = phone.startsWith("+") ? phone.slice(1) : phone;
  const method = (extra.method ?? "POST").toUpperCase();
  const authHeader = (extra.auth_header ?? "Bearer {{api_key}}")
    .replace(/\{\{api_key\}\}/g, apiKey);
  const bodyTemplate =
    extra.body_template ?? '{"phone":"{{phone}}","otp":"{{otp}}"}';
  const body = bodyTemplate
    .replace(/\{\{phone\}\}/g, mobile)
    .replace(/\{\{otp\}\}/g, otp)
    .replace(/\{\{api_key\}\}/g, apiKey);

  return await fetch(apiUrl, {
    method,
    redirect: "error",
    headers: { "Authorization": authHeader, "Content-Type": "application/json" },
    body: method === "GET" ? undefined : body,
  });
}

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

  // ── 1. Authenticate caller (admin user JWT) ────────────────────────────────
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader) return json({ error: "Unauthorized" }, 401);

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: { user }, error: authErr } = await userClient.auth.getUser();
  if (authErr || !user) return json({ error: "Unauthorized" }, 401);

  // ── 2. Verify caller is an active admin ────────────────────────────────────
  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });
  const { data: callerAdmin } = await adminClient
    .from("admin_users")
    .select("id, is_active")
    .eq("auth_user_id", user.id)
    .eq("is_active", true)
    .maybeSingle();
  if (!callerAdmin) return json({ error: "Forbidden" }, 403);

  // ── 3. Parse body ──────────────────────────────────────────────────────────
  let body: {
    provider?: string;
    test_phone?: string;
    mock?: boolean;
    mock_outcome?: string;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const { provider, test_phone, mock = false, mock_outcome = "success" } = body;
  if (!provider || !test_phone) {
    return json({ error: "provider and test_phone are required" }, 400);
  }
  // Accept either 10-digit local (917xxxxxxxx) or full E.164 with +
  if (!/^\+?\d{7,15}$/.test(test_phone)) {
    return json(
      { error: "test_phone must be 7–15 digits, optionally with a leading + (e.g. +919876543210)" },
      400,
    );
  }

  // ── 4. Load provider config ────────────────────────────────────────────────
  const { data: cfg, error: cfgErr } = await adminClient
    .from("sms_provider_configs")
    .select("is_enabled, api_url, extra_config, provider_name")
    .eq("provider", provider)
    .single();

  if (cfgErr || !cfg) return json({ error: "Provider configuration not found" }, 404);

  // ── Mock mode ───────────────────────────────────────────────────────────────
  // Config row was loaded above to confirm the provider exists.
  // Enabled state, API URL, Vault secret, and the real provider API are all
  // intentionally bypassed — no real SMS is sent.
  if (mock) {
    if (mock_outcome === "failure") {
      return json(
        {
          success: false,
          simulated: true,
          http_status: 500,
          provider_response: { message: "Simulated delivery failure — no real SMS was sent" },
        },
        422,
      );
    }
    return json({
      success: true,
      simulated: true,
      provider_response: { message: "Simulated — no real SMS was sent" },
    });
  }

  if (!cfg.is_enabled) {
    return json(
      { error: "Provider is disabled — enable it and save before testing" },
      400,
    );
  }
  if (!cfg.api_url) return json({ error: "API URL is not configured" }, 400);

  // ── 5. SSRF-validate the API URL ──────────────────────────────────────────
  const urlError = validateUrl(cfg.api_url as string);
  if (urlError) return json({ error: urlError }, 400);

  // ── 6. Retrieve API key from Vault ─────────────────────────────────────────
  const { data: apiKey, error: secretErr } = await adminClient.rpc(
    "get_sms_secret_value",
    { p_provider: provider, p_secret_name: "api_key" },
  );
  if (secretErr || !apiKey) {
    return json(
      { error: "API Key is not configured — add and save it before testing" },
      400,
    );
  }

  // ── 7. Send test SMS (OTP "000000" — clearly a test) ──────────────────────
  const extra = (cfg.extra_config ?? {}) as Record<string, string>;
  const testOtp = "000000";

  let apiRes: Response;
  try {
    switch (provider) {
      case "msg91":
        apiRes = await sendViaMSG91(
          cfg.api_url as string,
          apiKey as string,
          extra,
          test_phone,
          testOtp,
        );
        break;
      case "generic_http":
      default:
        apiRes = await sendViaGenericHttp(
          cfg.api_url as string,
          apiKey as string,
          extra,
          test_phone,
          testOtp,
        );
    }
  } catch (e) {
    const msg = (e as Error).message ?? "Network error";
    return json({ error: `Request failed: ${msg}` }, 502);
  }

  let responseData: unknown;
  const responseText = await apiRes.text().catch(() => "");
  try {
    responseData = JSON.parse(responseText);
  } catch {
    responseData = { raw: responseText };
  }

  // MSG91 OTP API always returns HTTP 200, even on rejection — check body
  if (provider === "msg91") {
    const r = responseData as Record<string, unknown>;
    if (r?.type === "error") {
      const msg = String(r.message ?? "unknown error");
      console.error(`[sms-test] MSG91 rejected: ${msg} | template_id: ${extra.template_id ?? "(not set)"}`);
      return json({ success: false, http_status: apiRes.status, provider_response: responseData }, 422);
    }
    console.log(`[sms-test] MSG91 accepted | template_id: ${extra.template_id ?? "(not set)"}`);
  }

  if (apiRes.ok) {
    return json({ success: true, provider_response: responseData });
  }
  return json(
    { success: false, http_status: apiRes.status, provider_response: responseData },
    422,
  );
});
