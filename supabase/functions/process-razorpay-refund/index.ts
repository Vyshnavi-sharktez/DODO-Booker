import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";
import type { SupabaseClient } from "@supabase/supabase-js";

// ── Types ─────────────────────────────────────────────────────────────────────

interface RequestBody {
  transaction_id?: string;
}

interface BeginProcessingPayload {
  transaction_id: string;
  refund_request_id: string;
  amount_paise: number;
  gateway_payment_id: string;
}

interface RazorpayRefundEntity {
  id: string;
  entity: string;
  amount: number;
  currency: string;
  payment_id: string;
  status: string;
  receipt: string | null;
  speed_processed: string;
  created_at: number;
  [key: string]: unknown;
}

interface RazorpayErrorBody {
  error?: {
    code: string;
    description: string;
    source?: string;
    step?: string;
    reason?: string;
    [key: string]: unknown;
  };
}

// ── Razorpay error classification ─────────────────────────────────────────────
//
// DEFINITIVE: Razorpay received the request and hard-rejected it.
//   The refund did NOT happen and will NOT happen.  Safe to mark as failed.
//
// UNCERTAIN: We cannot determine whether Razorpay queued the refund internally.
//   Leave transaction in 'processing'; admin must verify in Razorpay dashboard.
//
// Rule: 4xx response from Razorpay = definitive (they rejected our request).
//       5xx or network error      = uncertain (they may have queued it).
//
// These reason codes are also definitively safe to fail even from unusual paths:
const DEFINITIVE_RAZORPAY_REASONS = new Set([
  "payment_not_captured",
  "refund_amount_exceeds_payment_amount",
  "already_refunded",
  "invalid_payment_id",
]);

// ── Credential loading ────────────────────────────────────────────────────────
// Identical resolution order to create-razorpay-order:
//   1. payment_gateway_configs (is_enabled check) → Vault (get_gateway_secret_value)
//   2. RAZORPAY_KEY_ID + RAZORPAY_KEY_SECRET env vars (backward-compat fallback)

async function loadRazorpayCredentials(
  supabaseAdmin: SupabaseClient,
): Promise<{ keyId: string; keySecret: string } | null> {
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
  if (envKeyId && envKeySecret) return { keyId: envKeyId, keySecret: envKeySecret };

  return null;
}

// ── Razorpay Refunds API call ─────────────────────────────────────────────────
//
// POST /v1/payments/{payment_id}/refund
//
// idempotencyKey (= transaction UUID) is sent as X-Idempotency-Key so that
// retrying with the same transaction_id never creates a second refund.
// It is also embedded in receipt and notes for cross-reference in Razorpay
// dashboard.
//
// Returns a discriminated union:
//   { ok: true,  refund: RazorpayRefundEntity }
//   { ok: false, definitive: boolean, code: string, description: string }

async function callRazorpayRefundApi(
  keyId: string,
  keySecret: string,
  gatewayPaymentId: string,
  amountPaise: number,
  idempotencyKey: string,
): Promise<
  | { ok: true; refund: RazorpayRefundEntity }
  | { ok: false; definitive: boolean; code: string; description: string }
> {
  const credentials = btoa(`${keyId}:${keySecret}`);
  const receiptRef = idempotencyKey.replace(/-/g, "").slice(0, 40);

  let res: Response;
  try {
    res = await fetch(
      `https://api.razorpay.com/v1/payments/${gatewayPaymentId}/refund`,
      {
        method: "POST",
        headers: {
          "Authorization": `Basic ${credentials}`,
          "Content-Type": "application/json",
          "X-Idempotency-Key": idempotencyKey,
        },
        body: JSON.stringify({
          amount: amountPaise,
          speed: "normal",
          receipt: receiptRef,
          notes: { dodo_transaction_id: idempotencyKey },
        }),
      },
    );
  } catch (networkErr) {
    // TCP/TLS-level failure before the request reached Razorpay.
    // Uncertain: Razorpay may or may not have queued the refund.
    return {
      ok: false,
      definitive: false,
      code: "NETWORK_ERROR",
      description: networkErr instanceof Error
        ? networkErr.message
        : "Network error contacting Razorpay",
    };
  }

  if (res.ok) {
    const refund = await res.json() as RazorpayRefundEntity;
    return { ok: true, refund };
  }

  // Parse Razorpay error body.
  let errBody: RazorpayErrorBody | null = null;
  try {
    errBody = await res.json() as RazorpayErrorBody;
  } catch { /* ignore non-JSON error body */ }

  const code = errBody?.error?.code ?? `HTTP_${res.status}`;
  const description = errBody?.error?.description ?? `HTTP ${res.status}`;
  const reason = errBody?.error?.reason;

  // A 4xx from Razorpay means they received and rejected the request.
  // The refund was not created.  Safe to mark as a definitive failure.
  // A 5xx means Razorpay's own infrastructure had an issue; the refund may
  // have been queued internally despite the error response.
  const isDefinitive =
    (res.status >= 400 && res.status < 500) ||
    (reason != null && DEFINITIVE_RAZORPAY_REASONS.has(reason));

  return { ok: false, definitive: isDefinitive, code, description };
}

