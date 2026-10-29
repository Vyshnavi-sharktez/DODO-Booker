import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";
import type { SupabaseClient } from "@supabase/supabase-js";

// ── Types ─────────────────────────────────────────────────────────────────────

interface RequestBody {
  subscription_id?: string;
  payment_id?: string;
  vendor_id?: string;
  razorpay_payment_id?: string;
  razorpay_order_id?: string;
  razorpay_signature?: string;
}

interface PaymentRow {
  id: string;
  subscription_id: string;
  vendor_id: string;
  amount: number;
  status: string;
  gateway: string | null;
  gateway_order_id: string | null;
}

interface SubscriptionRow {
  id: string;
  vendor_id: string;
  plan_id: string | null;
  catalog_node_id: string | null;
  status: string;
  plan_duration_days: number | null;
}

// ── Credential loading ────────────────────────────────────────────────────────

async function loadKeySecret(supabaseAdmin: SupabaseClient): Promise<string | null> {
  const { data: vaultSecret } = await supabaseAdmin.rpc("get_gateway_secret_value", {
    p_gateway: "razorpay",
    p_secret_name: "key_secret",
  });
  if (vaultSecret) return vaultSecret as string;
  return Deno.env.get("RAZORPAY_KEY_SECRET") ?? null;
}

// ── HMAC-SHA256 signature verification ───────────────────────────────────────
// Identical algorithm to verify-razorpay-payment and verify-vendor-wallet-topup.
// message = razorpay_order_id + "|" + razorpay_payment_id

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

// ── Duration resolution ───────────────────────────────────────────────────────
// Resolves plan_duration_days for expiry calculation. Priority:
//   1. vendor_subscriptions.plan_duration_days (set at purchase time — preferred)
//   2. subscription_plans.duration_days (global plans only)
//   3. catalog_node_configs.config->>'duration_days' (catalog plans only)

async function resolveDurationDays(
  supabaseAdmin: SupabaseClient,
  subscription: SubscriptionRow,
): Promise<number | null> {
  if (subscription.plan_duration_days && subscription.plan_duration_days > 0) {
    return subscription.plan_duration_days;
  }

  if (subscription.plan_id) {
    const { data: plan } = await supabaseAdmin
      .from("subscription_plans")
      .select("duration_days")
      .eq("id", subscription.plan_id)
      .single<{ duration_days: number }>();
    if (plan?.duration_days) return plan.duration_days;
  }

  if (subscription.catalog_node_id) {
    const { data: nodeConfig } = await supabaseAdmin
      .from("catalog_node_configs")
      .select("config")
      .eq("node_id", subscription.catalog_node_id)
      .eq("module", "vendor_subscription")
      .maybeSingle<{ config: Record<string, unknown> }>();
    const days = (nodeConfig?.config as Record<string, unknown>)?.duration_days;
    if (typeof days === "number" && days > 0) return days;
  }

  return null;
}

// ── Handler ───────────────────────────────────────────────────────────────────

