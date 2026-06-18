#if canImport(Testing)
// BereanVisionMediaGateTests.swift
// AMENAPPTests
//
// Two-sided proof of the fail-closed Berean Vision MEDIA-GATE.
//
// BLOCK path (safety-critical, exhaustive): every forbidden shape — image-byte
// markers, encoded image strings, raw byte containers, unknown types, unrecognized
// keys, over-deep payloads — must be blocked. The frame path must block ALWAYS.
//
// ALLOW path: only positively-recognized, image-free derived DTO shapes pass.
//
// The gate is wired to nothing; these are unit-level, no camera and no real frames.

import Foundation
import CoreVideo

#if canImport(Testing)
import Testing
@testable import AMENAPP

@Suite("BereanVisionMediaGate — fail-closed")
struct BereanVisionMediaGateTests {

    let gate = BereanVisionMediaGate()

    // MARK: - Helpers

    /// A small, valid CVPixelBuffer for exercising the frame path.
    private func makePixelBuffer() -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 4, 4, kCVPixelFormatType_32BGRA, nil, &buffer)
        return buffer
    }

    // MARK: - 1. Frame path: ALWAYS blocks (no allow branch in Wave 1)

    @Test("Any camera frame is blocked — there is no cleared image path")
    func frameAlwaysBlocks() async {
        guard let frame = makePixelBuffer() else {
            Issue.record("Could not allocate a test CVPixelBuffer")
            return
        }
        let decision = await gate.evaluate(frame: frame)
        #expect(decision == .block)
    }

    @Test("The frame path blocks on repeated calls — no state opens it")
    func frameBlocksRepeatedly() async {
        guard let frame = makePixelBuffer() else {
            Issue.record("Could not allocate a test CVPixelBuffer")
            return
        }
        for _ in 0..<5 {
            #expect(await gate.evaluate(frame: frame) == .block)
        }
    }

    // MARK: - 2. Payload BLOCK path — nil & defaults

    @Test("Nil payload is blocked")
    func nilPayloadBlocks() {
        #expect(gate.evaluatePayload(nil) == .block)
    }

    // MARK: - 3. Payload BLOCK path — every forbidden key

    @Test("Each forbidden key blocks (any casing)", arguments: [
        "image", "imageData", "frame", "pixelBuffer", "bytes", "boundingBox",
        "jpeg", "png", "base64Image", "stillImage", "cvPixelBuffer",
        "uiImage", "cgImage", "ciImage", "pixels", "rawFrame",
        "IMAGE", "Frame", "BoundingBox", "PNG",
    ])
    func forbiddenKeyBlocks(_ key: String) {
        let payload: [String: Any] = [key: "anything"]
        #expect(gate.evaluatePayload(payload) == .block)
    }

    @Test("A forbidden key nested deep inside a permitted shape still blocks")
    func nestedForbiddenKeyBlocks() {
        let payload: [String: Any] = [
            "sceneContext": [
                "objects": [
                    ["label": "Bible", "confidence": 0.9, "image": "leak"]
                ]
            ]
        ]
        #expect(gate.evaluatePayload(payload) == .block)
    }

    // MARK: - 4. Payload BLOCK path — encoded image strings

    @Test("A data:image URI is blocked")
    func dataImageUriBlocks() {
        let payload: [String: Any] = ["recognizedText": ["data:image/png;base64,iVBOR"]]
        #expect(gate.evaluatePayload(payload) == .block)
    }

    @Test("A long contiguous base64 blob is blocked")
    func longBase64Blocks() {
        let blob = String(repeating: "A", count: 600)
        let payload: [String: Any] = ["recognizedText": [blob]]
        #expect(gate.evaluatePayload(payload) == .block)
    }

    @Test("A base64 blob with trailing padding is blocked")
    func paddedBase64Blocks() {
        let blob = String(repeating: "QkJC", count: 200) + "==" // 800+ base64 chars
        let payload: [String: Any] = ["recognizedText": [blob]]
        #expect(gate.evaluatePayload(payload) == .block)
    }

    // MARK: - 5. Payload BLOCK path — raw byte containers

    @Test("A Data value is blocked")
    func dataValueBlocks() {
        let payload: [String: Any] = ["recognizedText": Data([0x01, 0x02, 0x03])]
        #expect(gate.evaluatePayload(payload) == .block)
    }

    @Test("A [UInt8] byte array is blocked")
    func byteArrayBlocks() {
        let payload: [String: Any] = ["recognizedText": [UInt8]([0, 1, 2, 3])]
        #expect(gate.evaluatePayload(payload) == .block)
    }

    @Test("A long byte-range [Int] array (looks like raw bytes) is blocked")
    func longByteRangeIntArrayBlocks() {
        let bytes = Array(repeating: 200, count: 600)
        let payload: [String: Any] = ["confidence": bytes]
        #expect(gate.evaluatePayload(payload) == .block)
    }

    // MARK: - 6. Payload BLOCK path — unknown types & unrecognized shapes

    @Test("An unknown reference type is blocked (fail-closed default branch)")
    func unknownTypeBlocks() {
        let payload: [String: Any] = ["confidence": Date()]
        #expect(gate.evaluatePayload(payload) == .block)
    }

    @Test("An unrecognized key blocks even with no image bytes")
    func unrecognizedKeyBlocks() {
        let payload: [String: Any] = ["secretField": "harmless text"]
        #expect(gate.evaluatePayload(payload) == .block)
    }

    @Test("A non-dictionary top-level payload is blocked")
    func nonDictionaryTopLevelBlocks() {
        #expect(gate.evaluatePayload("just a string") == .block)
        #expect(gate.evaluatePayload(42) == .block)
        #expect(gate.evaluatePayload(["a", "b", "c"]) == .block) // top-level array, not a DTO
    }

    @Test("Over-deep nesting is blocked")
    func overDeepNestingBlocks() {
        // Build nesting deeper than maxDepth using only permitted keys.
        var node: Any = ["confidence": 1.0]
        for _ in 0..<10 {
            node = ["sceneContext": node]
        }
        #expect(gate.evaluatePayload(node) == .block)
    }

    // MARK: - 7. Fuzz — malformed / mixed inputs default to block

    @Test("Fuzzed payloads with a buried forbidden marker all block", arguments: 0..<8)
    func fuzzBuriedMarkerBlocks(_ seed: Int) {
        // Deterministic per-seed structure with a forbidden marker hidden inside.
        let markers = ["image", "pixelBuffer", "boundingBox", "bytes"]
        let marker = markers[seed % markers.count]
        let payload: [String: Any] = [
            "sceneContext": [
                "sceneType": "document",
                "objects": [["label": "x", "confidence": Double(seed) / 10.0]],
                "recognizedText": ["line \(seed)"],
                marker: Data([UInt8(seed)]),
            ]
        ]
        #expect(gate.evaluatePayload(payload) == .block)
    }

    @Test("Empty dictionary value at a permitted key does not open an image path")
    func emptyContainersDoNotLeak() {
        // No image bytes, no forbidden/unknown keys → recognized & clean.
        let payload: [String: Any] = ["objects": [], "recognizedText": []]
        #expect(gate.evaluatePayload(payload) == .allow)
    }

    // MARK: - 8. ALLOW path — only clean, recognized derived shapes

    @Test("A minimal SceneContext DTO is allowed")
    func minimalSceneContextAllows() {
        let payload: [String: Any] = [
            "sceneType": "scripture",
            "objects": [],
            "recognizedText": ["For God so loved the world"],
            "suggestedModes": ["reading"],
            "confidence": 0.82,
        ]
        #expect(gate.evaluatePayload(payload) == .allow)
    }

    @Test("A full ReasoningRequest DTO (derived only) is allowed")
    func fullReasoningRequestAllows() {
        let payload: [String: Any] = [
            "verb": "explain",
            "userIdHash": "ab12cd34",
            "mode": "sermonPrep",
            "sceneContext": [
                "sceneType": "sermonScreen",
                "objects": [
                    ["label": "projector slide", "confidence": 0.77],
                    ["label": "Bible", "confidence": 0.91],
                ],
                "recognizedText": ["Romans 8:28", "all things work together for good"],
                "suggestedModes": ["sermonPrep", "crossReferences"],
                "confidence": 0.88,
            ],
        ]
        #expect(gate.evaluatePayload(payload) == .allow)
    }

    @Test("Recognized text with ordinary prose (spaces, punctuation) is allowed")
    func ordinaryProseAllows() {
        // Long but human text with spaces is not a contiguous base64 blob.
        let longProse = String(repeating: "The grass withers and the flower fades. ", count: 30)
        let payload: [String: Any] = [
            "recognizedText": [longProse],
            "confidence": 0.5,
        ]
        #expect(gate.evaluatePayload(payload) == .allow)
    }
}
#endif
#endif
