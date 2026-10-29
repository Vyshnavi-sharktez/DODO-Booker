// Deno unit tests for exotel-webhook.
//
// Run with:
//   deno test --allow-env supabase/functions/exotel-webhook/webhook_test.ts
//
// Tests cover the pure, database-free logic:
//   • Token authentication (safeCompare)
//   • UUID validation (isValidUuid)
//   • Exotel status → DB status mapping
//   • Failure reason derivation
//   • Idempotency decisions
//
// Integration scenarios (delayed callbacks, duplicate delivery, recording URL
// arriving separately) require a Supabase local stack and are documented as
// manual test procedures at the bottom of this file.
//
// NOTE: The helper functions below are duplicated from index.ts rather than
// imported because index.ts depends on Supabase packages that are only
// available inside the Edge Functions runtime.  Keep them in sync with the
// production implementation.

import { assertEquals } from "jsr:@std/assert@^1";

// ── Duplicated helpers (keep in sync with index.ts) ───────────────────────────

function safeCompare(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isValidUuid(value: string): boolean {
  return UUID_RE.test(value);
}

const STATUS_MAP: Record<string, string> = {
  initiated:     "initiated",
  ringing:       "ringing",
  answered:      "connected",
  "in-progress": "connected",
  completed:     "ended",
  busy:          "failed",
  failed:        "failed",
  "no-answer":   "missed",
  canceled:      "missed",
};

const FAILURE_REASONS: Record<string, string> = {
  busy:        "The other party was busy",
  failed:      "Call failed due to a technical error",
  "no-answer": "No answer — call timed out",
  canceled:    "Call was canceled before connecting",
};

const TERMINAL_STATUSES = new Set(["ended", "failed", "missed"]);

function mapExotelStatus(exotelStatus: string): string | null {
  return STATUS_MAP[exotelStatus.toLowerCase().trim()] ?? null;
}

function deriveFailureReason(
  rawStatus: string,
  exotelFailureReason: string | null,
): string {
  return (
    exotelFailureReason ||
    FAILURE_REASONS[rawStatus] ||
    `Call ended with status: ${rawStatus}`
  );
}

// Represents the idempotency decision when a session is already terminal.
// Returns true if the DB write should be skipped; recording-URL processing
// is handled separately.
function shouldSkipTerminal(currentStatus: string): boolean {
  return TERMINAL_STATUSES.has(currentStatus);
}

// ── safeCompare tests ─────────────────────────────────────────────────────────

Deno.test("safeCompare: identical tokens return true", () => {
  assertEquals(safeCompare("secret_token_abc123", "secret_token_abc123"), true);
});

Deno.test("safeCompare: different tokens return false", () => {
  assertEquals(safeCompare("correct_token", "wrong_token__"), false);
});

Deno.test("safeCompare: different-length tokens return false immediately", () => {
  assertEquals(safeCompare("short", "much_longer_token"), false);
});

Deno.test("safeCompare: empty vs empty returns true", () => {
  assertEquals(safeCompare("", ""), true);
});

Deno.test("safeCompare: empty vs non-empty returns false", () => {
  assertEquals(safeCompare("", "token"), false);
});

Deno.test("safeCompare: one character difference returns false", () => {
  assertEquals(safeCompare("aaaa", "aaab"), false);
});

Deno.test("safeCompare: tokens with trailing space differ", () => {
  assertEquals(safeCompare("token", "token "), false);
});

// ── isValidUuid tests ─────────────────────────────────────────────────────────

const VALID_UUID = "550e8400-e29b-41d4-a716-446655440000";

Deno.test("isValidUuid: valid UUID v4 returns true", () => {
  assertEquals(isValidUuid(VALID_UUID), true);
});

Deno.test("isValidUuid: uppercase UUID returns true (case-insensitive)", () => {
  assertEquals(isValidUuid(VALID_UUID.toUpperCase()), true);
});

Deno.test("isValidUuid: UUID without hyphens returns false", () => {
  assertEquals(isValidUuid("550e8400e29b41d4a716446655440000"), false);
});

Deno.test("isValidUuid: empty string returns false", () => {
  assertEquals(isValidUuid(""), false);
});

Deno.test("isValidUuid: arbitrary Exotel CallSid returns false", () => {
  assertEquals(isValidUuid("abcd1234.abcd1234.abcd1234"), false);
});

Deno.test("isValidUuid: SQL injection attempt returns false", () => {
  assertEquals(isValidUuid("' OR 1=1 --"), false);
});

Deno.test("isValidUuid: truncated UUID returns false", () => {
  assertEquals(isValidUuid("550e8400-e29b-41d4-a716"), false);
});

// ── Status mapping tests ──────────────────────────────────────────────────────

Deno.test("mapExotelStatus: initiated → initiated", () => {
  assertEquals(mapExotelStatus("initiated"), "initiated");
});

Deno.test("mapExotelStatus: ringing → ringing", () => {
  assertEquals(mapExotelStatus("ringing"), "ringing");
});

Deno.test("mapExotelStatus: answered → connected", () => {
  assertEquals(mapExotelStatus("answered"), "connected");
});

Deno.test("mapExotelStatus: in-progress → connected", () => {
  assertEquals(mapExotelStatus("in-progress"), "connected");
});

Deno.test("mapExotelStatus: completed → ended", () => {
  assertEquals(mapExotelStatus("completed"), "ended");
});

Deno.test("mapExotelStatus: busy → failed", () => {
  assertEquals(mapExotelStatus("busy"), "failed");
});

Deno.test("mapExotelStatus: failed → failed", () => {
  assertEquals(mapExotelStatus("failed"), "failed");
});

Deno.test("mapExotelStatus: no-answer → missed", () => {
  assertEquals(mapExotelStatus("no-answer"), "missed");
});

Deno.test("mapExotelStatus: canceled → missed", () => {
  assertEquals(mapExotelStatus("canceled"), "missed");
});

Deno.test("mapExotelStatus: unknown status returns null", () => {
  assertEquals(mapExotelStatus("unknown_status"), null);
});

Deno.test("mapExotelStatus: empty string returns null", () => {
  assertEquals(mapExotelStatus(""), null);
});

Deno.test("mapExotelStatus: uppercase is normalised before lookup", () => {
  assertEquals(mapExotelStatus("COMPLETED"), "ended");
});

Deno.test("mapExotelStatus: status with leading/trailing whitespace is normalised", () => {
  assertEquals(mapExotelStatus("  completed  "), "ended");
});

// ── Terminal status tests ─────────────────────────────────────────────────────

Deno.test("TERMINAL_STATUSES includes ended", () => {
  assertEquals(TERMINAL_STATUSES.has("ended"), true);
});

Deno.test("TERMINAL_STATUSES includes failed", () => {
  assertEquals(TERMINAL_STATUSES.has("failed"), true);
});

Deno.test("TERMINAL_STATUSES includes missed", () => {
  assertEquals(TERMINAL_STATUSES.has("missed"), true);
});

Deno.test("TERMINAL_STATUSES does not include connected", () => {
  assertEquals(TERMINAL_STATUSES.has("connected"), false);
});

Deno.test("TERMINAL_STATUSES does not include ringing", () => {
  assertEquals(TERMINAL_STATUSES.has("ringing"), false);
});

// ── Idempotency decision tests ────────────────────────────────────────────────
//
// Production rule: once a session reaches a terminal state (ended/failed/missed),
// no further status writes are made.  Recording-URL delivery is still processed.

Deno.test("shouldSkipTerminal: ended session is terminal → skip DB write", () => {
  assertEquals(shouldSkipTerminal("ended"), true);
});

Deno.test("shouldSkipTerminal: failed session is terminal → skip DB write", () => {
  assertEquals(shouldSkipTerminal("failed"), true);
});

Deno.test("shouldSkipTerminal: missed session is terminal → skip DB write", () => {
  assertEquals(shouldSkipTerminal("missed"), true);
});

Deno.test("shouldSkipTerminal: connected session is not terminal → proceed", () => {
  assertEquals(shouldSkipTerminal("connected"), false);
});

Deno.test("shouldSkipTerminal: ringing session is not terminal → proceed", () => {
  assertEquals(shouldSkipTerminal("ringing"), false);
});

Deno.test("shouldSkipTerminal: initiated session is not terminal → proceed", () => {
  assertEquals(shouldSkipTerminal("initiated"), false);
});

// ── Failure reason derivation tests ──────────────────────────────────────────

Deno.test("deriveFailureReason: busy uses hardcoded message", () => {
  assertEquals(
    deriveFailureReason("busy", null),
    "The other party was busy",
  );
});

Deno.test("deriveFailureReason: no-answer uses hardcoded message", () => {
  assertEquals(
    deriveFailureReason("no-answer", null),
    "No answer — call timed out",
  );
});

Deno.test("deriveFailureReason: canceled uses hardcoded message", () => {
  assertEquals(
    deriveFailureReason("canceled", null),
    "Call was canceled before connecting",
  );
});

Deno.test("deriveFailureReason: failed uses hardcoded message", () => {
  assertEquals(
    deriveFailureReason("failed", null),
    "Call failed due to a technical error",
  );
});

Deno.test("deriveFailureReason: Exotel FailureReason takes precedence over hardcoded", () => {
  assertEquals(
    deriveFailureReason("failed", "SUBSCRIBER_ABSENT"),
    "SUBSCRIBER_ABSENT",
  );
});

Deno.test("deriveFailureReason: unknown status falls back to generic message", () => {
  assertEquals(
    deriveFailureReason("some_new_status", null),
    "Call ended with status: some_new_status",
  );
});

// ── Payload parsing tests ─────────────────────────────────────────────────────

function parseExotelPayload(body: string): URLSearchParams {
  return new URLSearchParams(body);
}

const SAMPLE_COMPLETED_BODY =
  `CallSid=abcd1234.abcd1234.abcd1234` +
  `&Status=completed` +
  `&From=%2B919876543210` +
  `&To=%2B911234567890` +
  `&Direction=outbound-api` +
  `&Duration=45` +
  `&CustomField=550e8400-e29b-41d4-a716-446655440000` +
  `&AccountSid=exoteldemo1`;

const SAMPLE_RECORDING_BODY =
  `CallSid=abcd1234.abcd1234.abcd1234` +
  `&Status=completed` +
  `&Duration=45` +
  `&CustomField=550e8400-e29b-41d4-a716-446655440000` +
  `&RecordingUrl=https%3A%2F%2Frecordings.exotel.com%2Ftest%2Faudio.mp3`;

const SAMPLE_FAILED_BODY =
  `CallSid=efgh5678.efgh5678.efgh5678` +
  `&Status=failed` +
  `&CustomField=660e8400-e29b-41d4-a716-446655440000` +
  `&FailureReason=SUBSCRIBER_ABSENT`;

const SAMPLE_NO_CUSTOM_FIELD_BODY =
  `CallSid=ijkl9012.ijkl9012.ijkl9012` +
  `&Status=completed` +
  `&Duration=30`;

Deno.test("payload: CallSid is extracted correctly", () => {
  const p = parseExotelPayload(SAMPLE_COMPLETED_BODY);
  assertEquals(p.get("CallSid"), "abcd1234.abcd1234.abcd1234");
});

Deno.test("payload: Status is extracted and maps to ended", () => {
  const p = parseExotelPayload(SAMPLE_COMPLETED_BODY);
  assertEquals(mapExotelStatus(p.get("Status") ?? ""), "ended");
});

Deno.test("payload: CustomField (session UUID) is extracted correctly", () => {
  const p = parseExotelPayload(SAMPLE_COMPLETED_BODY);
  assertEquals(p.get("CustomField"), "550e8400-e29b-41d4-a716-446655440000");
});

Deno.test("payload: Duration is extracted and parsed as integer", () => {
  const p = parseExotelPayload(SAMPLE_COMPLETED_BODY);
  assertEquals(parseInt(p.get("Duration") ?? "0", 10), 45);
});

Deno.test("payload: RecordingUrl is decoded from percent-encoding", () => {
  const p = parseExotelPayload(SAMPLE_RECORDING_BODY);
  assertEquals(
    p.get("RecordingUrl"),
    "https://recordings.exotel.com/test/audio.mp3",
  );
});

Deno.test("payload: FailureReason is extracted from failed callback", () => {
  const p = parseExotelPayload(SAMPLE_FAILED_BODY);
  assertEquals(p.get("FailureReason"), "SUBSCRIBER_ABSENT");
});

Deno.test("payload: missing CustomField yields empty string, not a valid UUID", () => {
  const p = parseExotelPayload(SAMPLE_NO_CUSTOM_FIELD_BODY);
  const cf = p.get("CustomField") ?? "";
  assertEquals(isValidUuid(cf), false);
});

Deno.test("payload: absent RecordingUrl yields null", () => {
  const p = parseExotelPayload(SAMPLE_COMPLETED_BODY);
  const recUrl = p.get("RecordingUrl")?.trim() || null;
  assertEquals(recUrl, null);
});

Deno.test("payload: CustomField passes UUID validation", () => {
  const p = parseExotelPayload(SAMPLE_COMPLETED_BODY);
  assertEquals(isValidUuid(p.get("CustomField") ?? ""), true);
});

Deno.test("payload: exotel_call_sid fallback is used when CustomField is absent", () => {
  const p = parseExotelPayload(SAMPLE_NO_CUSTOM_FIELD_BODY);
  const cf = p.get("CustomField") ?? "";
  // CustomField absent → UUID validation fails → fallback to exotel_call_sid
  assertEquals(isValidUuid(cf), false);
  assertEquals(p.get("CallSid"), "ijkl9012.ijkl9012.ijkl9012");
});

// ── Integration test scenarios (manual, require Supabase local stack) ─────────
//
// Scenario A — Valid completed callback (happy path):
//   1. Create a booking in accepted status.
//   2. Call initiate-exotel-call with a valid JWT.
//   3. Confirm a call_session row is created with status=ringing.
//   4. POST to /functions/v1/exotel-webhook?token=<configured_token> with:
//        CallSid=<any>
//        Status=completed
//        Duration=60
//        CustomField=<session_id from step 3>
//   Expected: call_session.status=ended, ended_at set, duration_seconds=60.
//   No recording_url in call_sessions; call_session_recordings is empty.
//
// Scenario B — Recording URL delivery:
//   After Scenario A, POST the same body but add RecordingUrl=<url>.
//   Expected: call_session_recordings row created with correct recording_url.
//   call_sessions.recording_status=available.
//   call_sessions.recording_url remains NULL (recording stored in separate table).
//
// Scenario C — Late recording URL delivery (second completed callback):
//   After Scenario A (status=ended), POST again with Status=completed and
//   RecordingUrl=<url>.
//   Expected: recording stored idempotently.  Status not changed (already terminal).
//
// Scenario D — Invalid token:
//   POST with wrong ?token= value.
//   Expected: HTTP 401, no DB changes.
//
// Scenario E — Missing token:
//   POST with no ?token= parameter.
//   Expected: HTTP 401.
//
// Scenario F — Webhook token not configured (vault secret absent):
//   Remove the webhook_token vault secret.
//   Expected: HTTP 503.  All callbacks are rejected until the token is set.
//
// Scenario G — Malformed body (not form-urlencoded):
//   POST with Content-Type: application/json and JSON body.
//   Expected: CallSid missing → HTTP 400.
//
// Scenario H — Duplicate completed callback (idempotency):
//   POST a completed callback twice with identical token and body.
//   Expected: first call → session.status=ended.  Second call → 200 OK,
//   session unchanged.
//
// Scenario I — Ringing callback arrives after call has ended:
//   Transition session to ended, then POST Status=ringing.
//   Expected: 200 OK, session.status remains ended (no regression).
//
// Scenario J — Failed call (busy):
//   POST Status=busy.
//   Expected: session.status=failed, failure_reason="The other party was busy".
//
// Scenario K — No-answer call:
//   POST Status=no-answer.
//   Expected: session.status=missed, failure_reason="No answer — call timed out".
//
// Scenario L — Unknown session (CustomField does not match any row):
//   POST with CustomField=<non-existent-uuid> and no exotel_call_sid match.
//   Expected: 200 OK (acknowledged), no DB changes.
