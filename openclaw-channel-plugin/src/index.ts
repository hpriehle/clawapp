/**
 * TalkClaw Channel Plugin for OpenClaw
 *
 * Inbound:  TalkClaw server POSTs user messages to /webhook/talkclaw
 * Outbound: Plugin sends AI replies back to TalkClaw REST API
 */

export default function register(api: any) {
  const config = api.getChannelConfig("talkclaw");
  if (!config?.enabled) return;

  const serverUrl = config.serverUrl || "http://localhost:8080";
  const apiToken = config.apiToken || "";
  const webhookSecret = config.webhookSecret || "";

  api.registerChannel({
    name: "talkclaw",
    displayName: "TalkClaw",

    capabilities: {
      markdown: true,
      images: true,
      files: true,
      streaming: false,
    },

    agentPromptHint:
      "The user is chatting via TalkClaw, a self-hosted iOS chat app with a widget engine for interactive dashboards.",

    webhookHandler: async (req: any, res: any) => {
      const { sessionId, content, secret } = req.body;

      // Verify webhook secret
      if (webhookSecret && secret !== webhookSecret) {
        api.logger.warn("TalkClaw webhook: invalid secret");
        res.status(401).json({ error: "Invalid webhook secret" });
        return;
      }

      if (!sessionId || !content) {
        res.status(400).json({ error: "Missing sessionId or content" });
        return;
      }

      api.logger.info(
        `TalkClaw: received message for session ${sessionId} (${content.length} chars)`
      );

      // Acknowledge immediately — response delivered async via deliver callback
      res.status(204).end();

      // Dispatch through the agent
      try {
        await api.dispatchReplyWithBufferedBlockDispatcher({
          channel: "talkclaw",
          chatId: `talkclaw:dm:${sessionId}`,
          userId: `talkclaw:user:${sessionId}`,
          content,
          dmPolicy: config.dmPolicy || "open",
          deliver: async (reply: any) => {
            const replyText = reply.text || "";
            if (!replyText.trim()) return;

            api.logger.info(
              `TalkClaw: sending reply to session ${sessionId} (${replyText.length} chars)`
            );

            // POST the reply back to TalkClaw server
            const url = `${serverUrl}/api/v1/sessions/${sessionId}/messages`;
            const response = await fetch(url, {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
                Authorization: `Bearer ${apiToken}`,
              },
              body: JSON.stringify({
                content: replyText,
                role: "assistant",
              }),
            });

            if (!response.ok) {
              api.logger.error(
                `TalkClaw: failed to deliver reply — HTTP ${response.status}`
              );
            } else {
              api.logger.info("TalkClaw: reply delivered successfully");
            }
          },
        });
      } catch (err: any) {
        api.logger.error(`TalkClaw: dispatch error — ${err.message}`);
      }
    },
  });

  api.logger.info("TalkClaw channel plugin registered");
}
