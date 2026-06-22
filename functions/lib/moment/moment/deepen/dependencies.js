"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createMomentDeepenDependencies = createMomentDeepenDependencies;
const firestore_1 = require("firebase-admin/firestore");
const firestore = (0, firestore_1.getFirestore)();
function createMomentDeepenDependencies() {
    return {
        berean: {
            run: runBereanDeepen,
        },
        constitutionalIntelligence: {
            review: reviewConstitutionalIntelligence,
        },
        guardianAegis: {
            review: reviewGuardianAegis,
        },
        livingMemory: {
            crossReference: crossReferenceLivingMemory,
        },
        save: {
            save: saveMomentOutput,
        },
        now: () => Date.now(),
    };
}
async function runBereanDeepen(input) {
    const moment = input.request.moment;
    const memoryLines = input.livingMemory
        .slice(0, 5)
        .map((hit) => `- ${hit.citation ? `${hit.citation}: ` : ""}${hit.text}`)
        .join("\n");
    const contextLine = `${moment.type} moment ${moment.id} (${moment.temporalState})`;
    switch (input.request.action) {
        case "summarize":
            return {
                output: `Summary for ${contextLine}:\n${formationSummary(moment.refId)}\n\nFormation prompt: What invitation toward prayer, repentance, wisdom, or love is present here?`,
                citations: citationList(input.livingMemory, moment.refId),
            };
        case "crossReference":
            return {
                output: memoryLines.length > 0
                    ? `Living Memory cross-references:\n${memoryLines}\n\nDiscernment: compare these references by fruit, context, and pastoral care before applying them.`
                    : `No Living Memory cross-references were found for ${contextLine}. Save teachings, notes, or journal entries first to deepen future matches.`,
                citations: citationList(input.livingMemory, moment.refId),
            };
        case "generatePrayer":
            return {
                output: `Lord, meet me in this ${moment.type}. Help me receive what is true, release what is hurried, and respond with faithfulness. Form this moment into prayer, love, and obedience. Amen.`,
                citations: citationList(input.livingMemory, moment.refId),
            };
        case "generateStudyGuide":
            return {
                output: [
                    `Study guide for ${contextLine}:`,
                    "1. Observe: What is actually said or shown?",
                    "2. Interpret: What does this reveal about God, neighbor, self, or mission?",
                    "3. Discern: What needs Scripture, counsel, or patience before acting?",
                    "4. Practice: Name one faithful next step that is small enough to do today.",
                ].join("\n"),
                citations: citationList(input.livingMemory, moment.refId),
            };
        case "generateDiscussion":
            return {
                output: [
                    "Discussion prompts:",
                    "1. What part of this moment feels most important to slow down with?",
                    "2. Where do you notice hope, conviction, comfort, or confusion?",
                    "3. What would a loving response look like this week?",
                ].join("\n"),
                citations: citationList(input.livingMemory, moment.refId),
            };
        case "generateDevotional":
            return {
                output: [
                    "Devotional reflection:",
                    `Receive this ${moment.type} without rushing to perform. Ask what God is forming, not just what the moment is producing.`,
                    "Practice: breathe, name one grace, name one next act of love, then close in prayer.",
                ].join("\n\n"),
                citations: citationList(input.livingMemory, moment.refId),
            };
        case "saveTo":
            return {
                output: `Saved this ${moment.type} moment for later formation and review.`,
                citations: citationList(input.livingMemory, moment.refId),
            };
    }
}
async function reviewConstitutionalIntelligence(input) {
    const output = input.draft.output.trim();
    const citations = Array.from(new Set(input.draft.citations.filter(Boolean)));
    return {
        output,
        citations,
        notes: [
            "Deepen-first",
            "No urgency push",
            "No live-count theater",
            "No streak or reward mechanics",
        ],
        metadata: {
            selectedMode: input.route.selectedMode,
            requestedMode: input.route.requestedMode,
        },
    };
}
async function reviewGuardianAegis(input) {
    const text = input.constitutional.output.toLowerCase();
    const blockedTerms = [
        "kill yourself",
        "self harm instructions",
        "sexual content involving minors",
        "evade law enforcement",
    ];
    const blockedTerm = blockedTerms.find((term) => text.includes(term));
    if (blockedTerm) {
        return {
            passed: false,
            policyVersion: "moment-v1",
            reason: `guardianBlocked:${blockedTerm}`,
        };
    }
    return {
        passed: true,
        policyVersion: "moment-v1",
        reason: "guardianPassed",
    };
}
async function crossReferenceLivingMemory(query) {
    const snapshot = await firestore
        .collection("users")
        .doc(query.requesterId)
        .collection("momentSaves")
        .orderBy("createdAt", "desc")
        .limit(12)
        .get();
    const needle = `${query.moment.type} ${query.moment.refId}`.toLowerCase();
    return snapshot.docs
        .map((doc) => {
        const data = doc.data();
        const content = typeof data.content === "string" ? data.content : "";
        const citations = Array.isArray(data.citations) ? data.citations.filter((value) => typeof value === "string") : [];
        return {
            id: doc.id,
            text: content,
            citation: citations[0],
            score: scoreMemoryHit(needle, content),
            metadata: {
                target: data.target,
                deepenAction: data.deepenAction,
            },
        };
    })
        .filter((hit) => hit.text.length > 0)
        .sort((a, b) => (b.score ?? 0) - (a.score ?? 0))
        .slice(0, 5);
}
async function saveMomentOutput(input) {
    const target = input.request.saveTarget;
    if (!target) {
        return;
    }
    const saveId = `${input.request.moment.id}_${input.result.action}_${input.result.createdAt}`
        .replace(/[^A-Za-z0-9_-]/g, "_")
        .slice(0, 120);
    await firestore
        .collection("users")
        .doc(input.request.requesterId)
        .collection("momentSaves")
        .doc(saveId)
        .set({
        schemaVersion: 1,
        momentId: input.request.moment.id,
        ownerId: input.request.requesterId,
        target,
        deepenAction: input.result.action,
        content: input.result.output,
        citations: input.result.citations,
        guardian: input.result.guardian,
        createdAt: input.result.createdAt,
    });
}
function formationSummary(refId) {
    return `This Moment points back to ${refId}. The v1 server preserves the object boundary, prepares a formation-safe response, and avoids social urgency mechanics.`;
}
function citationList(memory, fallback) {
    const citations = memory
        .map((hit) => hit.citation)
        .filter((citation) => typeof citation === "string" && citation.length > 0);
    return citations.length > 0 ? citations : [fallback];
}
function scoreMemoryHit(needle, content) {
    const haystack = content.toLowerCase();
    return needle
        .split(/\s+/)
        .filter((token) => token.length > 2 && haystack.includes(token))
        .length;
}
