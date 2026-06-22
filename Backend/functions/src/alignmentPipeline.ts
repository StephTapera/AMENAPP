// alignmentPipeline.ts
// Rule-based spiritual alignment + spiritual-protection classification pipeline.
// No LLM calls — fast, deterministic, runs inline with every post/comment/Berean send.
// Used by biblicalAlignmentFunctions.ts for server-side callable enforcement.

import * as crypto from "crypto";

// ─── Types ────────────────────────────────────────────────────────────────────

export type AlignmentStatus =
    | "aligned"
    | "context_needed"
    | "needs_discernment"
    | "blocked"
    | "human_review";

export type SuggestedAction =
    | "allow"
    | "allow_with_context"
    | "ask_user_preference"
    | "suggest_rewrite"
    | "hold_for_review"
    | "block";

export interface AlignmentCheckInput {
    text: string;
    targetType: string;
    sourceSurface: string;
    requestedLens?: string;
    hasMedia?: boolean;
    userProfile?: {
        explicitContentProtectionEnabled?: boolean;
        exploitationProtectionEnabled?: boolean;
        discernmentMode?: string;
    };
}

export interface AlignmentCheckResult {
    checkId: string;
    status: AlignmentStatus;
    alignmentScore: number;
    confidence: number;
    suggestedAction: SuggestedAction;
    userVisibleSummary: string;
    flags: string[];
    scriptureSuggestions: Array<{ reference: string; reason: string }>;
    rewriteSuggestion: string | null;
    modelMetadata: { pipeline: "rules_v1"; version: string };
}

// ─── Utilities ────────────────────────────────────────────────────────────────

export function hashContent(text: string): string {
    return crypto.createHash("sha256").update(text.trim()).digest("hex");
}

export function previewContent(text: string): string {
    const t = text.trim().replace(/\s+/g, " ");
    return t.length > 100 ? t.slice(0, 100) + "…" : t;
}

export function normalizeText(text: string): string {
    return text
        .toLowerCase()
        .replace(/0/g, "o").replace(/1/g, "i").replace(/3/g, "e")
        .replace(/4/g, "a").replace(/5/g, "s")
        .replace(/[^a-z0-9\s]/g, " ")
        .replace(/(.)\1{2,}/g, "$1$1")
        .replace(/\s+/g, " ")
        .trim();
}

// ─── Pattern Banks ────────────────────────────────────────────────────────────

// Hard-block patterns — always escalate regardless of user settings
const HARD_BLOCK_PATTERNS: Array<{ pattern: RegExp; flag: string }> = [
    // Trafficking & recruitment
    { pattern: /\b(traffick|smuggl).{0,40}(person|girl|boy|woman|man|minor|child)/i, flag: "trafficking" },
    { pattern: /\b(move|transport|take|bring).{0,30}(across border|out of state|for sex|for money)\b/i, flag: "trafficking" },
    { pattern: /\bsex work(er)?.{0,20}(recruit|hire|train|find)\b/i, flag: "trafficking" },
    { pattern: /\b(pimp|madam).{0,20}(train|manage|control|recruit)\b/i, flag: "trafficking" },
    // Grooming
    { pattern: /\bhow to.{0,30}groom.{0,30}(child|minor|kid|teen|young person)\b/i, flag: "grooming" },
    { pattern: /\bgain.{0,20}trust.{0,30}(child|minor|kid|teen).{0,30}(secret|alone|without parent)\b/i, flag: "grooming" },
    { pattern: /\bsend me.{0,20}(nude|naked|explicit|sexual).{0,20}(pic|photo|image|video)\b/i, flag: "grooming" },
    { pattern: /\b(you seem mature for your age|don.?t tell your parents|our secret)\b/i, flag: "grooming" },
    // Sexual blackmail & coercion
    { pattern: /\bsextort/i, flag: "sexual_blackmail" },
    { pattern: /\b(share|post|send|leak).{0,30}(your|her|his).{0,10}(nudes|naked|explicit).{0,20}(if|unless|or)\b/i, flag: "sexual_blackmail" },
    { pattern: /\bnon.?consensual.{0,20}(porn|image|video|content)\b/i, flag: "sexual_blackmail" },
    // Minor exploitation — zero tolerance
    { pattern: /\bchild pornograph/i, flag: "minor_exploitation" },
    { pattern: /\bcsam\b/i, flag: "minor_exploitation" },
    { pattern: /\b(sexual|explicit|nude).{0,20}(child|minor|underage|under.?age)\b/i, flag: "minor_exploitation" },
    // Direct threats
    { pattern: /\b(i.?ll|i will|gonna|going to).{0,20}(kill|hurt|harm|attack|murder|shoot|stab).{0,30}(you|your|them|him|her)\b/i, flag: "threats" },
    { pattern: /\byou (deserve to|should) (die|be killed)\b/i, flag: "threats" },
    { pattern: /\bburn in hell.{0,0}/i, flag: "threats" },
    // Explicit sexual content requests
    { pattern: /\bshow me.{0,20}(naked|nude|explicit|hardcore).{0,20}(woman|man|girl|boy|person)\b/i, flag: "explicit_sexual" },
    { pattern: /\b(find|send|get|show).{0,20}pornograph/i, flag: "explicit_sexual" },
];

