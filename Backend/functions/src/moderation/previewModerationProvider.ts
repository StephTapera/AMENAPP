import { createHash } from "crypto";

export interface PreviewModerationInput {
    text: string;
    postId?: string;
    commentId?: string;
    candidateType?: string;
    source?: string;
}

export interface PreviewModerationResult {
    passed: boolean;
    confidence: number;
    normalizedText: string;
    matchedRules: string[];
    rejectionReason?: string;
}

const SAFE_MIN_CONFIDENCE = 0.65;

const RULES: Array<{ name: string; pattern: RegExp; reason: string; confidence: number }> = [
    { name: "self_harm_kys", pattern: /\bk\s*[._-]?\s*y\s*[._-]?\s*s\b/, reason: "self_harm_encouragement", confidence: 0.99 },
    { name: "self_harm_kill_yourself", pattern: /\bkill+\s+yourself\b/, reason: "self_harm_encouragement", confidence: 0.99 },
    { name: "violent_threat", pattern: /\bi\s+will\s+kill\s+you\b|\bshoot\s+you\b|\bstab\s+you\b/, reason: "violent_threat", confidence: 0.96 },
    { name: "sexual_explicit", pattern: /\b(sex|sexual|nude|naked|explicit)\b/, reason: "sexual_explicit_content", confidence: 0.9 },
    { name: "porn", pattern: /\bporn|pornography|xxx\b/, reason: "pornographic_content", confidence: 0.95 },
    { name: "harassment", pattern: /\byou are worthless\b|\bgo die\b|\bidiot\b|\bmoron\b/, reason: "harassment", confidence: 0.88 },
    { name: "slur_bypass_placeholder", pattern: /\bn[\W_]*[i1!|][\W_]*g[\W_]*g[\W_]*[e3][\W_]*r\b/, reason: "slur_bypass", confidence: 0.98 },
    { name: "spam_obfuscated_url", pattern: /\bh(?:tt|xx)p(?:s)?\b|\bdot\s+com\b|\bd0t\s+c0m\b|\bfree\s+followers?\b|\bclick\s+here\b/, reason: "spam_or_scam_link", confidence: 0.9 },
    { name: "coercive_spiritual_abuse", pattern: /\bgod told me you must obey me\b|\bif you disobey me you disobey god\b/, reason: "coercive_spiritual_abuse", confidence: 0.86 },
    { name: "hostile_religious_attack", pattern: /\byour faith is garbage\b|\byour god is fake\b/, reason: "hostile_religious_attack", confidence: 0.86 },
];

function normalizeUnicode(input: string): string {
    return input
        .normalize("NFKD")
        .replace(/[\u0300-\u036f]/g, "")
        .replace(/[\u2018\u2019]/g, "'")
        .replace(/[\u201C\u201D]/g, "\"");
}

function normalizeLeetspeak(input: string): string {
    return input
        .replace(/0/g, "o")
        .replace(/3/g, "e")
        .replace(/4/g, "a")
        .replace(/5/g, "s")
        .replace(/7/g, "t")
        .replace(/1/g, "i");
}

function collapsePunctuation(input: string): string {
    return input.replace(/([!?.,:_-])\1{1,}/g, "$1");
}

function collapseSpacedAbuse(input: string): string {
    return input
        .replace(/\bk[\s.\-_]*y[\s.\-_]*s\b/g, "kys")
        .replace(/\bh[\s.\-_]*x[\s.\-_]*x[\s.\-_]*p\b/g, "hxxp")
        .replace(/\bd[\s.\-_]*o[\s.\-_]*t[\s.\-_]*c[\s.\-_]*o[\s.\-_]*m\b/g, "dot com");
}

function collapseRepeatedLetters(input: string): string {
    return input.replace(/([a-z])\1{2,}/g, "$1$1");
}

function normalizeText(input: string): string {
    const lower = normalizeUnicode(input.toLowerCase());
    const spaced = collapseSpacedAbuse(lower);
    const leet = normalizeLeetspeak(spaced);
    const punctuation = collapsePunctuation(leet);
    const collapsedLetters = collapseRepeatedLetters(punctuation);
    return collapsedLetters.trim().replace(/\s+/g, " ");
}

export function hashNormalizedText(normalizedText: string): string {
    return createHash("sha256").update(normalizedText).digest("hex");
}

export function moderatePreviewText(input: PreviewModerationInput): PreviewModerationResult {
    if (!input || typeof input.text !== "string") {
        return {
            passed: false,
            confidence: 0,
            normalizedText: "",
            matchedRules: ["invalid_input"],
            rejectionReason: "unknown_moderation_state",
        };
    }

    const normalizedText = normalizeText(input.text);
    if (!normalizedText || normalizedText.length < 2) {
        return {
            passed: false,
            confidence: 0.2,
            normalizedText,
            matchedRules: ["empty_or_too_short"],
            rejectionReason: "pending_or_uncertain_moderation",
        };
    }

    const matched = RULES.filter((rule) => rule.pattern.test(normalizedText));
    if (matched.length > 0) {
        const worst = matched.reduce((max, rule) => Math.max(max, rule.confidence), 0.85);
        return {
            passed: false,
            confidence: worst,
            normalizedText,
            matchedRules: matched.map((rule) => rule.name),
            rejectionReason: matched[0]?.reason ?? "blocked_by_policy",
        };
    }

    const confidence = normalizedText.length >= 4 ? 0.9 : 0.6;
    if (confidence < SAFE_MIN_CONFIDENCE) {
        return {
            passed: false,
            confidence,
            normalizedText,
            matchedRules: ["low_confidence"],
            rejectionReason: "pending_or_uncertain_moderation",
        };
    }

    return {
        passed: true,
        confidence,
        normalizedText,
        matchedRules: [],
    };
}
