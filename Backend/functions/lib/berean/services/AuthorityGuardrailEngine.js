"use strict";
/**
 * AuthorityGuardrailEngine.ts
 *
 * The Authority Alignment System: ensures Berean's responses stay under
 * Scripture and pastoral authority at all times.
 *
 * Responsibilities:
 *  1. Post-generation scan of AI responses for authority violations
 *  2. Leadership referral creation for escalated topics
 *  3. Response patching: inject humility markers when confidence is borderline
 *
 * Non-negotiable:
 *  - Never allow AI to claim divine authority
 *  - Crisis signals always escalate; never handle crisis in AI prose
 *  - Controversial doctrinal topics get a "please consult your pastor" footer
 *  - Referrals are stored but NEVER sent to leaders without explicit user consent
 */
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.auditResponse = auditResponse;
exports.createLeadershipReferral = createLeadershipReferral;
exports.buildEscalationContextSummary = buildEscalationContextSummary;
const admin = __importStar(require("firebase-admin"));
const uuid_1 = require("uuid");
// ---------------------------------------------------------------------------
// Authority patterns to detect in AI responses
// ---------------------------------------------------------------------------
// Phrases that suggest the AI is claiming divine authority
const DIVINE_AUTHORITY_PATTERNS = [
    /god is telling you/i,
    /god wants you to/i,
    /god is saying/i,
    /i am certain god/i,
    /god has revealed to me/i,
    /the holy spirit is telling/i,
    /this is god's will for you/i,
];
// Phrases that assert absolute doctrinal certainty where debate exists
const OVERCONFIDENT_DOCTRINE_PATTERNS = [
    /the bible clearly states.*you must/i,
    /all christians believe/i,
    /there is no debate/i,
    /god definitely/i,
];
/**
 * Audits a structured response before it is returned to the client.
 * May modify the answer text to add humility markers.
 */
function auditResponse(response, classification) {
    const flags = new Set(response.sensitivityFlags);
    let answer = response.answer;
    let patchedAnswer;
    // 1. Crisis override — short-circuit everything else
    if (classification?.primaryState === "crisis" || flags.has("crisis_escalation")) {
        flags.add("crisis_escalation");
        return {
            passesAudit: true, // Pass audit, but flag for UI to show crisis card
            detectedFlags: [...flags],
            leadershipPromptRequired: true,
        };
    }
    // 2. Divine authority detection
    const hasDivineAuthorityClaim = DIVINE_AUTHORITY_PATTERNS.some((p) => p.test(answer));
    if (hasDivineAuthorityClaim) {
        flags.add("divine_authority_assertion");
        // Patch the answer: prepend a humility disclaimer
        answer = `[Note: I want to be careful here — I can't speak on God's behalf or claim to know His specific will for your situation. What I can do is point you to what Scripture says.]\n\n${answer}`;
        patchedAnswer = answer;
    }
    // 3. Overconfident doctrinal patterns
    const hasOverconfidentDoctrine = OVERCONFIDENT_DOCTRINE_PATTERNS.some((p) => p.test(answer));
    if (hasOverconfidentDoctrine) {
        flags.add("controversial_doctrine");
    }
    // 4. Doctrinal confidence gate: if confidence < 0.6 and no disclaimer present
    if (response.doctrinalConfidence < 0.6 &&
        !answer.toLowerCase().includes("i could be wrong") &&
        !answer.toLowerCase().includes("please bring this to your pastor")) {
        const disclaimer = `\n\n*I hold this view humbly — faithful Christians disagree on some of these points. Please bring significant doctrinal questions to your pastor or a trusted spiritual mentor.*`;
        answer += disclaimer;
        patchedAnswer = answer;
    }
    // 5. Controversial doctrine flag → always show leadership prompt
    const leadershipPromptRequired = flags.has("pastoral_escalation") ||
        flags.has("controversial_doctrine") ||
        flags.has("scrupulosity_risk") ||
        response.leadershipPromptShown;
    return {
        passesAudit: !flags.has("divine_authority_assertion") || !!patchedAnswer,
        detectedFlags: [...flags],
        patchedAnswer: patchedAnswer !== answer ? patchedAnswer : undefined,
        leadershipPromptRequired,
    };
}
// ---------------------------------------------------------------------------
// Leadership Referral Creation
// ---------------------------------------------------------------------------
/**
 * Creates a leadership referral record when escalation is needed.
 * IMPORTANT: This only writes to Firestore; it does NOT notify any leader.
 * Leaders are only notified when the user explicitly shares the referral.
 */
async function createLeadershipReferral(userId, triggerFlag, contextSummary, suggestedNextStep) {
    const db = admin.firestore();
    const referralId = (0, uuid_1.v4)();
    const referral = {
        id: referralId,
        userId,
        leaderUserId: undefined, // Not targeted until user selects a leader
        triggerFlag,
        contextSummary,
        suggestedNextStep,
        status: "pending",
        createdAt: admin.firestore.Timestamp.now(),
        acknowledgedAt: undefined,
        resolvedAt: undefined,
    };
    await db
        .collection("leadership_referrals")
        .doc(referralId)
        .set(referral);
    return referralId;
}
// ---------------------------------------------------------------------------
// Escalation context builder
// ---------------------------------------------------------------------------
/**
 * Builds a privacy-respecting context summary for a leadership referral.
 * Never includes raw message text — only topic/theme level description.
 */
function buildEscalationContextSummary(primaryTopic, sensitivityFlag) {
    const descriptions = {
        crisis_escalation: `A member may be experiencing a crisis moment. Their conversation touched on themes of distress or hopelessness.`,
        pastoral_escalation: `A member had a question about "${primaryTopic}" that is beyond the scope of AI and would benefit from your pastoral wisdom.`,
        scrupulosity_risk: `A member may be experiencing spiritual anxiety around "${primaryTopic}". Gentle pastoral care is recommended.`,
        controversial_doctrine: `A member asked about a theologically contested topic: "${primaryTopic}". Your guidance would be valuable.`,
        divine_authority_assertion: `A study session touched on discernment of God's will regarding "${primaryTopic}".`,
        scripture_contradiction: `A study session raised a tension in scriptural interpretation around "${primaryTopic}".`,
        minor_user: `A younger member had questions about "${primaryTopic}" that merit age-appropriate pastoral guidance.`,
    };
    return descriptions[sensitivityFlag] ?? `A pastoral follow-up is recommended for "${primaryTopic}".`;
}
//# sourceMappingURL=AuthorityGuardrailEngine.js.map