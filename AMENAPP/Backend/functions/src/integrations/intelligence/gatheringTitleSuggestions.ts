// integrations/intelligence/gatheringTitleSuggestions.ts
// Berean AI: Title suggestions. No provider connection required. No storage of rejected suggestions.

import * as functions from "firebase-functions";
import { errorResponse } from "../integrationErrors";

const TITLE_BANK: Record<string, Array<{ title: string; rationale?: string }>> = {
  prayerNight: [
    { title: "Evening of Prayer", rationale: "Classic and welcoming" },
    { title: "Seeking His Face", rationale: "Scripture-focused (Psalm 27:8)" },
    { title: "Collective Prayer Gathering", rationale: "Community-centered" },
  ],
  bibleStudy: [
    { title: "Rooted in the Word", rationale: "Emphasizes biblical grounding" },
    { title: "Deep Dive: Scripture Study", rationale: "Signals depth" },
    { title: "Walking Through Scripture", rationale: "Journey-oriented" },
  ],
  worshipNight: [
    { title: "Worship Night", rationale: "Clear and inviting" },
    { title: "Hearts Lifted High", rationale: "Expressive and uplifting" },
    { title: "Open Heavens", rationale: "Spiritually evocative" },
  ],
  smallGroup: [
    { title: "Community Group", rationale: "Relational and approachable" },
    { title: "Life Together", rationale: "Dietrich Bonhoeffer inspired" },
    { title: "Iron Sharpens Iron", rationale: "Proverbs 27:17" },
  ],
  churchService: [
    { title: "Sunday Gathering", rationale: "Simple and consistent" },
    { title: "Corporate Worship Service", rationale: "Formal and reverent" },
    { title: "Sunday Celebration", rationale: "Joy-forward" },
  ],
  retreat: [
    { title: "Spiritual Retreat", rationale: "Clear purpose" },
    { title: "Sabbath Retreat", rationale: "Rest-focused" },
    { title: "Renewal Weekend", rationale: "Transformation-oriented" },
  ],
  volunteerOpportunity: [
    { title: "Serve Together", rationale: "Action-focused" },
    { title: "Ministry Volunteer Day", rationale: "Clear and direct" },
    { title: "Hands and Feet", rationale: "James 2:17 inspired" },
  ],
};

export const gatheringSuggestTitles = functions.https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  if (!uid) return errorResponse("auth-required");

  const gatheringType = data["gatheringType"] as string | undefined;
  if (!gatheringType) return errorResponse("invalid-input");

  const contextHint = data["contextHint"] as string | undefined;
  const base = TITLE_BANK[gatheringType] ?? [
    { title: "Ministry Gathering" },
    { title: "Community Meeting" },
    { title: `${gatheringType.charAt(0).toUpperCase() + gatheringType.slice(1)} Gathering` },
  ];

  const suggestions = contextHint
    ? [{ title: contextHint, rationale: "Your input" }, ...base].slice(0, 3)
    : base.slice(0, 3);

  return { suggestions };
});
