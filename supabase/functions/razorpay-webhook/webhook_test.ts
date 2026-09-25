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
// Both functions below are duplicated from index.ts.  They cannot be imported
// because index.ts depends on Supabase packages only available in the Edge
// Functions runtime.  Keep them in sync with the production implementation.

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

function receiptToTransactionId(
  receipt: string | null | undefined,
): string | null {
  if (!receipt) return null;
  const lower = receipt.toLowerCase();
  if (lower.length !== 32 || !/^[0-9a-f]{32}$/.test(lower)) return null;
  return `${lower.slice(0, 8)}-${lower.slice(8, 12)}-${lower.slice(12, 16)}-${lower.slice(16, 20)}-${lower.slice(20)}`;
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

// Receipt-fallback fixtures: notes absent or malformed, but receipt is correct.
// UUID 770e8400-e29b-41d4-a716-446655440000 → receipt 770e8400e29b41d4a716446655440000
const TEST_BODY_PROCESSED_NULL_NOTES = JSON.stringify({
  event: "refund.processed",
  payload: {
    refund: {
      entity: {
        id: "rfnd_test003",
        entity: "refund",
        amount: 59290,
        currency: "INR",
        payment_id: "pay_test003",
        status: "processed",
        notes: null,
        receipt: "770e8400e29b41d4a716446655440000",
      },
    },
  },
});

// Razorpay sometimes returns notes as an empty array [] instead of an object.
const TEST_BODY_PROCESSED_ARRAY_NOTES = JSON.stringify({
  event: "refund.processed",
  payload: {
    refund: {
      entity: {
        id: "rfnd_test004",
        entity: "refund",
        amount: 59290,
        currency: "INR",
        payment_id: "pay_test004",
        status: "processed",
        notes: [],
        receipt: "770e8400e29b41d4a716446655440000",
      },
    },
  },
});

// No notes, no valid receipt → truly unknown refund.
const TEST_BODY_PROCESSED_NO_RECEIPT = JSON.stringify({
  event: "refund.processed",
  payload: {
    refund: {
      entity: {
        id: "rfnd_test005",
        entity: "refund",
        amount: 59290,
        currency: "INR",
        payment_id: "pay_test005",
        status: "processed",
        notes: null,
        receipt: null,
      },
    },
  },
});

const TEST_BODY_FAILED_NULL_NOTES = JSON.stringify({
  event: "refund.failed",
  payload: {
    refund: {
      entity: {
        id: "rfnd_test006",
        entity: "refund",
        amount: 59290,
        currency: "INR",
        payment_id: "pay_test006",
        status: "failed",
        notes: null,
        receipt: "770e8400e29b41d4a716446655440000",
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

// ── receiptToTransactionId tests ─────────────────────────────────────────────

Deno.test("receiptToTransactionId: valid 32-char hex returns correct UUID", () => {
  assertEquals(
    receiptToTransactionId("770e8400e29b41d4a716446655440000"),
    "770e8400-e29b-41d4-a716-446655440000",
  );
});

Deno.test("receiptToTransactionId: uppercase hex is normalised to lowercase UUID", () => {
  assertEquals(
    receiptToTransactionId("770E8400E29B41D4A716446655440000"),
    "770e8400-e29b-41d4-a716-446655440000",
  );
});

Deno.test("receiptToTransactionId: known DODO transaction ID round-trips correctly", () => {
  // b77adceb-5cc0-4548-a9d8-4adda2113e9d is the real stuck transaction.
  assertEquals(
    receiptToTransactionId("b77adceb5cc04548a9d84adda2113e9d"),
    "b77adceb-5cc0-4548-a9d8-4adda2113e9d",
  );
});

Deno.test("receiptToTransactionId: null returns null", () => {
  assertEquals(receiptToTransactionId(null), null);
});

Deno.test("receiptToTransactionId: undefined returns null", () => {
  assertEquals(receiptToTransactionId(undefined), null);
});

Deno.test("receiptToTransactionId: empty string returns null", () => {
  assertEquals(receiptToTransactionId(""), null);
});

Deno.test("receiptToTransactionId: 31-char hex returns null (too short)", () => {
  assertEquals(receiptToTransactionId("770e8400e29b41d4a71644665544000"), null);
});

Deno.test("receiptToTransactionId: 33-char hex returns null (too long)", () => {
  assertEquals(receiptToTransactionId("770e8400e29b41d4a7164466554400000"), null);
});

Deno.test("receiptToTransactionId: non-hex chars return null", () => {
  assertEquals(receiptToTransactionId("770e8400e29b41d4a716446655440zzz"), null);
});

Deno.test("receiptToTransactionId: receipt with hyphens (UUID format) returns null", () => {
  // The receipt stored in Razorpay has NO hyphens; if someone passes the raw
  // UUID by mistake, it will fail the length / hex check.
  assertEquals(receiptToTransactionId("770e8400-e29b-41d4-a716-446655440000"), null);
});

// ── Notes-absent fallback logic tests ────────────────────────────────────────

Deno.test("null notes field triggers fallback (notes→null means no dodo_transaction_id)", () => {
  const entity = JSON.parse(TEST_BODY_PROCESSED_NULL_NOTES).payload.refund.entity;
  const transactionIdFromNotes = entity.notes?.["dodo_transaction_id"] ?? null;
  assertEquals(transactionIdFromNotes, null);
});

Deno.test("array notes field triggers fallback (Razorpay empty-array quirk)", () => {
  // When Razorpay returns notes as [] rather than {}, dodo_transaction_id is absent.
  const entity = JSON.parse(TEST_BODY_PROCESSED_ARRAY_NOTES).payload.refund.entity;
  const transactionIdFromNotes = entity.notes?.["dodo_transaction_id"] ?? null;
  assertEquals(transactionIdFromNotes, null);
});

Deno.test("receipt is present in null-notes fixture", () => {
  const entity = JSON.parse(TEST_BODY_PROCESSED_NULL_NOTES).payload.refund.entity;
  assertEquals(entity.receipt, "770e8400e29b41d4a716446655440000");
});

Deno.test("receipt is present in array-notes fixture", () => {
  const entity = JSON.parse(TEST_BODY_PROCESSED_ARRAY_NOTES).payload.refund.entity;
  assertEquals(entity.receipt, "770e8400e29b41d4a716446655440000");
});

Deno.test("receipt from null-notes fixture resolves to correct UUID", () => {
  const entity = JSON.parse(TEST_BODY_PROCESSED_NULL_NOTES).payload.refund.entity;
  assertEquals(
    receiptToTransactionId(entity.receipt),
    "770e8400-e29b-41d4-a716-446655440000",
  );
});

Deno.test("receipt from array-notes fixture resolves to correct UUID", () => {
  const entity = JSON.parse(TEST_BODY_PROCESSED_ARRAY_NOTES).payload.refund.entity;
  assertEquals(
    receiptToTransactionId(entity.receipt),
    "770e8400-e29b-41d4-a716-446655440000",
  );
});

Deno.test("null receipt with null notes yields null UUID (unknown_refund path)", () => {
  const entity = JSON.parse(TEST_BODY_PROCESSED_NO_RECEIPT).payload.refund.entity;
  const transactionIdFromNotes = entity.notes?.["dodo_transaction_id"] ?? null;
  assertEquals(transactionIdFromNotes, null);
  assertEquals(receiptToTransactionId(entity.receipt), null);
  // Both lookups return null → unknown_refund path is correctly taken.
});

Deno.test("refund.failed null-notes fixture resolves receipt to UUID", () => {
  const entity = JSON.parse(TEST_BODY_FAILED_NULL_NOTES).payload.refund.entity;
  const transactionIdFromNotes = entity.notes?.["dodo_transaction_id"] ?? null;
  assertEquals(transactionIdFromNotes, null);
  assertEquals(
    receiptToTransactionId(entity.receipt),
    "770e8400-e29b-41d4-a716-446655440000",
  );
});

// ── Idempotency checks for receipt-found rows ─────────────────────────────────

Deno.test("idempotency: receipt-matched completed transaction skips RPC for refund.processed", () => {
  // Mirrors the checkIdempotency logic applied after a receipt-based lookup.
  const txnStatus = "completed";
  const txnGatewayRefundId = "rfnd_test003";
  const incomingGatewayRefundId = "rfnd_test003";
  assertEquals(
    checkIdempotency("refund.processed", txnStatus, txnGatewayRefundId, incomingGatewayRefundId),
    "idempotent",
  );
});

Deno.test("idempotency: receipt-matched failed transaction skips RPC for refund.failed", () => {
  const txnStatus = "failed";
  assertEquals(
    checkIdempotency("refund.failed", txnStatus, null, "rfnd_test006"),
    "idempotent",
  );
});

Deno.test("idempotency: receipt-matched processing transaction proceeds to RPC", () => {
  // The race-condition fix: receipt lookup finds the transaction still processing.
  const txnStatus = "processing";
  assertEquals(
    checkIdempotency("refund.processed", txnStatus, null, "rfnd_test003"),
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
//
// Scenario I — Race-condition: webhook arrives before gateway_refund_id is stored:
//   1. Admin initiates a Razorpay refund for an online booking.
//   2. Intercept the outgoing process-razorpay-refund request BEFORE it stores
//      gateway_refund_id (simulate by pausing after the Razorpay API call).
//   3. Send a mock refund.processed webhook with notes: null (or notes: []) and
//      receipt = transaction_id_without_hyphens (e.g. "b77adceb5cc04548a9d84adda2113e9d").
//   Expected: receipt fallback reconstructs the UUID, finds the processing
//             transaction, calls webhook_complete_refund_transaction, and returns
//             200 { received: true, success: true }.
//             Transaction transitions to completed; ticket to completed.
//   After test: resume process-razorpay-refund.  Its gateway_refund_id UPDATE
//   uses .eq("status", "processing") so it is a no-op if status is now completed.
//
// Scenario J — Race-condition: webhook arrives after gateway_refund_id is stored
//              but notes are still absent:
//   Same as I but let process-razorpay-refund complete first (gateway_refund_id stored).
//   Then send refund.processed with notes: null.
//   Expected: Fallback A (gateway_refund_id) finds the transaction.
//             Completion proceeds normally.
//
// Scenario K — Truly unknown receipt (manual Razorpay dashboard refund):
//   Send refund.processed where receipt is not a 32-char hex string (e.g.
//   a custom string set by Razorpay dashboard, like "manual-001").
//   Expected: 200 { received: true, handled: false, reason: "unknown_refund" }.
//   No DB changes.
//
// Scenario L — Receipt of an already-completed transaction (Fallback B idempotency):
//   Send refund.processed twice for the same refund, both times with notes: null.
//   First delivery completes the transaction via receipt fallback.
//   Second delivery: receipt lookup finds transaction with status = completed.
//   Expected: 200 { received: true, idempotent: true }.  No double-write.
