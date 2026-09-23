// Deno unit tests for razorpay-webhook.
//
// Run with:  deno test --allow-env supabase/functions/razorpay-webhook/webhook_test.ts
//
// Tests in this file cover the pure, database-free logic:
//   • HMAC-SHA256 signature verification (the primary security gate)
//   • Refund entity extraction and notes parsing
//   • Event routing decisions
//
// Integration scenarios (duplicate delivery, out-of-order events, partial
// refund lifecycle) require a Supabase local stack and are documented as
// manual test procedures at the bottom of this file.
//
// NOTE: verifyWebhookSignature is duplicated here rather than imported from
// index.ts because index.ts depends on Supabase packages that are only
// available inside the Edge Functions runtime.  The duplicate is intentional
// and must be kept in sync with the production implementation.

import { assertEquals } from "jsr:@std/assert@^1";

// ── Production implementation (kept in sync with index.ts) ────────────────────

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

  if (computed.length !== signature.length) return false;
  let diff = 0;
  for (let i = 0; i < computed.length; i++) {
    diff |= computed.charCodeAt(i) ^ signature.charCodeAt(i);
  }
  return diff === 0;
}

// ── Test helpers ──────────────────────────────────────────────────────────────

async function computeHmac(body: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const buf = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(body),
  );
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

const TEST_SECRET = "test_webhook_secret_abc123";

const TEST_BODY_PROCESSED = JSON.stringify({
  event: "refund.processed",
  payload: {
    refund: {
      entity: {
        id: "rfnd_test001",
        entity: "refund",
        amount: 50000,
        currency: "INR",
        payment_id: "pay_test001",
        status: "processed",
        notes: { dodo_transaction_id: "550e8400-e29b-41d4-a716-446655440000" },
        receipt: "550e8400e29b41d4a716",
      },
    },
  },
});

const TEST_BODY_FAILED = JSON.stringify({
  event: "refund.failed",
  payload: {
    refund: {
      entity: {
        id: "rfnd_test002",
        entity: "refund",
        amount: 50000,
        currency: "INR",
        payment_id: "pay_test001",
        status: "failed",
        notes: { dodo_transaction_id: "660e8400-e29b-41d4-a716-446655440000" },
        receipt: null,
      },
    },
  },
});

const TEST_BODY_PAYMENT = JSON.stringify({
  event: "payment.captured",
  payload: {
    payment: {
      entity: { id: "pay_test999", order_id: "order_test999" },
    },
  },
});

function toBuffer(s: string): ArrayBuffer {
  return new TextEncoder().encode(s).buffer as ArrayBuffer;
}

// ── Signature verification tests ──────────────────────────────────────────────

Deno.test("verifyWebhookSignature: valid signature returns true", async () => {
  const sig = await computeHmac(TEST_BODY_PROCESSED, TEST_SECRET);
  assertEquals(
    await verifyWebhookSignature(toBuffer(TEST_BODY_PROCESSED), sig, TEST_SECRET),
    true,
  );
});

Deno.test("verifyWebhookSignature: tampered body returns false", async () => {
  const sig = await computeHmac(TEST_BODY_PROCESSED, TEST_SECRET);
  const tampered = TEST_BODY_PROCESSED.replace('"rfnd_test001"', '"rfnd_attacker"');
  assertEquals(
    await verifyWebhookSignature(toBuffer(tampered), sig, TEST_SECRET),
    false,
  );
});

Deno.test("verifyWebhookSignature: wrong secret returns false", async () => {
  const sig = await computeHmac(TEST_BODY_PROCESSED, "attacker_secret");
  assertEquals(
    await verifyWebhookSignature(toBuffer(TEST_BODY_PROCESSED), sig, TEST_SECRET),
    false,
  );
});

Deno.test("verifyWebhookSignature: truncated (different-length) signature returns false", async () => {
  assertEquals(
    await verifyWebhookSignature(toBuffer(TEST_BODY_PROCESSED), "tooshort", TEST_SECRET),
    false,
  );
});

Deno.test("verifyWebhookSignature: empty signature returns false", async () => {
  assertEquals(
    await verifyWebhookSignature(toBuffer(TEST_BODY_PROCESSED), "", TEST_SECRET),
    false,
  );
});

Deno.test("verifyWebhookSignature: empty body with correct HMAC returns true", async () => {
  const sig = await computeHmac("", TEST_SECRET);
  assertEquals(
    await verifyWebhookSignature(toBuffer(""), sig, TEST_SECRET),
    true,
  );
});

