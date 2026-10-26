import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";
import { Webhook } from "standardwebhooks";

// ── CORS ───────────────────────────────────────────────────────────────────────
// The Send SMS Hook is called server-to-server by Supabase Auth.
// CORS headers are included for completeness; the hook does not originate
// from a browser and OPTIONS preflight will not normally arrive.

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
  try { u = new URL(rawUrl); } catch { return "Invalid API URL format"; }
  if (u.protocol !== "https:") return "Provider API URL must use HTTPS";
  if (isBlockedHostname(u.hostname)) return "Provider API URL hostname is not allowed";
  return null;
}

// ── Provider adapters ─────────────────────────────────────────────────────────
// Each adapter receives the resolved config and sends the OTP via its API.
// Throws on any delivery failure — the caller maps this to a 502 response
// which Supabase Auth surfaces as "Error sending OTP".

interface AdapterArgs {
  apiUrl: string;
  apiKey: string;
  extra: Record<string, string>;
  phone: string; // E.164 with leading +
  otp: string;
}

async function msg91Adapter(args: AdapterArgs): Promise<void> {
  const { apiUrl, apiKey, extra, phone, otp } = args;
  // MSG91 requires the number without leading +
  const mobile = phone.startsWith("+") ? phone.slice(1) : phone;
  const templateId = extra.template_id ?? "";
  if (!templateId) throw new Error("MSG91 template_id is not configured");

  const payload: Record<string, string> = { template_id: templateId, mobile, otp };
  const senderId = (extra.sender_id ?? "").trim();
  if (senderId) payload.sender = senderId;

  const res = await fetch(apiUrl, {
    method: "POST",
    redirect: "error",
    headers: {
      "authkey": apiKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });

  // Read body once — used for both HTTP-level and application-level error detection
  const resText = await res.text().catch(() => "");
  if (!res.ok) {
    throw new Error(`MSG91 error ${res.status}: ${resText}`);
  }

  // MSG91 OTP API always returns HTTP 200, even on rejection — check body
  let resJson: Record<string, unknown> | null = null;
  try { resJson = JSON.parse(resText); } catch { /* non-JSON body */ }

  if (resJson?.type === "error") {
    const msg = String(resJson.message ?? "unknown error");
    console.error(`MSG91 rejected OTP delivery: ${msg} | template_id: ${extra.template_id ?? "(not set)"}`);
    throw new Error(`MSG91 rejected the request: ${msg}`);
  }
  console.log(`MSG91 OTP accepted | template_id: ${extra.template_id ?? "(not set)"}`);
}

async function genericHttpAdapter(args: AdapterArgs): Promise<void> {
  const { apiUrl, apiKey, extra, phone, otp } = args;
  const mobile = phone.startsWith("+") ? phone.slice(1) : phone;
  const method = (extra.method ?? "POST").toUpperCase();

  // The auth_header field supports a {{api_key}} placeholder.
  const authHeader = (extra.auth_header ?? "Bearer {{api_key}}")
    .replace(/\{\{api_key\}\}/g, apiKey);

  // The body_template field supports {{phone}}, {{otp}}, {{api_key}} placeholders.
  const bodyTemplate =
    extra.body_template ?? '{"phone":"{{phone}}","otp":"{{otp}}"}';
  const body = bodyTemplate
    .replace(/\{\{phone\}\}/g, mobile)
    .replace(/\{\{otp\}\}/g, otp)
    .replace(/\{\{api_key\}\}/g, apiKey);

  const res = await fetch(apiUrl, {
    method,
    redirect: "error",
    headers: {
      "Authorization": authHeader,
      "Content-Type": "application/json",
    },
    body: method === "GET" ? undefined : body,
  });

  if (!res.ok) {
    const resBody = await res.text().catch(() => "");
    throw new Error(`Provider error ${res.status}: ${resBody}`);
  }
}

// ── Main handler ──────────────────────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  // ── 1. Verify Standard Webhooks signature ────────────────────────────────────
  // Supabase Auth Hooks uses the Standard Webhooks spec: the signature is in
  // webhook-id / webhook-timestamp / webhook-signature headers, covering the
  // raw request body. Bearer JWT is NOT used for this hook type.
  const hookSecret = Deno.env.get("SEND_SMS_HOOK_SECRET");
  if (!hookSecret) {
    console.error("SEND_SMS_HOOK_SECRET is not configured");
    return json({ error: "Hook secret not configured" }, 500);
  }

  // Signature covers raw bytes — body must be read as text before verifying.
  const rawBody = await req.text().catch(() => null);
  if (rawBody === null) return json({ error: "Failed to read request body" }, 400);

  // Dashboard stores the secret as v1,whsec_<base64>. The standardwebhooks
  // library expects whsec_<base64>, so strip the v1, version prefix if present.
  let hookBody: { user?: { phone?: string }; sms?: { otp?: string } };
  try {
    const secret = hookSecret.startsWith("v1,") ? hookSecret.slice(3) : hookSecret;
    const wh = new Webhook(secret);
    hookBody = wh.verify(rawBody, Object.fromEntries(req.headers)) as {
      user?: { phone?: string };
      sms?: { otp?: string };
    };
  } catch (e) {
    console.error("Hook signature verification failed:", (e as Error).message);
    return json({ error: "Unauthorized" }, 401);
  }

  // ── 2. Extract phone and OTP ──────────────────────────────────────────────────
  const phone = hookBody.user?.phone;
  const otp = hookBody.sms?.otp;
  if (!phone || !otp) {
    return json(
      { error: "user.phone and sms.otp are required in hook payload" },
      400,
    );
  }

  // ── 3. Load active provider config ───────────────────────────────────────────
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  const { data: cfg, error: cfgErr } = await adminClient
    .from("sms_provider_configs")
    .select("provider, provider_name, is_enabled, api_url, extra_config")
    .eq("is_enabled", true)
    .single();

  if (cfgErr || !cfg) {
    console.error("No active SMS provider found:", cfgErr?.message);
    return json(
      { error: "No SMS provider is enabled. Configure one in the admin panel." },
      503,
    );
  }

  // ── 4. SSRF-validate the API URL ──────────────────────────────────────────────
  const urlError = validateUrl(cfg.api_url as string);
  if (urlError) {
    console.error("SMS provider API URL blocked:", urlError);
    return json({ error: urlError }, 400);
  }

  // ── 5. Retrieve API key from Vault ────────────────────────────────────────────
  const { data: apiKey, error: secretErr } = await adminClient.rpc(
    "get_sms_secret_value",
    { p_provider: cfg.provider, p_secret_name: "api_key" },
  );

  if (secretErr || !apiKey) {
    console.error(
      "SMS API key not found in Vault:",
      secretErr?.message ?? "null result",
    );
    return json(
      { error: "SMS provider API key is not configured" },
      503,
    );
  }

  // ── 6. Dispatch to provider adapter ──────────────────────────────────────────
  const extra = (cfg.extra_config ?? {}) as Record<string, string>;
  const adapterArgs: AdapterArgs = {
    apiUrl: cfg.api_url as string,
    apiKey: apiKey as string,
    extra,
    phone,
    otp,
  };

  try {
    switch (cfg.provider) {
      case "msg91":
        await msg91Adapter(adapterArgs);
        break;
      case "generic_http":
        await genericHttpAdapter(adapterArgs);
        break;
      default:
        // Unknown provider slug — attempt generic HTTP as a best-effort fallback
        // for any future provider added via admin panel before a dedicated adapter
        // is implemented. The generic adapter requires body_template in extra_config.
        await genericHttpAdapter(adapterArgs);
    }
  } catch (e) {
    const msg = (e as Error).message ?? "Unknown delivery error";
    console.error(`SMS delivery failed via ${cfg.provider}:`, msg);
    return json({ error: `SMS delivery failed: ${msg}` }, 502);
  }

  // Supabase Auth expects HTTP 200 with a JSON body to consider the hook
  // successful.  An empty object is sufficient.
  return json({});
});
