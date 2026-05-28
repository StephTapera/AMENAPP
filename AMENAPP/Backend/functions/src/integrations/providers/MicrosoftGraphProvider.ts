// integrations/providers/MicrosoftGraphProvider.ts
// Microsoft Graph API — Outlook calendar events + Teams online meetings

import { AmenIntegrationError, AmenProviderError, mapProviderHttpError } from "../integrationErrors";
import type { MeetingProvider } from "./IntegrationProvider";
import type { CreateMeetingInput, CreateMeetingOutput } from "../types";

const GRAPH_BASE = "https://graph.microsoft.com/v1.0";
const TIMEOUT_MS = 15_000;

async function graphRequest<T>(method: string, path: string, token: string, body?: unknown): Promise<T> {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  try {
    const resp = await fetch(`${GRAPH_BASE}${path}`, {
      method,
      headers: { "Authorization": `Bearer ${token}`, "Content-Type": "application/json", "Accept": "application/json" },
      ...(body ? { body: JSON.stringify(body) } : {}),
      signal: ctrl.signal,
    });
    if (!resp.ok) {
      console.error(`[MicrosoftGraphProvider] ${method} ${path} → ${resp.status}`);
      throw new AmenProviderError(mapProviderHttpError(resp.status), resp.status);
    }
    if (resp.status === 204) return {} as T;
    return resp.json() as Promise<T>;
  } catch (e) {
    if (e instanceof AmenProviderError || e instanceof AmenIntegrationError) throw e;
    if ((e as Error).name === "AbortError") throw new AmenIntegrationError("provider-timeout");
    throw new AmenIntegrationError("provider-error");
  } finally {
    clearTimeout(t);
  }
}

export class MicrosoftGraphProvider implements MeetingProvider {
  async createMeeting(accessToken: string, input: CreateMeetingInput): Promise<CreateMeetingOutput> {
    const startAt = new Date(input.startAtMs);
    const endAt = new Date(input.endAtMs ?? input.startAtMs + 60 * 60_000);
    const tz = input.timezone ?? "UTC";

    type GraphEvent = { id: string; onlineMeeting?: { joinUrl?: string }; webLink?: string };

    const event = await graphRequest<GraphEvent>("POST", "/me/events", accessToken, {
      subject: input.title,
      start: { dateTime: startAt.toISOString().replace("Z", ""), timeZone: tz },
      end: { dateTime: endAt.toISOString().replace("Z", ""), timeZone: tz },
      isOnlineMeeting: true,
      onlineMeetingProvider: "teamsForBusiness",
    });

    const joinUrl = event.onlineMeeting?.joinUrl ?? event.webLink;
    if (!joinUrl) throw new AmenIntegrationError("provider-error");
    return { providerMeetingId: event.id, joinUrl, startAt, endAt };
  }

  async updateMeeting(accessToken: string, providerMeetingId: string, input: Partial<CreateMeetingInput>): Promise<void> {
    const patch: Record<string, unknown> = {};
    if (input.title) patch["subject"] = input.title;
    if (input.startAtMs) patch["start"] = { dateTime: new Date(input.startAtMs).toISOString().replace("Z", ""), timeZone: input.timezone ?? "UTC" };
    if (input.endAtMs) patch["end"] = { dateTime: new Date(input.endAtMs).toISOString().replace("Z", ""), timeZone: input.timezone ?? "UTC" };
    if (Object.keys(patch).length > 0) {
      await graphRequest("PATCH", `/me/events/${encodeURIComponent(providerMeetingId)}`, accessToken, patch);
    }
  }

  async cancelMeeting(accessToken: string, providerMeetingId: string): Promise<void> {
    await graphRequest("DELETE", `/me/events/${encodeURIComponent(providerMeetingId)}`, accessToken);
  }
}