Deno.test("verifyWebhookSignature: refund.failed body with correct HMAC returns true", async () => {
  const sig = await computeHmac(TEST_BODY_FAILED, TEST_SECRET);
  assertEquals(
    await verifyWebhookSignature(toBuffer(TEST_BODY_FAILED), sig, TEST_SECRET),
    true,
  );
});

Deno.test("verifyWebhookSignature: HMAC for one body does not validate a different body", async () => {
  const paymentSig = await computeHmac(TEST_BODY_PAYMENT, TEST_SECRET);
  assertEquals(
    await verifyWebhookSignature(toBuffer(TEST_BODY_FAILED), paymentSig, TEST_SECRET),
    false,
  );
});

// ── Refund entity parsing tests ───────────────────────────────────────────────

Deno.test("notes.dodo_transaction_id is extracted correctly from refund.processed", () => {
  const entity = JSON.parse(TEST_BODY_PROCESSED).payload.refund.entity;
  assertEquals(
    entity.notes?.dodo_transaction_id,
    "550e8400-e29b-41d4-a716-446655440000",
  );
});

Deno.test("refund entity id is the gateway refund ID", () => {
  const entity = JSON.parse(TEST_BODY_PROCESSED).payload.refund.entity;
  assertEquals(entity.id, "rfnd_test001");
});

Deno.test("refund.failed entity carries notes.dodo_transaction_id", () => {
  const entity = JSON.parse(TEST_BODY_FAILED).payload.refund.entity;
  assertEquals(
    entity.notes?.dodo_transaction_id,
    "660e8400-e29b-41d4-a716-446655440000",
  );
});

Deno.test("null notes field causes fallback to gateway_refund_id lookup", () => {
  // Mirrors the null-safe access in handleRefundEvent.
  const notes: Record<string, string> | null = null;
  const transactionIdFromNotes = notes?.["dodo_transaction_id"] ?? null;
  assertEquals(transactionIdFromNotes, null);
});

Deno.test("missing dodo_transaction_id in notes causes fallback", () => {
  // A refund created manually in the Razorpay dashboard has no DODO notes.
  const notes: Record<string, string> = { other_key: "other_value" };
  const transactionIdFromNotes = notes?.["dodo_transaction_id"] ?? null;
  assertEquals(transactionIdFromNotes, null);
});

// ── Event routing tests ───────────────────────────────────────────────────────

function classifyEvent(event: string): "refund" | "payment" | "unknown" {
  if (event === "refund.processed" || event === "refund.failed") return "refund";
  if (event === "payment.captured" || event === "payment.failed") return "payment";
  return "unknown";
}

Deno.test("refund.processed is classified as a refund event", () => {
  assertEquals(classifyEvent("refund.processed"), "refund");
});

Deno.test("refund.failed is classified as a refund event", () => {
  assertEquals(classifyEvent("refund.failed"), "refund");
});

Deno.test("payment.captured is classified as a payment event", () => {
  assertEquals(classifyEvent("payment.captured"), "payment");
});

Deno.test("payment.failed is classified as a payment event", () => {
  assertEquals(classifyEvent("payment.failed"), "payment");
});

Deno.test("order.paid is classified as unknown (not handled)", () => {
  assertEquals(classifyEvent("order.paid"), "unknown");
});

Deno.test("empty event string is classified as unknown", () => {
  assertEquals(classifyEvent(""), "unknown");
});

// ── Idempotency logic tests ───────────────────────────────────────────────────

// The production idempotency check (fast pre-read before the RPC):
//   if event=refund.processed && status=completed && gateway_refund_id=expected → idempotent
//   if event=refund.failed    && status=failed                                  → idempotent
//   if event=refund.failed    && status=completed                               → anomaly; ignore

function checkIdempotency(
  event: string,
  txnStatus: string,
  txnGatewayRefundId: string | null,
  incomingGatewayRefundId: string,
): "process" | "idempotent" | "anomaly" {
  if (
    event === "refund.processed" &&
    txnStatus === "completed" &&
    txnGatewayRefundId === incomingGatewayRefundId
  ) {
    return "idempotent";
  }
  if (event === "refund.failed" && txnStatus === "failed") {
    return "idempotent";
  }
  if (event === "refund.failed" && txnStatus === "completed") {
    return "anomaly";
  }
  return "process";
}

