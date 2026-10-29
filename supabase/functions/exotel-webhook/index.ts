// exotel-webhook — receives StatusCallback POST requests from Exotel and
// updates call_sessions in Supabase.
//
// Authentication
// Exotel does not sign webhook payloads (unlike Razorpay/Twilio).  The
// standard Exotel-recommended mechanism is to embed a secret token in the
// StatusCallback URL as a query parameter (?token=<value>).
// initiate-exotel-call appends the token when registering the callback;
// this function validates it against the vault on every request.
//
// Security properties
// • Fail closed: if the webhook_token vault secret is not configured, ALL
//   requests are rejected with 503 rather than processed unauthenticated.
// • Constant-time comparison to prevent timing attacks on the token.
// • CustomField UUID is validated before use as a DB primary-key lookup.
// • Terminal session states (ended/failed/missed) are immutable: a later
//   ringing/connected callback cannot overwrite them.
// • Recording URLs are written to call_session_recordings (admin-only RLS),
//   never to call_sessions (which call participants can read).

import { createClient } from "npm:@supabase/supabase-js@^2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Exotel Connect API StatusCallback Status values → our DB enum
// Ref: https://developer.exotel.com/api/#call-an-api-call
export const STATUS_MAP: Record<string, string> = {
  initiated:     "initiated",
  ringing:       "ringing",
  answered:      "connected",  // used in some Exotel API versions
  "in-progress": "connected",  // standard status while call is live
  completed:     "ended",
  busy:          "failed",
  failed:        "failed",
  "no-answer":   "missed",
  canceled:      "missed",
};

const FAILURE_REASONS: Record<string, string> = {
  busy:        "The other party was busy",
  failed:      "Call failed due to a technical error",
  "no-answer": "No answer — call timed out",
  canceled:    "Call was canceled before connecting",
};

export const TERMINAL_STATUSES = new Set(["ended", "failed", "missed"]);

