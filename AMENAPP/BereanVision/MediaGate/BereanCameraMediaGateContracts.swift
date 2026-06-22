import Foundation
import SwiftUI
import UIKit
@preconcurrency import Vision
import CoreImage
import FirebaseFunctions

// MediaGatePipeline: ordered, fail-closed media publishing stages from capture through final disposition.
enum MediaGatePipelineStage: String, CaseIterable, Codable, Sendable {
    case capture = "Capture"
    case onDevicePrecheck = "OnDevicePrecheck"
    case quarantine = "Quarantine"
    case serverScan = "ServerScan"
    case policyDecision = "PolicyDecision"
    case publish = "Publish"
    case blur = "Blur"
    case limit = "Limit"
    case block = "Block"
    case review = "Review"
}

// PolicyDecision: server-authoritative result; any uncertainty defaults to review/block, never publish.
enum MediaGatePolicyDecision: String, Codable, Sendable, CaseIterable {
    case publish
    case blur
    case limit
    case block
    case review

    static var failClosedDefault: MediaGatePolicyDecision { .review }

    var allowsPublishWithoutReview: Bool { self == .publish }

    var allowsClientPostAfterServerGate: Bool {
        switch self {
        case .publish, .blur, .limit:
            return true
        case .block, .review:
            return false
        }
    }
}

// RedactionAction: transformations that can be suggested on-device and must be re-applied server-side.
enum MediaGateRedactionAction: Codable, Hashable, Sendable {
    case blurRegion(MediaGateRegion)
    case muteSpan(MediaGateTimeSpan)
    case stripEXIF
    case removeLocation
    case aiLabel(String)
    case restrictAudience(String)

    var displayName: String {
        switch self {
        case .blurRegion: return "Blur detected area"
        case .muteSpan: return "Mute audio segment"
        case .stripEXIF: return "Strip EXIF"
        case .removeLocation: return "Remove location"
        case .aiLabel: return "Add AI label"
        case .restrictAudience: return "Restrict audience"
        }
    }

    var serverDictionary: [String: Any] {
        switch self {
        case .blurRegion(let region):
            return ["type": "blurRegion", "region": region.serverDictionary]
        case .muteSpan(let timeSpan):
            return ["type": "muteSpan", "timeSpan": timeSpan.serverDictionary]
        case .stripEXIF:
            return ["type": "stripEXIF"]
        case .removeLocation:
            return ["type": "removeLocation"]
        case .aiLabel(let label):
            return ["type": "aiLabel", "label": label]
        case .restrictAudience(let audience):
            return ["type": "restrictAudience", "audience": audience]
        }
    }
}

// SafetyFinding: typed candidate signal only; never embeds raw media or raw private text.
struct MediaGateSafetyFinding: Codable, Hashable, Sendable, Identifiable {
    enum Category: String, Codable, Sendable {
        case faceCandidate
        case textCandidate
        case plateCandidate
        case exifLocation
        case audioPII
    }

    let id: UUID
    let category: Category
    let confidence: Double
    let region: MediaGateRegion?
    let timeSpan: MediaGateTimeSpan?
    let suggestedAction: MediaGateRedactionAction
    let summary: String

    init(
        id: UUID = UUID(),
        category: Category,
        confidence: Double,
        region: MediaGateRegion?,
        timeSpan: MediaGateTimeSpan?,
        suggestedAction: MediaGateRedactionAction,
        summary: String
    ) {
        self.id = id
        self.category = category
        self.confidence = min(max(confidence, 0), 1)
        self.region = region
        self.timeSpan = timeSpan
        self.suggestedAction = suggestedAction
        self.summary = summary
    }

    var serverDictionary: [String: Any] {
        var payload: [String: Any] = [
            "category": category.rawValue,
            "confidence": confidence,
            "suggestedAction": suggestedAction.serverDictionary
        ]
        if let region { payload["region"] = region.serverDictionary }
        if let timeSpan { payload["timeSpan"] = timeSpan.serverDictionary }
        return payload
    }
}

struct MediaGateRegion: Codable, Hashable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    static func normalized(_ rect: CGRect) -> MediaGateRegion {
        MediaGateRegion(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.size.width,
            height: rect.size.height
        )
    }

    var serverDictionary: [String: Any] {
        ["x": x, "y": y, "width": width, "height": height]
    }
}

struct MediaGateTimeSpan: Codable, Hashable, Sendable {
    let startSeconds: Double
    let endSeconds: Double

    var serverDictionary: [String: Any] {
        ["startSeconds": startSeconds, "endSeconds": endSeconds]
    }
}

