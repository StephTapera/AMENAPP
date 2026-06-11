import Anthropic from "@anthropic-ai/sdk";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import type {
    ActionSource,
    ActionTier,
    AmbientContext,
    AmbientSummary,
    PriorityAction,
    SmartComposerIntent,
} from "./types";
import { enforceAmbientAIRateLimit, requireAmbientOSEnabled } from "./guards";

const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
const validTiers = new Set<ActionTier>(["high", "medium", "low"]);
const validSources = new Set<ActionSource>(["prayer", "note", "message", "church", "selah", "berean"]);
const validChips = new Set(["photo", "churchNote", "event", "prayerRequest", "sermon", "scripture"]);
const validPostTypes = new Set(["PrayerRequest", "Testimony", "ChurchNote"]);

export const summarizeAmbientContext = onCall(
    { enforceAppCheck: true, maxInstances: 20, timeoutSeconds: 30 },
    async (req): Promise<AmbientSummary> => {
        if (!req.auth) {
            throw new HttpsError("unauthenticated", "Sign in required.");
        }
        await requireAmbientOSEnabled();
        await enforceAmbientAIRateLimit(req.auth.uid);

        const context = req.data?.context as AmbientContext | undefined;
        if (!context) {
            throw new HttpsError("invalid-argument", "context required.");
        }

        if (!process.env.ANTHROPIC_API_KEY) {
            return deterministicSummary(context);
        }

        const response = await client.messages.create({
            model: "claude-opus-4-5",
            max_tokens: 1024,
            system: [
                "You are Berean, a faith-grounded pastoral assistant for AMEN.",
                "Return JSON only: {\"greetingProse\": string, \"actions\": PriorityAction[]}.",
                "Never reference public engagement metrics, follower numbers, or reaction counts.",
                "Never draft relational or spiritual actions on the user's behalf.",
                "Actions are review prompts only; use existing deep links from the AmbientContext.",
            ].join("\n"),
            messages: [{ role: "user", content: JSON.stringify(context) }],
        });

        const parsed = parseJsonObject(response.content[0]);
        return normalizeSummary(parsed, context);
    },
);

export const classifyComposerIntent = onCall(
    { enforceAppCheck: true, maxInstances: 30, timeoutSeconds: 10 },
    async (req): Promise<SmartComposerIntent> => {
        if (!req.auth) {
            throw new HttpsError("unauthenticated", "Sign in required.");
        }
        await requireAmbientOSEnabled();
        await enforceAmbientAIRateLimit(req.auth.uid);

        const text = String(req.data?.text ?? "").trim();
        if (!text) {
            return { chips: [] };
        }

        if (!process.env.ANTHROPIC_API_KEY) {
            return deterministicComposerIntent(text);
        }

        const response = await client.messages.create({
            model: "claude-haiku-4-5-20251001",
            max_tokens: 128,
            system: [
                "Classify AMEN composer text into attachment chips.",
                "Return JSON only: {\"chips\": string[], \"postType\"?: string}.",
                "chips: photo, churchNote, event, prayerRequest, sermon, scripture.",
                "postType: PrayerRequest, Testimony, ChurchNote.",
                "Advisory only. Do not generate message or post body.",
            ].join("\n"),
            messages: [{ role: "user", content: text }],
        });

        return normalizeComposerIntent(parseJsonObject(response.content[0]));
    },
);

function normalizeSummary(value: Record<string, unknown>, context: AmbientContext): AmbientSummary {
    const actions = Array.isArray(value.actions)
        ? value.actions.map((action, index) => normalizeAction(action, index)).filter((action): action is PriorityAction => action !== nil)
        : deterministicActions(context);

    return {
        greetingProse: typeof value.greetingProse === "string" && value.greetingProse.trim()
            ? value.greetingProse.trim()
            : deterministicSummary(context).greetingProse,
        actions,
    };
}

const nil = Symbol("nil");

function normalizeAction(value: unknown, index: number): PriorityAction | typeof nil {
    if (!value || typeof value !== "object") {
        return nil;
    }

    const record = value as Record<string, unknown>;
    const title = typeof record.title === "string" ? record.title.trim() : "";
    const deepLink = typeof record.deepLink === "string" ? record.deepLink : "";
    if (!title || !deepLink) {
        return nil;
    }

    const tier = validTiers.has(record.tier as ActionTier) ? record.tier as ActionTier : "medium";
    const source = validSources.has(record.source as ActionSource) ? record.source as ActionSource : "berean";

    return {
        id: typeof record.id === "string" && record.id.trim() ? record.id : `ambient-action-${index}`,
        tier,
        title,
        source,
        deepLink,
        scheduledAt: typeof record.scheduledAt === "string" ? record.scheduledAt : undefined,
    };
}

