import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";
import type { SupabaseClient } from "@supabase/supabase-js";

// ── Types ─────────────────────────────────────────────────────────────────────

interface RequestBody {
  topup_attempt_id?: string;
  vendor_id?: string;
  razorpay_payment_id?: string;
  razorpay_order_id?: string;
  razorpay_signature?: string;
}

interface TopupAttemptRow {
  id: string;
  vendor_id: string;
  gateway: string;
  gateway_order_id: string | null;
  status: string;
  amount: number;
}

// ── Credential loading ────────────────────────────────────────────────────────
// Identical to verify-razorpay-payment:
//   1. Vault / Admin Panel (get_gateway_secret_value RPC, service_role only)
//   2. RAZORPAY_KEY_SECRET env var (backward-compat fallback)

async function loadKeySecret(supabaseAdmin: SupabaseClient): Promise<string | null> {
  const { data: vaultSecret } = await supabaseAdmin.rpc(
    "get_gateway_secret_value",
    { p_gateway: "razorpay", p_secret_name: "key_secret" },
  );
  if (vaultSecret) return vaultSecret as string;

  return Deno.env.get("RAZORPAY_KEY_SECRET") ?? null;
}

// ── HMAC-SHA256 signature verification ───────────────────────────────────────
// Same algorithm as verify-razorpay-payment.
// message = razorpay_order_id + "|" + razorpay_payment_id
// HMAC-SHA256(message, key_secret) must equal razorpay_signature (hex).

async function verifyRazorpaySignature(
  razorpayOrderId: string,
  razorpayPaymentId: string,
  razorpaySignature: string,
  keySecret: string,
): Promise<boolean> {
  const message = `${razorpayOrderId}|${razorpayPaymentId}`;

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(keySecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const signatureBuffer = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(message),
  );

  const computed = Array.from(new Uint8Array(signatureBuffer))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  // Constant-time comparison.
  if (computed.length !== razorpaySignature.length) return false;
  let diff = 0;
  for (let i = 0; i < computed.length; i++) {
    diff |= computed.charCodeAt(i) ^ razorpaySignature.charCodeAt(i);
  }
  return diff === 0;
}

// ── Handler ───────────────────────────────────────────────────────────────────

export default {
  fetch: withSupabase({ auth: ["publishable", "secret"] }, async (req, ctx) => {
    // ── Parse request body ──────────────────────────────────────────────────
    let body: RequestBody;
    try {
      body = await req.json() as RequestBody;
    } catch {
      return Response.json({ error: "Invalid JSON body." }, { status: 400 });
    }

    const {
      topup_attempt_id,
      vendor_id,
      razorpay_payment_id,
      razorpay_order_id,
      razorpay_signature,
    } = body;

    if (!topup_attempt_id || typeof topup_attempt_id !== "string" || topup_attempt_id.trim() === "") {
      return Response.json({ error: "topup_attempt_id is required." }, { status: 400 });
    }
    if (!vendor_id || typeof vendor_id !== "string" || vendor_id.trim() === "") {
      return Response.json({ error: "vendor_id is required." }, { status: 400 });
    }
    if (!razorpay_payment_id || typeof razorpay_payment_id !== "string" || razorpay_payment_id.trim() === "") {
      return Response.json({ error: "razorpay_payment_id is required." }, { status: 400 });
    }
    if (!razorpay_order_id || typeof razorpay_order_id !== "string" || razorpay_order_id.trim() === "") {
      return Response.json({ error: "razorpay_order_id is required." }, { status: 400 });
    }
    if (!razorpay_signature || typeof razorpay_signature !== "string" || razorpay_signature.trim() === "") {
      return Response.json({ error: "razorpay_signature is required." }, { status: 400 });
    }

    // ── Load key secret ────────────────────────────────────────────────────
    const keySecret = await loadKeySecret(ctx.supabaseAdmin);
    if (!keySecret) {
      return Response.json(
        { error: "Payment gateway is not configured." },
        { status: 503 },
      );
    }

    // ── Fetch the top-up attempt ───────────────────────────────────────────
    const { data: attempt, error: attemptError } = await ctx.supabaseAdmin
      .from("vendor_wallet_topup_attempts")
      .select("id, vendor_id, gateway, gateway_order_id, status, amount")
      .eq("id", topup_attempt_id)
      .single<TopupAttemptRow>();

    if (attemptError || !attempt) {
      return Response.json(
        { error: "Top-up attempt record not found." },
        { status: 404 },
      );
    }

    // ── Validate caller-supplied fields against DB ─────────────────────────
    if (attempt.vendor_id !== vendor_id) {
      return Response.json(
        { error: "vendor_id does not match the top-up attempt." },
        { status: 422 },
      );
    }

    if (attempt.gateway !== "razorpay") {
      return Response.json(
        { error: "Top-up attempt is not a Razorpay payment." },
        { status: 422 },
      );
    }

    if (attempt.gateway_order_id !== razorpay_order_id) {
      return Response.json(
        { error: "razorpay_order_id does not match the top-up attempt." },
        { status: 422 },
      );
    }

    // ── Idempotency: already verified — return success without mutating ────
    if (attempt.status === "success") {
      return Response.json({ success: true, idempotent: true });
    }

    // Non-pending attempts cannot be completed via this path.
    if (attempt.status !== "pending") {
      return Response.json(
        { error: `Top-up attempt is in status '${attempt.status}' and cannot be verified.` },
        { status: 409 },
      );
    }

    // ── Verify HMAC-SHA256 signature ───────────────────────────────────────
    const signatureValid = await verifyRazorpaySignature(
      razorpay_order_id,
      razorpay_payment_id,
      razorpay_signature,
      keySecret,
    );

    if (!signatureValid) {
      // Mark failed via RPC so the state machine stays consistent.
      await ctx.supabaseAdmin.rpc("fail_vendor_wallet_topup", {
        p_topup_attempt_id: topup_attempt_id,
        p_failure_reason: "signature_mismatch",
      });

      return Response.json(
        { error: "Payment verification failed: signature mismatch." },
        { status: 400 },
      );
    }

    // ── Call complete_vendor_wallet_topup RPC ─────────────────────────────
    // This atomically: marks the attempt success, credits the wallet, inserts
    // the ledger row, and sends the vendor notification. It is idempotent.
    const { data: rpcResult, error: rpcError } = await ctx.supabaseAdmin.rpc(
      "complete_vendor_wallet_topup",
      {
        p_topup_attempt_id:   topup_attempt_id,
        p_vendor_id:          vendor_id,
        p_gateway_payment_id: razorpay_payment_id,
        p_gateway_signature:  razorpay_signature,
        p_gateway_response:   null,
      },
    );

    if (rpcError) {
      return Response.json(
        { error: "Failed to credit wallet. Contact support." },
        { status: 500 },
      );
    }

    const idempotent = rpcResult === "already_complete";

    return Response.json({ success: true, idempotent });
  }),
};