// SafetyAuditRecord: retention-bounded decisions only; raw media/private text is never stored here.
struct MediaGateSafetyAuditRecord: Codable, Sendable {
    enum AppealStatus: String, Codable, Sendable {
        case none
        case open
        case resolved
    }

    let auditId: UUID
    let postId: String?
    let createdAt: Date
    let providerVersion: String
    let modelVersion: String
    let findingCategories: [MediaGateSafetyFinding.Category]
    let actionsTaken: [String]
    let policyDecision: MediaGatePolicyDecision
    let appealStatus: AppealStatus
    let reviewerDecision: String?
    let retentionExpiresAt: Date
    let openAppealMediaReference: String?

    var containsRawMediaOrPrivateText: Bool {
        let joined = (actionsTaken + [reviewerDecision, openAppealMediaReference].compactMap { $0 })
            .joined(separator: " ")
            .lowercased()
        return joined.contains("data:image")
            || joined.contains("base64")
            || joined.contains("rawtext")
            || joined.contains("transcript:")
            || joined.contains("exif:")
    }
}

// MediaGateInvariants: executable policy constants for fail-closed, disabled CSAM, and stricter known-minor defaults.
enum MediaGateInvariants {
    static let failClosed = true
    static let csamProviderGated = true
    static let csamHashScanDefaultEnabled = false
    static let knownMinorPublicLocationAllowed = false
    static let knownMinorDefaultActions: [MediaGateRedactionAction] = [
        .removeLocation,
        .stripEXIF,
        .restrictAudience("followers")
    ]

    static func decisionAfterRequiredStageFailure() -> MediaGatePolicyDecision {
        .review
    }

    static func shouldRouteToCSAMProvider(csamHashScanEnabled: Bool) -> Bool {
        csamProviderGated && csamHashScanEnabled
    }
}

struct MediaGatePrecheckResult: Sendable {
    let strippedImageData: Data
    let findings: [MediaGateSafetyFinding]
    let suggestedActions: [MediaGateRedactionAction]
    let localDecision: MediaGatePolicyDecision

    var requiresReview: Bool {
        localDecision != .publish || !findings.isEmpty
    }
}

struct MediaGatePolicyEvaluation: Sendable {
    let decision: MediaGatePolicyDecision
    let auditId: String?

    static let failClosed = MediaGatePolicyEvaluation(decision: .review, auditId: nil)
}

@MainActor
final class BereanMediaGatePolicyClient {
    static let shared = BereanMediaGatePolicyClient()

    private lazy var functions = Functions.functions(region: "us-east1")

    private init() {}

    func evaluateUploadedMedia(
        postId: String,
        uploadPath: String,
        findings: [MediaGateSafetyFinding],
        actions: [MediaGateRedactionAction],
        knownMinorAuthor: Bool
    ) async -> MediaGatePolicyEvaluation {
        guard AMENFeatureFlags.shared.mediaGateEnabled else {
            return MediaGatePolicyEvaluation(decision: .publish, auditId: nil)
        }

        let payload: [String: Any] = [
            "postId": postId,
            "uploadPath": uploadPath,
            "clientFindings": findings.map(\.serverDictionary),
            "requestedActions": actions.map(\.serverDictionary),
            "knownMinorAuthor": knownMinorAuthor
        ]

        do {
            let result = try await functions.httpsCallable("evaluateMediaGatePolicy").call(payload)
            guard let data = result.data as? [String: Any],
                  let rawDecision = data["decision"] as? String,
                  let decision = MediaGatePolicyDecision(rawValue: rawDecision) else {
                return .failClosed
            }
            return MediaGatePolicyEvaluation(decision: decision, auditId: data["auditId"] as? String)
        } catch {
            dlog("[MediaGate] Server policy failed closed: \(error)")
            return .failClosed
        }
    }
}

