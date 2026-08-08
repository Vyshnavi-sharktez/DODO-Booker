import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";

// ── Types ─────────────────────────────────────────────────────────────────────

interface RazorpayPaymentEntity {
  id: string;
  order_id: string;
  error_description?: string;
  error_code?: string;
  [key: string]: unknown;
}

interface RazorpayWebhookPayload {
  event: string;
  payload: {
    payment: {
      entity: RazorpayPaymentEntity;
    };
  };
}

// ── HMAC-SHA256 webhook signature verification ────────────────────────────────
// Razorpay signs each delivery: HMAC-SHA256(rawBody, RAZORPAY_WEBHOOK_SECRET).
// The resulting hex digest appears in the X-Razorpay-Signature header.
// This is a separate secret from RAZORPAY_KEY_SECRET (used for payment HMAC).

async function verifyWebhookSignature(
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

    // ── Load webhook secret ─────────────────────────────────────────────────
    const webhookSecret = Deno.env.get("RAZORPAY_WEBHOOK_SECRET");
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
