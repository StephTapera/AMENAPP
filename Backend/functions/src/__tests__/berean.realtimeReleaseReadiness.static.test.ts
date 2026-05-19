import * as fs from "fs";
import * as path from "path";

const repoRoot = path.resolve(__dirname, "../../../..");

function readRepoFile(relativePath: string): string {
    return fs.readFileSync(path.join(repoRoot, relativePath), "utf8");
}

function expectSourceContains(relativePath: string, patterns: RegExp[]): void {
    const source = readRepoFile(relativePath);
    for (const pattern of patterns) {
        expect(source).toMatch(pattern);
    }
}

function parseJson(relativePath: string): any {
    return JSON.parse(readRepoFile(relativePath));
}

function hasIndex(indexes: any[], collectionGroup: string, fieldPaths: string[]): boolean {
    return indexes.some((index) => {
        if (index.collectionGroup !== collectionGroup) return false;
        const actual = (index.fields ?? []).map((field: any) => field.fieldPath);
        return fieldPaths.every((fieldPath) => actual.includes(fieldPath));
    });
}

describe("Berean realtime release readiness", () => {
    test("Firebase deploy config targets the hardened rules and indexes files", () => {
        const firebase = parseJson("firebase.json");
        expect(firebase.firestore.rules).toBe("AMENAPP/firestore.deploy.rules");
        expect(firebase.firestore.indexes).toBe("firestore.indexes.json");
        expect(firebase.functions).toEqual(
            expect.arrayContaining([
                expect.objectContaining({
                    codebase: "creator",
                    source: "Backend/functions",
                }),
            ]),
        );
    });

    test("OpenAI realtime and translation functions require server secret brokering and App Check", () => {
        expectSourceContains("Backend/functions/src/realtime/createRealtimeSession.ts", [
            /defineSecret\("OPENAI_API_KEY"\)/,
            /secrets:\s*\[\s*openaiApiKey\s*\]/,
            /enforceAppCheck:\s*true/,
            /\/v1\/realtime\/client_secrets/,
            /requireAuthAndAppCheck/,
            /enforceAmenGuards/,
        ]);

        expectSourceContains("Backend/functions/src/berean/translation/translateMultilingualContent.ts", [
            /defineSecret\("OPENAI_API_KEY"\)/,
            /secrets:\s*\[\s*openaiApiKey\s*\]/,
            /enforceAppCheck:\s*true/,
            /scripture/i,
            /confidence/i,
        ]);
    });

    test("stream persistence is backend-only, owner-validated, moderated, and chunked", () => {
        expectSourceContains("Backend/functions/src/berean/transcripts/persistRealtimeTranscriptChunk.ts", [
            /enforceAppCheck:\s*true/,
            /requireAuthAndAppCheck/,
            /ownerId/,
            /participantIds/,
            /lightweightModeration/,
            /realtimeModerationEvents/,
            /transcriptChunks/,
            /captionChunks/,
            /translationChunks/,
            /streamHealth/,
        ]);
    });

    test("Firestore rules cover every Berean realtime collection and prevent client writes to generated streams", () => {
        const rules = readRepoFile("AMENAPP/firestore 18.rules");
        const requiredCollections = [
            "realtimeSessions",
            "translatedStreams",
            "liveCaptions",
            "sermonSummaries",
            "translationPreferences",
            "multilingualContent",
            "scriptureReferences",
            "livePrayerSessions",
            "voiceInteractions",
            "realtimeModerationEvents",
        ];

        for (const collection of requiredCollections) {
            expect(rules).toContain(`match /${collection}/`);
        }

        expect(rules).toMatch(/match \/translationChunks\/\{chunkId\}[\s\S]*allow create: if false;/);
        expect(rules).toMatch(/match \/realtimeModerationEvents\/\{eventId\}[\s\S]*allow read: if isAdmin\(\);[\s\S]*allow write: if false;/);
    });

    test("deployed Firestore indexes include realtime session, caption, transcript, and moderation query paths", () => {
        const indexes = parseJson("firestore.indexes.json").indexes;
        expect(hasIndex(indexes, "realtimeSessions", ["ownerId", "status", "updatedAt"])).toBe(true);
        expect(hasIndex(indexes, "realtimeSessions", ["participantIds", "status", "updatedAt"])).toBe(true);
        expect(hasIndex(indexes, "translationChunks", ["targetLanguage", "createdAt"])).toBe(true);
        expect(hasIndex(indexes, "captionChunks", ["language", "createdAt"])).toBe(true);
        expect(hasIndex(indexes, "transcriptChunks", ["language", "createdAt"])).toBe(true);
        expect(hasIndex(indexes, "liveCaptions", ["sessionId", "targetLanguage", "createdAt"])).toBe(true);
        expect(hasIndex(indexes, "multilingualContent", ["sourceId", "targetLanguage", "updatedAt"])).toBe(true);
        expect(hasIndex(indexes, "realtimeModerationEvents", ["sessionId", "severity", "createdAt"])).toBe(true);
    });

    test("iOS realtime transport is explicit about WebSocket fallback and does not pretend WebRTC exists", () => {
        expectSourceContains("AMENAPP/AIIntelligence/BereanRealtimeTransportCoordinator.swift", [
            /supportsNativeWebRTC:\s*false/,
            /supportsWebSocketFallback:\s*true/,
            /webSocketFallback/,
        ]);

        expectSourceContains("AMENAPP/AIIntelligence/BereanRealtimeWebSocketTransport.swift", [
            /wss:\/\/api\.openai\.com\/v1\/realtime/,
            /Authorization/,
            /OpenAI-Beta/,
            /backpressureLimitReached/,
            /persistRealtimeTranscriptChunk/,
        ]);
    });

    test("10/10 scripts can use the repo-pinned Firebase CLI instead of requiring a global install", () => {
        expectSourceContains("scripts/verify_berean_realtime_10_go.sh", [
            /Backend\/rules-tests\/node_modules\/\.bin\/firebase/,
            /FIREBASE_CMD=\(/,
            /--non-interactive/,
            /functions:secrets:access OPENAI_API_KEY/,
            /--dry-run/,
        ]);

        expectSourceContains("scripts/configure_berean_realtime_secrets.sh", [
            /Backend\/rules-tests\/node_modules\/\.bin\/firebase/,
            /FIREBASE_CMD=\(/,
            /functions:secrets:set OPENAI_API_KEY/,
            /functions:secrets:access OPENAI_API_KEY/,
        ]);
    });

    test("production Firebase deploy is blocked by the Berean realtime strict gate", () => {
        expectSourceContains("scripts/deploy_production_firebase.sh", [
            /verify_berean_realtime_10_go\.sh/,
            /REQUIRE_FIREBASE_LIVE=1/,
            /REQUIRE_DEVICE_SMOKE_ACK=1/,
            /REQUIRE_DEPLOY_DRY_RUN=0/,
            /Backend\/rules-tests\/node_modules\/\.bin\/firebase/,
            /--non-interactive/,
        ]);
    });
});
