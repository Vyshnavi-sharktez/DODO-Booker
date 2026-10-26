import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";

// ── CORS ───────────────────────────────────────────────────────────────────────

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

// ── SSRF prevention ───────────────────────────────────────────────────────────
// Blocks private, loopback, link-local, and reserved IP ranges.
// Also blocks "localhost" hostname and common metadata endpoints.

function isBlockedHostname(hostname: string): boolean {
  const h = hostname.toLowerCase().replace(/^\[|\]$/g, ""); // strip IPv6 brackets

  if (h === "localhost") return true;
  if (h === "::1") return true;
  if (h === "0.0.0.0") return true;
  // AWS/GCP/Azure metadata endpoints
  if (h === "169.254.169.254" || h === "metadata.google.internal") return true;

  // IPv4 private / reserved ranges
  const m = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(h);
  if (m) {
    const [a, b, , ] = m.slice(1).map(Number);
    if (a === 127) return true;                          // 127.x.x.x loopback
    if (a === 10) return true;                           // 10.x.x.x private
    if (a === 172 && b >= 16 && b <= 31) return true;   // 172.16-31.x.x private
    if (a === 192 && b === 168) return true;             // 192.168.x.x private
    if (a === 169 && b === 254) return true;             // 169.254.x.x link-local
    if (a === 100 && b >= 64 && b <= 127) return true;  // 100.64-127 shared address
    if (a === 0) return true;                            // 0.x.x.x unspecified
    if (a >= 240) return true;                           // 240+ reserved
  }

  // IPv6 unique local (fc00::/7)
  if (h.startsWith("fc") || h.startsWith("fd")) return true;
  // IPv6 link-local (fe80::/10)
  if (/^fe[89ab]/i.test(h)) return true;

  return false;
}

function validateUrl(rawUrl: string): string | null {
  let u: URL;
  try {
    u = new URL(rawUrl);
  } catch {
    return "Invalid URL format";
  }
  if (u.protocol !== "https:") return "Only HTTPS URLs are allowed";
  if (isBlockedHostname(u.hostname)) return "URL hostname is not allowed (private/reserved address)";
  return null;
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

  // ── 1. Authenticate caller (user JWT) ────────────────────────────────────────
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader) return json({ error: "Unauthorized" }, 401);

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: { user }, error: authErr } = await userClient.auth.getUser();
  if (authErr || !user) return json({ error: "Unauthorized" }, 401);

  // ── 2. Verify caller is an active admin ──────────────────────────────────────
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

  // ── 3. Parse body ─────────────────────────────────────────────────────────────
  let body: { provider?: string; test_phone?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const { provider, test_phone } = body;
  if (!provider || !test_phone) {
    return json({ error: "provider and test_phone are required" }, 400);
  }
  if (!/^\d{7,15}$/.test(test_phone)) {
    return json({ error: "test_phone must be 7–15 digits (E.164 without + prefix, e.g. 919876543210)" }, 400);
  }

  // ── 4. Load provider config ───────────────────────────────────────────────────
  const { data: cfg, error: cfgErr } = await adminClient
    .from("whatsapp_provider_configs")
    .select("is_enabled, api_url, extra_config, provider_name")
    .eq("provider", provider)
    .single();

  if (cfgErr || !cfg) return json({ error: "Provider configuration not found" }, 404);
  if (!cfg.is_enabled) return json({ error: "Provider is disabled — enable it and save before testing" }, 400);
  if (!cfg.api_url) return json({ error: "API URL is not configured" }, 400);

  // ── 5. Validate API URL (SSRF prevention) ────────────────────────────────────
  const urlError = validateUrl(cfg.api_url as string);
  if (urlError) return json({ error: urlError }, 400);

  // ── 6. Load API key from Vault ────────────────────────────────────────────────
  const { data: apiKey, error: secretErr } = await adminClient
    .rpc("get_whatsapp_secret_value", { p_provider: provider, p_secret_name: "api_key" });
  if (secretErr || !apiKey) {
    return json({ error: "API Key is not configured — add and save it before testing" }, 400);
  }

  // ── 7. Send test message ──────────────────────────────────────────────────────
  const extra = (cfg.extra_config ?? {}) as Record<string, string>;
  const templateName = extra.template_name || "hello_world";
  const languageCode = extra.language_code || "en";

  let apiRes: Response;
  try {
    apiRes = await fetch(cfg.api_url as string, {
      method: "POST",
      redirect: "error", // never follow redirects (prevents open-redirect SSRF)
      headers: {
        "Authorization": `Basic ${apiKey as string}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        fullPhoneNumber: test_phone,
        callbackData: "dodo_whatsapp_test",
        type: "Template",
        template: {
          name: templateName,
          languageCode,
          headerValues: [],
          bodyValues: [],
          buttonValues: {},
        },
      }),
    });
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

  if (apiRes.ok) {
    return json({ success: true, provider_response: responseData });
  }
  return json({ success: false, http_status: apiRes.status, provider_response: responseData }, 422);
});
