// integrations/intelligence/gatheringAgendaSuggestions.ts
// Berean AI: Agenda suggestions. User must confirm before any agenda is stored.

import * as functions from "firebase-functions";
import { errorResponse } from "../integrationErrors";

type AgendaItem = { durationMinutes: number; activity: string; scriptureReference?: string };

const AGENDA_BANK: Record<string, AgendaItem[]> = {
  prayerNight: [
    { durationMinutes: 10, activity: "Welcome & Opening Prayer" },
    { durationMinutes: 15, activity: "Worship Songs (2–3 songs)" },
    { durationMinutes: 20, activity: "Scripture Reading & Reflection", scriptureReference: "Philippians 4:6-7" },
    { durationMinutes: 20, activity: "Corporate Prayer — Specific Requests" },
    { durationMinutes: 10, activity: "Closing Worship & Blessing" },
  ],
  bibleStudy: [
    { durationMinutes: 10, activity: "Welcome & Opening Prayer" },
    { durationMinutes: 20, activity: "Scripture Reading & Context" },
    { durationMinutes: 25, activity: "Group Discussion & Questions" },
    { durationMinutes: 15, activity: "Application & Personal Reflection" },
    { durationMinutes: 10, activity: "Closing Prayer & Next Steps" },
  ],
  worshipNight: [
    { durationMinutes: 5, activity: "Welcome" },
    { durationMinutes: 35, activity: "Extended Worship Set" },
    { durationMinutes: 10, activity: "Scripture Reading", scriptureReference: "Psalm 150" },
    { durationMinutes: 15, activity: "Prayer & Ministry Time" },
    { durationMinutes: 5, activity: "Closing" },
  ],
  smallGroup: [
    { durationMinutes: 15, activity: "Welcome & Ice Breaker" },
    { durationMinutes: 15, activity: "Worship" },
    { durationMinutes: 20, activity: "Teaching & Discussion" },
    { durationMinutes: 15, activity: "Prayer Pairs" },
    { durationMinutes: 5, activity: "Announcements & Closing" },
  ],
  retreat: [
    { durationMinutes: 30, activity: "Arrival & Welcome" },
    { durationMinutes: 60, activity: "Opening Session & Teaching" },
    { durationMinutes: 30, activity: "Break & Fellowship" },
    { durationMinutes: 60, activity: "Small Group Discussion" },
    { durationMinutes: 60, activity: "Worship & Ministry Time" },
    { durationMinutes: 30, activity: "Closing Reflection & Prayer" },
  ],
};

export const gatheringSuggestAgenda = functions.https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  if (!uid) return errorResponse("auth-required");

  const gatheringType = data["gatheringType"] as string | undefined;
  if (!gatheringType) return errorResponse("invalid-input");

  const totalMinutes = Math.max(30, Math.min(480, (data["durationMinutes"] as number | undefined) ?? 60));
  const base = AGENDA_BANK[gatheringType] ?? AGENDA_BANK.smallGroup;
  const totalBase = base.reduce((s, i) => s + i.durationMinutes, 0);
  const scale = totalMinutes / totalBase;

  const agendaItems = base.map((item) => ({
    ...item,
    durationMinutes: Math.max(5, Math.round(item.durationMinutes * scale)),
  }));

  return { agendaItems };
});