// Needs-discernment patterns — pastoral response, not hard block
const DISCERNMENT_PATTERNS: Array<{ pattern: RegExp; flag: string; category: string }> = [
    // Scripture misuse / spiritual abuse
    { pattern: /\b(the bible says|god says|scripture says).{0,80}(you are condemned|god hates you|you are cursed|going to hell)\b/i, flag: "scripture_misuse", category: "spiritual_harm" },
    { pattern: /\bgod hates.{0,20}(gays|trans|sinners|people like you)\b/i, flag: "scripture_misuse", category: "spiritual_harm" },
    // Shame-based religious language
    { pattern: /\byou (are|'?re).{0,10}(spiritually blind|spiritually dead|damned|cursed)\b/i, flag: "shame_language", category: "shame_based" },
    { pattern: /\bgod is punishing you\b/i, flag: "shame_language", category: "shame_based" },
    { pattern: /\bthis is god.?s (judgment|judgement|punishment) on you\b/i, flag: "shame_language", category: "shame_based" },
    // Harassment in faith framing
    { pattern: /\b(you disgust|you.?re disgusting).{0,30}/i, flag: "harassment", category: "harassment" },
    { pattern: /\bgod hates people like you\b/i, flag: "harassment", category: "harassment" },
    // Pride patterns
    { pattern: /\bi.?(am|'?m).{0,20}(more righteous|holier|better|above).{0,20}(everyone|other|them|you|most)\b/i, flag: "pride", category: "pride" },
    // Wrath
    { pattern: /\bi want (revenge|to hurt|to punish|to destroy).{0,0}/i, flag: "wrath", category: "wrath" },
    // Lust
    { pattern: /\b(lusting after|sexual fantasy about|pornograph|masturbat).{0,30}(is it ok|is that sin|can i|should i)\b/i, flag: "lust", category: "lust" },
    // Theological sensitivity
    { pattern: /\b(what happens|does god think|is it ok).{0,30}(suicide|killing yourself|end your life|self harm)\b/i, flag: "theological_sensitivity", category: "theological_ambiguity" },
    { pattern: /\b(is (abortion|euthanasia|capital punishment)).{0,20}(a sin|biblical|allowed|ok)\b/i, flag: "theological_sensitivity", category: "theological_ambiguity" },
    // Crisis / self-harm — escalate to human review
    { pattern: /\b(want to end my life|kill myself|not be here anymore|take my own life)\b/i, flag: "self_harm", category: "crisis" },
];

// Positive faith signals (increase confidence in "aligned" classification)
const ALIGNED_SIGNALS: RegExp[] = [
    /\b(jesus|christ|god|holy spirit|scripture|bible|pray|faith|grace|love|forgive|mercy|salvation|worship)\b/i,
    /\b(amen|blessed|hallelujah|praise|testimony|gospel|church|sermon|devotion|disciple)\b/i,
];

// ─── Core Classification ───────────────────────────────────────────────────────

export function classifyLocalRisk(
    text: string,
    context: { targetType?: string; userProfile?: AlignmentCheckInput["userProfile"] } = {}
): { status: AlignmentStatus; flags: string[]; confidence: number } {
    if (!text || text.trim().length === 0) {
        return { status: "aligned", flags: [], confidence: 0.95 };
    }

    const norm = normalizeText(text);
    const flags: string[] = [];

    for (const { pattern, flag } of HARD_BLOCK_PATTERNS) {
        if (pattern.test(text) || pattern.test(norm)) {
            if (!flags.includes(flag)) flags.push(flag);
        }
    }

    // Hard-block categories: always block regardless of user settings
    if (flags.some(f => ["trafficking", "grooming", "minor_exploitation", "sexual_blackmail"].includes(f))) {
        return { status: "blocked", flags, confidence: 0.96 };
    }
    if (flags.some(f => f === "threats")) {
        return { status: "blocked", flags, confidence: 0.92 };
    }
    // Explicit content: blocked when protection is on (default), discernment otherwise
    if (flags.some(f => f === "explicit_sexual")) {
        const protect = context.userProfile?.explicitContentProtectionEnabled !== false;
        return { status: protect ? "blocked" : "needs_discernment", flags, confidence: 0.90 };
    }

    // Discernment pass
    for (const { pattern, flag, category } of DISCERNMENT_PATTERNS) {
        if (pattern.test(text) || pattern.test(norm)) {
            if (!flags.includes(flag)) flags.push(flag);
            if (category === "crisis") {
                return { status: "human_review", flags, confidence: 0.90 };
            }
        }
    }

    if (flags.some(f => ["scripture_misuse", "shame_language", "harassment"].includes(f))) {
        return { status: "needs_discernment", flags, confidence: 0.84 };
    }
    if (flags.some(f => ["wrath", "lust", "pride"].includes(f))) {
        return { status: "context_needed", flags, confidence: 0.76 };
    }
    if (flags.some(f => ["theological_sensitivity"].includes(f))) {
        return { status: "context_needed", flags, confidence: 0.72 };
    }

    const hasAlignedSignal = ALIGNED_SIGNALS.some(p => p.test(text));
    return { status: "aligned", flags: [], confidence: hasAlignedSignal ? 0.93 : 0.79 };
}

// ─── Scripture Suggestions ────────────────────────────────────────────────────

const SCRIPTURE_MAP: Record<string, Array<{ reference: string; reason: string }>> = {
    wrath: [
        { reference: "Ephesians 4:26", reason: "Be angry but do not sin; process anger with God." },
        { reference: "Proverbs 15:1", reason: "A gentle answer turns away wrath." },
    ],
    pride: [
        { reference: "Proverbs 11:2", reason: "When pride comes, disgrace follows; wisdom comes with humility." },
        { reference: "Philippians 2:3", reason: "In humility count others more significant than yourselves." },
    ],
    lust: [
        { reference: "1 Corinthians 6:18–20", reason: "Flee sexual immorality; your body is a temple." },
        { reference: "Matthew 5:28", reason: "Jesus on the heart-level nature of lust." },
    ],
    shame_language: [
        { reference: "Romans 8:1", reason: "There is no condemnation for those in Christ Jesus." },
        { reference: "John 3:17", reason: "God sent His Son to save, not to condemn." },
    ],
    scripture_misuse: [
        { reference: "Acts 17:11", reason: "The Bereans examined scriptures daily to verify what they heard." },
        { reference: "2 Timothy 2:15", reason: "Correctly handle the word of truth." },
    ],
    harassment: [
        { reference: "Ephesians 4:29", reason: "Let only what builds others up come from your mouth." },
    ],
    trafficking: [
        { reference: "Matthew 18:6", reason: "God's fierce protection over the vulnerable." },
    ],
    grooming: [
        { reference: "Matthew 18:6", reason: "God's fierce protection over the vulnerable." },
    ],
    theological_sensitivity: [
        { reference: "Proverbs 4:7", reason: "Seek wisdom before making important decisions." },
        { reference: "James 1:5", reason: "If you lack wisdom, ask God who gives generously." },
    ],
};

export function buildScriptureSuggestions(flags: string[]): Array<{ reference: string; reason: string }> {
    const seen = new Set<string>();
    const out: Array<{ reference: string; reason: string }> = [];
    for (const f of flags) {
        for (const s of SCRIPTURE_MAP[f] ?? []) {
            if (!seen.has(s.reference)) { seen.add(s.reference); out.push(s); }
        }
    }
    return out.slice(0, 3);
}

// ─── User-Visible Summary ─────────────────────────────────────────────────────

export function buildUserVisibleSummary(status: AlignmentStatus, flags: string[]): string {
    const has = (f: string) => flags.includes(f);

    if (status === "blocked") {
        if (has("trafficking") || has("grooming") || has("minor_exploitation")) {
            return "This content appears to involve exploitation or harm to a person. It cannot be posted.";
        }
        if (has("sexual_blackmail")) {
            return "This content involves sexual coercion or blackmail. It cannot be posted.";
        }
        if (has("explicit_sexual")) {
            return "Explicit sexual content cannot be posted here.";
        }
        if (has("threats")) {
            return "This message appears to include a direct threat. It cannot be posted.";
        }
        return "This content cannot be posted based on Amen's community safety standards.";
    }

    if (status === "human_review") {
        return "This content has been held for a compassionate review before it can be shared.";
    }

    if (status === "needs_discernment") {
        if (has("scripture_misuse")) {
            return "This post uses scripture in a way that may condemn others. Would you like to rewrite it with more grace?";
        }
        if (has("shame_language")) {
            return "This message may be harmful to someone's spiritual wellbeing. Consider rewriting with compassion.";
        }
        if (has("harassment")) {
            return "This comment may feel degrading to someone. You can rewrite it in a way that is honest and respectful.";
        }
        return "This content may need some discernment before sharing with others.";
    }

    if (status === "context_needed") {
        if (has("wrath")) return "This may be expressing strong anger. Want to pause, pray, or rewrite before posting?";
        if (has("lust")) return "This topic touches on sexual content. Berean can offer scripture or pastoral guidance.";
        if (has("pride")) return "This may benefit from a tone of humility. Would you like Berean to suggest a rewrite?";
        if (has("theological_sensitivity")) return "This is a theologically sensitive topic. Berean can offer balanced perspectives.";
        return "Berean found some context that may be helpful before you post.";
    }

    return "Your content looks aligned.";
}

// ─── Supporting Helpers ───────────────────────────────────────────────────────

export function computeAlignmentScore(status: AlignmentStatus, confidence: number): number {
    const base: Record<AlignmentStatus, number> = {
        aligned: 0.95, context_needed: 0.65, needs_discernment: 0.40,
        blocked: 0.05, human_review: 0.20,
    };
    return Math.round(base[status] * confidence * 100) / 100;
}

export function determineSuggestedAction(status: AlignmentStatus, flags: string[]): SuggestedAction {
    switch (status) {
        case "aligned": return "allow";
        case "context_needed":
            return (flags.includes("lust") || flags.includes("theological_sensitivity"))
                ? "ask_user_preference" : "allow_with_context";
        case "needs_discernment": return "suggest_rewrite";
        case "blocked": return "block";
        case "human_review": return "hold_for_review";
    }
}

export function buildRewriteSuggestion(text: string, flags: string[]): string {
    const has = (f: string) => flags.includes(f);
    if (has("shame_language") || has("scripture_misuse")) {
        return "I believe this passage calls us to reflect carefully on our own hearts. I'd encourage everyone to read it prayerfully and consider what God may be teaching through it.";
    }
    if (has("harassment")) {
        return "I see this differently, and I want to respond with respect. Here is my perspective…";
    }
    if (has("wrath")) {
        return "I've been feeling a lot of hurt around this. I want to pause and process before I respond further.";
    }
    if (has("pride")) {
        return "I'm still learning about this topic and find this perspective worth reflecting on.";
    }
    return text;
}

// ─── Discernment Prompt Builder ───────────────────────────────────────────────

export function getDiscernmentPromptData(flags: string[]): {
    shouldPrompt: boolean;
    promptTitle: string;
    promptMessage: string;
    options: Array<{ id: string; label: string; description: string }>;
} {
    const has = (f: string) => flags.includes(f);
    const isSensitive = has("wrath") || has("lust") || has("theological_sensitivity")
        || has("pride") || has("scripture_misuse") || has("shame_language");

    if (!isSensitive) return { shouldPrompt: false, promptTitle: "", promptMessage: "", options: [] };

    let promptTitle = "This may need spiritual discernment";
    let promptMessage = "How would you like Berean to respond?";

    if (has("wrath")) {
        promptTitle = "This feels like it comes from pain or anger";
        promptMessage = "Berean can offer scripture, pastoral wisdom, or a safe space to process.";
    } else if (has("theological_sensitivity")) {
        promptTitle = "This is a theologically sensitive question";
        promptMessage = "How would you like Berean to approach this topic?";
    } else if (has("lust")) {
        promptTitle = "This may be touching a sensitive area";
        promptMessage = "Want Berean to respond with pastoral care, scripture, or practical wisdom?";
    }

    return {
        shouldPrompt: true,
        promptTitle,
        promptMessage,
        options: [
            { id: "scripture",  label: "Answer with Scripture",  description: "Ground the answer in a specific passage" },
            { id: "pastoral",   label: "Pastoral Guidance",       description: "Warm, empathetic response with practical next steps" },
            { id: "study",      label: "Study Mode",              description: "Deeper theological context and historical background" },
            { id: "practical",  label: "Practical Wisdom",        description: "What does this mean for my day-to-day life?" },
            { id: "neutral",    label: "Neutral Answer",          description: "Balanced overview without spiritual pressure" },
            { id: "simple",     label: "Simple Answer",           description: "Short, clear, plain language" },
        ],
    };
}

// ─── Main Pipeline ────────────────────────────────────────────────────────────

export async function runBiblicalAlignmentPipeline(
    input: AlignmentCheckInput
): Promise<AlignmentCheckResult> {
    const { text, targetType, userProfile } = input;
    const { status, flags, confidence } = classifyLocalRisk(text, { targetType, userProfile });
    const suggestedAction = determineSuggestedAction(status, flags);
    const userVisibleSummary = buildUserVisibleSummary(status, flags);
    const scriptureSuggestions = buildScriptureSuggestions(flags);
    const alignmentScore = computeAlignmentScore(status, confidence);
    const checkId = `chk_${Date.now()}_${hashContent(text).slice(0, 8)}`;

    return {
        checkId, status, alignmentScore, confidence,
        suggestedAction, userVisibleSummary, flags, scriptureSuggestions,
        rewriteSuggestion: null,
        modelMetadata: { pipeline: "rules_v1", version: "1.0.0" },
    };
}
