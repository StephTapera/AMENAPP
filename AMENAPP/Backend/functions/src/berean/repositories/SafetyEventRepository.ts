// berean/repositories/SafetyEventRepository.ts
// Write-only for berean_safety_events. Never exposed to client directly.

import * as admin from "firebase-admin";
import { BereanSafetyEvent } from "../models/berean";

const db = () => admin.firestore();

export class SafetyEventRepository {
  async logSafetyEvent(event: Omit<BereanSafetyEvent, "id">): Promise<string> {
    const ref = db().collection("berean_safety_events").doc();
    await ref.set(event);
    return ref.id;
  }

  async logStateSession(
    userId: string,
    conversationId: string,
    messageId: string,
    primaryState: string,
    responseMode: string,
    sensitivityFlags: string[],
    escalationTriggered: boolean
  ): Promise<string> {
    const ref = db().collection("spiritual_state_sessions").doc();
    await ref.set({
      userId,
      conversationId,
      messageId,
      primaryState,
      responseMode,
      sensitivityFlags,
      escalationTriggered,
      generatedAt: admin.firestore.Timestamp.now(),
    });
    return ref.id;
  }
}

export const safetyEventRepository = new SafetyEventRepository();
