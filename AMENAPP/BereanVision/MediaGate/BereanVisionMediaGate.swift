import Foundation
import CoreVideo

// MARK: - BereanVisionMediaGate
//
// The fail-closed MEDIA-GATE for Berean Vision. Wave 1 scope: this is the LOCK,
// wired to nothing. There is no camera, no frame analysis, no retention, and no
// egress path behind it — those are HARD-GATED behind ESP/NCMEC registration, a
// hash-provider contract, written legal sign-off, and non-engineer review, none
// of which are cleared.
//
// Design rule: the gate never defaults open. Any uncertainty, any unrecognized
// input shape, any error → .block. The allow path requires POSITIVE recognition
// of a known, image-free derived shape — absence of evidence is not allowance.

public struct BereanVisionMediaGate: MediaGate {

    public init() {}

    // MARK: Frame path (MediaGate protocol conformance)

    /// Fail-closed. In Wave 1 NO frame can be cleared: the only safe state for a
    /// camera frame is .block, because the cleared image path (ESP/NCMEC + hash
    /// provider + legal sign-off + non-engineer review) does not exist yet.
    /// This intentionally has no allow branch. Do not add one without the gates.
    public func evaluate(frame: CVPixelBuffer) async -> MediaGateDecision {
        // No analysis is performed. A frame is raw image data; with no cleared
        // path to handle it, the only safe answer is to deny.
        return .block
    }

    // MARK: Derived-payload egress guard (on-device mirror of server containsImageBytes)

    /// Evaluates a DERIVED payload destined for the reasoning layer. Returns
    /// .allow ONLY when the payload positively matches the known image-free DTO
    /// shape AND carries no image-byte markers. Everything else → .block.
    public func evaluatePayload(_ payload: Any?) -> MediaGateDecision {
        guard let payload else { return .block }                 // nil → block
        if containsImageBytes(payload, depth: 0) { return .block } // forbidden markers → block
        guard isPermittedDerivedShape(payload, depth: 0) else { return .block } // unrecognized → block
        return .allow
    }

    // MARK: Forbidden-marker scan (mirrors functions/src/bereanVision/bereanVisionReason.ts)

    /// Keys that could carry, reference, or reconstruct raw image data.
    static let forbiddenKeys: Set<String> = [
        "image", "imagedata", "frame", "pixelbuffer", "bytes",
        "data:image", "jpeg", "png", "base64image", "stillimage", "boundingbox",
        "cvpixelbuffer", "uiimage", "cgimage", "ciimage", "pixels", "rawframe",
    ]

    /// Longest permitted depth for a derived payload. Deeper → fail-closed.
    static let maxDepth = 6

    private func containsImageBytes(_ node: Any?, depth: Int) -> Bool {
        if depth > Self.maxDepth { return true }                 // too deep → fail-closed
        guard let node else { return false }

        switch node {
        case let s as String:
            return looksLikeImageString(s)

        case is Data:
            return true                                          // raw bytes

        case let bytes as [UInt8]:
            return !bytes.isEmpty                                // typed byte array

        case let nums as [Int]:
            // A long array of byte-range integers looks like raw pixel/image bytes.
            return nums.count >= 512 && nums.allSatisfy { $0 >= 0 && $0 <= 255 }

        case let dict as [String: Any]:
            for (key, value) in dict {
                if Self.forbiddenKeys.contains(key.lowercased()) { return true }
                if containsImageBytes(value, depth: depth + 1) { return true }
            }
            return false

        case let array as [Any]:
            for element in array where containsImageBytes(element, depth: depth + 1) {
                return true
            }
            return false

        case is NSNumber, is Bool, is Int, is Double, is Float:
            return false

        case is NSNull:
            return false

        default:
            // Unknown reference/object type (could be a UIImage/CGImage/etc) → fail-closed.
            return true
        }
    }

    private func looksLikeImageString(_ s: String) -> Bool {
        let lower = s.lowercased()
        if lower.hasPrefix("data:image") { return true }
        // A long, contiguous base64 run (no whitespace) resembles an encoded image.
        if s.count >= 512, isContiguousBase64(s) { return true }
        return false
    }

    private func isContiguousBase64(_ s: String) -> Bool {
        // Mirrors server regex ^[A-Za-z0-9+/]{512,}={0,2}$ — no spaces, base64 alphabet only.
        var trimmed = Substring(s)
        while trimmed.last == "=" { trimmed = trimmed.dropLast() }
        if trimmed.count < 512 { return false }
        return trimmed.allSatisfy { ch in
            ch.isLetter && ch.isASCII || ch.isNumber && ch.isASCII || ch == "+" || ch == "/"
        }
    }

    // MARK: Positive allow-list (the derived DTO shape, image-free)

    /// Keys permitted anywhere in a derived Berean Vision payload. Any key outside
    /// this set means the shape is unrecognized → fail-closed .block.
    static let permittedKeys: Set<String> = [
        // SceneContextDTO
        "scenetype", "objects", "recognizedtext", "suggestedmodes", "confidence",
        // ReasoningRequestDTO
        "verb", "scenecontext", "useridhash", "mode",
        // object entries
        "label",
    ]

    private func isPermittedDerivedShape(_ node: Any?, depth: Int) -> Bool {
        if depth > Self.maxDepth { return false }                // too deep → not recognized
        guard let node else { return false }

        switch node {
        case is String, is Bool, is Int, is Double, is Float, is NSNumber:
            return true                                          // scalar leaf, already byte-scanned

        case let dict as [String: Any]:
            for (key, value) in dict {
                guard Self.permittedKeys.contains(key.lowercased()) else { return false }
                guard isPermittedDerivedShape(value, depth: depth + 1) else { return false }
            }
            return true

        case let array as [Any]:
            return array.allSatisfy { isPermittedDerivedShape($0, depth: depth + 1) }

        default:
            return false                                         // unknown type → not recognized
        }
    }
}