export default {
  fetch: withSupabase({ auth: ["publishable", "secret"] }, async (req, ctx) => {
    let body: RequestBody;
    try {
      body = await req.json() as RequestBody;
    } catch {
      return Response.json({ error: "Invalid JSON body." }, { status: 400 });
    }

    const {
      subscription_id,
      payment_id,
      vendor_id,
      razorpay_payment_id,
      razorpay_order_id,
      razorpay_signature,
    } = body;

    if (!subscription_id || typeof subscription_id !== "string" || subscription_id.trim() === "") {
      return Response.json({ error: "subscription_id is required." }, { status: 400 });
    }
    if (!payment_id || typeof payment_id !== "string" || payment_id.trim() === "") {
      return Response.json({ error: "payment_id is required." }, { status: 400 });
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

    // ── Load key secret ───────────────────────────────────────────────────────
    const keySecret = await loadKeySecret(ctx.supabaseAdmin);
    if (!keySecret) {
      return Response.json({ error: "Payment gateway is not configured." }, { status: 503 });
    }

    // ── Fetch payment row ─────────────────────────────────────────────────────
    const { data: payment, error: paymentError } = await ctx.supabaseAdmin
      .from("vendor_subscription_payments")
      .select("id, subscription_id, vendor_id, amount, status, gateway, gateway_order_id")
      .eq("id", payment_id)
      .single<PaymentRow>();

    if (paymentError || !payment) {
      return Response.json({ error: "Payment record not found." }, { status: 404 });
    }

    // ── Cross-validate all supplied IDs against the DB row ───────────────────
    if (payment.vendor_id !== vendor_id) {
      return Response.json(
        { error: "vendor_id does not match the payment record." },
        { status: 422 },
      );
    }
    if (payment.subscription_id !== subscription_id) {
      return Response.json(
        { error: "subscription_id does not match the payment record." },
        { status: 422 },
      );
    }
    if (payment.gateway !== "razorpay") {
      return Response.json(
        { error: "Payment record is not a Razorpay payment." },
        { status: 422 },
      );
    }
    if (payment.gateway_order_id !== razorpay_order_id) {
      return Response.json(
        { error: "razorpay_order_id does not match the payment record." },
        { status: 422 },
      );
    }

    // ── Idempotency: already verified ─────────────────────────────────────────
    if (payment.status === "paid") {
      return Response.json({ success: true, idempotent: true });
    }

    if (payment.status !== "pending") {
      return Response.json(
        { error: `Payment is in status '${payment.status}' and cannot be verified.` },
        { status: 409 },
      );
    }

    // ── Verify HMAC-SHA256 signature ──────────────────────────────────────────
    const signatureValid = await verifyRazorpaySignature(
      razorpay_order_id,
      razorpay_payment_id,
      razorpay_signature,
      keySecret,
    );

    if (!signatureValid) {
      await ctx.supabaseAdmin
        .from("vendor_subscription_payments")
        .update({
          status: "failed",
          failure_reason: "signature_mismatch",
          gateway_payment_id: razorpay_payment_id,
          gateway_signature: razorpay_signature,
        })
        .eq("id", payment_id);

      return Response.json(
        { error: "Payment verification failed: signature mismatch." },
        { status: 400 },
      );
    }

    // ── Fetch subscription row ────────────────────────────────────────────────
    const { data: subscription, error: subError } = await ctx.supabaseAdmin
      .from("vendor_subscriptions")
      .select("id, vendor_id, plan_id, catalog_node_id, status, plan_duration_days")
      .eq("id", subscription_id)
      .single<SubscriptionRow>();

    if (subError || !subscription) {
      return Response.json({ error: "Subscription record not found." }, { status: 404 });
    }

    if (subscription.vendor_id !== vendor_id) {
      return Response.json(
        { error: "vendor_id does not match the subscription record." },
        { status: 422 },
      );
    }

    // ── Resolve plan duration for expiry calculation ──────────────────────────
    const durationDays = await resolveDurationDays(ctx.supabaseAdmin, subscription);
    if (!durationDays || durationDays <= 0) {
      return Response.json(
        { error: "Could not determine subscription duration. Contact support." },
        { status: 500 },
      );
    }

    const now = new Date();
    const expiryDate = new Date(now.getTime() + durationDays * 24 * 60 * 60 * 1000);

    // ── Mark payment paid ─────────────────────────────────────────────────────
    const { error: paymentUpdateError } = await ctx.supabaseAdmin
      .from("vendor_subscription_payments")
      .update({
        status: "paid",
        paid_at: now.toISOString(),
        payment_reference: razorpay_payment_id,
        gateway_payment_id: razorpay_payment_id,
        gateway_signature: razorpay_signature,
      })
      .eq("id", payment_id);

    if (paymentUpdateError) {
      return Response.json({ error: "Failed to update payment record." }, { status: 500 });
    }

    // ── Activate subscription ─────────────────────────────────────────────────
    const { error: subUpdateError } = await ctx.supabaseAdmin
      .from("vendor_subscriptions")
      .update({
        status: "active",
        start_date: now.toISOString(),
        expiry_date: expiryDate.toISOString(),
      })
      .eq("id", subscription_id);

    if (subUpdateError) {
      return Response.json(
        { error: "Payment recorded but failed to activate subscription. Contact support." },
        { status: 500 },
      );
    }

    return Response.json({ success: true });
  }),
};
