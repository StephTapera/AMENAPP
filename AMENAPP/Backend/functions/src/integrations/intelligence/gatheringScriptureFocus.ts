// integrations/intelligence/gatheringScriptureFocus.ts
// Berean AI: Scripture focus suggestions for gatherings

import * as functions from "firebase-functions";
import { errorResponse } from "../integrationErrors";

type ScriptureSuggestion = { reference: string; theme: string; preview: string };

const SCRIPTURE_BANK: Record<string, ScriptureSuggestion[]> = {
  prayerNight: [
    { reference: "Matthew 6:9-13", theme: "The Lord's Prayer", preview: "Our Father in heaven, hallowed be your name..." },
    { reference: "Philippians 4:6-7", theme: "Prayer & Peace", preview: "Do not be anxious about anything, but in every situation, by prayer..." },
    { reference: "1 Thessalonians 5:17", theme: "Continual Prayer", preview: "Pray continually." },
  ],
  bibleStudy: [
    { reference: "2 Timothy 3:16-17", theme: "Scripture's Authority", preview: "All Scripture is God-breathed and is useful for teaching, rebuking..." },
    { reference: "Psalm 119:105", theme: "God's Word as Guide", preview: "Your word is a lamp for my feet, a light on my path." },
    { reference: "Hebrews 4:12", theme: "Living Word", preview: "For the word of God is alive and active. Sharper than any double-edged sword..." },
  ],
  worshipNight: [
    { reference: "Psalm 150", theme: "Praise the Lord", preview: "Praise God in his sanctuary; praise him in his mighty heavens..." },
    { reference: "John 4:23-24", theme: "True Worship", preview: "True worshipers will worship the Father in the Spirit and in truth..." },
    { reference: "Psalm 95:1-7", theme: "Come Let Us Worship", preview: "Come, let us sing for joy to the LORD; let us shout aloud to the Rock of our salvation." },
  ],
  smallGroup: [
    { reference: "Acts 2:42-47", theme: "Early Church Fellowship", preview: "They devoted themselves to the apostles' teaching and to fellowship..." },
    { reference: "Hebrews 10:24-25", theme: "Spurring One Another On", preview: "Let us consider how we may spur one another on toward love and good deeds..." },
    { reference: "Matthew 18:20", theme: "Gathered in His Name", preview: "For where two or three gather in my name, there am I with them." },
  ],
  retreat: [
    { reference: "Psalm 46:10", theme: "Be Still", preview: "Be still, and know that I am God." },
    { reference: "Isaiah 40:31", theme: "Renewed Strength", preview: "Those who hope in the LORD will renew their strength. They will soar on wings like eagles..." },
    { reference: "Mark 6:31", theme: "Come Away and Rest", preview: "Come with me by yourselves to a quiet place and get some rest." },
  ],
};

export const gatheringSuggestScripture = functions.https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  if (!uid) return errorResponse("auth-required");

  const gatheringType = data["gatheringType"] as string | undefined;
  if (!gatheringType) return errorResponse("invalid-input");

  const suggestions = (SCRIPTURE_BANK[gatheringType] ?? SCRIPTURE_BANK.smallGroup).slice(0, 3);
  return { suggestions };
});
