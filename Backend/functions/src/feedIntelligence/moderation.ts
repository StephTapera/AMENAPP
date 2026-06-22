import { HttpsError } from "firebase-functions/v2/https";

const CRISIS_PATTERNS = [
  /\b(suicide|kill myself|end my life|self.harm|hurt myself)\b/i,
  /\b(rape|assault|molest|grooming|trafficking)\b/i,
  /\b(i am in danger|immediate danger|emergency)\b/i,
];

const MANIPULATION_PATTERNS = [
  /only show (me )?(people|accounts|content) (who |that )?(agree|support|confirm)/i,
  /hide (all )?(opposing|different|other) (views?|voices?|perspectives?)/i,
  /never show (me )?(anyone|content) (who |that )?(disagree|challenge|question)/i,
  /block (all )?(liberals?|conservatives?|democrats?|republicans?)/i,
];

const ABUSIVE_PATTERNS = [
  /\b(hate|kill|destroy|attack|ban)\s+(all\s+)?(christians?|muslims?|jews?|blacks?|whites?)\b/i,
];

export function moderateInput(text: string): {
  approved: boolean;
  safetyNotice?: string;
  echoChamberRisk: boolean;
  selfHarmRisk: boolean;
  manipulationRisk: boolean;
  rejectionReason?: string;
} {
  const selfHarmRisk = CRISIS_PATTERNS.some((p) => p.test(text));
  const manipulationRisk = MANIPULATION_PATTERNS.some((p) => p.test(text));
  const abusive = ABUSIVE_PATTERNS.some((p) => p.test(text));

  if (selfHarmRisk) {
    return {
      approved: false,
      selfHarmRisk: true,
      manipulationRisk: false,
      echoChamberRisk: false,
      rejectionReason: "crisis",
      safetyNotice: "If you're struggling, please reach out to a trusted person or call 988 (Suicide & Crisis Lifeline).",
    };
  }

  if (abusive) {
    return {
      approved: false,
      selfHarmRisk: false,
      manipulationRisk: false,
      echoChamberRisk: false,
      rejectionReason: "abusive_content",
    };
  }

  if (manipulationRisk) {
    // Soft approve with echo-chamber protection applied
    return {
      approved: true,
      selfHarmRisk: false,
      manipulationRisk: true,
      echoChamberRisk: true,
      safetyNotice:
        "Amen can reduce hostile or unhelpful content, but will preserve healthy diversity in your feed.",
    };
  }

  return { approved: true, selfHarmRisk: false, manipulationRisk: false, echoChamberRisk: false };
}

export function sanitizeText(text: string): string {
  return text.trim().slice(0, 800).replace(/<[^>]*>/g, "").replace(/[^\w\s.,!?'"()-]/g, " ").replace(/\s+/g, " ").trim();
}

export function requireAuth(request: import("firebase-functions/v2/https").CallableRequest): string {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Authentication required.");
  return uid;
}

export function requireAppCheck(request: import("firebase-functions/v2/https").CallableRequest): void {
  if (!request.app) throw new HttpsError("failed-precondition", "App Check required.");
}