function deterministicSummary(context: AmbientContext): AmbientSummary {
    const segments: string[] = [];
    if (context.prayer.awaitingResponse.length > 0) {
        segments.push("prayer requests to tend");
    }
    if (context.notes.unfinished.length > 0) {
        segments.push("a note still open");
    }
    if (context.calendar.nextEvent) {
        segments.push(`${context.calendar.nextEvent.title} ahead`);
    }

    const focus = segments.length > 0 ? segments.join(", ") : "a quiet day to move with intention";
    return {
        greetingProse: `Good day, ${context.user.firstName}. You have ${focus}.`,
        actions: deterministicActions(context),
    };
}

function deterministicActions(context: AmbientContext): PriorityAction[] {
    const actions: PriorityAction[] = [];
    context.prayer.awaitingResponse.forEach((prayer, index) => {
        actions.push({
            id: `prayer-${prayer.id}`,
            tier: index === 0 ? "high" : "medium",
            title: `Review prayer request: ${prayer.title}`,
            source: "prayer",
            deepLink: prayer.deepLink,
        });
    });

    context.notes.unfinished.forEach((note) => {
        actions.push({
            id: `note-${note.id}`,
            tier: "medium",
            title: `Continue note: ${note.title}`,
            source: "note",
            deepLink: note.deepLink,
        });
    });

    context.messages.needingFollowUp.forEach((thread) => {
        actions.push({
            id: `message-${thread.id}`,
            tier: "medium",
            title: `Review conversation: ${thread.title}`,
            source: "message",
            deepLink: thread.deepLink,
        });
    });

    if (context.calendar.nextEvent) {
        actions.push({
            id: `event-${context.calendar.nextEvent.id}`,
            tier: "medium",
            title: context.calendar.nextEvent.title,
            source: "church",
            deepLink: context.calendar.nextEvent.deepLink,
            scheduledAt: context.calendar.nextEvent.startsAt,
        });
    }

    if (context.selah.resumeAt) {
        actions.push({
            id: `selah-${context.selah.resumeAt.book}-${context.selah.resumeAt.chapter}`,
            tier: "low",
            title: `Resume Selah: ${context.selah.resumeAt.book} ${context.selah.resumeAt.chapter}`,
            source: "selah",
            deepLink: context.selah.resumeAt.deepLink,
        });
    }

    if (actions.length === 0 && context.bereanSuggestion) {
        actions.push({
            id: "berean-suggestion",
            tier: "low",
            title: context.bereanSuggestion.label,
            source: "berean",
            deepLink: context.bereanSuggestion.deepLink,
        });
    }

    return actions;
}

function deterministicComposerIntent(text: string): SmartComposerIntent {
    const lower = text.toLowerCase();
    const chips = [
        lower.includes("photo") || lower.includes("picture") ? "photo" : undefined,
        lower.includes("sermon") ? "sermon" : undefined,
        lower.includes("scripture") || /\b(psalm|john|romans|genesis|matthew)\b/.test(lower) ? "scripture" : undefined,
        lower.includes("pray") || lower.includes("prayer") ? "prayerRequest" : undefined,
        lower.includes("event") || lower.includes("retreat") || lower.includes("meeting") ? "event" : undefined,
        lower.includes("note") ? "churchNote" : undefined,
    ].filter((chip): chip is SmartComposerIntent["chips"][number] => Boolean(chip));

    const postType = lower.includes("testimony")
        ? "Testimony"
        : lower.includes("pray") || lower.includes("prayer")
            ? "PrayerRequest"
            : lower.includes("sermon") || lower.includes("note")
                ? "ChurchNote"
                : undefined;

    return { chips, postType };
}

function normalizeComposerIntent(value: Record<string, unknown>): SmartComposerIntent {
    const chips = Array.isArray(value.chips)
        ? value.chips.filter((chip): chip is SmartComposerIntent["chips"][number] => typeof chip === "string" && validChips.has(chip))
        : [];
    const postType = typeof value.postType === "string" && validPostTypes.has(value.postType) ? value.postType as SmartComposerIntent["postType"] : undefined;
    return { chips, postType };
}

function parseJsonObject(content: unknown): Record<string, unknown> {
    const text = typeof content === "object" && content && "text" in content
        ? String((content as { text?: unknown }).text ?? "{}")
        : "{}";
    const clean = text.replace(/```json\n?/g, "").replace(/```\n?/g, "").trim();

    try {
        const parsed = JSON.parse(clean);
        return parsed && typeof parsed === "object" ? parsed : {};
    } catch {
        return {};
    }
}
