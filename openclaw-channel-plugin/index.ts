import type {
  ChannelPlugin,
  InboundMessage,
  OutboundEvent,
} from "@openclaw/plugin-sdk";

const plugin: ChannelPlugin = {
  /**
   * Called when TalkClaw POSTs a user message to OpenClaw.
   * Transforms the HTTP payload into an OpenClaw inbound message.
   */
  async onInbound(req): Promise<InboundMessage> {
    const { sessionId, content } = req.body;
    return {
      sessionKey: `talkclaw:dm:${sessionId}`,
      content,
      metadata: {
        channel: "talkclaw",
        provider: "talkclaw",
        surface: "talkclaw",
        chat_id: `talkclaw:dm:${sessionId}`,
      },
    };
  },

  /**
   * Called by OpenClaw when the agent produces output.
   * Forwards events to TalkClaw's webhook endpoint via HTTP POST.
   */
  async onOutbound(event: OutboundEvent): Promise<void> {
    const webhookURL = process.env.TALKCLAW_WEBHOOK_URL!;
    const secret = process.env.TALKCLAW_WEBHOOK_SECRET!;

    // Extract sessionId from the session key (talkclaw:dm:{uuid})
    const sessionId = event.sessionKey.replace("talkclaw:dm:", "");

    let payload: Record<string, unknown>;

    switch (event.type) {
      case "agent.delta":
        payload = {
          type: "chat_delta",
          sessionId,
          messageId: event.messageId,
          delta: event.delta,
        };
        break;

      case "agent.complete":
        payload = {
          type: "chat_complete",
          sessionId,
          messageId: event.messageId,
          text: event.text,
        };
        break;

      case "agent.error":
        payload = {
          type: "chat_error",
          sessionId,
          error: event.error,
        };
        break;

      default:
        return;
    }

    const res = await fetch(webhookURL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${secret}`,
      },
      body: JSON.stringify(payload),
    });

    if (!res.ok) {
      console.error(`Webhook POST failed: ${res.status} ${res.statusText}`);
    }
  },
};

export default plugin;
