import * as admin from "firebase-admin";
import type {GroundingSource, LivestreamRecord} from "../models/churchTrust";
import {churchConfidenceEngine} from "./ChurchConfidenceEngine";

type LivestreamProbe = {
    provider: LivestreamRecord["provider"];
    title: string;
    streamUrl: string;
    thumbnailUrl?: string | null;
    scheduledAt?: Date | null;
    startedAt?: Date | null;
    viewerSignal?: number | null;
    providerConfirmedLive?: boolean;
    websiteConfirmed?: boolean;
};

export class ChurchLivestreamIngestionService {
    buildRecord(probe: LivestreamProbe): LivestreamRecord {
        const confidence = this.computeConfidence(probe);
        const sources = this.buildSources(probe, confidence);

        return {
            provider: probe.provider,
            title: probe.title,
            thumbnailUrl: probe.thumbnailUrl ?? null,
            streamUrl: probe.streamUrl,
            liveNow: confidence >= 0.75 && probe.providerConfirmedLive === true,
            startedAt: probe.startedAt ? admin.firestore.Timestamp.fromDate(probe.startedAt) : null,
            scheduledAt: probe.scheduledAt ? admin.firestore.Timestamp.fromDate(probe.scheduledAt) : null,
            viewerSignal: probe.viewerSignal ?? null,
            ingestConfidence: confidence,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            sources,
        };
    }

    private computeConfidence(probe: LivestreamProbe): number {
        let confidence = 0.2;
        if (probe.providerConfirmedLive) confidence += 0.45;
        if (probe.websiteConfirmed) confidence += 0.2;
        if (probe.startedAt) confidence += 0.1;
        if ((probe.viewerSignal ?? 0) > 0) confidence += 0.1;
        return Math.max(0.1, Math.min(0.98, Number(confidence.toFixed(3))));
    }

    private buildSources(probe: LivestreamProbe, confidence: number): GroundingSource[] {
        const sources: GroundingSource[] = [
            {
                id: `provider:${probe.provider}`,
                type: "livestream",
                title: `${probe.provider} provider signal`,
                detail: probe.providerConfirmedLive ? "Provider API indicates live state." : "Provider metadata only.",
                url: probe.streamUrl,
                verified: probe.providerConfirmedLive === true,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
        ];

        if (probe.websiteConfirmed) {
            sources.push({
                id: "official-site",
                type: "officialWebsite",
                title: "Official church website",
                detail: "Stream link matched from official church web metadata.",
                url: probe.streamUrl,
                verified: true,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        }

        const envelope = churchConfidenceEngine.buildEnvelope(confidence, sources, confidence < 0.75 ? "Live state not fully confirmed yet." : null);
        return envelope.sources;
    }
}

export const churchLivestreamIngestionService = new ChurchLivestreamIngestionService();
