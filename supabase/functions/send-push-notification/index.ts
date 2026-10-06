import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";

// ── Types ─────────────────────────────────────────────────────────────────────

interface PushPayload {
  notification_id: string;
  user_type: string;
  user_id: string | null;
  title: string;
  body: string;
  data: Record<string, string>;
}

interface DeviceToken {
  id: string;
  token: string;
  platform: string;
}

interface FcmErrorDetail {
  code: string;
  message: string;
  status: string;
}

// ── Timing-safe secret comparison ────────────────────────────────────────────

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) {
    // Still iterate to avoid length-based timing leak
    let dummy = 0;
    for (let i = 0; i < a.length; i++) dummy |= a.charCodeAt(i);
    return dummy === -1; // always false
  }
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

// ── FCM OAuth2 JWT + access token ─────────────────────────────────────────────

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

async function getFcmAccessToken(serviceAccount: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const claim = {
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const header = { alg: "RS256", typ: "JWT" };
  const encode = (obj: object) =>
    btoa(JSON.stringify(obj)).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");

  const headerB64 = encode(header);
  const claimB64 = encode(claim);
  const signingInput = `${headerB64}.${claimB64}`;

  // Import the RSA private key (PKCS#8 PEM)
  const pemContents = serviceAccount.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");
  const keyBytes = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    keyBytes,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(signingInput),
  );

  const sigB64 = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");

  const jwt = `${signingInput}.${sigB64}`;

  // Exchange JWT for access token
  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!tokenRes.ok) {
    throw new Error(`FCM OAuth2 token exchange failed: ${tokenRes.status}`);
  }

  const tokenData = await tokenRes.json();
  return tokenData.access_token as string;
}

// ── Send single FCM message ───────────────────────────────────────────────────

