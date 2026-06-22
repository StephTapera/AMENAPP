import * as admin from "firebase-admin";
import type {ChurchModerationState, GroundingSource, ModerationQueueRecord} from "../models/churchTrust";
import {churchConfidenceEngine} from "./ChurchConfidenceEngine";

type ModerationInput = {
    labels?: string[];
    ocrText?: string;
    captionText?: string;
    uploadVelocity?: number;
    impersonationSignal?: number;
};

export class ChurchModerationEngine {
    evaluate(input: ModerationInput): Pick<ModerationQueueRecord, "moderationState" | "moderationReasons" | "aiScores" | "escalated"> {
        const labelText = (input.labels ?? []).join(" ").toLowerCase();
        const bodyText = `${input.ocrText ?? ""} ${input.captionText ?? ""}`.toLowerCase();

        const nudity = this.keywordScore(labelText, ["nudity", "sexual", "explicit"], 0.92);
        const hate = this.keywordScore(bodyText, ["hate", "extremist", "supremacy"], 0.96);
        const misleading = this.keywordScore(bodyText, ["official stream", "verified", "pastor"], 0.45);
        const spam = Math.min(1, (input.uploadVelocity ?? 0) / 10);
        const impersonation = Math.max(0, Math.min(1, input.impersonationSignal ?? 0));

        const reasons: string[] = [];
        let moderationState: ChurchModerationState = "approved";
        let escalated = false;

        if (nudity >= 0.9) reasons.push("explicit_content");
        if (hate >= 0.85) reasons.push("hate_or_extremism");
        if (impersonation >= 0.75) reasons.push("impersonation_risk");
        if (misleading >= 0.8) reasons.push("misleading_imagery");
        if (spam >= 0.8) reasons.push("spam_upload_pattern");

        if (nudity >= 0.9 || hate >= 0.85) {
            moderationState = "blocked";
        } else if (reasons.length > 0) {
            moderationState = "needsReview";
            escalated = true;
        }

        return {
            moderationState,
            moderationReasons: reasons,
            aiScores: {
                nudity,
                hate,
                misleading,
                spam,
                impersonation,
                confidence: churchConfidenceEngine.scoreChurchProfile({
                    approvedMediaCount: moderationState === "approved" ? 1 : 0,
                }),
            },
            escalated,
        };
    }

    buildGroundingSource(itemId: string, state: ChurchModerationState): GroundingSource {
        return {
            id: `moderation:${itemId}`,
            type: "approvedMedia",
            title: "Approved church media",
            detail: `Moderation state: ${state}`,
            verified: state === "approved",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };
    }

    private keywordScore(text: string, matches: string[], weight: number): number {
        return matches.some((match) => text.includes(match)) ? weight : 0;
    }
}

export const churchModerationEngine = new ChurchModerationEngine();
