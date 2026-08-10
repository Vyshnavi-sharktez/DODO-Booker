import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";
import type { SupabaseClient } from "@supabase/supabase-js";

// ── Types ─────────────────────────────────────────────────────────────────────

interface RequestBody {
  booking_id?: string;
}

interface Booking {
  id: string;
  total_amount: number;
  payment_method: string;
  payment_status: string;
}

interface RazorpayOrderResponse {
  id: string;
  amount: number;
  currency: string;
  receipt: string;
  status: string;
}

interface RazorpayCredentials {
  keyId: string;
  keySecret: string;
}

// ── Credential loading ────────────────────────────────────────────────────────
// Resolution order:
//   1. Admin Panel / Supabase Vault (payment_gateway_configs + get_gateway_secret_value)
//   2. RAZORPAY_KEY_ID + RAZORPAY_KEY_SECRET env vars (backward-compat fallback only)
//
// is_enabled enforcement:
//   When a payment_gateway_configs row exists, its is_enabled flag is authoritative.
//   is_enabled=false → return null immediately (blocks order creation).
//   The env-var fallback is only reached when no DB row exists at all (legacy deployments).
//
// Test vs Live mode:
//   The mode column is informational — it is NOT checked here. The credential itself
//   determines test vs live: Razorpay keys are prefixed rzp_test_ or rzp_live_ and
//   Razorpay enforces the mode server-side. The Admin Panel mode field helps the admin
//   track which credential set they have entered.

