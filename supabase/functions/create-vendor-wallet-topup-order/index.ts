import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";
import type { SupabaseClient } from "@supabase/supabase-js";

// ── Types ─────────────────────────────────────────────────────────────────────

interface RequestBody {
  vendor_id?: string;
  amount?: number; // rupees (e.g. 500.00); converted to paise server-side
}

interface RazorpayCredentials {
  keyId: string;
  keySecret: string;
}

interface RazorpayOrderResponse {
  id: string;
  amount: number;
  currency: string;
  receipt: string;
  status: string;
}

// ── Credential loading ────────────────────────────────────────────────────────
// Identical resolution order to create-razorpay-order:
//   1. Admin Panel / Supabase Vault (payment_gateway_configs + get_gateway_secret_value)
//   2. RAZORPAY_KEY_ID + RAZORPAY_KEY_SECRET env vars (backward-compat fallback)
//
// is_enabled=false → returns null → caller returns 503 (gateway disabled).

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

  // Env-var fallback for pre-Admin-Panel deployments.
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
): Promise<RazorpayOrderResponse> {
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

  return res.json() as Promise<RazorpayOrderResponse>;
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

    const { vendor_id, amount } = body;

    if (!vendor_id || typeof vendor_id !== "string" || vendor_id.trim() === "") {
      return Response.json({ error: "vendor_id is required." }, { status: 400 });
    }
    if (typeof amount !== "number" || !isFinite(amount) || amount <= 0) {
      return Response.json(
        { error: "amount must be a positive number (rupees)." },
        { status: 400 },
      );
    }

    // Round to 2 decimal places to guard against floating-point drift.
    const amountRupees = Math.round(amount * 100) / 100;
    const amountPaise = Math.round(amountRupees * 100);

    if (amountPaise < 100) {
      return Response.json(
        { error: "Minimum top-up amount is ₹1.00." },
        { status: 422 },
      );
    }

    // ── Validate vendor exists ─────────────────────────────────────────────
    const { data: vendor, error: vendorError } = await ctx.supabaseAdmin
      .from("vendors")
      .select("id")
      .eq("id", vendor_id)
      .single<{ id: string }>();

    if (vendorError || !vendor) {
      return Response.json({ error: "Vendor not found." }, { status: 404 });
    }

    // ── Load Razorpay credentials ─────────────────────────────────────────
    const creds = await loadRazorpayCredentials(ctx.supabaseAdmin);
    if (!creds) {
      return Response.json(
        { error: "Payment gateway is not configured or is disabled." },
        { status: 503 },
      );
    }

    // ── Idempotency: reuse an existing pending order for the same vendor/amount
    // Covers the case where the vendor taps "Add Money" and the network fails
    // before the Razorpay sheet opens, then retries immediately.
    const { data: reusable } = await ctx.supabaseAdmin
      .from("vendor_wallet_topup_attempts")
      .select("id, gateway_order_id, amount")
      .eq("vendor_id", vendor_id)
      .eq("status", "pending")
      .eq("amount", amountRupees)
      .not("gateway_order_id", "is", null)
      .order("created_at", { ascending: false })
      .limit(1);

    if (reusable && reusable.length > 0) {
      const existing = reusable[0] as {
        id: string;
        gateway_order_id: string;
        amount: number;
      };
      return Response.json({
        attempt_id: existing.id,
        key_id: creds.keyId,
        order_id: existing.gateway_order_id,
        amount_paise: amountPaise,
        currency: "INR",
      });
    }

    // ── Insert pending attempt row ─────────────────────────────────────────
    const { data: attemptRow, error: insertError } = await ctx.supabaseAdmin
      .from("vendor_wallet_topup_attempts")
      .insert({
        vendor_id,
        amount: amountRupees,
        gateway: "razorpay",
        status: "pending",
      })
      .select("id")
      .single<{ id: string }>();

    if (insertError || !attemptRow) {
      return Response.json(
        { error: "Failed to create top-up attempt record." },
        { status: 500 },
      );
    }

    // ── Create Razorpay order ─────────────────────────────────────────────
    // Receipt prefix 'vwt_' (vendor wallet topup) distinguishes these orders
    // from booking payment orders ('bp_') in the Razorpay dashboard and webhook.
    let razorpayOrder: RazorpayOrderResponse;
    try {
      razorpayOrder = await createRazorpayOrder(
        creds.keyId,
        creds.keySecret,
        amountPaise,
        `vwt_${attemptRow.id}`,
      );
    } catch (err) {
      await ctx.supabaseAdmin
        .from("vendor_wallet_topup_attempts")
        .update({
          status: "failed",
          failure_reason: err instanceof Error
            ? err.message
            : "Razorpay order creation failed.",
          gateway_response: { error: String(err) },
        })
        .eq("id", attemptRow.id);

      return Response.json(
        { error: "Failed to create payment order. Please try again." },
        { status: 502 },
      );
    }

    // ── Persist gateway_order_id ───────────────────────────────────────────
    const { error: updateError } = await ctx.supabaseAdmin
      .from("vendor_wallet_topup_attempts")
      .update({
        gateway_order_id: razorpayOrder.id,
        gateway_response: razorpayOrder as unknown as Record<string, unknown>,
      })
      .eq("id", attemptRow.id);

    if (updateError) {
      return Response.json(
        {
          error:
            "Order created but failed to save. Contact support with vendor ID.",
        },
        { status: 500 },
      );
    }

    return Response.json({
      attempt_id: attemptRow.id,
      key_id: creds.keyId,
      order_id: razorpayOrder.id,
      amount_paise: razorpayOrder.amount,
      currency: "INR",
    });
  }),
};
