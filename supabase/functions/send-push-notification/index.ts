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

  // ── 1. Authenticate request using PUSH_FUNCTION_SECRET (timing-safe) ────────
  const pushSecret = Deno.env.get("PUSH_FUNCTION_SECRET");
  if (!pushSecret) {
    console.error("PUSH_FUNCTION_SECRET not configured");
    return new Response("Unauthorized", { status: 401 });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const incomingSecret = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";

  if (!timingSafeEqual(incomingSecret, pushSecret)) {
    return new Response("Unauthorized", { status: 401 });
  }

  // ── 2. Parse payload ─────────────────────────────────────────────────────────
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

  // ── 3. Create Supabase admin client ──────────────────────────────────────────
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  // ── 4. Idempotency check — claim this notification_id ────────────────────────
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

  // ── 5. Load FCM service account from environment ─────────────────────────────
  const serviceAccountB64 = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON_B64");
  if (!serviceAccountB64) {
    console.error("FCM_SERVICE_ACCOUNT_JSON_B64 not configured");
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
    console.error("FCM_SERVICE_ACCOUNT_JSON_B64 could not be decoded or parsed");
    return new Response("Internal error", { status: 500 });
  }

  // ── 6. Get FCM access token ───────────────────────────────────────────────────
  let accessToken: string;
  try {
    accessToken = await getFcmAccessToken(serviceAccount);
  } catch (e) {
    console.error(`FCM access token error: ${(e as Error).message}`);
    return new Response("Internal error", { status: 500 });
  }

  // ── 7. Query device tokens ────────────────────────────────────────────────────
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

  // ── 8. Send FCM messages and collect stale token IDs ─────────────────────────
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

  // ── 9. Deactivate stale tokens by ID (never log the token string) ─────────────
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

  // ── 10. Record final counts ──────────────────────────────────────────────────
  await supabase
    .from("push_deliveries")
    .update({ tokens_sent: sent, tokens_failed: failed })
    .eq("notification_id", notification_id);

  console.log(`push delivery complete: notification_id=${notification_id} sent=${sent} failed=${failed}`);

  return new Response(JSON.stringify({ sent, failed }), { status: 200 });
});
