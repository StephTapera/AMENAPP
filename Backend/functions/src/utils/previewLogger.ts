import { logger } from "firebase-functions/v2";
import { hashNormalizedText } from "../moderation/previewModerationProvider";

export interface PreviewLogContext {
    postId?: string;
    previewId?: string;
    candidateType?: string;
    refreshReason?: string;
    score?: number;
    rankPosition?: number;
    moderationResult?: string;
    suppressionReason?: string;
    matchedRules?: string[];
    candidateCountIn?: number;
    candidateCountOut?: number;
    latencyMs?: number;
    viewerId?: string | null;
    sourceCommentIdsCount?: number;
    normalizedText?: string;
    error?: unknown;
}

function toSafePayload(ctx: PreviewLogContext): Record<string, unknown> {
    const payload: Record<string, unknown> = {
        postId: ctx.postId ?? null,
        previewId: ctx.previewId ?? null,
        candidateType: ctx.candidateType ?? null,
        refreshReason: ctx.refreshReason ?? null,
        score: ctx.score ?? null,
        rankPosition: ctx.rankPosition ?? null,
        moderationResult: ctx.moderationResult ?? null,
        suppressionReason: ctx.suppressionReason ?? null,
        matchedRules: ctx.matchedRules ?? [],
        candidateCountIn: ctx.candidateCountIn ?? null,
        candidateCountOut: ctx.candidateCountOut ?? null,
        latencyMs: ctx.latencyMs ?? null,
        viewerId: ctx.viewerId ?? null,
        sourceCommentIdsCount: ctx.sourceCommentIdsCount ?? null,
    };
    if (ctx.normalizedText) {
        payload.normalizedTextHash = hashNormalizedText(ctx.normalizedText);
        payload.redactedSnippet = `${ctx.normalizedText.slice(0, 20)}...`;
    }
    if (ctx.error) payload.error = String(ctx.error);
    return payload;
}

export function logPreviewEvent(eventName: string, ctx: PreviewLogContext): void {
    logger.info(eventName, toSafePayload(ctx));
}

export function logPreviewError(eventName: string, ctx: PreviewLogContext): void {
    logger.error(eventName, toSafePayload(ctx));
}
