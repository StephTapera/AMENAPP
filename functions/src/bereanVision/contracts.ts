// Source of truth. Swift ReasoningRequest/Result mirror this exactly.
export type VisionSceneType =
  | "scripture" | "studyTable" | "sermonScreen"
  | "document" | "book" | "travel" | "unknown";

export type ReasoningVerb =
  | "explain" | "compare" | "challenge" | "teach" | "simplify"
  | "apply" | "memorize" | "connect" | "debate" | "predict";

export interface SceneContextDTO {
  sceneType: VisionSceneType;
  objects: { label: string; confidence: number }[]; // NO bounding boxes server-side, NO image
  recognizedText: string[];
  suggestedModes: string[];
  confidence: number;
}

export interface ReasoningRequestDTO {
  verb: ReasoningVerb;
  sceneContext: SceneContextDTO;   // derived data ONLY
  userIdHash: string;              // hashed
  mode?: string;
}

export interface ReasoningResultDTO {
  verb: ReasoningVerb;
  paragraphs: string[];
  citations: string[];
  memoryLinkIds: string[];
}