async function loadRazorpayCredentials(
  supabaseAdmin: SupabaseClient,
): Promise<RazorpayCredentials | null> {
  // ── 1. Vault / Admin Panel (preferred) ─────────────────────────────────────
  const { data: cfg } = await supabaseAdmin
    .from("payment_gateway_configs")
    .select("is_enabled, public_key")
    .eq("gateway", "razorpay")
    .single();

  if (cfg !== null) {
    // Admin Panel row exists — it is the authority for enable/disable.
    // Explicitly disabled → block new order creation regardless of env vars.
    if (!cfg.is_enabled) return null;

    if (cfg.public_key) {
      const { data: vaultSecret } = await supabaseAdmin
        .rpc("get_gateway_secret_value", {
          p_gateway: "razorpay",
          p_secret_name: "key_secret",
        });
      if (vaultSecret) {
        return { keyId: cfg.public_key, keySecret: vaultSecret as string };
      }
    }
  }

  // ── 2. Environment variables (backward-compat fallback) ────────────────────
  // Only reached when no payment_gateway_configs row exists (pre-Admin-Panel deployments).
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
    body: JSON.stringify({
      amount: amountPaise,
      currency: "INR",
      receipt,
    }),
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

    const { booking_id } = body;

    if (!booking_id || typeof booking_id !== "string" || booking_id.trim() === "") {
      return Response.json({ error: "booking_id is required." }, { status: 400 });
    }

    // ── Fetch booking (server-side; never trust client for amount) ──────────
    const { data: booking, error: bookingError } = await ctx.supabaseAdmin
      .from("bookings")
      .select("id, total_amount, payment_method, payment_status")
      .eq("id", booking_id)
      .single<Booking>();

    if (bookingError || !booking) {
      return Response.json({ error: "Booking not found." }, { status: 404 });
    }

    // ── Validate payment method ─────────────────────────────────────────────
    if (booking.payment_method !== "razorpay") {
      return Response.json(
        { error: "This booking is not configured for Razorpay payment." },
        { status: 422 },
      );
    }

    // ── Guard against double payment ────────────────────────────────────────
    if (booking.payment_status === "success") {
      return Response.json(
        { error: "This booking has already been paid." },
        { status: 409 },
      );
    }

    // ── Load Razorpay credentials (Vault → env var fallback) ───────────────────
    const creds = await loadRazorpayCredentials(ctx.supabaseAdmin);
    if (!creds) {
      return Response.json(
        { error: "Payment gateway is not configured." },
        { status: 503 },
      );
    }

    // ── Idempotency: reuse an existing pending order if one exists ───────────
    // Covers cases where the client retries after a network failure mid-flow.
    const { data: reusableRows, error: reusableError } = await ctx.supabaseAdmin
      .from("booking_payments")
      .select("id, gateway_order_id, amount, currency")
      .eq("booking_id", booking_id)
      .eq("gateway", "razorpay")
      .eq("status", "pending")
      .not("gateway_order_id", "is", null)
      .order("attempt_number", { ascending: false })
      .limit(1);

    if (reusableError) {
      return Response.json(
        { error: "Failed to check for existing payment order." },
        { status: 500 },
      );
    }

    if (reusableRows && reusableRows.length > 0) {
      const existing = reusableRows[0] as {
        id: string;
        gateway_order_id: string;
        amount: number;
        currency: string;
      };
      return Response.json({
        key_id: creds.keyId,
        order_id: existing.gateway_order_id,
        amount: Math.round(existing.amount * 100),
        currency: existing.currency,
      });
    }

    // ── Resolve next attempt_number ─────────────────────────────────────────
    const { data: existingAttempts, error: attemptsError } = await ctx.supabaseAdmin
      .from("booking_payments")
      .select("attempt_number")
      .eq("booking_id", booking_id)
      .order("attempt_number", { ascending: false })
      .limit(1);

    if (attemptsError) {
      return Response.json(
        { error: "Failed to resolve payment attempt number." },
        { status: 500 },
      );
    }

    const lastAttempt = existingAttempts?.[0]?.attempt_number ?? 0;
    const attemptNumber = (lastAttempt as number) + 1;

    // ── Amount: always from bookings.total_amount, converted to paise ───────
    const amountPaise = Math.round(booking.total_amount * 100);

    // ── Insert booking_payments row (status = pending) ──────────────────────
    const { data: paymentRow, error: insertError } = await ctx.supabaseAdmin
      .from("booking_payments")
      .insert({
        booking_id,
        gateway: "razorpay",
        amount: booking.total_amount,
        currency: "INR",
        status: "pending",
        attempt_number: attemptNumber,
      })
      .select("id")
      .single<{ id: string }>();

    if (insertError || !paymentRow) {
      return Response.json(
        { error: "Failed to create payment record." },
        { status: 500 },
      );
    }

    // ── Create order with Razorpay ──────────────────────────────────────────
    let razorpayOrder: RazorpayOrderResponse;
    try {
      razorpayOrder = await createRazorpayOrder(
        creds.keyId,
        creds.keySecret,
        amountPaise,
        `bp_${paymentRow.id}`,
      );
    } catch (err) {
      await ctx.supabaseAdmin
        .from("booking_payments")
        .update({
          status: "failed",
          failure_reason: err instanceof Error ? err.message : "Razorpay order creation failed.",
          gateway_response: { error: String(err) },
        })
        .eq("id", paymentRow.id);

      return Response.json(
        { error: "Failed to create payment order. Please try again." },
        { status: 502 },
      );
    }

    // ── Persist gateway_order_id and raw gateway response ───────────────────
    const { error: updateError } = await ctx.supabaseAdmin
      .from("booking_payments")
      .update({
        gateway_order_id: razorpayOrder.id,
        gateway_response: razorpayOrder as unknown as Record<string, unknown>,
      })
      .eq("id", paymentRow.id);

    if (updateError) {
      return Response.json(
        { error: "Order created but failed to save. Contact support with booking ID." },
        { status: 500 },
      );
    }

    // ── Return only what the Flutter SDK needs ───────────────────────────────
    return Response.json({
      key_id: creds.keyId,
      order_id: razorpayOrder.id,
      amount: razorpayOrder.amount,
      currency: "INR",
    });
  }),
};