enum MediaGateImageRedactor {
    static func applying(actions: [MediaGateRedactionAction], to imageData: Data) -> Data {
        let regions = actions.compactMap { action -> MediaGateRegion? in
            if case .blurRegion(let region) = action { return region }
            return nil
        }
        guard !regions.isEmpty,
              let image = UIImage(data: imageData),
              let cgImage = image.cgImage else {
            return imageData
        }

        let baseImage = CIImage(cgImage: cgImage)
        let context = CIContext(options: nil)
        let renderer = UIGraphicsImageRenderer(size: image.size)
        let redactedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))

            for region in regions {
                let drawRect = CGRect(
                    x: region.x * image.size.width,
                    y: (1 - region.y - region.height) * image.size.height,
                    width: region.width * image.size.width,
                    height: region.height * image.size.height
                ).insetBy(dx: -8, dy: -8)

                let pixelScaleX = CGFloat(cgImage.width) / image.size.width
                let pixelScaleY = CGFloat(cgImage.height) / image.size.height
                let cropRect = CGRect(
                    x: max(drawRect.minX * pixelScaleX, 0),
                    y: max((image.size.height - drawRect.maxY) * pixelScaleY, 0),
                    width: min(drawRect.width * pixelScaleX, CGFloat(cgImage.width)),
                    height: min(drawRect.height * pixelScaleY, CGFloat(cgImage.height))
                )

                guard let filter = CIFilter(name: "CIGaussianBlur") else { continue }
                filter.setValue(baseImage.cropped(to: cropRect).clampedToExtent(), forKey: kCIInputImageKey)
                filter.setValue(18.0, forKey: kCIInputRadiusKey)
                guard let output = filter.outputImage?.cropped(to: cropRect),
                      let blurredCGImage = context.createCGImage(output, from: cropRect) else { continue }

                UIImage(cgImage: blurredCGImage, scale: image.scale, orientation: image.imageOrientation)
                    .draw(in: drawRect)
            }
        }

        return redactedImage.jpegData(compressionQuality: 0.9) ?? imageData
    }
}