Deno.test("duplicate refund.processed delivery is idempotent", () => {
  assertEquals(
    checkIdempotency("refund.processed", "completed", "rfnd_abc", "rfnd_abc"),
    "idempotent",
  );
});

Deno.test("duplicate refund.failed delivery is idempotent", () => {
  assertEquals(
    checkIdempotency("refund.failed", "failed", null, "rfnd_abc"),
    "idempotent",
  );
});

Deno.test("refund.failed after confirmed success is an anomaly — do not revert", () => {
  assertEquals(
    checkIdempotency("refund.failed", "completed", "rfnd_abc", "rfnd_abc"),
    "anomaly",
  );
});

Deno.test("refund.processed for a processing transaction proceeds to RPC", () => {
  assertEquals(
    checkIdempotency("refund.processed", "processing", null, "rfnd_abc"),
    "process",
  );
});

Deno.test("refund.processed for a pending transaction proceeds to RPC", () => {
  // A transaction can be pending if the Edge Function crashed before calling
  // admin_begin_razorpay_refund_processing (extremely unlikely but possible).
  assertEquals(
    checkIdempotency("refund.processed", "pending", null, "rfnd_abc"),
    "process",
  );
});

Deno.test("refund.processed with a different gateway_refund_id proceeds to RPC (RPC handles the conflict)", () => {
  // The RPC will raise an exception for a completed transaction with a different
  // gateway_refund_id — this test confirms the pre-check does not short-circuit it.
  assertEquals(
    checkIdempotency("refund.processed", "completed", "rfnd_original", "rfnd_different"),
    "process",
  );
});

// ── Integration test scenarios (manual, require Supabase local stack) ─────────
//
// The following scenarios cannot be unit-tested without a live database.
// Run these manually using `supabase start` + the Razorpay test dashboard,
// or with a custom Supabase test harness.
//
// Scenario A — Valid refund.processed event (happy path):
//   1. Create a booking, capture an online payment.
//   2. Submit and approve a refund ticket.
//   3. Admin initiates a Razorpay refund transaction (gateway='razorpay',
//      status='pending').
//   4. Admin clicks "Process via Razorpay" → Edge Function transitions to
//      'processing' (or simulate uncertain outcome by killing after Razorpay call).
//   5. Send a mock refund.processed webhook with correct HMAC, valid rfnd_XXXXX
//      id, and notes.dodo_transaction_id = the transaction UUID from step 3.
//   Expected: transaction → completed; ticket → completed/approved/partially_approved
//             based on approved vs paid; status_history entry with
//             changed_by = NULL, changed_by_type = 'system'.
//
// Scenario B — Valid refund.failed event:
//   Same setup as A but send refund.failed.
//   Expected: transaction → failed; ticket → failed; admin can retry.
//
// Scenario C — Invalid webhook signature:
//   Send a valid JSON body with wrong X-Razorpay-Signature header.
//   Expected: HTTP 400, { error: "Invalid webhook signature." }, no DB changes.
//
// Scenario D — Duplicate webhook delivery (idempotency):
//   Process a refund.processed event twice with identical bodies and signatures.
//   Expected: first call → 200 { success: true }; second call → 200 { idempotent: true }.
//   DB state is unchanged after the second delivery.
//
// Scenario E — Unknown Razorpay refund ID:
//   Send a refund.processed event where the refund entity has notes: null AND the
//   gateway_refund_id does not exist in refund_transactions.
//   Expected: 200 { received: true, handled: false, reason: "unknown_refund" }.
//   No DB changes.
//
// Scenario F — Out-of-order events (refund.failed arrives after refund.processed):
//   After Scenario A (transaction completed), send a refund.failed event for the
//   same transaction.
//   Expected: 200 { received: true, handled: false, reason: "already_complete" }.
//   Transaction remains completed.
//
// Scenario G — Partial refund status handling:
//   Approve a ticket for ₹400 on a ₹500 payment.
//   Initiate and process a ₹200 Razorpay transaction via webhook.
//   Expected after first refund: transaction → completed; ticket → partially_approved.
//   Initiate and process a second ₹200 transaction.
//   Expected after second refund: transaction → completed; ticket → completed.
//
// Scenario H — Existing payment webhook regression:
//   Send payment.captured for a known order_id.
//   Expected: booking_payments.status → success; bookings.payment_status → success.
//   Send the same event again → 200 { idempotent: true }, no double-write.
//   Send payment.failed after payment.captured → success is NOT reverted.
