// integrations/intelligence/gatheringFollowUps.ts
// Berean AI: Post-gathering follow-up prompts. Only suggests — user confirms before storage.

import * as functions from "firebase-functions";
import { errorResponse } from "../integrationErrors";

const FOLLOWUP_BANK: Record<string, string[]> = {
  prayerNight: [
    "What specific prayers were lifted tonight?",
    "Are there follow-up care actions for those who shared needs?",
    "What scripture themes emerged during prayer?",
  ],
  bibleStudy: [
    "What was the key takeaway from tonight's passage?",
    "What personal application steps did the group identify?",
    "Which questions deserve deeper exploration next session?",
  ],
  worshipNight: [
    "What moments of breakthrough were noticed tonight?",
    "Are there needs that surfaced during ministry time?",
    "What songs or themes resonated most with the group?",
  ],
  smallGroup: [
    "What prayer requests were shared tonight?",
    "Are there action items for the group this week?",
    "Who might benefit from a personal check-in this week?",
  ],
  retreat: [
    "What commitments did participants make?",
    "What were the key themes God highlighted this weekend?",
    "How can we support continued growth after the retreat?",
  ],
};

export const gatheringSuggestFollowUps = functions.https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  if (!uid) return errorResponse("auth-required");

  const gatheringType = data["gatheringType"] as string | undefined;
  if (!gatheringType) return errorResponse("invalid-input");

  const prompts = FOLLOWUP_BANK[gatheringType] ?? FOLLOWUP_BANK.smallGroup;
  return { prompts };
});
