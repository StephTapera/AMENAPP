import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import type {
    AmbientBereanSuggestion,
    AmbientContext,
    AmbientMode,
    NoteRef,
    ThreadRef,
} from "./types";
import { enforceAmbientContextRateLimit, requireAmbientOSEnabled } from "./guards";

const validModes = new Set<AmbientMode>(["default", "driving", "atChurch"]);
const serverReadableTiers = new Set(["S", "C"]);

interface ContextFacetValue {
    kind?: string;
    payload?: unknown;
}

interface ContextFacetDoc {
    category?: string;
    key?: string;
    label?: string;
    value?: ContextFacetValue;
    tier?: string;
    createdAt?: unknown;
    updatedAt?: unknown;
}

export const getAmbientContext = onCall(
    { enforceAppCheck: true, maxInstances: 50, timeoutSeconds: 15 },
    async (req): Promise<AmbientContext> => {
        if (!req.auth) {
            throw new HttpsError("unauthenticated", "Sign in required.");
        }

        const uid = req.auth.uid;
        await requireAmbientOSEnabled();
        await enforceAmbientContextRateLimit(uid);

        const requestedMode = req.data?.mode as AmbientMode | undefined;
        const mode: AmbientMode = requestedMode && validModes.has(requestedMode) ? requestedMode : "default";
        const now = new Date();
        const facets = await loadApprovedContextFacets(uid);
        const displayName = typeof req.auth.token.name === "string" ? req.auth.token.name : "";
        const firstName = displayName.trim().split(/\s+/)[0] || "Friend";
        const tz = typeof req.data?.tz === "string" && req.data.tz.trim().length > 0 ? req.data.tz : "UTC";

        const noteFacets = facets
            .filter((facet) => ["current_focus", "goals", "learning", "work"].includes(facet.data.category ?? ""))
            .slice(0, 3);

        const communicationFacets = facets
            .filter((facet) => facet.data.category === "communication")
            .slice(0, 3);

        const unfinished: NoteRef[] = noteFacets.map((facet) => ({
            id: facet.id,
            title: facetTitle(facet.data),
            deepLink: facetDeepLink(facet.id),
            editedAt: isoValue(facet.data.updatedAt ?? facet.data.createdAt),
        }));

        const needingFollowUp: ThreadRef[] = communicationFacets.map((facet) => ({
            id: facet.id,
            title: facetTitle(facet.data),
            deepLink: facetDeepLink(facet.id),
            lastMessageAt: isoValue(facet.data.updatedAt ?? facet.data.createdAt),
        }));

        const suggestionFacet = facets.find((facet) => facet.data.category === "faith_journey")
            ?? noteFacets[0]
            ?? facets.find((facet) => facet.data.category === "communities");
        const bereanSuggestion = makeBereanSuggestion(suggestionFacet);

        return {
            generatedAt: now.toISOString(),
            user: { id: uid, firstName, localTime: now.toISOString(), tz },
            prayer: { awaitingResponse: [], openRequests: 0 },
            notes: { unfinished, lastEditedAt: unfinished[0]?.editedAt },
            messages: { needingFollowUp, unreadThreads: 0 },
            calendar: { today: [] },
            church: { upcomingEvents: [] },
            selah: { streakDays: 0 },
            arise: { upcomingBroadcasts: [] },
            bereanSuggestion,
            mode,
        };
    },
);

async function loadApprovedContextFacets(uid: string): Promise<Array<{ id: string; data: ContextFacetDoc }>> {
    const snap = await getFirestore()
        .collection("contextFacets")
        .doc(uid)
        .collection("facets")
        .where("tier", "in", ["S", "C"])
        .where("provenance.userApproved", "==", true)
        .limit(40)
        .get();

    return snap.docs
        .map((doc) => ({ id: doc.id, data: doc.data() as ContextFacetDoc }))
        .filter((facet) => serverReadableTiers.has(facet.data.tier ?? ""));
}

function makeBereanSuggestion(facet?: { id: string; data: ContextFacetDoc }): AmbientBereanSuggestion | undefined {
    if (!facet) {
        return undefined;
    }

    const label = facetTitle(facet.data);
    const kind: AmbientBereanSuggestion["kind"] = facet.data.category === "faith_journey" ? "study" : "reflect";

    return {
        kind,
        label: `Review ${label}`,
        deepLink: facetDeepLink(facet.id),
    };
}

function facetTitle(facet: ContextFacetDoc): string {
    const label = stringValue(facet.label, "");
    if (label) {
        return label;
    }

    const summary = facetSummary(facet.value);
    if (summary) {
        return summary;
    }

    return stringValue(facet.key, "Approved context");
}

function facetSummary(value: ContextFacetValue | undefined): string {
    const payload = value?.payload;
    if (typeof payload === "string") {
        return payload.trim();
    }

    if (Array.isArray(payload)) {
        return payload
            .filter((item): item is string => typeof item === "string" && item.trim().length > 0)
            .slice(0, 3)
            .join(", ");
    }

    if (payload && typeof payload === "object") {
        const record = payload as Record<string, unknown>;
        for (const key of ["title", "label", "name", "summary"]) {
            const value = record[key];
            if (typeof value === "string" && value.trim().length > 0) {
                return value.trim();
            }
        }
    }

    return "";
}

function facetDeepLink(id: string): string {
    return `amen://context/facets/${encodeURIComponent(id)}`;
}

function stringValue(value: unknown, fallback: string): string {
    return typeof value === "string" && value.trim().length > 0 ? value.trim() : fallback;
}

function isoValue(value: unknown): string {
    if (value instanceof Timestamp) {
        return value.toDate().toISOString();
    }

    if (typeof value === "object" && value && "toDate" in value && typeof value.toDate === "function") {
        return value.toDate().toISOString();
    }

    if (typeof value === "string") {
        return value;
    }

    return new Date().toISOString();
}
