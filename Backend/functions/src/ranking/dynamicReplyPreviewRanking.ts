interface RankedCommentLike {
    id: string;
    text: string;
    amenCount?: number;
    lightbulbCount?: number;
    replyCount?: number;
    prayerCount?: number;
    saveCount?: number;
    reportCount?: number;
    createdAt?: { toMillis?: () => number };
}

export interface RankingInput {
    comment: RankedCommentLike;
    viewerId?: string;
    authorAffinity?: number;
    safetyConfidence: number;
}

export interface RankingResult {
    finalScore: number;
    relevance: number;
    engagementQuality: number;
    recency: number;
    spiritualUsefulness: number;
    safetyConfidence: number;
    authorAffinity: number;
    includedWeights: string[];
    omittedWeights: string[];
    reasonForOmission: string[];
}

const WEIGHTS = {
    relevance: 0.28,
    engagementQuality: 0.24,
    recency: 0.12,
    spiritualUsefulness: 0.14,
    safetyConfidence: 0.22,
    authorAffinity: 0.18,
};

function clamp(value: number): number {
    if (value < 0) return 0;
    if (value > 1) return 1;
    return value;
}

function relevanceScore(text: string): number {
    const len = text.trim().length;
    if (len < 8) return 0.15;
    if (len <= 180) return clamp(len / 120);
    return clamp(1 - (len - 180) / 300);
}

function engagementScore(input: RankedCommentLike): number {
    const positive = (input.amenCount ?? 0) + (input.lightbulbCount ?? 0) + (input.replyCount ?? 0) + (input.prayerCount ?? 0) + (input.saveCount ?? 0);
    const reports = input.reportCount ?? 0;
    return clamp((positive - reports * 2) / 20);
}

function recencyScore(createdAt?: { toMillis?: () => number }): number {
    const now = Date.now();
    const ts = createdAt?.toMillis?.() ?? now;
    const ageHours = Math.max(0, (now - ts) / (1000 * 60 * 60));
    return clamp(1 - ageHours / 168);
}

function spiritualUsefulnessScore(text: string): number {
    const normalized = text.toLowerCase();
    let score = 0;
    if (/\bpray|prayer|amen|encourage|standing with you|with you\b/.test(normalized)) score += 0.4;
    if (/\b(john|psalm|romans|matthew|luke|acts)\b|\d+:\d+/.test(normalized)) score += 0.35;
    if (/\bhope|grace|faith|peace|repent|repentance|lament\b/.test(normalized)) score += 0.25;
    return clamp(score);
}

export function rankDynamicReplyCandidate(input: RankingInput): RankingResult {
    const relevance = relevanceScore(input.comment.text);
    const engagementQuality = engagementScore(input.comment);
    const recency = recencyScore(input.comment.createdAt);
    const spiritualUsefulness = spiritualUsefulnessScore(input.comment.text);
    const safetyConfidence = clamp(input.safetyConfidence);

    const includedWeights = ["relevance", "engagementQuality", "recency", "spiritualUsefulness", "safetyConfidence"];
    const omittedWeights: string[] = [];
    const reasonForOmission: string[] = [];

    let authorAffinity = 0;
    if (input.viewerId && typeof input.authorAffinity === "number") {
        authorAffinity = clamp(input.authorAffinity);
        includedWeights.push("authorAffinity");
    } else {
        omittedWeights.push("authorAffinity");
        reasonForOmission.push("viewerId_missing_or_no_real_relationship_signal");
    }

    const finalScore =
        relevance * WEIGHTS.relevance +
        engagementQuality * WEIGHTS.engagementQuality +
        recency * WEIGHTS.recency +
        spiritualUsefulness * WEIGHTS.spiritualUsefulness +
        safetyConfidence * WEIGHTS.safetyConfidence +
        authorAffinity * (includedWeights.includes("authorAffinity") ? WEIGHTS.authorAffinity : 0);

    return {
        finalScore: clamp(finalScore),
        relevance,
        engagementQuality,
        recency,
        spiritualUsefulness,
        safetyConfidence,
        authorAffinity,
        includedWeights,
        omittedWeights,
        reasonForOmission,
    };
}