// Constant-time string comparison — prevents timing side-channel on the token.
export function safeCompare(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

// Validate UUID v4 format before using a value as a DB primary-key lookup.
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isValidUuid(value: string): boolean {
  return UUID_RE.test(value);
}

// Map an Exotel status string to our DB status, or null if unknown.
export function mapExotelStatus(exotelStatus: string): string | null {
  return STATUS_MAP[exotelStatus.toLowerCase().trim()] ?? null;
}

// Derive failure_reason text from Exotel status and optional FailureReason field.
export function deriveFailureReason(
  rawStatus: string,
  exotelFailureReason: string | null,
): string {
  return (
    exotelFailureReason ||
    FAILURE_REASONS[rawStatus] ||
    `Call ended with status: ${rawStatus}`
  );
}

// deno-lint-ignore no-explicit-any
async function storeRecording(client: any, sessId: string, recUrl: string) {
  const { error } = await client
    .from("call_session_recordings")
    .upsert(
      { session_id: sessId, recording_url: recUrl },
      { onConflict: "session_id" },
    );
  if (error) {
    console.error(
      `exotel-webhook: failed to store recording for session ${sessId}:`,
      error.message,
    );
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "content-type",
      },
    });
  }

  if (req.method !== "POST") {
    return new Response(null, { status: 405 });
  }

  // ── Token authentication ──────────────────────────────────────────────────────
  const url = new URL(req.url);
  const tokenParam = url.searchParams.get("token");

  if (!tokenParam) {
    return Response.json({ error: "Missing token" }, { status: 401 });
  }

  const serviceClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });

  // Fail closed: reject all requests if the webhook token is not configured.
  const { data: webhookToken, error: tokenError } = await serviceClient.rpc(
    "get_call_secret_value",
    { p_provider: "exotel", p_secret_name: "webhook_token" },
  );

  if (tokenError || !webhookToken) {
    console.error(
      "exotel-webhook: webhook_token not configured in vault.",
      tokenError?.message,
    );
    return Response.json({ error: "Webhook not configured" }, { status: 503 });
  }

  if (!safeCompare(tokenParam, webhookToken as string)) {
    return Response.json({ error: "Invalid token" }, { status: 401 });
  }

  // ── Parse Exotel form-urlencoded body ─────────────────────────────────────────
  // Exotel sends StatusCallback as POST application/x-www-form-urlencoded.
  let params: URLSearchParams;
  try {
    const text = await req.text();
    params = new URLSearchParams(text);
  } catch {
    return Response.json({ error: "Invalid body" }, { status: 400 });
  }

  const callSid = params.get("CallSid")?.trim() ?? "";
  const rawStatus = (params.get("Status") ?? "").toLowerCase().trim();
  const customField = params.get("CustomField")?.trim() ?? "";
  const durationStr = params.get("Duration");
  const recordingUrl = params.get("RecordingUrl")?.trim() || null;
  // Exotel sends FailureReason for some technical failures
  const exotelFailureReason = params.get("FailureReason")?.trim() || null;

  if (!callSid) {
    return Response.json({ error: "Missing CallSid" }, { status: 400 });
  }

  const dbStatus = mapExotelStatus(rawStatus);
  if (!dbStatus) {
    // Unknown status string: acknowledge to stop retries, no DB change.
    console.log(
      `exotel-webhook: unknown status '${rawStatus}' for CallSid ${callSid} — acknowledging`,
    );
    return new Response("OK", { status: 200 });
  }

  const isTerminal = TERMINAL_STATUSES.has(dbStatus);
  const isFailed = dbStatus === "failed" || dbStatus === "missed";
  const duration =
    durationStr !== null ? parseInt(durationStr, 10) : undefined;

  // ── Locate the call session ───────────────────────────────────────────────────
  // Primary: CustomField carries the session UUID embedded at call initiation.
  // Fallback: exotel_call_sid stored when Exotel acknowledged the call request.
  let sessionId: string | null = null;
  let currentStatus: string | null = null;

  if (customField && isValidUuid(customField)) {
    const { data } = await serviceClient
      .from("call_sessions")
      .select("id, status")
      .eq("id", customField)
      .maybeSingle();
    if (data) {
      sessionId = data.id as string;
      currentStatus = data.status as string;
    }
  }

  if (!sessionId) {
    const { data } = await serviceClient
      .from("call_sessions")
      .select("id, status")
      .eq("exotel_call_sid", callSid)
      .maybeSingle();
    if (data) {
      sessionId = data.id as string;
      currentStatus = data.status as string;
    }
  }

  if (!sessionId) {
    // No matching session: test delivery, retried callback for a deleted
    // session, or misconfigured CustomField.  Acknowledge to stop retries.
    console.log(
      `exotel-webhook: session not found — CallSid=${callSid} CustomField=${customField || "(none)"}`,
    );
    return new Response("OK", { status: 200 });
  }

  const sid = sessionId;

  // ── Idempotency: terminal states are immutable ────────────────────────────────
  // A "completed" webhook and a subsequent recording-URL delivery can both carry
  // Status=completed.  We skip the status write on re-delivery but still store
  // the recording URL if it arrives late in a separate callback.
  if (currentStatus && TERMINAL_STATUSES.has(currentStatus)) {
    if (recordingUrl) {
      await storeRecording(serviceClient, sid, recordingUrl);
      await serviceClient
        .from("call_sessions")
        .update({
          recording_status: "available",
          updated_at: new Date().toISOString(),
        })
        .eq("id", sid);
    }
    return new Response("OK", { status: 200 });
  }

  // ── Build call_sessions update ────────────────────────────────────────────────
  const update: Record<string, unknown> = {
    status: dbStatus,
    updated_at: new Date().toISOString(),
  };

  if (isTerminal) {
    update.ended_at = new Date().toISOString();
    if (duration !== undefined && duration > 0) {
      update.duration_seconds = duration;
    }
  }

  if (isFailed) {
    update.failure_reason = deriveFailureReason(rawStatus, exotelFailureReason);
  }

  if (recordingUrl) {
    // recording_status only — URL is stored in the admin-only table below
    update.recording_status = "available";
  } else if (dbStatus === "ended") {
    // Call ended; if recording is enabled, Exotel will send the URL in a
    // later callback.  "pending" signals that we are waiting for it.
    update.recording_status = "pending";
  }

  // ── Persist status ────────────────────────────────────────────────────────────
  const { error: updateError } = await serviceClient
    .from("call_sessions")
    .update(update)
    .eq("id", sid);

  if (updateError) {
    console.error(
      `exotel-webhook: DB update failed for session ${sid}:`,
      updateError.message,
    );
    // Non-200 → Exotel retries; idempotency handles re-delivery cleanly.
    return Response.json({ error: "DB update failed" }, { status: 500 });
  }

  // ── Store recording URL in admin-only table ───────────────────────────────────
  // recording_url is intentionally NOT written to call_sessions, which is
  // readable by call participants.  Only admins can query call_session_recordings.
  if (recordingUrl) {
    await storeRecording(serviceClient, sid, recordingUrl);
  }

  // Exotel expects 200 OK to acknowledge delivery; anything else causes retries.
  return new Response("OK", { status: 200 });
});
