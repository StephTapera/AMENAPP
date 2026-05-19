import * as admin from "firebase-admin";
import {churchConfidenceEngine} from "./ChurchConfidenceEngine";
import type {GroundingSource} from "../models/churchTrust";

const db = admin.firestore();

type GroundedAnswerResult = {
    response: string;
    confidence: number;
    confidenceLevel: "low" | "medium" | "high" | "verified";
    sources: GroundingSource[];
    note: string;
    fallbackMessage?: string;
};

export class ChurchGroundingService {
    async answerChurchQuestion(churchId: string, question: string): Promise<GroundedAnswerResult> {
        const [churchDoc, summaryDoc, liveStateDoc] = await Promise.all([
            db.collection("churches").doc(churchId).get(),
            db.collection("churches").doc(churchId).collection("experience_summary").doc("current").get(),
            db.collection("churches").doc(churchId).collection("live_state").doc("current").get(),
        ]);

        const church = churchDoc.data() ?? {};
        const summary = summaryDoc.data() ?? {};
        const liveState = liveStateDoc.data() ?? {};
        const sources = this.collectSources(church, summary, liveState);
        const confidence = Math.min(0.95, Math.max(0.15, (church.profileConfidence as number | undefined) ?? 0.2));
        const note = confidence < 0.35
            ? "This has not yet been confirmed by the church."
            : "This appears based on public church metadata.";

        if (sources.length === 0) {
            return {
                response: "I do not have enough verified information yet.",
                confidence: 0.1,
                confidenceLevel: "low",
                sources: [],
                note,
                fallbackMessage: "This appears based on public church metadata.",
            };
        }

        return {
            response: this.composeAnswer(question, church, summary, liveState),
            confidence,
            confidenceLevel: churchConfidenceEngine.levelForConfidence(confidence),
            sources,
            note,
            fallbackMessage: confidence < 0.35 ? "This has not yet been confirmed by the church." : undefined,
        };
    }

    private composeAnswer(question: string, church: Record<string, unknown>, summary: Record<string, unknown>, liveState: Record<string, unknown>): string {
        const lower = question.toLowerCase();
        if (lower.includes("livestream")) {
            return typeof liveState.title === "string"
                ? `${liveState.title} ${typeof liveState.description === "string" ? liveState.description : ""}`.trim()
                : "I do not have enough verified information yet.";
        }

        const parts = [
            typeof church.name === "string" ? church.name : "This church",
            typeof summary.firstTimeFlow === "string" ? summary.firstTimeFlow : null,
            typeof summary.accessibility === "string" ? `Accessibility: ${summary.accessibility}` : null,
            typeof summary.parking === "string" ? `Parking: ${summary.parking}` : null,
        ].filter((value): value is string => Boolean(value && value.trim()));

        return parts.join(" ");
    }

    private collectSources(
        church: Record<string, unknown>,
        summary: Record<string, unknown>,
        liveState: Record<string, unknown>
    ): GroundingSource[] {
        const sources: GroundingSource[] = [];

        if (typeof church.name === "string") {
            sources.push({
                id: "church-profile",
                type: "verifiedMetadata",
                title: "Church profile",
                detail: "Canonical AMEN church metadata.",
                verified: church.verificationStatus === "verified",
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        }

        if (typeof church.website === "string" && church.website.length > 0) {
            sources.push({
                id: "official-website",
                type: "officialWebsite",
                title: "Official church website",
                url: church.website,
                verified: church.officialWebsiteVerified === true,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        }

        if (Object.keys(summary).length > 0) {
            sources.push({
                id: "experience-summary",
                type: "adminProvided",
                title: "Church experience summary",
                detail: "Admin-provided or approved summary fields.",
                verified: true,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        }

        if (Object.keys(liveState).length > 0) {
            sources.push({
                id: "live-state",
                type: "livestream",
                title: "Church live state",
                detail: "Current livestream state metadata.",
                verified: liveState.confidenceLevel === "verified",
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        }

        return sources;
    }
}

export const churchGroundingService = new ChurchGroundingService();
