import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";
import type { SupabaseClient } from "@supabase/supabase-js";

// ── Types ─────────────────────────────────────────────────────────────────────

interface RequestBody {
  subscription_id?: string;
  payment_id?: string;
  vendor_id?: string;
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

interface RazorpayCredentials {
  keyId: string;
  keySecret: string;
}

// ── Credential loading ────────────────────────────────────────────────────────
// Identical resolution order to create-razorpay-order and create-vendor-wallet-topup-order:
//   1. Admin Panel / Supabase Vault (payment_gateway_configs + get_gateway_secret_value)
//   2. RAZORPAY_KEY_ID + RAZORPAY_KEY_SECRET env vars (backward-compat fallback)

async function loadRazorpayCredentials(
  supabaseAdmin: SupabaseClient,
): Promise<RazorpayCredentials | null> {
  const { data: cfg } = await supabaseAdmin
    .from("payment_gateway_configs")
    .select("is_enabled, public_key")
    .eq("gateway", "razorpay")
    .single();

  if (cfg !== null) {
    if (!cfg.is_enabled) return null;
    if (cfg.public_key) {
      const { data: vaultSecret } = await supabaseAdmin.rpc(
        "get_gateway_secret_value",
        { p_gateway: "razorpay", p_secret_name: "key_secret" },
      );
      if (vaultSecret) {
        return { keyId: cfg.public_key, keySecret: vaultSecret as string };
      }
    }
  }

  const envKeyId = Deno.env.get("RAZORPAY_KEY_ID");
  const envKeySecret = Deno.env.get("RAZORPAY_KEY_SECRET");
  if (envKeyId && envKeySecret) {
    return { keyId: envKeyId, keySecret: envKeySecret };
  }

  return null;
}

// ── Razorpay Orders API ───────────────────────────────────────────────────────

async function createRazorpayOrder(
  keyId: string,
  keySecret: string,
  amountPaise: number,
  receipt: string,
): Promise<{ id: string; amount: number; currency: string }> {
  const credentials = btoa(`${keyId}:${keySecret}`);

  const res = await fetch("https://api.razorpay.com/v1/orders", {
    method: "POST",
    headers: {
      "Authorization": `Basic ${credentials}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ amount: amountPaise, currency: "INR", receipt }),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Razorpay API error ${res.status}: ${body}`);
  }

  return res.json() as Promise<{ id: string; amount: number; currency: string }>;
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

    const { subscription_id, payment_id, vendor_id } = body;

    if (!subscription_id || typeof subscription_id !== "string" || subscription_id.trim() === "") {
      return Response.json({ error: "subscription_id is required." }, { status: 400 });
    }
    if (!payment_id || typeof payment_id !== "string" || payment_id.trim() === "") {
      return Response.json({ error: "payment_id is required." }, { status: 400 });
    }
    if (!vendor_id || typeof vendor_id !== "string" || vendor_id.trim() === "") {
      return Response.json({ error: "vendor_id is required." }, { status: 400 });
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

    // ── Validate ownership ────────────────────────────────────────────────────
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

    // ── Guard against invalid states ──────────────────────────────────────────
    if (payment.status === "paid") {
      return Response.json(
        { error: "This subscription has already been paid." },
        { status: 409 },
      );
    }
    if (payment.status === "failed") {
      return Response.json(
        { error: "This payment attempt has failed. Please go back and start a new payment." },
        { status: 409 },
      );
    }
    if (payment.status !== "pending") {
      return Response.json(
        { error: `Payment is in unexpected status '${payment.status}'.` },
        { status: 422 },
      );
    }

    // ── Validate amount ───────────────────────────────────────────────────────
    if (!payment.amount || payment.amount <= 0) {
      return Response.json({ error: "Payment amount must be greater than zero." }, { status: 422 });
    }

    const amountPaise = Math.round(payment.amount * 100);
    if (amountPaise < 100) {
      return Response.json({ error: "Minimum payment amount is ₹1.00." }, { status: 422 });
    }

    // ── Load Razorpay credentials ─────────────────────────────────────────────
    const creds = await loadRazorpayCredentials(ctx.supabaseAdmin);
    if (!creds) {
      return Response.json(
        { error: "Payment gateway is not configured or is disabled." },
        { status: 503 },
      );
    }

    // ── Idempotency: reuse an existing pending order ──────────────────────────
    // Covers the case where create-subscription-order succeeded but the response
    // was lost (network failure). The vendor retaps "Pay Now" — same order is returned
    // so they can complete the same Razorpay checkout session.
    if (payment.gateway_order_id && payment.gateway === "razorpay") {
      return Response.json({
        key_id: creds.keyId,
        order_id: payment.gateway_order_id,
        amount_paise: amountPaise,
        currency: "INR",
      });
    }

    // ── Create Razorpay order ─────────────────────────────────────────────────
    // Receipt prefix 'sp_' (subscription payment) distinguishes these orders from
    // booking payments ('bp_') and wallet top-ups ('vwt_') in the Razorpay dashboard.
    let razorpayOrder: { id: string; amount: number; currency: string };
    try {
      razorpayOrder = await createRazorpayOrder(
        creds.keyId,
        creds.keySecret,
        amountPaise,
        `sp_${payment_id}`,
      );
    } catch (err) {
      await ctx.supabaseAdmin
        .from("vendor_subscription_payments")
        .update({
          status: "failed",
          failure_reason: err instanceof Error ? err.message : "Razorpay order creation failed.",
          gateway_response: { error: String(err) },
        })
        .eq("id", payment_id);

      return Response.json(
        { error: "Failed to create payment order. Please try again." },
        { status: 502 },
      );
    }

    // ── Persist gateway order ID ──────────────────────────────────────────────
    const { error: updateError } = await ctx.supabaseAdmin
      .from("vendor_subscription_payments")
      .update({
        gateway: "razorpay",
        gateway_order_id: razorpayOrder.id,
        gateway_response: razorpayOrder as unknown as Record<string, unknown>,
      })
      .eq("id", payment_id);

    if (updateError) {
      return Response.json(
        { error: "Order created but failed to save. Contact support with payment ID." },
        { status: 500 },
      );
    }

    return Response.json({
      key_id: creds.keyId,
      order_id: razorpayOrder.id,
      amount_paise: razorpayOrder.amount,
      currency: "INR",
    });
  }),
};
