import { onDocumentCreated, onDocumentWritten } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions/v2";
import * as admin from "firebase-admin";

const db = admin.firestore();

type PolicyLevel = "allow" | "nudge" | "requireReview" | "restrict" | "crisisEscalation";

interface FabricSnapshot {
    uid?: string;
    contentId?: string;
    contentType?: string;
    surface?: string;
    safetyTreatment?: string;
    trustSignals?: string[];
    humanStates?: string[];
    spiritualIntents?: string[];
    shouldReduceAmplification?: boolean;
    metadata?: Record<string, string>;
}

function arrayField(value: unknown): string[] {
    return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

function normalizeSnapshot(data: admin.firestore.DocumentData): FabricSnapshot {
    return {
        uid: typeof data.uid === "string" ? data.uid : undefined,
        contentId: typeof data.contentId === "string" ? data.contentId : undefined,
        contentType: typeof data.contentType === "string" ? data.contentType : undefined,
        surface: typeof data.surface === "string" ? data.surface : undefined,
        safetyTreatment: typeof data.safetyTreatment === "string" ? data.safetyTreatment : "normal",
        trustSignals: arrayField(data.trustSignals),
        humanStates: arrayField(data.humanStates),
        spiritualIntents: arrayField(data.spiritualIntents),
        shouldReduceAmplification: data.shouldReduceAmplification === true,
        metadata: typeof data.metadata === "object" && data.metadata !== null ? data.metadata : {},
    };
}

function computePolicy(snapshot: FabricSnapshot): PolicyLevel {
    const trustSignals = new Set(snapshot.trustSignals ?? []);
    const intents = new Set(snapshot.spiritualIntents ?? []);
    const safety = snapshot.safetyTreatment ?? "normal";

    if (safety === "crisis") return "crisisEscalation";
    if (safety === "restricted") return "restrict";
    if (safety === "highConcern" || trustSignals.has("needsVerification") || intents.has("give")) {
        return "requireReview";
    }
    if (safety === "supportiveReplies" || snapshot.surface === "directMessage") return "nudge";
    return "allow";
}

function computeTrustScore(snapshot: FabricSnapshot): number {
    const trustSignals = new Set(snapshot.trustSignals ?? []);
    let score = 50;
    if (trustSignals.has("knownChurch")) score += 15;
    if (trustSignals.has("verifiedMinistry")) score += 25;
    if (trustSignals.has("communityOverlap")) score += 10;
    if (trustSignals.has("longTermMember")) score += 10;
    if (trustSignals.has("aiDisclosed")) score += 5;
    if (trustSignals.has("needsVerification")) score -= 35;
    return Math.max(0, Math.min(score, 100));
}

function reputationDimensions(snapshot: FabricSnapshot): string[] {
    const states = new Set(snapshot.humanStates ?? []);
    const intents = new Set(snapshot.spiritualIntents ?? []);
    const trustSignals = new Set(snapshot.trustSignals ?? []);
    const dimensions = new Set<string>();

    if (states.has("celebration")) dimensions.add("encourager");
    if (intents.has("learn")) dimensions.add("teacher");
    if (intents.has("serve")) dimensions.add("volunteer");
    if (intents.has("pray") || states.has("prayerSeeking")) dimensions.add("prayerPartner");
    if (intents.has("give") && !trustSignals.has("needsVerification")) dimensions.add("giver");
    if (trustSignals.has("verifiedMinistry")) dimensions.add("verifiedLeader");

    return [...dimensions];
}

async function writeModerationQueue(snapshotId: string, snapshot: FabricSnapshot, policyLevel: PolicyLevel): Promise<void> {
    if (policyLevel === "allow" || policyLevel === "nudge") return;

    const queueId = `fabric_${snapshotId}`;
    await db.collection("moderationQueue").doc(queueId).set({
        source: "amenIntelligenceFabric",
        snapshotId,
        uid: snapshot.uid ?? "anonymous",
        contentId: snapshot.contentId ?? "",
        contentType: snapshot.contentType ?? "",
        surface: snapshot.surface ?? "",
        policyLevel,
        safetyTreatment: snapshot.safetyTreatment ?? "normal",
        trustSignals: snapshot.trustSignals ?? [],
        humanStates: snapshot.humanStates ?? [],
        spiritualIntents: snapshot.spiritualIntents ?? [],
        status: "pending",
        priority: policyLevel === "crisisEscalation" ? 1 : policyLevel === "restrict" ? 2 : 3,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
}

async function writeSafetyMode(snapshotId: string, snapshot: FabricSnapshot, policyLevel: PolicyLevel): Promise<void> {
    if (policyLevel !== "crisisEscalation" || !snapshot.uid) return;

    await db.collection("amenSafetyModeStates").doc(snapshot.uid).set({
        uid: snapshot.uid,
        source: "amenIntelligenceFabric",
        snapshotId,
        sourceContentId: snapshot.contentId ?? "",
        sourceContentType: snapshot.contentType ?? "",
        pauseNotifications: true,
        disableStrangerDMs: true,
        notifyModeration: true,
        trustedCircleEligible: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
}

export const processAmenIntelligenceSnapshot = onDocumentWritten(
    "amenIntelligenceSnapshots/{snapshotId}",
    async (event) => {
        const after = event.data?.after;
        if (!after?.exists) return;

        const snapshotId = event.params.snapshotId;
        const snapshot = normalizeSnapshot(after.data() ?? {});
        const policyLevel = computePolicy(snapshot);
        const trustScore = computeTrustScore(snapshot);
        const dimensions = reputationDimensions(snapshot);

        await db.collection("amenIntelligenceDecisions").doc(snapshotId).set({
            snapshotId,
            uid: snapshot.uid ?? "anonymous",
            contentId: snapshot.contentId ?? "",
            contentType: snapshot.contentType ?? "",
            surface: snapshot.surface ?? "",
            policyLevel,
            trustScore,
            relationshipRisk: snapshot.surface === "directMessage" || snapshot.surface === "group",
            nonprofitVerificationRequired: (snapshot.trustSignals ?? []).includes("needsVerification"),
            reputationDimensions: dimensions,
            shouldReduceAmplification: snapshot.shouldReduceAmplification === true || policyLevel === "crisisEscalation",
            requiresHumanReview: policyLevel === "requireReview" || policyLevel === "restrict" || policyLevel === "crisisEscalation",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        await writeModerationQueue(snapshotId, snapshot, policyLevel);
        await writeSafetyMode(snapshotId, snapshot, policyLevel);
        logger.info(`[AmenFabric] processed snapshot ${snapshotId} with policy ${policyLevel}`);
    }
);

export const processAmenIntelligenceAuditEvent = onDocumentCreated(
    "amenIntelligenceAuditEvents/{eventId}",
    async (event) => {
        const data = event.data?.data();
        if (!data) return;

        const policyLevel = typeof data.policyLevel === "string" ? data.policyLevel as PolicyLevel : "allow";
        if (policyLevel === "allow" || policyLevel === "nudge") return;

        await db.collection("moderationQueue").doc(`fabric_audit_${event.params.eventId}`).set({
            source: "amenIntelligenceAuditEvent",
            eventId: event.params.eventId,
            uid: typeof data.uid === "string" ? data.uid : "anonymous",
            contentId: typeof data.contentId === "string" ? data.contentId : "",
            contentType: typeof data.contentType === "string" ? data.contentType : "",
            surface: typeof data.surface === "string" ? data.surface : "",
            policyLevel,
            safetyTreatment: typeof data.safetyTreatment === "string" ? data.safetyTreatment : "normal",
            status: "pending",
            priority: policyLevel === "crisisEscalation" ? 1 : policyLevel === "restrict" ? 2 : 3,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
    }
);