async function sendFcmMessage(
  accessToken: string,
  projectId: string,
  deviceToken: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<{ success: boolean; errorCode?: string }> {
  const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

  const message = {
    message: {
      token: deviceToken,
      notification: { title, body },
      data,
      android: {
        notification: {
          channel_id: "dodo_push_channel",
          sound: "default",
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
          },
        },
      },
    },
  };

  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${accessToken}`,
    },
    body: JSON.stringify(message),
  });

  if (res.ok) return { success: true };

  const errBody = await res.json().catch(() => ({}));
  const errDetail = errBody?.error as FcmErrorDetail | undefined;
  const errorCode = errDetail?.status ?? `HTTP_${res.status}`;

  // Log error code only — never log the token itself
  console.log(`FCM send failed: status=${errorCode}`);
  return { success: false, errorCode };
}

// ── Main handler ──────────────────────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  // ── 1. Create Supabase admin client ──────────────────────────────────────────
  // Created before auth so vault secrets can be read for authentication.
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  // ── 2. Load push secret — vault preferred, env var fallback ──────────────────
  // Vault is the source of truth when configured via the Admin Panel.
  // The env var (PUSH_FUNCTION_SECRET) remains supported as a fallback so that
  // existing deployments continue to work without any re-configuration.
  let pushSecret = "";
  const { data: vaultPushSecret } = await supabase.rpc("get_fcm_vault_secret_value", {
    p_name: "push_function_secret",
  });
  pushSecret = (vaultPushSecret as string | null ?? Deno.env.get("PUSH_FUNCTION_SECRET")) ?? "";

  if (!pushSecret) {
    console.error("push_function_secret not configured in vault or PUSH_FUNCTION_SECRET env var");
    return new Response("Unauthorized", { status: 401 });
  }

  // ── 3. Authenticate request (timing-safe) ────────────────────────────────────
  const authHeader = req.headers.get("Authorization") ?? "";
  const incomingSecret = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";

  if (!timingSafeEqual(incomingSecret, pushSecret)) {
    return new Response("Unauthorized", { status: 401 });
  }

  // ── 4. Parse payload ─────────────────────────────────────────────────────────
  let payload: PushPayload;
  try {
    payload = await req.json() as PushPayload;
  } catch {
    return new Response("Invalid JSON", { status: 400 });
  }

  const { notification_id, user_type, user_id, title, body, data } = payload;
  if (!notification_id || !user_type || !title) {
    return new Response("Missing required fields", { status: 400 });
  }

  // ── 5. Idempotency check — claim this notification_id ────────────────────────
  const { data: claimed, error: claimErr } = await supabase
    .from("push_deliveries")
    .insert({ notification_id })
    .select("notification_id")
    .single();

  if (claimErr || !claimed) {
    // Conflict (23505) means another delivery already ran — skip silently
    if (claimErr?.code === "23505") {
      console.log(`push_deliveries conflict for ${notification_id}, skipping duplicate`);
      return new Response(JSON.stringify({ skipped: true }), { status: 200 });
    }
    console.error(`push_deliveries insert failed for ${notification_id}: code=${claimErr?.code}`);
    return new Response("Internal error", { status: 500 });
  }

  // ── 6. Load FCM service account — env var preferred, vault fallback ──────────
  // The env var (FCM_SERVICE_ACCOUNT_JSON_B64) continues to work unchanged.
  // If absent, the vault secret set via the Admin Panel is used instead.
  let serviceAccountB64 = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON_B64");
  if (!serviceAccountB64) {
    const { data: vaultSa } = await supabase.rpc("get_fcm_vault_secret_value", {
      p_name: "fcm_service_account_b64",
    });
    serviceAccountB64 = (vaultSa as string | null) ?? undefined;
  }

  if (!serviceAccountB64) {
    console.error("FCM service account not configured in vault or FCM_SERVICE_ACCOUNT_JSON_B64 env var");
    await supabase
      .from("push_deliveries")
      .update({ tokens_sent: 0, tokens_failed: 0 })
      .eq("notification_id", notification_id);
    return new Response(JSON.stringify({ sent: 0, failed: 0 }), { status: 200 });
  }

  let serviceAccount: ServiceAccount;
  try {
    // Base64-decode → UTF-8 string → parse as JSON
    const decoded = new TextDecoder().decode(
      Uint8Array.from(atob(serviceAccountB64), (c) => c.charCodeAt(0)),
    );
    serviceAccount = JSON.parse(decoded) as ServiceAccount;
  } catch {
    console.error("FCM service account could not be decoded or parsed");
    return new Response("Internal error", { status: 500 });
  }

  // ── 7. Get FCM access token ───────────────────────────────────────────────────
  let accessToken: string;
  try {
    accessToken = await getFcmAccessToken(serviceAccount);
  } catch (e) {
    console.error(`FCM access token error: ${(e as Error).message}`);
    return new Response("Internal error", { status: 500 });
  }

  // ── 8. Query device tokens ────────────────────────────────────────────────────
  let tokenQuery = supabase
    .from("device_tokens")
    .select("id, token, platform")
    .eq("user_type", user_type)
    .eq("is_active", true);

  if (user_id) {
    tokenQuery = tokenQuery.eq("user_id", user_id);
  }
  // user_id null means broadcast to all admins — no user_id filter

  const { data: tokens, error: tokensErr } = await tokenQuery;
  if (tokensErr) {
    console.error(`device_tokens query failed: code=${tokensErr.code}`);
    return new Response("Internal error", { status: 500 });
  }

  const deviceTokens = (tokens ?? []) as DeviceToken[];
  if (deviceTokens.length === 0) {
    await supabase
      .from("push_deliveries")
      .update({ tokens_sent: 0, tokens_failed: 0 })
      .eq("notification_id", notification_id);
    return new Response(JSON.stringify({ sent: 0, failed: 0 }), { status: 200 });
  }

  // ── 9. Send FCM messages and collect stale token IDs ─────────────────────────
  const staleIds: string[] = [];
  let sent = 0;
  let failed = 0;

  await Promise.all(
    deviceTokens.map(async (dt) => {
      const result = await sendFcmMessage(
        accessToken,
        serviceAccount.project_id,
        dt.token,
        title,
        body,
        data ?? {},
      );
      if (result.success) {
        sent++;
      } else {
        failed++;
        if (result.errorCode === "UNREGISTERED" || result.errorCode === "INVALID_ARGUMENT") {
          staleIds.push(dt.id);
        }
      }
    }),
  );

  // ── 10. Deactivate stale tokens by ID (never log the token string) ─────────────
  if (staleIds.length > 0) {
    const { error: deactivateErr } = await supabase
      .from("device_tokens")
      .update({ is_active: false, updated_at: new Date().toISOString() })
      .in("id", staleIds);
    if (deactivateErr) {
      console.error(`stale token deactivation failed: code=${deactivateErr.code}`);
    } else {
      console.log(`deactivated ${staleIds.length} stale token(s)`);
    }
  }

  // ── 11. Record final counts ──────────────────────────────────────────────────
  await supabase
    .from("push_deliveries")
    .update({ tokens_sent: sent, tokens_failed: failed })
    .eq("notification_id", notification_id);

  console.log(`push delivery complete: notification_id=${notification_id} sent=${sent} failed=${failed}`);

  return new Response(JSON.stringify({ sent, failed }), { status: 200 });
});
