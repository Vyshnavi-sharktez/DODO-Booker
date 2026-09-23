import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";
import type { SupabaseClient } from "@supabase/supabase-js";

// ── Types ─────────────────────────────────────────────────────────────────────

interface RazorpayPaymentEntity {
  id: string;
  order_id: string;
  error_description?: string;
  error_code?: string;
  [key: string]: unknown;
}

interface RazorpayRefundEntity {
  id: string;          // rfnd_XXXXX
  entity: string;
  amount: number;      // paise
  currency: string;
  payment_id: string;  // pay_XXXXX that was refunded
  status: string;      // "processed" | "failed"
  // notes is a flat string-keyed object.  We embed dodo_transaction_id here
  // when creating the refund so we can match this event back to our DB row.
  notes: Record<string, string> | null;
  receipt: string | null;
  [key: string]: unknown;
}

interface RazorpayWebhookPayload {
  event: string;
  payload: {
    payment?: { entity: RazorpayPaymentEntity };
    refund?:  { entity: RazorpayRefundEntity };
  };
}

// ── Credential loading ────────────────────────────────────────────────────────
// Resolution order:
//   1. Admin Panel / Supabase Vault (get_gateway_secret_value RPC, service_role only)
//   2. RAZORPAY_WEBHOOK_SECRET env var (backward-compat fallback only)

async function loadWebhookSecret(supabaseAdmin: SupabaseClient): Promise<string | null> {
  // ── 1. Vault / Admin Panel (preferred) ─────────────────────────────────────
  const { data: vaultSecret } = await supabaseAdmin
    .rpc("get_gateway_secret_value", {
      p_gateway: "razorpay",
      p_secret_name: "webhook_secret",
    });
  if (vaultSecret) return vaultSecret as string;

  // ── 2. Environment variable (backward-compat fallback) ─────────────────────
  return Deno.env.get("RAZORPAY_WEBHOOK_SECRET") ?? null;
}

// ── HMAC-SHA256 webhook signature verification ────────────────────────────────
// Razorpay signs each delivery: HMAC-SHA256(rawBody, RAZORPAY_WEBHOOK_SECRET).
// The resulting hex digest appears in the X-Razorpay-Signature header.
// This is a separate secret from RAZORPAY_KEY_SECRET (used for payment HMAC).

export async function verifyWebhookSignature(
  rawBody: ArrayBuffer,
  signature: string,
  secret: string,
): Promise<boolean> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const signatureBuffer = await crypto.subtle.sign("HMAC", key, rawBody);

  const computed = Array.from(new Uint8Array(signatureBuffer))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  // Constant-time comparison to prevent timing attacks.
  if (computed.length !== signature.length) return false;
  let diff = 0;
  for (let i = 0; i < computed.length; i++) {
    diff |= computed.charCodeAt(i) ^ signature.charCodeAt(i);
  }
  return diff === 0;
}

// ── Refund event handler ──────────────────────────────────────────────────────
//
// Called after the webhook signature has been verified.
//
// Transaction lookup strategy:
//   1. Primary: extract our internal transaction UUID from
//      refundEntity.notes.dodo_transaction_id (embedded when the refund was
//      created by process-razorpay-refund Edge Function).  This is the direct
//      match key — we set it, so it cannot be spoofed once the HMAC is verified.
//
//   2. Fallback: look up refund_transactions.gateway_refund_id = rfnd_XXXXX.
//      Used for refunds whose notes don't contain our UUID (e.g. manual refunds
//      created via the Razorpay dashboard) or for already-completed rows.
//
//   3. If neither lookup matches → acknowledge 200 without any state change to
//      stop Razorpay retries for unknown refunds.
//
// Security notes:
//   • HMAC verification is the auth gate — no admin JWT is present in a webhook.
//   • The transaction UUID in notes was set BY US, so it cannot be forged by an
//     attacker who can only manipulate Razorpay's notes field (they would need
//     the webhook secret to pass HMAC verification first).
//   • The RPCs (webhook_complete/fail_refund_transaction) are SECURITY DEFINER
//     and GRANTED to service_role only — no authenticated user can call them
//     directly.

