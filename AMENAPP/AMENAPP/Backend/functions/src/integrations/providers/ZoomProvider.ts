// integrations/providers/ZoomProvider.ts
// Zoom API — meeting creation/updates/cancellation
// Security: host URL NEVER returned to participants; stored in hostSecrets subcollection only

import { AmenIntegrationError, AmenProviderError, mapProviderHttpError } from "../integrationErrors";
import type { MeetingProvider } from "./IntegrationProvider";
import type { CreateMeetingInput, CreateMeetingOutput } from "../types";

const ZOOM_BASE = "https://api.zoom.us/v2";
const TIMEOUT_MS = 15_000;

async function zoomRequest<T>(method: string, path: string, token: string, body?: unknown): Promise<T> {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  try {
    const resp = await fetch(`${ZOOM_BASE}${path}`, {
      method,
      headers: { "Authorization": `Bearer ${token}`, "Content-Type": "application/json" },
      ...(body ? { body: JSON.stringify(body) } : {}),
      signal: ctrl.signal,
    });
    if (!resp.ok) {
      console.error(`[ZoomProvider] ${method} ${path} → ${resp.status}`);
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

export class ZoomMeetingProvider implements MeetingProvider {
  async createMeeting(accessToken: string, input: CreateMeetingInput): Promise<CreateMeetingOutput> {
    const startAt = new Date(input.startAtMs);
    const durationMin = input.endAtMs
      ? Math.round((input.endAtMs - input.startAtMs) / 60_000)
      : 60;

    type ZoomMeeting = { id: number; join_url: string; start_url: string; start_time: string; duration: number };

    const meeting = await zoomRequest<ZoomMeeting>("POST", "/users/me/meetings", accessToken, {
      topic: input.title,
      type: input.isRecurring ? 8 : 2,
      start_time: startAt.toISOString(),
      duration: durationMin,
      timezone: input.timezone ?? "UTC",
      settings: {
        waiting_room: input.waitingRoom ?? true,
        join_before_host: false,
        mute_upon_entry: false,
        auto_recording: "none",
        host_video: false,
        participant_video: false,
        approval_type: 2,
      },
      ...(input.passcode ? { password: input.passcode } : {}),
    });

    const endAt = new Date(new Date(meeting.start_time).getTime() + meeting.duration * 60_000);
    return {
      providerMeetingId: String(meeting.id),
      joinUrl: meeting.join_url,
      hostUrl: meeting.start_url, // Internal only — stored in hostSecrets, never returned to participants
      startAt: new Date(meeting.start_time),
      endAt,
    };
  }

  async updateMeeting(accessToken: string, providerMeetingId: string, input: Partial<CreateMeetingInput>): Promise<void> {
    const body: Record<string, unknown> = {};
    if (input.title) body["topic"] = input.title;
    if (input.startAtMs) body["start_time"] = new Date(input.startAtMs).toISOString();
    if (input.endAtMs && input.startAtMs) body["duration"] = Math.round((input.endAtMs - input.startAtMs) / 60_000);
    if (Object.keys(body).length > 0) {
      await zoomRequest("PATCH", `/meetings/${encodeURIComponent(providerMeetingId)}`, accessToken, body);
    }
  }

  async cancelMeeting(accessToken: string, providerMeetingId: string): Promise<void> {
    await zoomRequest("DELETE", `/meetings/${encodeURIComponent(providerMeetingId)}`, accessToken);
  }
}
