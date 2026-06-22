import {readFileSync} from "fs";
import {join} from "path";

const controllerSource = readFileSync(join(__dirname, "churchTrustCallables.ts"), "utf8");
const indexSource = readFileSync(join(__dirname, "..", "..", "index.ts"), "utf8");

describe("church trust callable deployment surface", () => {
    it("does not deploy unavailable or placeholder trust callables", () => {
        expect(controllerSource).not.toContain("unavailableCallable");
        expect(controllerSource).not.toContain("status: \"stub\"");
        expect(controllerSource).not.toContain("syncYouTubeChurchStreams");
        expect(controllerSource).not.toContain("updateChurchLiveSignals");
        expect(indexSource).not.toContain("syncYouTubeChurchStreams");
        expect(indexSource).not.toContain("updateChurchLiveSignals");
    });

    it("exports real trust callables and trigger from the deployed index", () => {
        expect(indexSource).toContain("submitChurchVerificationRequest");
        expect(indexSource).toContain("submitChurchProfileUpdate");
        expect(indexSource).toContain("reviewChurchModerationItem");
        expect(indexSource).toContain("refreshChurchLivestreamState");
        expect(indexSource).toContain("generateGroundedChurchAnswer");
        expect(indexSource).toContain("moderateChurchMediaUpload");
        expect(indexSource).toContain("onChurchVerificationReviewed");
    });
});