async function handleRefundEvent(
  event: "refund.processed" | "refund.failed",
  refundEntity: RazorpayRefundEntity,
  supabase: SupabaseClient,
): Promise<Response> {
  const gatewayRefundId = refundEntity.id;
  const transactionIdFromNotes = refundEntity.notes?.dodo_transaction_id ?? null;

  let transactionId: string | null = transactionIdFromNotes;

  if (!transactionId) {
    // ── Fallback: look up by gateway_refund_id already stored in DB ──────────
    const { data: existing } = await supabase
      .from("refund_transactions")
      .select("id, status, gateway_refund_id")
      .eq("gateway_refund_id", gatewayRefundId)
      .maybeSingle();

    if (!existing) {
      // Unknown refund — not created by this system, test event, or manual
      // Razorpay dashboard refund.  Acknowledge to stop retries.
      return Response.json(
        { received: true, handled: false, reason: "unknown_refund" },
      );
    }

    // Quick idempotency for already-terminal rows found by gateway_refund_id.
    if (existing.status === "completed" && event === "refund.processed") {
      return Response.json({ received: true, idempotent: true });
    }
    if (existing.status === "failed" && event === "refund.failed") {
      return Response.json({ received: true, idempotent: true });
    }

    transactionId = existing.id as string;
  }

  // ── Fast idempotency read before acquiring a row lock ─────────────────────
  // The RPCs handle all state-machine transitions correctly under a row lock,
  // so this pre-check is an optimisation only — it is NOT a correctness gate.
  const { data: txn } = await supabase
    .from("refund_transactions")
    .select("id, status, gateway_refund_id")
    .eq("id", transactionId)
    .maybeSingle();

  if (txn) {
    if (
      event === "refund.processed" &&
      txn.status === "completed" &&
      txn.gateway_refund_id === gatewayRefundId
    ) {
      return Response.json({ received: true, idempotent: true });
    }
    if (event === "refund.failed" && txn.status === "failed") {
      return Response.json({ received: true, idempotent: true });
    }
    // A refund.failed event for an already-confirmed transaction is an anomaly.
    // Acknowledge to stop retries but never revert a completed refund.
    if (event === "refund.failed" && txn.status === "completed") {
      console.warn(
        `[razorpay-webhook] refund.failed event for already-completed ` +
          `transaction ${transactionId} (${gatewayRefundId}). ` +
          `Ignoring — a confirmed success is immutable.`,
      );
      return Response.json(
        { received: true, handled: false, reason: "already_complete" },
      );
    }
  }

  // ── Delegate to RPC (handles locking, state transition, audit trail) ───────

  if (event === "refund.processed") {
    const { data: result, error } = await supabase.rpc(
      "webhook_complete_refund_transaction",
      {
        p_transaction_id:    transactionId,
        p_gateway_refund_id: gatewayRefundId,
        p_gateway_response:  refundEntity as unknown as Record<string, unknown>,
      },
    );

    if (error) {
      // P0002 = transaction not found (very unlikely after lookup above).
      if (error.code === "P0002") {
        return Response.json(
          { received: true, handled: false, reason: "transaction_not_found" },
        );
      }
      console.error(
        `[razorpay-webhook] webhook_complete_refund_transaction failed ` +
          `for transaction ${transactionId}: ${error.message}`,
      );
      return Response.json(
        { error: "Failed to update refund record." },
        { status: 500 },
      );
    }

    // 'already_complete' and 'already_failed' are idempotent outcomes.
    return Response.json({
      received: true,
      success: result === "completed",
      idempotent: result !== "completed",
      result,
      gateway_refund_id: gatewayRefundId,
    });
  }

  // ── refund.failed ─────────────────────────────────────────────────────────
  const failureReason =
    String((refundEntity as Record<string, unknown>)["description"] ?? "") ||
    String((refundEntity as Record<string, unknown>)["error_code"] ?? "") ||
    "Refund failed (refund.failed webhook)";

  const { data: result, error } = await supabase.rpc(
    "webhook_fail_refund_transaction",
    {
      p_transaction_id:    transactionId,
      p_gateway_refund_id: gatewayRefundId,
      p_failure_reason:    failureReason,
      p_gateway_response:  refundEntity as unknown as Record<string, unknown>,
    },
  );

  if (error) {
    if (error.code === "P0002") {
      return Response.json(
        { received: true, handled: false, reason: "transaction_not_found" },
      );
    }
    console.error(
      `[razorpay-webhook] webhook_fail_refund_transaction failed ` +
        `for transaction ${transactionId}: ${error.message}`,
    );
    return Response.json(
      { error: "Failed to update refund record." },
      { status: 500 },
    );
  }

  return Response.json({
    received: true,
    failed: result === "failed",
    idempotent: result !== "failed",
    result,
  });
}

// ── Handler ───────────────────────────────────────────────────────────────────

