import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";

// ── Types ─────────────────────────────────────────────────────────────────────

interface BotConfig {
  is_enabled: boolean;
  model: string;
  system_prompt: string;
  max_history: number;
  handoff_triggers: string;
  close_triggers: string;
  bot_admin_id: string;
  api_key: string | null;
}

interface SupportMessage {
  sender_type: "customer" | "admin";
  message: string;
}

interface WebhookPayload {
  type: string;
  record: {
    id: string;
    conversation_id: string;
    sender_type: string;
    sender_id: string;
    message: string;
  };
}

// ── Gemini REST call ──────────────────────────────────────────────────────────

interface GeminiPart {
  text: string;
}

interface GeminiContent {
  role: "user" | "model";
  parts: GeminiPart[];
}

async function callGemini(
  apiKey: string,
  model: string,
  systemPrompt: string,
  history: SupportMessage[],
  newMessage: string,
): Promise<string> {
  const prior = history.slice(0, -1);

  const contents: GeminiContent[] = [];

  for (const msg of prior) {
    const role: "user" | "model" = msg.sender_type === "customer" ? "user" : "model";
    contents.push({ role, parts: [{ text: msg.message }] });
  }

  while (contents.length > 0 && contents[0].role === "model") {
    contents.shift();
  }

  contents.push({ role: "user", parts: [{ text: newMessage }] });

  const body: Record<string, unknown> = { contents };

  if (systemPrompt) {
    body.system_instruction = { parts: [{ text: systemPrompt }] };
  }

  const url = `https://generativelanguage.googleapis.com/v1/models/${model}:generateContent?key=${apiKey}`;

  for (let attempt = 1; attempt <= 3; attempt++) {
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });

    if (res.status === 503 && attempt < 3) {
      await new Promise((r) => setTimeout(r, 2000 * attempt));
      continue;
    }

    if (!res.ok) {
      const err = await res.text().catch(() => "");
      throw new Error(`Gemini API error ${res.status}: ${err}`);
    }

    const data = await res.json();
    const text: string = data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
    return text.trim();
  }

  throw new Error("Gemini API error: max retries exceeded on 503");
}

// ── Helpers ───────────────────────────────────────────────────────────────────

