export type ContextContentType =
  | "scripture"
  | "post"
  | "comment"
  | "caption"
  | "transcript"
  | "note"
  | "message"
  | "media"
  | "article"
  | "unknown";

export type ContextAction =
  | "askBerean"
  | "explain"
  | "simplify"
  | "summarize"
  | "reflect"
  | "prayAboutThis"
  | "compareScripture"
  | "translate"
  | "define"
  | "historicalContext"
  | "saveToChurchNotes"
  | "createStudy"
  | "addReminder"
  | "turnIntoPrayer"
  | "turnIntoDevotional"
  | "turnIntoSermonOutline"
  | "shareReflection"
  | "askFollowUp"
  | "voiceExplain"
  | "discussWithGroup"
  | "askMentor"
  | "askPastor"
  | "searchRelatedVerses"
  | "createCarousel"
  | "createPost"
  | "continueReading"
  | "factCheck"
  | "crossReference"
  | "emotionalInsight"
  | "leadershipInsight"
  | "youthExplanation"
  | "beginnerExplanation";

export interface BereanContextPayload {
  id: string;
  selectedText: string;
  surroundingText?: string;
  sourceSurface: string;
  sourceId?: string;
  contentType: ContextContentType;
  scriptureReference?: string;
  languageCode?: string;
  metadata?: Record<string, string>;
}

export const allowedContextActions: ContextAction[] = [
  "askBerean",
  "explain",
  "simplify",
  "summarize",
  "reflect",
  "prayAboutThis",
  "compareScripture",
  "translate",
  "define",
  "historicalContext",
  "saveToChurchNotes",
  "createStudy",
  "addReminder",
  "turnIntoPrayer",
  "turnIntoDevotional",
  "turnIntoSermonOutline",
  "shareReflection",
  "askFollowUp",
  "voiceExplain",
  "discussWithGroup",
  "askMentor",
  "askPastor",
  "searchRelatedVerses",
  "createCarousel",
  "createPost",
  "continueReading",
  "factCheck",
  "crossReference",
  "emotionalInsight",
  "leadershipInsight",
  "youthExplanation",
  "beginnerExplanation",
];

export const allowedContextContentTypes: ContextContentType[] = [
  "scripture",
  "post",
  "comment",
  "caption",
  "transcript",
  "note",
  "message",
  "media",
  "article",
  "unknown",
];

export const allowedContextSourceSurfaces = [
  "selah_scripture_reader",
  "church_notes_editor",
  "church_notes_review",
  "communication_os",
  "message_thread",
  "berean_pulse",
  "feed",
  "media_detail",
  "covenant",
  "object_hub",
];

export interface SanitizedContextRequest {
  action: ContextAction;
  payload: BereanContextPayload;
}

export function actionInstruction(action: ContextAction): string {
  switch (action) {
    case "askBerean":
      return "Answer the user's contextual question about the selected content.";
    case "explain":
      return "Explain the selected content clearly and faithfully.";
    case "simplify":
      return "Simplify the selected content without flattening its meaning.";
    case "summarize":
      return "Summarize the selected content in a concise way.";
    case "reflect":
      return "Offer a grounded reflection that preserves user agency.";
    case "prayAboutThis":
      return "Turn the selected content into a short, humble prayer prompt.";
    case "compareScripture":
      return "Compare the selected content with related Scripture, noting uncertainty.";
    case "translate":
      return "Translate or explain language meaning when appropriate.";
    case "define":
      return "Define key terms in the selection.";
    case "historicalContext":
      return "Give historical and cultural context with interpretive caution.";
    case "saveToChurchNotes":
      return "Create a private Church Notes-ready summary.";
    case "createStudy":
      return "Create a compact study outline.";
    case "addReminder":
      return "Suggest a calm reminder based on the selected content.";
    case "turnIntoPrayer":
      return "Convert the selected content into a prayer.";
    case "turnIntoDevotional":
      return "Convert the selected content into a brief devotional.";
    case "turnIntoSermonOutline":
      return "Create a sermon outline from the selected content.";
    case "shareReflection":
      return "Draft a shareable reflection without exposing private context.";
    case "askFollowUp":
      return "Suggest thoughtful follow-up questions.";
    case "voiceExplain":
      return "Write a spoken explanation suitable for voice playback.";
    case "discussWithGroup":
      return "Create a group discussion prompt.";
    case "askMentor":
      return "Frame a question the user could ask a mentor.";
    case "askPastor":
      return "Frame a question the user could ask a pastor.";
    case "searchRelatedVerses":
      return "Return related verses and why they are relevant.";
    case "createCarousel":
      return "Draft carousel slide copy from the selection.";
    case "createPost":
      return "Draft a thoughtful post from the selection.";
    case "continueReading":
      return "Suggest what to read next and why.";
    case "factCheck":
      return "Check factual or theological claims with caution.";
    case "crossReference":
      return "Find cross references and explain connections.";
    case "emotionalInsight":
      return "Name possible emotional tone without pretending certainty.";
    case "leadershipInsight":
      return "Offer leadership insight while avoiding spiritual authority overreach.";
    case "youthExplanation":
      return "Explain this for a youth audience.";
    case "beginnerExplanation":
      return "Explain this for someone new to faith or Scripture.";
  }
}

