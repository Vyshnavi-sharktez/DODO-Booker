import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";

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

// ── Hook JWT verification ─────────────────────────────────────────────────────
// Supabase Auth signs every hook request with an HS256 JWT using the hook
// signing secret configured in the Dashboard.  The same secret must be stored
// as the SEND_SMS_HOOK_SECRET project secret so this function can verify it.
// Ref: https://supabase.com/docs/guides/auth/auth-hooks#http-hooks

async function verifyHookJwt(
  authHeader: string | null,
  secret: string,
): Promise<void> {
  if (!authHeader?.startsWith("Bearer ")) {
    throw new Error("Missing or invalid Authorization header");
  }
  const token = authHeader.slice(7);
  const parts = token.split(".");
  if (parts.length !== 3) throw new Error("Malformed JWT");

  const [headerEnc, payloadEnc, sigEnc] = parts;

  // Import the signing key (HS256 = HMAC-SHA-256).
  const keyData = new TextEncoder().encode(secret);
  const key = await crypto.subtle.importKey(
    "raw",
    keyData,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );

  // Base64url → binary
  const b64urlToBytes = (s: string): Uint8Array =>
    Uint8Array.from(
      atob(s.replace(/-/g, "+").replace(/_/g, "/")),
      (c) => c.charCodeAt(0),
    );

  const sigBytes = b64urlToBytes(sigEnc);
  const signedInput = new TextEncoder().encode(`${headerEnc}.${payloadEnc}`);

  const valid = await crypto.subtle.verify("HMAC", key, sigBytes, signedInput);
  if (!valid) throw new Error("Hook JWT signature is invalid");

  // Decode payload and check expiry if present.
  const payload = JSON.parse(
    new TextDecoder().decode(b64urlToBytes(payloadEnc)),
  );
  const now = Math.floor(Date.now() / 1000);
  if (typeof payload.exp === "number" && payload.exp < now) {
    throw new Error("Hook JWT has expired");
  }
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

  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`MSG91 error ${res.status}: ${body}`);
  }
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

  // ── 1. Verify hook JWT ────────────────────────────────────────────────────────
  // SEND_SMS_HOOK_SECRET must be set as a Supabase project secret BEFORE the
  // Auth Send SMS Hook is activated in the Dashboard.  If it is absent the
  // function refuses all requests — it must never run unprotected.
  const hookSecret = Deno.env.get("SEND_SMS_HOOK_SECRET");
  if (!hookSecret) {
    console.error("SEND_SMS_HOOK_SECRET is not configured");
    return json({ error: "Hook secret not configured" }, 500);
  }

  try {
    await verifyHookJwt(req.headers.get("Authorization"), hookSecret);
  } catch (e) {
    console.error("Hook JWT verification failed:", (e as Error).message);
    return json({ error: "Unauthorized" }, 401);
  }

  // ── 2. Parse hook body ────────────────────────────────────────────────────────
  // Supabase Auth Send SMS Hook payload shape:
  //   { user: { phone: "+91..." }, sms: { otp: "123456" } }
  // Ref: https://supabase.com/docs/guides/auth/auth-hooks#send-sms-hook
  let hookBody: { user?: { phone?: string }; sms?: { otp?: string } };
  try {
    hookBody = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

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