actor BereanCameraMediaGatePrecheckService {
    static let shared = BereanCameraMediaGatePrecheckService()

    private init() {}

    func precheckImageData(_ imageData: Data) async -> MediaGatePrecheckResult {
        let stripResult = await CameraMetadataStripService.shared.stripMetadata(from: imageData)
        var findings = await detectImageFindings(in: stripResult.strippedData)

        if stripResult.hadGPSData {
            findings.append(MediaGateSafetyFinding(
                category: .exifLocation,
                confidence: 1.0,
                region: nil,
                timeSpan: nil,
                suggestedAction: .removeLocation,
                summary: "Location metadata removed"
            ))
        }

        if stripResult.hadDeviceData {
            findings.append(MediaGateSafetyFinding(
                category: .textCandidate,
                confidence: 1.0,
                region: nil,
                timeSpan: nil,
                suggestedAction: .stripEXIF,
                summary: "Camera metadata removed"
            ))
        }

        let actions = suggestedActions(for: findings)
        return MediaGatePrecheckResult(
            strippedImageData: stripResult.strippedData,
            findings: findings,
            suggestedActions: actions,
            localDecision: findings.isEmpty ? .publish : .review
        )
    }

    private func detectImageFindings(in imageData: Data) async -> [MediaGateSafetyFinding] {
        guard let image = UIImage(data: imageData), let cgImage = image.cgImage else {
            return [MediaGateSafetyFinding(
                category: .textCandidate,
                confidence: 1.0,
                region: nil,
                timeSpan: nil,
                suggestedAction: .stripEXIF,
                summary: "Image could not be decoded for safety precheck"
            )]
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let faceRequest = VNDetectFaceRectanglesRequest()
                let textRequest = VNRecognizeTextRequest()
                textRequest.recognitionLevel = .fast
                textRequest.usesLanguageCorrection = false

                let rectangleRequest = VNDetectRectanglesRequest()
                rectangleRequest.maximumObservations = 8
                rectangleRequest.minimumConfidence = 0.45
                rectangleRequest.minimumAspectRatio = 0.25
                rectangleRequest.maximumAspectRatio = 0.95

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([faceRequest, textRequest, rectangleRequest])
                    var findings: [MediaGateSafetyFinding] = []

                    let faces = faceRequest.results ?? []
                    findings.append(contentsOf: faces.map { face in
                        MediaGateSafetyFinding(
                            category: .faceCandidate,
                            confidence: Double(face.confidence),
                            region: .normalized(face.boundingBox),
                            timeSpan: nil,
                            suggestedAction: .blurRegion(.normalized(face.boundingBox)),
                            summary: "Face candidate detected"
                        )
                    })

                    let textObservations = textRequest.results ?? []
                    for observation in textObservations {
                        guard let candidate = observation.topCandidates(1).first else { continue }
                        let text = candidate.string
                        if Self.looksLikePII(text) {
                            findings.append(MediaGateSafetyFinding(
                                category: .textCandidate,
                                confidence: Double(max(observation.confidence, candidate.confidence)),
                                region: .normalized(observation.boundingBox),
                                timeSpan: nil,
                                suggestedAction: .blurRegion(.normalized(observation.boundingBox)),
                                summary: Self.redactedTextSummary(text)
                            ))
                        }
                        if Self.looksLikeLicensePlate(text) {
                            findings.append(MediaGateSafetyFinding(
                                category: .plateCandidate,
                                confidence: Double(max(observation.confidence, candidate.confidence)),
                                region: .normalized(observation.boundingBox),
                                timeSpan: nil,
                                suggestedAction: .blurRegion(.normalized(observation.boundingBox)),
                                summary: "Possible license plate text"
                            ))
                        }
                    }

                    let rectangles = rectangleRequest.results ?? []
                    findings.append(contentsOf: rectangles.prefix(3).map { rectangle in
                        MediaGateSafetyFinding(
                            category: .plateCandidate,
                            confidence: Double(rectangle.confidence),
                            region: .normalized(rectangle.boundingBox),
                            timeSpan: nil,
                            suggestedAction: .blurRegion(.normalized(rectangle.boundingBox)),
                            summary: "Rectangle candidate detected"
                        )
                    })

                    continuation.resume(returning: findings)
                } catch {
                    continuation.resume(returning: [MediaGateSafetyFinding(
                        category: .textCandidate,
                        confidence: 1.0,
                        region: nil,
                        timeSpan: nil,
                        suggestedAction: .stripEXIF,
                        summary: "Vision precheck failed"
                    )])
                }
            }
        }
    }

    private func suggestedActions(for findings: [MediaGateSafetyFinding]) -> [MediaGateRedactionAction] {
        var uniqueActions: [MediaGateRedactionAction] = []
        for action in findings.map(\.suggestedAction) + [.stripEXIF, .removeLocation] {
            if !uniqueActions.contains(action) {
                uniqueActions.append(action)
            }
        }
        return uniqueActions
    }

    private static func looksLikePII(_ text: String) -> Bool {
        let patterns = [
            #"\b\d{3}[-.\s]?\d{3}[-.\s]?\d{4}\b"#,
            #"\b\d{1,5}\s+[A-Za-z0-9.'-]+\s+(Street|St|Avenue|Ave|Road|Rd|Drive|Dr|Lane|Ln|Boulevard|Blvd)\b"#,
            #"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#
        ]
        return patterns.contains { pattern in
            text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    private static func looksLikeLicensePlate(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 5 && compact.count <= 8 else { return false }
        let hasLetter = compact.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil
        let hasNumber = compact.range(of: #"\d"#, options: .regularExpression) != nil
        let allowed = compact.range(of: #"^[A-Za-z0-9-]+$"#, options: .regularExpression) != nil
        return hasLetter && hasNumber && allowed
    }

    private static func redactedTextSummary(_ text: String) -> String {
        if text.contains("@") { return "Background email visible" }
        if text.range(of: #"\d{3}[-.\s]?\d{3}[-.\s]?\d{4}"#, options: .regularExpression) != nil {
            return "Background phone number visible"
        }
        return "Background address visible"
    }
}

struct BereanMediaGateReviewSheet: View {
    let result: MediaGatePrecheckResult
    let onMakeSafeAndPost: ([MediaGateRedactionAction]) -> Void
    let onEdit: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(summaryLine)
                        .font(.headline)
                    ForEach(result.findings) { finding in
                        Label(finding.summary, systemImage: iconName(for: finding.category))
                    }
                }

                Section("Suggested") {
                    ForEach(Array(result.suggestedActions.enumerated()), id: \.offset) { _, action in
                        Label(action.displayName, systemImage: "checkmark.shield")
                    }
                }
            }
            .navigationTitle("Safety Review")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Adjust") { onEdit() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Make Safe & Post") { onMakeSafeAndPost(result.suggestedActions) }
                        .bold()
                }
            }
        }
    }

    private var summaryLine: String {
        let faces = result.findings.filter { $0.category == .faceCandidate }.count
        let plates = result.findings.filter { $0.category == .plateCandidate }.count
        let text = result.findings.filter { $0.category == .textCandidate }.count
        var parts: [String] = []
        if faces > 0 { parts.append("\(faces) face\(faces == 1 ? "" : "s") detected") }
        if plates > 0 { parts.append("\(plates) plate candidate\(plates == 1 ? "" : "s")") }
        if text > 0 { parts.append("background private text visible") }
        return parts.isEmpty ? "No safety issues detected" : parts.joined(separator: " · ")
    }

    private func iconName(for category: MediaGateSafetyFinding.Category) -> String {
        switch category {
        case .faceCandidate: return "person.crop.rectangle"
        case .textCandidate: return "text.viewfinder"
        case .plateCandidate: return "rectangle.dashed"
        case .exifLocation: return "location.slash"
        case .audioPII: return "waveform.badge.exclamationmark"
        }
    }
}
