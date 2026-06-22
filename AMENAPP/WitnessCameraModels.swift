import Foundation
import CoreGraphics

enum WitnessCaptureMode: String, Codable, CaseIterable, Equatable {
    case dualPhoto
    case singlePhoto
    case singleVideo
}

enum WitnessCameraSurfaceMode: String, CaseIterable, Equatable {
    case photo
    case video
}

enum WitnessPrimaryCamera: String, Codable, Equatable {
    case back
    case front
}

enum WitnessLayoutStyle: String, Codable, Equatable {
    case backPrimary
    case frontPrimary
}

struct WitnessPiPLayout: Codable, Equatable {
    var normalizedOriginX: CGFloat
    var normalizedOriginY: CGFloat
    var normalizedWidth: CGFloat
    var normalizedHeight: CGFloat

    static let `default` = WitnessPiPLayout(
        normalizedOriginX: 0.62,
        normalizedOriginY: 0.63,
        normalizedWidth: 0.28,
        normalizedHeight: 0.22
    )
}

struct WitnessMediaAssetDescriptor: Codable, Equatable, Hashable {
    var url: String?
    var storagePath: String?
    var localPath: String?
    var thumbnailURL: String?
    var width: Int?
    var height: Int?
    var durationSec: Double?
    var contentType: String

    init(
        url: String? = nil,
        storagePath: String? = nil,
        localPath: String? = nil,
        thumbnailURL: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        durationSec: Double? = nil,
        contentType: String
    ) {
        self.url = url
        self.storagePath = storagePath
        self.localPath = localPath
        self.thumbnailURL = thumbnailURL
        self.width = width
        self.height = height
        self.durationSec = durationSec
        self.contentType = contentType
    }
}

struct PostWitnessMediaMetadata: Codable, Equatable, Hashable {
    var enabled: Bool
    var mode: WitnessCaptureMode
    var layout: WitnessLayoutStyle
    var durationSec: Double?
    var frontAsset: WitnessMediaAssetDescriptor?
    var backAsset: WitnessMediaAssetDescriptor?
    var finalAsset: WitnessMediaAssetDescriptor
    var thumbnailAsset: WitnessMediaAssetDescriptor?
    var captureTimestamp: Date
    var retakesUsed: Int
    var deviceMultiCamSupported: Bool
    var version: Int

    init(
        enabled: Bool = true,
        mode: WitnessCaptureMode,
        layout: WitnessLayoutStyle,
        durationSec: Double? = nil,
        frontAsset: WitnessMediaAssetDescriptor? = nil,
        backAsset: WitnessMediaAssetDescriptor? = nil,
        finalAsset: WitnessMediaAssetDescriptor,
        thumbnailAsset: WitnessMediaAssetDescriptor? = nil,
        captureTimestamp: Date,
        retakesUsed: Int,
        deviceMultiCamSupported: Bool,
        version: Int = 1
    ) {
        self.enabled = enabled
        self.mode = mode
        self.layout = layout
        self.durationSec = durationSec
        self.frontAsset = frontAsset
        self.backAsset = backAsset
        self.finalAsset = finalAsset
        self.thumbnailAsset = thumbnailAsset
        self.captureTimestamp = captureTimestamp
        self.retakesUsed = retakesUsed
        self.deviceMultiCamSupported = deviceMultiCamSupported
        self.version = version
    }
}

struct WitnessDraftAttachment: Identifiable, Codable, Equatable {
    let id: String
    var mode: WitnessCaptureMode
    var primaryCamera: WitnessPrimaryCamera
    var layout: WitnessLayoutStyle
    var pipLayout: WitnessPiPLayout
    var captureTimestamp: Date
    var durationSec: Double?
    var retakeCount: Int
    var deviceMultiCamSupported: Bool
    var finalAsset: WitnessMediaAssetDescriptor
    var frontAsset: WitnessMediaAssetDescriptor?
    var backAsset: WitnessMediaAssetDescriptor?
    var thumbnailAsset: WitnessMediaAssetDescriptor?

    init(
        id: String = UUID().uuidString,
        mode: WitnessCaptureMode,
        primaryCamera: WitnessPrimaryCamera,
        layout: WitnessLayoutStyle,
        pipLayout: WitnessPiPLayout,
        captureTimestamp: Date,
        durationSec: Double? = nil,
        retakeCount: Int = 0,
        deviceMultiCamSupported: Bool,
        finalAsset: WitnessMediaAssetDescriptor,
        frontAsset: WitnessMediaAssetDescriptor? = nil,
        backAsset: WitnessMediaAssetDescriptor? = nil,
        thumbnailAsset: WitnessMediaAssetDescriptor? = nil
    ) {
        self.id = id
        self.mode = mode
        self.primaryCamera = primaryCamera
        self.layout = layout
        self.pipLayout = pipLayout
        self.captureTimestamp = captureTimestamp
        self.durationSec = durationSec
        self.retakeCount = retakeCount
        self.deviceMultiCamSupported = deviceMultiCamSupported
        self.finalAsset = finalAsset
        self.frontAsset = frontAsset
        self.backAsset = backAsset
        self.thumbnailAsset = thumbnailAsset
    }

    var finalFileURL: URL? {
        guard let localPath = finalAsset.localPath else { return nil }
        return URL(fileURLWithPath: localPath)
    }

    var thumbnailFileURL: URL? {
        guard let localPath = thumbnailAsset?.localPath else { return nil }
        return URL(fileURLWithPath: localPath)
    }

    var isVideo: Bool {
        mode == .singleVideo
    }

    var postMediaType: PostMediaType {
        isVideo ? .video : .image
    }
}

struct WitnessUploadResult {
    var mediaItem: PostMediaItem
    var metadata: PostWitnessMediaMetadata
    var storageRootPath: String
}

struct WitnessCaptureReviewState: Equatable {
    var attachment: WitnessDraftAttachment
    var canRetake: Bool
}
