export type SmartEntityType =
  | "scriptureReference"
  | "dateTime"
  | "event"
  | "location"
  | "prayerRequest"
  | "question"
  | "topic"
  | "actionItem"
  | "voiceTranscript"
  | "studyTheme"
  | "bereanAction"
  | "knowledgeNode";

export type SmartActionType =
  | "openScripture"
  | "askBerean"
  | "addToCalendar"
  | "addReminder"
  | "createPrayerRequest"
  | "prayNow"
  | "summarizeThread"
  | "startStudyMode"
  | "saveToJournal"
  | "createTopic"
  | "searchRelated"
  | "openKnowledgeGraph"
  | "transcribeVoice"
  | "createStudyGuide";

export type SmartPrivacyLevel = "private" | "space" | "publicMetadata";

export interface TextRange {
  start: number;
  length: number;
}

export interface SmartDetectedEntity {
  id: string;
  type: SmartEntityType;
  sourceText: string;
  normalizedValue: string;
  confidence: number;
  range: TextRange;
  createdAt: number;
  metadata?: Record<string, unknown>;
}

export interface SmartMessageAction {
  id: string;
  title: string;
  subtitle: string;
  iconSystemName: string;
  actionType: SmartActionType;
  payload: Record<string, unknown>;
  requiresConfirmation: boolean;
  privacyLevel: SmartPrivacyLevel;
}

export interface SmartDiscussionInsight {
  summary: string;
  keyTakeaways: string[];
  scriptures: string[];
  prayerRequests: string[];
  topics: string[];
  actionItems: string[];
  unresolvedQuestions: string[];
  suggestedNextActions: SmartMessageAction[];
}

export interface SmartStudySession {
  id: string;
  spaceId: string;
  threadId: string;
  title: string;
  scriptures: string[];
  topics: string[];
  notes: string[];
  participants: string[];
  createdBy: string;
  createdAt: number;
  updatedAt: number;
}

export interface SmartKnowledgeNode {
  id: string;
  ownerScope: "user" | "space";
  nodeType: "scripture" | "topic" | "prayer" | "study" | "sermon" | "discussion" | "question";
  title: string;
  summary: string;
  scriptureRefs: string[];
  topics: string[];
  linkedMessageIds: string[];
  linkedThreadIds: string[];
  linkedSpaceIds: string[];
  createdAt: number;
  updatedAt: number;
}

export interface SmartMessageContext {
  uid: string;
  spaceId: string;
  threadId: string;
  messageId?: string;
  text: string;
}