// ── Handler ───────────────────────────────────────────────────────────────────

export default {
  fetch: withSupabase({ auth: ["user", "secret"] }, async (req, ctx) => {
    if (req.method !== "POST") {
      return new Response(null, { status: 405 });
    }

    // ── Parse body ──────────────────────────────────────────────────────────
    let body: RequestBody;
    try {
      body = await req.json() as RequestBody;
    } catch {
      return Response.json({ error: "Invalid JSON body." }, { status: 400 });
    }

    const { transaction_id } = body;
    if (
      !transaction_id ||
      typeof transaction_id !== "string" ||
      transaction_id.trim() === ""
    ) {
      return Response.json({ error: "transaction_id is required." }, { status: 400 });
    }

    // ── Load Razorpay credentials ────────────────────────────────────────────
    // Uses ctx.supabaseAdmin (service_role) for Vault access.
    // Credentials are NEVER returned to the client.
    const creds = await loadRazorpayCredentials(ctx.supabaseAdmin);
    if (!creds) {
      return Response.json(
        { error: "Payment gateway is not configured or disabled." },
        { status: 503 },
      );
    }

    // ── Atomically verify admin + lock transaction + get payment context ────
    //
    // ctx.supabase uses the caller's JWT, so auth.uid() inside the RPC equals
    // the admin's user ID.  fn_assert_active_admin() validates this identity.
    // The FOR UPDATE lock inside the RPC prevents a concurrent Edge Function
    // call from also proceeding to the Razorpay API for the same transaction.
    //
    // The RPC transitions 'pending' → 'processing' and returns everything
    // needed for the API call.  It rejects 'processing' (already in-flight),
    // wrong gateway, missing payment context, and any non-admin caller.
    const { data: payload, error: beginError } = await ctx.supabase.rpc(
      "admin_begin_razorpay_refund_processing",
      { p_transaction_id: transaction_id },
    );

    if (beginError) {
      if (beginError.code === "42501") {
        return Response.json(
          { error: "Not authorised: caller is not an active admin." },
          { status: 403 },
        );
      }
      if (beginError.code === "P0002") {
        return Response.json({ error: beginError.message }, { status: 404 });
      }
      // P0001 covers: already processing, wrong gateway, no payment_id, etc.
      return Response.json({ error: beginError.message }, { status: 409 });
    }

    if (!payload) {
      return Response.json(
        { error: "No data returned from begin_processing RPC." },
        { status: 500 },
      );
    }

    const { amount_paise, gateway_payment_id } =
      payload as unknown as BeginProcessingPayload;

    // ── Call Razorpay Refunds API ────────────────────────────────────────────
    //
    // The transaction is now in 'processing' state.  The Razorpay API call
    // happens outside any database transaction — failures here require manual
    // resolution (check Razorpay dashboard, then mark complete/failed via UI).
    //
    // X-Idempotency-Key = transaction_id:
    //   Razorpay deduplicates on this key.  If this function is retried with
    //   the same transaction_id, Razorpay returns the same refund without
    //   creating a second one.  However, the database transition to 'processing'
    //   already prevents re-entry through admin_begin_razorpay_refund_processing,
    //   so this key is a belt-and-suspenders safeguard.
    const razorpayResult = await callRazorpayRefundApi(
      creds.keyId,
      creds.keySecret,
      gateway_payment_id,
      amount_paise,
      transaction_id,
    );

    // ── Razorpay accepted the refund request ─────────────────────────────────
    //
    // HTTP 200 from Razorpay does NOT mean the refund has completed.  It means:
    //
    //   status = "processed" — Razorpay immediately settled the refund (rare;
    //     only for instant-refund-eligible payments).  Safe to mark complete now.
    //
    //   status = "pending"   — Razorpay has queued the refund.  Money has NOT
    //     moved yet.  Razorpay will send a refund.processed (or refund.failed)
    //     webhook once the refund clears (typically 5–7 business days for normal
    //     speed).  Do NOT mark the transaction complete yet.
    //
    // Only call admin_mark_refund_transaction_complete when Razorpay explicitly
    // confirms status = "processed".  For any other value (including "pending"),
    // store the gateway_refund_id so the webhook handler can locate this
    // transaction via both the notes-based and gateway_refund_id fallback lookups,
    // then return HTTP 202 so the admin panel knows to wait for the webhook.
    if (razorpayResult.ok) {
      const razorpayRefundStatus = razorpayResult.refund.status;

      if (razorpayRefundStatus === "processed") {
        // ── Immediately settled — mark complete now ───────────────────────────
        const { error: completeError } = await ctx.supabase.rpc(
          "admin_mark_refund_transaction_complete",
          {
            p_transaction_id: transaction_id,
            p_gateway_refund_id: razorpayResult.refund.id,
            p_gateway_response: razorpayResult.refund,
          },
        );

        if (completeError) {
          // CRITICAL: Razorpay settled the refund but our record update failed.
          // The gateway_refund_id UNIQUE constraint prevents double-recording on
          // manual retry.  Log prominently so the admin can reconcile.
          console.error(
            `[process-razorpay-refund] CRITICAL: Razorpay refund ` +
              `${razorpayResult.refund.id} processed for transaction ` +
              `${transaction_id} but admin_mark_refund_transaction_complete ` +
              `failed: ${completeError.message}`,
          );
          return Response.json(
            {
              error:
                "Razorpay confirmed the refund but our record update failed. " +
                `Razorpay refund ID: ${razorpayResult.refund.id}. ` +
                "Use 'Mark Complete' in the UI with this ID to reconcile.",
              gateway_refund_id: razorpayResult.refund.id,
            },
            { status: 500 },
          );
        }

        return Response.json({
          success: true,
          gateway_refund_id: razorpayResult.refund.id,
          razorpay_status: razorpayRefundStatus,
        });
      }

      // ── Refund queued (status = "pending" or any unrecognised value) ────────
      // Store the gateway_refund_id on the transaction while it stays in
      // 'processing' state.  This enables the webhook handler's fallback
      // gateway_refund_id lookup in addition to the notes-based primary lookup.
      // webhook_complete_refund_transaction / webhook_fail_refund_transaction
      // will perform the final state transition when Razorpay delivers the
      // refund.processed or refund.failed event.
      const { error: storeError } = await ctx.supabaseAdmin
        .from("refund_transactions")
        .update({
          gateway_refund_id: razorpayResult.refund.id,
          gateway_response: razorpayResult.refund,
        })
        .eq("id", transaction_id)
        .eq("status", "processing");

      if (storeError) {
        // Non-fatal: the notes-based webhook lookup still works without this.
        console.warn(
          `[process-razorpay-refund] Could not store gateway_refund_id ` +
            `for pending refund on transaction ${transaction_id}: ` +
            storeError.message,
        );
      }

      // Return 202 so the admin panel shows an informational message rather
      // than a success confirmation.  The webhook finalises the transaction.
      return Response.json(
        {
          pending: true,
          message:
            "Razorpay has queued the refund. The transaction will be marked " +
            "complete automatically once Razorpay processes it " +
            "(typically 5–7 business days for normal-speed refunds).",
          gateway_refund_id: razorpayResult.refund.id,
          razorpay_status: razorpayRefundStatus,
        },
        { status: 202 },
      );
    }

    // ── Razorpay returned an error ───────────────────────────────────────────
    const { definitive, code, description } = razorpayResult;

    if (definitive) {
      // Razorpay definitively rejected the refund (4xx).
      // The money did not move.  Safe to mark as failed so admin can retry
      // after resolving the root cause (e.g. wrong payment ID, over-refund).
      const { error: failedError } = await ctx.supabase.rpc(
        "admin_mark_refund_transaction_failed",
        {
          p_transaction_id: transaction_id,
          p_failure_reason: `${code}: ${description}`,
          p_gateway_response: { error_code: code, error_description: description },
        },
      );

      if (failedError) {
        console.error(
          `[process-razorpay-refund] Failed to mark transaction ` +
            `${transaction_id} as failed after Razorpay rejection: ` +
            failedError.message,
        );
      }

      return Response.json(
        { error: `Razorpay rejected the refund: ${description}` },
        { status: 422 },
      );
    }

    // ── Uncertain outcome (5xx or network error) ─────────────────────────────
    //
    // Razorpay may have queued the refund internally despite the error.
    // The transaction stays in 'processing' to preserve the in-flight state.
    // The admin must:
    //   1. Check the Razorpay dashboard for a pending refund on this payment.
    //   2. If found: use 'Mark Complete' in the UI with the rfnd_XXXXX ID.
    //   3. If not found: use 'Mark Failed' in the UI, then retry.
    console.warn(
      `[process-razorpay-refund] Uncertain outcome for transaction ` +
        `${transaction_id}: ${code}: ${description}`,
    );

    return Response.json(
      {
        uncertain: true,
        message:
          "The Razorpay API did not return a clear response. " +
          "The transaction is now in 'processing' state. " +
          "Check the Razorpay dashboard for the original payment and " +
          "mark this transaction complete or failed manually.",
        error_code: code,
      },
      { status: 202 },
    );
  }),
};
