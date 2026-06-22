export type MomentType =
  | "prayer"
  | "scripture"
  | "sermon"
  | "event"
  | "creator"
  | "study"
  | "mission"
  | "thread";

export type TemporalState = "upcoming" | "live" | "recap" | "evergreen";

export type MomentDeepenAction =
  | "summarize"
  | "crossReference"
  | "generatePrayer"
  | "generateStudyGuide"
  | "generateDiscussion"
  | "generateDevotional"
  | "saveTo";

export type MomentBereanMode = "ask" | "discern" | "build";

export type MomentSaveTarget =
  | "prayerJournal"
  | "studyJournal"
  | "churchNotes"
  | "sermonCollection"
  | "savedTeachings";

export interface MomentAdapterMoment {
  id: string;
  type: MomentType;
  temporalState: TemporalState;
  refId: string;
  ownerId: string;
  createdAt: number;
}

export interface MomentDeepenRequest {
  moment: MomentAdapterMoment;
  action: MomentDeepenAction;
  requesterId: string;
  bereanMode?: MomentBereanMode;
  saveTarget?: MomentSaveTarget;
  locale?: string;
}

export interface MomentGuardianReview {
  passed: boolean;
  policyVersion: string;
  reason?: string;
}

export interface MomentDeepenResult {
  momentId: string;
  action: MomentDeepenAction;
  output: string;
  citations: string[];
  savedTo?: MomentSaveTarget;
  guardian: MomentGuardianReview;
  createdAt: number;
}

export interface MomentDeepenRoute {
  action: MomentDeepenAction;
  selectedMode: MomentBereanMode;
  requestedMode?: MomentBereanMode;
  requiresLivingMemory: boolean;
}

export interface LivingMemoryHit {
  id: string;
  text: string;
  citation?: string;
  score?: number;
  metadata?: Record<string, unknown>;
}

export interface LivingMemoryQuery {
  requesterId: string;
  moment: MomentAdapterMoment;
  action: "crossReference";
  locale?: string;
}

export interface LivingMemoryPineconePort {
  crossReference(query: LivingMemoryQuery): Promise<LivingMemoryHit[]>;
}

export interface BereanDeepenInput {
  request: MomentDeepenRequest;
  route: MomentDeepenRoute;
  livingMemory: LivingMemoryHit[];
}

export interface BereanDeepenDraft {
  output: string;
  citations: string[];
  metadata?: Record<string, unknown>;
}

export interface BereanDeepenPort {
  run(input: BereanDeepenInput): Promise<BereanDeepenDraft>;
}

export interface ConstitutionalIntelligenceInput {
  request: MomentDeepenRequest;
  route: MomentDeepenRoute;
  draft: BereanDeepenDraft;
}

export interface ConstitutionalIntelligenceResult {
  output: string;
  citations: string[];
  notes?: string[];
  metadata?: Record<string, unknown>;
}

export interface ConstitutionalIntelligencePort {
  review(input: ConstitutionalIntelligenceInput): Promise<ConstitutionalIntelligenceResult>;
}

export interface GuardianAegisInput {
  request: MomentDeepenRequest;
  route: MomentDeepenRoute;
  constitutional: ConstitutionalIntelligenceResult;
}

export interface GuardianAegisPort {
  review(input: GuardianAegisInput): Promise<MomentGuardianReview>;
}

export interface MomentSaveInput {
  request: MomentDeepenRequest;
  result: MomentDeepenResult;
}

export interface MomentSavePort {
  save(input: MomentSaveInput): Promise<void>;
}

export interface MomentDeepenDependencies {
  berean: BereanDeepenPort;
  constitutionalIntelligence: ConstitutionalIntelligencePort;
  guardianAegis: GuardianAegisPort;
  livingMemory?: LivingMemoryPineconePort;
  save?: MomentSavePort;
  now?: () => number;
}

export type MomentAdapterDependency =
  | "berean"
  | "constitutionalIntelligence"
  | "guardianAegis"
  | "livingMemory"
  | "save";