const normalize = (s: string) => s.toLowerCase().replace(/[''`']/g, "");

// Phrases that confirm the customer wants to close when bot asked "anything else?"
const CLOSE_CONFIRM_PHRASES = [
  "no", "nope", "nah", "nothing", "nothing else", "no more", "no thanks",
  "no thank you", "done", "close", "close it", "please close", "finish",
  "finished", "all good", "all done", "good thanks", "good thank you",
  "thats it", "thats all", "that's it", "that's all", "im done", "i'm done",
  "bye", "goodbye", "see you", "take care", "yes close", "yes please close",
  "go ahead", "sure close",
];

// Phrases that mean the customer has more to say — cancel the pending close
const CLOSE_DENY_PHRASES = [
  "wait", "actually", "hold on", "one more", "not yet", "no wait",
  "before you close", "actually yes",
];

// ── Main handler ──────────────────────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("ok", { status: 200 });
  }

  try {
    const payload: WebhookPayload = await req.json();
    const record = payload?.record;

    if (!record || record.sender_type !== "customer") {
      return new Response("ok", { status: 200 });
    }

    const conversationId = record.conversation_id;
    const messageText = record.message;

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const db = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    // ── 1. Load bot config ─────────────────────────────────────────────────────
    const { data: config, error: configErr } = await db.rpc("get_bot_config");
    if (configErr || !config) {
      console.error("[SupportBot] get_bot_config failed:", configErr);
      return new Response("ok", { status: 200 });
    }

    const cfg = config as BotConfig;

    if (!cfg.is_enabled || !cfg.api_key || !cfg.bot_admin_id) {
      return new Response("ok", { status: 200 });
    }

    // ── 2. Load conversation state ─────────────────────────────────────────────
    const { data: conv } = await db
      .from("support_conversations")
      .select("current_episode_started_at, status, pending_close, pending_farewell")
      .eq("id", conversationId)
      .maybeSingle();

    if (conv?.status === "closed") {
      return new Response("ok", { status: 200 });
    }

    const episodeStart: string | null = conv?.current_episode_started_at ?? null;
    const pendingClose: boolean = conv?.pending_close ?? false;
    const pendingFarewell: boolean = conv?.pending_farewell ?? false;

    // ── 3. Stay silent if a human admin already replied this episode ───────────
    let humanReplyQuery = db
      .from("support_messages")
      .select("id")
      .eq("conversation_id", conversationId)
      .eq("sender_type", "admin")
      .neq("sender_id", cfg.bot_admin_id);

    if (episodeStart) {
      humanReplyQuery = humanReplyQuery.gte("created_at", episodeStart);
    }

    const { data: humanReply } = await humanReplyQuery.limit(1).maybeSingle();

    if (humanReply) {
      return new Response("ok", { status: 200 });
    }

    // ── 4. Normalise message ───────────────────────────────────────────────────
    const normalizedMessage = normalize(messageText);

    // ── 5. Check handoff triggers ──────────────────────────────────────────────
    const triggers = cfg.handoff_triggers
      .split(",")
      .map((t: string) => normalize(t.trim()))
      .filter((t: string) => t.length > 0);

    const isHandoff = triggers.some((t: string) => normalizedMessage.includes(t));

    if (isHandoff) {
      await db.from("support_messages").insert({
        conversation_id: conversationId,
        sender_type: "admin",
        sender_id: cfg.bot_admin_id,
        message: "I'll connect you with our support team right away. Please wait a moment.",
      });
      await db.from("support_conversations").update({
        last_handoff_at: new Date().toISOString(),
        handoff_timeout_notified: false,
        pending_close: false,
        pending_farewell: false,
      }).eq("id", conversationId);

      let dedupQuery = db
        .from("notifications")
        .select("id")
        .eq("notification_type", "support_handoff")
        .eq("entity_type", "support_conversation")
        .eq("entity_id", conversationId)
        .eq("is_read", false);

      if (episodeStart) {
        dedupQuery = dedupQuery.gte("created_at", episodeStart);
      }

      const { data: existing } = await dedupQuery.limit(1).maybeSingle();
      if (!existing) {
        await db.from("notifications").insert({
          user_type: "admin",
          user_id: null,
          title: "Customer Needs Support",
          message: "A customer has requested human assistance. Please respond.",
          notification_type: "support_handoff",
          entity_type: "support_conversation",
          entity_id: conversationId,
          is_read: false,
        });
      }
      return new Response("ok", { status: 200 });
    }

    // ── 6. Fetch conversation history (shared by all Gemini paths below) ───────
    const { data: messages } = await db
      .from("support_messages")
      .select("sender_type, message")
      .eq("conversation_id", conversationId)
      .order("created_at", { ascending: false })
      .limit(cfg.max_history);

    const history: SupportMessage[] = ((messages ?? []) as SupportMessage[]).reverse();

    // ── 7. Handle pending-close confirmation ───────────────────────────────────
    if (pendingClose) {
      const isConfirm = CLOSE_CONFIRM_PHRASES.some(
        (p) => normalizedMessage.includes(normalize(p)),
      );
      const isDeny = !isConfirm &&
        CLOSE_DENY_PHRASES.some((p) => normalizedMessage.includes(normalize(p)));

      if (isConfirm) {
        // Send Gemini farewell, then wait for customer's final ack before closing
        const farewellPrompt =
          cfg.system_prompt +
          "\n\nThe customer is wrapping up. Send a warm farewell message: thank them for contacting " +
          "DODO and wish them a great day. Keep it to 1-2 sentences. Do not ask any further questions.";

        const farewell = await callGemini(
          cfg.api_key,
          cfg.model || "gemini-2.5-flash",
          farewellPrompt,
          history,
          messageText,
        );

        if (farewell) {
          await db.from("support_messages").insert({
            conversation_id: conversationId,
            sender_type: "admin",
            sender_id: cfg.bot_admin_id,
            message: farewell,
          });
        }

        // Move to farewell stage — close on customer's next reply
        await db.from("support_conversations")
          .update({ pending_close: false, pending_farewell: true })
          .eq("id", conversationId);

        return new Response("ok", { status: 200 });
      }

      // Denied or unclear — reset pending_close and answer normally with Gemini
      await db.from("support_conversations")
        .update({ pending_close: false })
        .eq("id", conversationId);

      const reply = await callGemini(
        cfg.api_key,
        cfg.model || "gemini-2.5-flash",
        cfg.system_prompt || "",
        history,
        messageText,
      );

      if (reply) {
        await db.from("support_messages").insert({
          conversation_id: conversationId,
          sender_type: "admin",
          sender_id: cfg.bot_admin_id,
          message: reply,
        });
      }

      return new Response("ok", { status: 200 });
    }

    // ── 8. Handle pending-farewell final ack ──────────────────────────────────
    // Bot already sent farewell. Any reply here = customer acknowledged → close.
    // We only keep the conversation open if they clearly have more to say.
    if (pendingFarewell) {
      const FINAL_DENY_PHRASES = [
        "wait", "actually", "one more", "hold on", "not yet", "no wait",
        "before you close", "actually yes", "i have a question",
      ];

      const isDeny = FINAL_DENY_PHRASES.some((p) => normalizedMessage.includes(normalize(p)));

      if (isDeny) {
        // Customer has more — reset everything and answer normally
        await db.from("support_conversations")
          .update({ pending_farewell: false, pending_close: false })
          .eq("id", conversationId);

        const reply = await callGemini(
          cfg.api_key,
          cfg.model || "gemini-2.5-flash",
          cfg.system_prompt || "",
          history,
          messageText,
        );

        if (reply) {
          await db.from("support_messages").insert({
            conversation_id: conversationId,
            sender_type: "admin",
            sender_id: cfg.bot_admin_id,
            message: reply,
          });
        }
      } else {
        // Any other reply (thanks, sure, okay, 👍, etc.) → close silently
        await db.from("support_conversations")
          .update({ status: "closed", pending_farewell: false, pending_close: false })
          .eq("id", conversationId);
      }

      return new Response("ok", { status: 200 });
    }

    // ── 10. Check close triggers ───────────────────────────────────────────────
    const closeTriggers = (cfg.close_triggers ?? "")
      .split(",")
      .map((t: string) => normalize(t.trim()))
      .filter((t: string) => t.length > 0);

    const isClose = closeTriggers.some((t: string) => normalizedMessage.includes(t));

    if (isClose) {
      // Ask for confirmation before closing
      const confirmPrompt =
        cfg.system_prompt +
        "\n\nThe customer seems to be wrapping up the conversation. " +
        "Ask warmly if there is anything else you can help them with before closing the chat. " +
        "Keep it to 1-2 sentences.";

      const confirmAsk = await callGemini(
        cfg.api_key,
        cfg.model || "gemini-2.5-flash",
        confirmPrompt,
        history,
        messageText,
      );

      if (confirmAsk) {
        await db.from("support_messages").insert({
          conversation_id: conversationId,
          sender_type: "admin",
          sender_id: cfg.bot_admin_id,
          message: confirmAsk,
        });
      }

      await db.from("support_conversations")
        .update({ pending_close: true })
        .eq("id", conversationId);

      return new Response("ok", { status: 200 });
    }

    // ── 11. Normal Gemini reply ────────────────────────────────────────────────
    const reply = await callGemini(
      cfg.api_key,
      cfg.model || "gemini-2.5-flash",
      cfg.system_prompt || "",
      history,
      messageText,
    );

    if (!reply) {
      console.error("[SupportBot] Gemini returned empty reply");
      return new Response("ok", { status: 200 });
    }

    await db.from("support_messages").insert({
      conversation_id: conversationId,
      sender_type: "admin",
      sender_id: cfg.bot_admin_id,
      message: reply,
    });

    // Clear any stale handoff state so the cron job doesn't fire a
    // "support team is busy" message after the bot has resumed normal replies.
    await db.from("support_conversations")
      .update({ last_handoff_at: null, handoff_timeout_notified: true })
      .eq("id", conversationId);

    return new Response("ok", { status: 200 });

  } catch (err) {
    console.error("[SupportBot] Unhandled error:", err);
    return new Response("ok", { status: 200 });
  }
});
