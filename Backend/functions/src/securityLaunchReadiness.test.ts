import * as fs from "fs";
import * as path from "path";

const srcRoot = path.resolve(__dirname);
const projectRoot = path.resolve(srcRoot, "../../..");

function readProjectFile(relativePath: string): string {
    return fs.readFileSync(path.join(projectRoot, relativePath), "utf8");
}

describe("Amen launch safety gates", () => {
    it("creates the operational artifacts required for severe reports", () => {
        const source = readProjectFile("Backend/functions/src/submitReport.ts");
        for (const collection of ["moderationCases", "trustSafetyEvents", "evidenceVault", "ncmecReadiness"]) {
            expect(source).toContain(`collection("${collection}")`);
        }
        expect(source).toContain("requiresEvidencePreservation");
        expect(source).toContain("dualApprovalRequired");
        expect(source).toContain("breakGlassRequiredForPrivateContent");
        expect(source).toContain("needs_trained_reviewer_assessment");
        expect(source).toContain("automatedCyberTipSubmitted: false");
    });

    it("keeps posts with media private until the media moderation pipeline approves every item", () => {
        const source = readProjectFile("Backend/functions/src/mediaModerationPipeline.ts");
        expect(source).toContain("moderationBlocked: true");
        expect(source).toContain('mediaModerationStatus: "pending"');
        expect(source).toContain("applyPostMediaGate");
        expect(source).toContain("approvedForPublicServing");
        expect(source).toContain("moderationBlocked: !approvedForPublicServing");
    });

    it("keeps raw media quarantine and processed media server-owned in Storage rules", () => {
        const rules = readProjectFile("AMENAPP/storage.rules");
        expect(rules).toContain("match /mediaUploads/{userId}/{mediaId}/raw/{fileName}");
        expect(rules).toContain("request.auth.uid == userId");
        expect(rules).toContain("match /mediaProcessed/{mediaId}/{kind}/{fileName}");
        expect(rules).toContain("allow write: if false;");
        expect(rules).toContain("match /posts/images/{fileName}");
        expect(rules).toContain("DENY new writes");
    });

    it("has server-side classifiers for the highest-risk child and sexual safety categories", () => {
        const source = readProjectFile("Backend/functions/src/safetyOS.ts");
        for (const token of [
            "childSafety",
            "csam",
            "grooming",
            "sexTrafficking",
            "sextortion",
            "pornography",
            "nonConsensualIntimateImagery",
            "prostitutionFacilitation",
            "recipientIsMinor",
            "Potential grooming message to minor",
        ]) {
            expect(source).toContain(token);
        }
    });

    it("keeps legacy iOS report paths on callable-backed report submission", () => {
        const swiftSources = [
            "AMENAPP/BlockUserHelper.swift",
            "AMENAPP/AMENAPP/SelahMediaDetailView.swift",
            "AMENAPP/AMENAPP/Covenant/AmenReportContentSheet.swift",
            "AMENAPP/FirebaseMessagingService+RequestsAndBlocking.swift",
            "AMENAPP/ModerationService.swift",
            "AMENAPP/ModerationPipeline.swift",
        ].map(readProjectFile).join("\n");

        expect(swiftSources).toContain("submitTrustSafetyReport");
        expect(swiftSources).not.toContain('collection("reports").addDocument');
        expect(swiftSources).not.toContain('collection("reports").document');
        expect(swiftSources).not.toContain('collection("userReports").addDocument');
    });

    it("uses configured moderation providers instead of silent all-clear placeholders", () => {
        const source = readProjectFile("Backend/functions/src/mediaModerationPipeline.ts");
        expect(source).toContain("ImageAnnotatorClient");
        expect(source).toContain("safeSearchDetection");
        expect(source).toContain("TEXT_DETECTION");
        expect(source).toContain("CSAM_HASH_LOOKUP_URL");
        expect(source).toContain("REQUIRE_MEDIA_MODERATION_PROVIDERS");
        expect(source).toContain("throw new Error(\"CSAM hash lookup provider is not configured.\")");
        expect(source).toContain("PERSPECTIVE_API_KEY");
        expect(source).toContain("throw new Error(\"Text safety provider is not configured.\")");
    });

    it("has iOS client surfaces for reporting, blocking, minor safety, privacy, and deletion", () => {
        const requiredFiles = [
            "AMENAPP/SafetyReportingService.swift",
            "AMENAPP/AmenSafetyReportService.swift",
            "AMENAPP/BlockService.swift",
            "AMENAPP/MinorSafetyService.swift",
            "AMENAPP/PrivacyDashboardView.swift",
            "AMENAPP/DeleteAccountView.swift",
            "AMENAPP/BereanSafetyPolicy.swift",
            "AMENAPP/MediaSafetyGateway.swift",
            "AMENAPP/MessageSafetyGateway.swift",
        ];

        for (const relativePath of requiredFiles) {
            expect(fs.existsSync(path.join(projectRoot, relativePath))).toBe(true);
        }

        const safetyReporting = readProjectFile("AMENAPP/SafetyReportingService.swift");
        expect(safetyReporting).toContain('httpsCallable("submitReport")');
        expect(safetyReporting).toContain("blockImmediately");
    });
});