export function sanitizePayload(raw: unknown): BereanContextPayload {
  const data = (raw ?? {}) as Record<string, unknown>;
  const selectedText = String(data.selectedText ?? "").trim();
  const sourceSurface = String(data.sourceSurface ?? "unknown").slice(0, 80);
  const contentType = String(data.contentType ?? "unknown") as ContextContentType;
  const metadata = data.metadata && typeof data.metadata === "object"
    ? Object.fromEntries(
        Object.entries(data.metadata as Record<string, unknown>)
          .slice(0, 20)
          .map(([key, value]) => [key.slice(0, 40), String(value).slice(0, 160)])
      )
    : {};

  return {
    id: String(data.id ?? "").slice(0, 80),
    selectedText: selectedText.slice(0, 6000),
    surroundingText: String(data.surroundingText ?? "").slice(0, 6000),
    sourceSurface,
    sourceId: String(data.sourceId ?? "").slice(0, 160),
    contentType,
    scriptureReference: String(data.scriptureReference ?? "").slice(0, 120),
    languageCode: String(data.languageCode ?? "").slice(0, 16),
    metadata,
  };
}

export function selectedTextLength(raw: unknown): number {
  const data = (raw ?? {}) as Record<string, unknown>;
  return String(data.selectedText ?? "").trim().length;
}

export function isSupportedContextSource(payload: BereanContextPayload): boolean {
  return (
    allowedContextContentTypes.includes(payload.contentType) &&
    allowedContextSourceSurfaces.includes(payload.sourceSurface)
  );
}

export function isPrivacySafeContextResult(data: Record<string, unknown>): boolean {
  const serialized = JSON.stringify(data).toLowerCase();
  const blocked = [
    "god told me about you",
    "god told me you",
    "i remember you",
    "your previous prayer",
    "your private struggle",
    "your emotional pattern",
    "your saved memory says",
  ];
  return blocked.every((pattern) => !serialized.includes(pattern));
}

export function sanitizeContextResponse(data: Record<string, unknown>): Record<string, unknown> {
  const safe: Record<string, unknown> = {
    id: String(data.id ?? ""),
    title: String(data.title ?? ""),
    answer: String(data.answer ?? ""),
    scriptureReferences: Array.isArray(data.scriptureReferences)
      ? data.scriptureReferences.map((item) => String(item)).slice(0, 12)
      : [],
    suggestedActions: Array.isArray(data.suggestedActions)
      ? data.suggestedActions.map((item) => String(item)).slice(0, 8)
      : [],
    safetyNotice: String(data.safetyNotice ?? ""),
    threadId: String(data.threadId ?? ""),
  };

  if (!isPrivacySafeContextResult(safe)) {
    safe.answer = "Berean cannot safely use or imply private memory for this response. Please ask again with only the context you want included.";
    safe.suggestedActions = [];
  }

  return safe;
}
