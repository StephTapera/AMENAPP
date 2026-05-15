import type {ConfidenceEnvelope, ConfidenceLevel, GroundingSource} from "../models/churchTrust";

export class ChurchConfidenceEngine {
    levelForConfidence(confidence: number): ConfidenceLevel {
        if (confidence < 0.35) return "low";
        if (confidence < 0.7) return "medium";
        if (confidence < 0.9) return "high";
        return "verified";
    }

    buildEnvelope(confidence: number, sources: GroundingSource[], note?: string | null): ConfidenceEnvelope {
        return {
            confidence: this.clamp(confidence),
            confidenceLevel: this.levelForConfidence(confidence),
            sources,
            note: note ?? null,
            updatedAt: new Date() as never,
        };
    }

    scoreChurchProfile(input: {
        verificationStatus?: string | null;
        officialWebsiteVerified?: boolean;
        livestreamVerified?: boolean;
        ownershipClaimed?: boolean;
        approvedMediaCount?: number;
        serviceTimeCount?: number;
        hasAdminEdits?: boolean;
    }): number {
        let score = 0.2;
        if (input.ownershipClaimed) score += 0.15;
        if (input.officialWebsiteVerified) score += 0.2;
        if (input.livestreamVerified) score += 0.15;
        if ((input.approvedMediaCount ?? 0) > 0) score += Math.min(0.1, (input.approvedMediaCount ?? 0) * 0.02);
        if ((input.serviceTimeCount ?? 0) > 0) score += 0.1;
        if (input.hasAdminEdits) score += 0.1;
        if (input.verificationStatus === "verified") score += 0.2;
        return this.clamp(score);
    }

    private clamp(value: number) {
        return Math.max(0, Math.min(1, Number(value.toFixed(3))));
    }
}

export const churchConfidenceEngine = new ChurchConfidenceEngine();
