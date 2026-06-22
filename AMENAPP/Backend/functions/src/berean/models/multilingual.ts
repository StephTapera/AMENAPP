// berean/models/multilingual.ts
// AMEN - Berean multilingual layer Wave 0 contracts
//
// Frozen after Wave 0. Runtime behavior, callables, and model/provider wiring land
// in later waves only.

export type LanguageCode = string;

export const supportedLanguages = ["en", "es", "fr", "pt", "de"] as const;
export type SupportedLanguage = (typeof supportedLanguages)[number];

export type BereanMode = "ask" | "discern" | "build" | "guard" | "reflect";

export interface ScriptureRef {
  book: string;
  chapter: number;
  verseStart: number;
  verseEnd?: number;
}

export type LicenseTag =
  | { kind: "publicDomain" }
  | { kind: "licensed"; id: string };

export interface VerseText {
  ref: ScriptureRef;
  translationId: string;
  languageCode: LanguageCode;
  text: string;
  attribution: string;
  license: LicenseTag;
  source: "scriptureTextStore";
}

export interface TranslationManifest {
  translationId: string;
  languageCode: LanguageCode;
  license: LicenseTag;
  isPublicDomain: boolean;
  attribution: string;
  enabled: boolean;
  humanApprovedLicense: boolean;
}

export type CitationSourceType = "lexicon" | "crossref" | "tradition" | "history";

export interface Citation {
  sourceId: string;
  sourceType: CitationSourceType;
  label: string;
  url?: string;
}

export interface Explanation {
  sourceRefs: ScriptureRef[];
  languageCode: LanguageCode;
  body: string;
  citations: Citation[];
  generatedByModel: true;
}

export interface MultilingualRequest {
  mode: BereanMode;
  inputText: string;
  inputLanguage: LanguageCode;
  targetLanguage: LanguageCode;
  refs?: ScriptureRef[];
}

export interface ModerationVerdict {
  passed: boolean;
  capabilitiesTriggered: string[];
  languageDetected: LanguageCode;
  coverageVerified: boolean;
  reason?: string;
}

export interface MultilingualResponse {
  verses: VerseText[];
  explanation: Explanation;
  moderation: ModerationVerdict;
}

export type BereanMultilingualInvariant =
  | "M1_VERSE_INTEGRITY"
  | "M2_LICENSE_GATE"
  | "M3_CITATION_GATE"
  | "M4_VOICE_STAYS_ON_DEVICE"
  | "M5_UGC_RELAY_MODERATED"
  | "M6_OFFLINE_IS_STATIC"
  | "M7_MINOR_POSTURE_INHERITED"
  | "M8_FLAGS_OFF";

export class MultilingualContractError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "MultilingualContractError";
  }
}

export function assertSupportedLanguage(languageCode: LanguageCode): asserts languageCode is SupportedLanguage {
  if (!supportedLanguages.includes(languageCode as SupportedLanguage)) {
    throw new MultilingualContractError(`Unsupported language code: ${languageCode}`);
  }
}

export function assertScriptureRef(ref: ScriptureRef): void {
  if (!ref.book.trim() || ref.chapter < 1 || ref.verseStart < 1) {
    throw new MultilingualContractError("Invalid Scripture reference");
  }
  if (ref.verseEnd !== undefined && ref.verseEnd < ref.verseStart) {
    throw new MultilingualContractError("Invalid Scripture reference range");
  }
}

export function assertTranslationManifest(manifest: TranslationManifest): void {
  assertSupportedLanguage(manifest.languageCode);
  if (!manifest.translationId.trim() || !manifest.attribution.trim()) {
    throw new MultilingualContractError("Translation manifest missing required fields");
  }
  if (manifest.isPublicDomain !== (manifest.license.kind === "publicDomain")) {
    throw new MultilingualContractError("Translation manifest license mismatch");
  }
  if (manifest.enabled && !manifest.isPublicDomain && !manifest.humanApprovedLicense) {
    throw new MultilingualContractError("Enabled translations require a human-approved license");
  }
}

export function assertVerseText(verse: VerseText): void {
  assertScriptureRef(verse.ref);
  assertSupportedLanguage(verse.languageCode);
  if (verse.source !== "scriptureTextStore") {
    throw new MultilingualContractError("Verse text must come from the Scripture text store");
  }
  if (!verse.translationId.trim() || !verse.text.trim() || !verse.attribution.trim()) {
    throw new MultilingualContractError("Verse text missing required fields");
  }
}

export function assertCitation(citation: Citation): void {
  if (!citation.sourceId.trim() || !citation.label.trim()) {
    throw new MultilingualContractError("Citation must resolve to a real source entry");
  }
}

export function assertExplanation(explanation: Explanation): void {
  assertSupportedLanguage(explanation.languageCode);
  if (explanation.generatedByModel !== true) {
    throw new MultilingualContractError("Explanation channel must declare model generation");
  }
  if (!explanation.sourceRefs.length || !explanation.body.trim()) {
    throw new MultilingualContractError("Explanation missing required fields");
  }
  if (!explanation.citations.length) {
    throw new MultilingualContractError("Explanation claims require citations");
  }
  explanation.sourceRefs.forEach(assertScriptureRef);
  explanation.citations.forEach(assertCitation);
}

export function assertModerationVerdict(verdict: ModerationVerdict): void {
  assertSupportedLanguage(verdict.languageDetected);
  if (verdict.passed && !verdict.coverageVerified) {
    throw new MultilingualContractError("Passing moderation requires verified language coverage");
  }
}

export function assertMultilingualResponse(response: MultilingualResponse): void {
  response.verses.forEach(assertVerseText);
  assertExplanation(response.explanation);
  assertModerationVerdict(response.moderation);
  if (!response.moderation.passed) {
    throw new MultilingualContractError("Multilingual moderation blocked the response");
  }
}
