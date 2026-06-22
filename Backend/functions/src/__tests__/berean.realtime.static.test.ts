import * as fs from "fs";
import * as path from "path";

const CREATE_SESSION = path.resolve(__dirname, "../realtime/createRealtimeSession.ts");
const PERSIST_CHUNK = path.resolve(__dirname, "../berean/transcripts/persistRealtimeTranscriptChunk.ts");
const IOS_TRANSPORT = path.resolve(__dirname, "../../../../AMENAPP/AIIntelligence/BereanRealtimeWebSocketTransport.swift");

function read(file: string): string {
    return fs.readFileSync(file, "utf8");
}

describe("Berean realtime implementation invariants", () => {
    test("brokers a real OpenAI realtime client secret and never returns fake ephemeral ids", () => {
        const code = read(CREATE_SESSION);
        expect(code).toContain("https://api.openai.com/v1/realtime/client_secrets");
        expect(code).toContain("defineSecret(\"OPENAI_API_KEY\")");
        expect(code).toContain("openAISecret.value");
        expect(code).not.toContain("ephemeral_${sessionId}");
    });

    test("realtime session creation enforces App Check, feature flags, rate limits, and expiration", () => {
        const code = read(CREATE_SESSION);
        expect(code).toContain("enforceAppCheck: true");
        expect(code).toContain("requireAuthAndAppCheck");
        expect(code).toContain("enforceAmenGuards");
        expect(code).toContain("expiresAt");
        expect(code).toContain("participantIds");
    });

    test("stream chunks persist only through backend moderation and owner validation", () => {
        const code = read(PERSIST_CHUNK);
        expect(code).toContain("requireAuthAndAppCheck");
        expect(code).toContain("lightweightModeration");
        expect(code).toContain("assertSessionAccess");
        expect(code).toContain("realtimeModerationEvents");
        expect(code).toContain("translationChunks");
        expect(code).toContain("transcriptChunks");
    });

    test("iOS websocket fallback has retry, token refresh, and backpressure controls", () => {
        const code = read(IOS_TRANSPORT);
        expect(code).toContain("reconnecting(Int)");
        expect(code).toContain("refreshClientSecret");
        expect(code).toContain("maxBufferedAudioBytes");
        expect(code).toContain("backpressureLimitReached");
        expect(code).toContain("persistRealtimeTranscriptChunk");
    });
});
