import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";

// ── Types ─────────────────────────────────────────────────────────────────────

interface RequestBody {
  booking_id?: string;
  razorpay_payment_id?: string;
  razorpay_order_id?: string;
  razorpay_signature?: string;
}

interface PaymentRow {
  id: string;
  booking_id: string;
  gateway: string;
  gateway_order_id: string | null;
  status: string;
}

// ── HMAC-SHA256 verification ──────────────────────────────────────────────────

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

  // Constant-time comparison to prevent timing attacks.
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

    const { booking_id, razorpay_payment_id, razorpay_order_id, razorpay_signature } = body;

    if (!booking_id || typeof booking_id !== "string" || booking_id.trim() === "") {
      return Response.json({ error: "booking_id is required." }, { status: 400 });
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

    // ── Load secret before any DB work ─────────────────────────────────────
    const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET");
    if (!keySecret) {
      return Response.json(
        { error: "Payment gateway is not configured." },
        { status: 503 },
      );
    }

    // ── Fetch the payment row by gateway_order_id (indexed, unique) ─────────
    const { data: paymentRow, error: paymentError } = await ctx.supabaseAdmin
      .from("booking_payments")
      .select("id, booking_id, gateway, gateway_order_id, status")
      .eq("gateway_order_id", razorpay_order_id)
      .single<PaymentRow>();

    if (paymentError || !paymentRow) {
      return Response.json({ error: "Payment record not found." }, { status: 404 });
    }

    // ── Validate the payment row against caller-supplied fields ─────────────
    if (paymentRow.booking_id !== booking_id) {
      return Response.json(
        { error: "booking_id does not match the payment record." },
        { status: 422 },
      );
    }

    if (paymentRow.gateway !== "razorpay") {
      return Response.json(
        { error: "Payment record is not a Razorpay payment." },
        { status: 422 },
      );
    }

    // ── Idempotency: already verified — return success without mutating ──────
    if (paymentRow.status === "success") {
      return Response.json({ success: true, idempotent: true });
    }

    // ── Verify HMAC-SHA256 signature ────────────────────────────────────────
    const signatureValid = await verifyRazorpaySignature(
      razorpay_order_id,
      razorpay_payment_id,
      razorpay_signature,
      keySecret,
    );

    if (!signatureValid) {
      // Mark the attempt as failed; do NOT touch bookings.payment_status.
      await ctx.supabaseAdmin
        .from("booking_payments")
        .update({
          status: "failed",
          failure_reason: "signature_mismatch",
        })
        .eq("id", paymentRow.id);

      return Response.json(
        { error: "Payment verification failed: signature mismatch." },
        { status: 400 },
      );
    }

    // ── Signature valid: update booking_payments ────────────────────────────
    const { error: paymentUpdateError } = await ctx.supabaseAdmin
      .from("booking_payments")
      .update({
        status: "success",
        gateway_payment_id: razorpay_payment_id,
        gateway_signature: razorpay_signature,
        verified_at: new Date().toISOString(),
      })
      .eq("id", paymentRow.id);

    if (paymentUpdateError) {
      return Response.json(
        { error: "Failed to update payment record." },
        { status: 500 },
      );
    }

    // ── Update bookings.payment_status ──────────────────────────────────────
    const { error: bookingUpdateError } = await ctx.supabaseAdmin
      .from("bookings")
      .update({ payment_status: "success" })
      .eq("id", booking_id);

    if (bookingUpdateError) {
      return Response.json(
        { error: "Payment recorded but failed to update booking status. Contact support." },
        { status: 500 },
      );
    }

    return Response.json({ success: true });
  }),
};
