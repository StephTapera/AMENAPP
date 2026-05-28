// integrations/providers/SlackProvider.ts
// Slack API — channel notifications, ministry alerts, signing verification

import * as crypto from "crypto";
import { AmenIntegrationError, AmenProviderError, mapProviderHttpError } from "../integrationErrors";
import type { SlackMessagingProvider } from "./IntegrationProvider";
import type { SlackNotificationInput } from "../types";

const TIMEOUT_MS = 10_000;

async function slackApi<T>(path: string, token: string, body?: unknown): Promise<T> {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  try {
    const resp = await fetch(`https://slack.com/api/${path}`, {
      method: body ? "POST" : "GET",
      headers: { "Authorization": `Bearer ${token}`, "Content-Type": "application/json; charset=utf-8" },
      ...(body ? { body: JSON.stringify(body) } : {}),
      signal: ctrl.signal,
    });
    if (!resp.ok) throw new AmenProviderError(mapProviderHttpError(resp.status), resp.status);
    const json = await resp.json() as { ok: boolean; error?: string };
    if (!json.ok) { console.error(`[SlackProvider] API error: ${json.error}`); throw new AmenIntegrationError("provider-error"); }
    return json as unknown as T;
  } catch (e) {
    if (e instanceof AmenProviderError || e instanceof AmenIntegrationError) throw e;
    if ((e as Error).name === "AbortError") throw new AmenIntegrationError("provider-timeout");
    throw new AmenIntegrationError("provider-error");
  } finally {
    clearTimeout(t);
  }
}

export class SlackProviderImpl implements SlackMessagingProvider {
  async sendChannelNotification(accessToken: string, input: SlackNotificationInput): Promise<void> {
    await slackApi("chat.postMessage", accessToken, { channel: input.channelId, text: input.text });
  }

  async listChannels(accessToken: string): Promise<Array<{ id: string; name: string; isPrivate: boolean }>> {
    type Resp = { ok: boolean; channels?: Array<{ id: string; name: string; is_private: boolean }> };
    const resp = await slackApi<Resp>("conversations.list", accessToken);
    return (resp.channels ?? []).map((c) => ({ id: c.id, name: c.name, isPrivate: c.is_private }));
  }

  verifyRequestSignature(signingSecret: string, signature: string, timestamp: string, body: string): boolean {
    // Reject requests older than 5 minutes
    if (Math.abs(Date.now() / 1000 - parseInt(timestamp, 10)) > 300) return false;
    const expected = `v0=${crypto.createHmac("sha256", signingSecret).update(`v0:${timestamp}:${body}`).digest("hex")}`;
    try {
      return crypto.timingSafeEqual(Buffer.from(expected, "utf8"), Buffer.from(signature, "utf8"));
    } catch {
      return false;
    }
  }
}
