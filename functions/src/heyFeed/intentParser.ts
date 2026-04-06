// intentParser.ts — Server-side intent parser for Hey Feed NL commands

import { HeyFeedParsedIntent, HeyFeedNLAction, HeyFeedDurationType, HeyFeedNLTarget } from "./types";
import { TOPIC_SYNONYMS, TOPIC_LABELS, PARSER_VERSION } from "./constants";

export function parseHeyFeedText(text: string): HeyFeedParsedIntent {
  const normalized = text.trim().toLowerCase();

  if (!normalized) {
    return fallback(text);
  }

  const action   = detectAction(normalized);
  const targets  = detectTargets(normalized);
  const duration = detectDuration(normalized);
  const strength = detectStrength(normalized);
  const confidence = computeConfidence(targets);

  return {
    action,
    targets,
    duration,
    strength,
    confidence,
    originalText: text,
    requiresConfirmation: confidence < 0.55 || targets.length === 0,
    parserVersion: PARSER_VERSION,
  };
}

function detectAction(text: string): HeyFeedNLAction {
  const mute      = ["no more", "stop showing", "hide", "never show", "sick of", "tired of", "enough of", "dont show", "don't show", "remove all"];
  const decrease  = ["less", "fewer", "reduce", "cut back", "not as much", "avoid", "limit", "see less", "show less", "deprioritize"];
  const increase  = ["more", "show me more", "give me more", "see more", "want more", "increase", "prioritize", "boost", "surface more"];
  const explore   = ["explore", "discover", "try new", "something new", "variety", "different", "broaden", "mix it up"];
  const balance   = ["balance", "reset", "rebalance", "neutral", "normal", "go back", "default", "clear"];

  if (mute.some(w => text.includes(w)))     return "mute";
  if (decrease.some(w => text.includes(w))) return "decrease";
  if (increase.some(w => text.includes(w))) return "increase";
  if (explore.some(w => text.includes(w)))  return "explore";
  if (balance.some(w => text.includes(w)))  return "balance";
  return "increase"; // default
}

function detectTargets(text: string): HeyFeedNLTarget[] {
  const found: HeyFeedNLTarget[] = [];

  for (const [topicId, keywords] of Object.entries(TOPIC_SYNONYMS)) {
    const matches = keywords.filter(kw => text.includes(kw)).length;
    if (matches > 0) {
      const conf = Math.min(1.0, matches * 0.4 + 0.55);
      found.push({
        id: topicId,
        type: "topic",
        label: TOPIC_LABELS[topicId] ?? topicId,
        confidence: conf,
      });
    }
  }

  // Special targets
  if (text.includes("people i follow") || text.includes("followed accounts") || text.includes("accounts i follow")) {
    found.push({ id: "relationship_followed", type: "relationship", label: "People you follow", confidence: 0.92 });
  }
  if (text.includes("nearby") || text.includes("near me") || text.includes("local") || text.includes("my area")) {
    found.push({ id: "local_relevance", type: "locality", label: "Local content", confidence: 0.88 });
  }
  if (text.includes("repetitive") || text.includes("same thing") || text.includes("already seen")) {
    found.push({ id: "repetition", type: "format", label: "Repetitive content", confidence: 0.90 });
  }
  if (text.includes("intense") || text.includes("heavy") || text.includes("lighter") || text.includes("calmer")) {
    found.push({ id: "intensity", type: "intensity", label: "Intense/heavy content", confidence: 0.85 });
  }

  return found;
}

function detectDuration(text: string): HeyFeedDurationType {
  if (text.includes("tonight") || text.includes("right now") || text.includes("just now"))   return "session";
  if (text.includes("today") || text.includes("this afternoon") || text.includes("this morning")) return "today";
  if (text.includes("this week") || text.includes("week") || text.includes("7 days"))        return "seven_days";
  if (text.includes("3 days") || text.includes("three days") || text.includes("for a bit"))  return "three_days";
  if (text.includes("always") || text.includes("from now on") || text.includes("permanently")) return "persistent";
  return "three_days"; // Matches Threads default
}

function detectStrength(text: string): number {
  const strong   = ["a lot", "much more", "mostly", "really", "way more", "definitely", "absolutely"];
  const moderate = ["some", "a bit", "somewhat", "kind of", "occasionally", "sometimes"];
  const soft     = ["tiny bit", "slightly", "just a touch", "barely"];
  if (strong.some(w => text.includes(w)))   return 0.90;
  if (moderate.some(w => text.includes(w))) return 0.55;
  if (soft.some(w => text.includes(w)))     return 0.30;
  return 0.70;
}

function computeConfidence(targets: HeyFeedNLTarget[]): number {
  if (targets.length === 0) return 0.20;
  const avg = targets.reduce((sum, t) => sum + t.confidence, 0) / targets.length;
  return Math.min(0.97, avg + Math.min(0.15, (targets.length - 1) * 0.08));
}

function fallback(original: string): HeyFeedParsedIntent {
  return {
    action: "balance",
    targets: [],
    duration: "three_days",
    strength: 0.5,
    confidence: 0.10,
    originalText: original,
    requiresConfirmation: true,
    parserVersion: PARSER_VERSION,
  };
}