export default {
  fetch: async (req: Request): Promise<Response> => {
    if (req.method !== "POST") {
      return new Response(null, { status: 405 });
    }

    // ── Read raw body BEFORE any JSON parsing ───────────────────────────────
    // The HMAC must be computed over the exact bytes Razorpay sent.
    // Once a body stream is consumed it cannot be re-read, so we hold the
    // ArrayBuffer and derive both the HMAC input and the JSON from it.
    let rawBody: ArrayBuffer;
    try {
      rawBody = await req.arrayBuffer();
    } catch {
      return Response.json({ error: "Failed to read request body." }, { status: 400 });
    }

    // ── Signature header ────────────────────────────────────────────────────
    const signature = req.headers.get("X-Razorpay-Signature");
    if (!signature) {
      return Response.json(
        { error: "Missing X-Razorpay-Signature header." },
        { status: 400 },
      );
    }

    // ── Supabase admin client ───────────────────────────────────────────────
    // Razorpay sends no Supabase JWT, so withSupabase (which validates the JWT)
    // cannot be used. We instantiate createClient directly with the service_role
    // key, which bypasses RLS — the same effective access as ctx.supabaseAdmin
    // in the sibling Edge Functions.
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) {
      return Response.json({ error: "Supabase not configured." }, { status: 503 });
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    // ── Load webhook secret (Vault → env var fallback) ──────────────────────
    const webhookSecret = await loadWebhookSecret(supabase);
    if (!webhookSecret) {
      return Response.json({ error: "Webhook not configured." }, { status: 503 });
    }

    // ── Verify HMAC ─────────────────────────────────────────────────────────
    const signatureValid = await verifyWebhookSignature(rawBody, signature, webhookSecret);
    if (!signatureValid) {
      return Response.json({ error: "Invalid webhook signature." }, { status: 400 });
    }

    // ── Parse JSON from the already-held raw body ───────────────────────────
    let payload: RazorpayWebhookPayload;
    try {
      payload = JSON.parse(
        new TextDecoder().decode(rawBody),
      ) as RazorpayWebhookPayload;
    } catch {
      return Response.json({ error: "Invalid JSON body." }, { status: 400 });
    }

    const { event } = payload;

    // ── Refund events ─────────────────────────────────────────────────────────
    // Handled before payment events to avoid a fall-through to the unknown-event
    // early return.
    if (event === "refund.processed" || event === "refund.failed") {
      const refundEntity = payload.payload?.refund?.entity;
      if (!refundEntity?.id) {
        // Unexpected payload shape — acknowledge to stop retries.
        return Response.json({ received: true, handled: false });
      }
      return handleRefundEvent(event, refundEntity, supabase);
    }

    // ── Payment events ────────────────────────────────────────────────────────
    // Acknowledge unhandled events — return 200 to prevent Razorpay retries.
    if (event !== "payment.captured" && event !== "payment.failed") {
      return Response.json({ received: true, handled: false });
    }

    // ── Extract payment entity ──────────────────────────────────────────────
    const paymentEntity = payload.payload?.payment?.entity;
    if (!paymentEntity?.id || !paymentEntity?.order_id) {
      // Unexpected payload shape — acknowledge to stop retries.
      return Response.json({ received: true, handled: false });
    }

    const razorpayOrderId = paymentEntity.order_id;
    const razorpayPaymentId = paymentEntity.id;

    // ── Look up booking_payments row by gateway_order_id ───────────────────
    // gateway_order_id has a partial unique index — this is a fast indexed lookup.
    const { data: paymentRow, error: lookupError } = await supabase
      .from("booking_payments")
      .select("id, booking_id, gateway, status")
      .eq("gateway_order_id", razorpayOrderId)
      .single();

    if (lookupError || !paymentRow) {
      // Unknown order: test delivery, different system, or late delivery for a
      // manually-cancelled order. Always acknowledge to stop Razorpay retries.
      return Response.json({ received: true, handled: false });
    }

    if (paymentRow.gateway !== "razorpay") {
      return Response.json({ received: true, handled: false });
    }

    // ── Idempotency ─────────────────────────────────────────────────────────
    // A success terminal state is never reversed, even by a late failure event.
    // This also handles the race where verify-razorpay-payment wins first.
    if (paymentRow.status === "success") {
      return Response.json({ received: true, idempotent: true });
    }
    if (event === "payment.failed" && paymentRow.status === "failed") {
      return Response.json({ received: true, idempotent: true });
    }

    // ── payment.captured → success ──────────────────────────────────────────
    if (event === "payment.captured") {
      const { error: paymentUpdateError } = await supabase
        .from("booking_payments")
        .update({
          status: "success",
          gateway_payment_id: razorpayPaymentId,
          verified_at: new Date().toISOString(),
          gateway_response: paymentEntity as unknown as Record<string, unknown>,
        })
        .eq("id", paymentRow.id);

      if (paymentUpdateError) {
        // Non-200 causes Razorpay to retry; idempotency handles re-delivery cleanly.
        return Response.json(
          { error: "Failed to update payment record." },
          { status: 500 },
        );
      }

      const { error: bookingUpdateError } = await supabase
        .from("bookings")
        .update({ payment_status: "success" })
        .eq("id", paymentRow.booking_id);

      if (bookingUpdateError) {
        // booking_payments is already success; the next retry hits idempotency
        // and returns 200 without repeating the bookings update.
        return Response.json(
          { error: "Payment recorded but failed to update booking status." },
          { status: 500 },
        );
      }

      return Response.json({ received: true, success: true });
    }

    // ── payment.failed → failed ─────────────────────────────────────────────
    // Do NOT touch bookings — the customer can retry payment without re-booking.
    const failureReason =
      paymentEntity.error_description ??
      paymentEntity.error_code ??
      "Payment failed";

    const { error: failedUpdateError } = await supabase
      .from("booking_payments")
      .update({
        status: "failed",
        failure_reason: failureReason,
        gateway_payment_id: razorpayPaymentId,
        gateway_response: paymentEntity as unknown as Record<string, unknown>,
      })
      .eq("id", paymentRow.id);

    if (failedUpdateError) {
      return Response.json(
        { error: "Failed to update payment record." },
        { status: 500 },
      );
    }

    return Response.json({ received: true, failed: true });
  },
};
