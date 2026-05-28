// integrations/providers/IntegrationProvider.ts
// Abstract provider interfaces — implemented by Microsoft, Zoom, Slack

import type { CreateMeetingInput, CreateMeetingOutput, SlackNotificationInput } from "../types";

export interface MeetingProvider {
  createMeeting(accessToken: string, input: CreateMeetingInput): Promise<CreateMeetingOutput>;
  updateMeeting?(accessToken: string, providerMeetingId: string, input: Partial<CreateMeetingInput>): Promise<void>;
  cancelMeeting?(accessToken: string, providerMeetingId: string): Promise<void>;
}

export interface SlackMessagingProvider {
  sendChannelNotification(accessToken: string, input: SlackNotificationInput): Promise<void>;
  listChannels(accessToken: string): Promise<Array<{ id: string; name: string; isPrivate: boolean }>>;
  verifyRequestSignature(signingSecret: string, signature: string, timestamp: string, body: string): boolean;
}
