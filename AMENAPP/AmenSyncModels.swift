// AmenSyncModels.swift
// AMEN Sync — Create Once, Distribute Everywhere
// Core data models for all sync entities

import SwiftUI
import FirebaseFirestore

// MARK: - Platform Destination

enum SyncPlatform: String, Codable, CaseIterable, Identifiable {
    case amenFeed       = "amen_feed"
    case instagram      = "instagram"
    case tiktok         = "tiktok"
    case youtube        = "youtube"
    case youtubeShorts  = "youtube_shorts"
    case twitter        = "twitter"
    case facebook       = "facebook"
    case linkedin       = "linkedin"
    case threads        = "threads"
    case podcast        = "podcast"
    case churchBulletin = "church_bulletin"
    case email          = "email"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .amenFeed:       return "AMEN Feed"
        case .instagram:      return "Instagram"
        case .tiktok:         return "TikTok"
        case .youtube:        return "YouTube"
        case .youtubeShorts:  return "YouTube Shorts"
        case .twitter:        return "X / Twitter"
        case .facebook:       return "Facebook"
        case .linkedin:       return "LinkedIn"
        case .threads:        return "Threads"
        case .podcast:        return "Podcast"
        case .churchBulletin: return "Church Bulletin"
        case .email:          return "Email Newsletter"
        }
    }

    var icon: String {
        switch self {
        case .amenFeed:       return "a.circle.fill"
        case .instagram:      return "camera.fill"
        case .tiktok:         return "music.note.tv.fill"
        case .youtube:        return "play.rectangle.fill"
        case .youtubeShorts:  return "play.circle.fill"
        case .twitter:        return "bird.fill"
        case .facebook:       return "f.cursive.circle.fill"
        case .linkedin:       return "briefcase.fill"
        case .threads:        return "at.circle.fill"
        case .podcast:        return "mic.fill"
        case .churchBulletin: return "doc.text.fill"
        case .email:          return "envelope.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .amenFeed:       return .teal
        case .instagram:      return .pink
        case .tiktok:         return .red
        case .youtube:        return .red
        case .youtubeShorts:  return .orange
        case .twitter:        return .blue
        case .facebook:       return Color(red: 0.23, green: 0.35, blue: 0.60)
        case .linkedin:       return Color(red: 0.09, green: 0.46, blue: 0.69)
        case .threads:        return .primary
        case .podcast:        return .purple
        case .churchBulletin: return .brown
        case .email:          return .teal
        }
    }

    var canAutoPublish: Bool {
        switch self {
        case .amenFeed, .churchBulletin, .email: return true
        default: return false  // Others require connected accounts
        }
    }

    /// Target dimensions for this platform
    var targetAspectRatio: CGFloat {
        switch self {
        case .amenFeed:       return 1.0          // 1:1
        case .instagram:      return 1.0          // 1:1
        case .instagramStory: return 9.0 / 16.0   // 9:16
        case .tiktok:         return 9.0 / 16.0   // 9:16
        case .youtube:        return 16.0 / 9.0   // 16:9
        case .youtubeShorts:  return 9.0 / 16.0   // 9:16
        case .twitter:        return 16.0 / 9.0   // 16:9
        case .facebook:       return 1.91 / 1.0   // 1.91:1
        case .linkedin:       return 1.91 / 1.0   // 1.91:1
        case .threads:        return 1.0          // 1:1
        case .podcast:        return 1.0          // square artwork
        case .churchBulletin: return 8.5 / 11.0   // Letter
        case .email:          return 600.0 / 200.0
        }
    }

    var targetPixelWidth: Int {
        switch self {
        case .amenFeed, .instagram, .threads: return 1080
        case .tiktok, .youtubeShorts: return 1080
        case .youtube, .twitter, .facebook, .linkedin: return 1920
        case .podcast: return 3000
        case .churchBulletin, .email: return 1200
        }
    }

    var maxCaptionLength: Int {
        switch self {
        case .amenFeed:       return 2200
        case .instagram:      return 2200
        case .instagramStory: return 300
        case .tiktok:         return 2200
        case .youtube:        return 5000
        case .youtubeShorts:  return 2200
        case .twitter:        return 280
        case .facebook:       return 63206
        case .linkedin:       return 3000
        case .threads:        return 500
        case .podcast:        return 4000
        case .churchBulletin: return 800
        case .email:          return 10000
        }
    }

    var supportsHashtags: Bool {
        switch self {
        case .twitter, .instagram, .tiktok, .threads, .amenFeed: return true
        default: return false
        }
    }
}

// MARK: - Sync Project

struct AmenSyncProject: Identifiable, Codable {
    @DocumentID var id: String?
    var authorId: String
    var title: String
    var description: String
    var mediaType: SyncMediaType
    var status: SyncProjectStatus
    var selectedPlatforms: [SyncPlatform]
    var masterAssetURL: String?           // Original uploaded media URL
    var thumbnailURL: String?
    var createdAt: Date
    var updatedAt: Date
    var scheduledAt: Date?
    var publishedAt: Date?
    var tags: [String]
    var scriptureRef: String?
    var moderationStatus: SyncModerationStatus
    var moderationScore: Double           // 0.0 safe → 1.0 harmful
    var publishSummary: SyncPublishSummary?

    enum CodingKeys: String, CodingKey {
        case id, authorId, title, description, mediaType, status
        case selectedPlatforms, masterAssetURL, thumbnailURL
        case createdAt, updatedAt, scheduledAt, publishedAt
        case tags, scriptureRef, moderationStatus, moderationScore, publishSummary
    }
}

enum SyncMediaType: String, Codable, CaseIterable {
    case image      = "image"
    case video      = "video"
    case audio      = "audio"
    case graphic    = "graphic"
    case text       = "text"

    var displayName: String {
        switch self {
        case .image: return "Image"
        case .video: return "Video"
        case .audio: return "Audio"
        case .graphic: return "Graphic"
        case .text: return "Text Post"
        }
    }

    var icon: String {
        switch self {
        case .image:   return "photo.fill"
        case .video:   return "video.fill"
        case .audio:   return "waveform"
        case .graphic: return "paintbrush.fill"
        case .text:    return "text.quote"
        }
    }
}

enum SyncProjectStatus: String, Codable {
    case draft       = "draft"
    case processing  = "processing"
    case ready       = "ready"
    case scheduled   = "scheduled"
    case publishing  = "publishing"
    case published   = "published"
    case failed      = "failed"
    case archived    = "archived"

    var displayName: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .draft:      return .gray
        case .processing: return .orange
        case .ready:      return .blue
        case .scheduled:  return .purple
        case .publishing: return .teal
        case .published:  return .green
        case .failed:     return .red
        case .archived:   return .secondary
        }
    }
}

enum SyncModerationStatus: String, Codable {
    case pending  = "pending"
    case approved = "approved"
    case flagged  = "flagged"
    case rejected = "rejected"
}

// MARK: - Sync Variant (Per-platform adaptation)

struct AmenSyncVariant: Identifiable, Codable {
    @DocumentID var id: String?
    var projectId: String
    var platform: SyncPlatform
    var mediaURL: String?               // Adapted media URL
    var caption: String
    var hashtags: [String]
    var overlayText: String?
    var overlayPosition: SyncOverlayPosition
    var cropRect: SyncCropRect?
    var aiCaption: Bool                 // Caption was AI-generated
    var captionApproved: Bool           // User accepted AI caption
    var status: SyncVariantStatus
    var publishedAt: Date?
    var platformPostId: String?         // Platform's native post ID after publish
    var errorMessage: String?
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, projectId, platform, mediaURL, caption, hashtags
        case overlayText, overlayPosition, cropRect
        case aiCaption, captionApproved, status
        case publishedAt, platformPostId, errorMessage, updatedAt
    }
}

enum SyncVariantStatus: String, Codable {
    case pending   = "pending"
    case adapting  = "adapting"
    case ready     = "ready"
    case approved  = "approved"
    case published = "published"
    case failed    = "failed"
}

struct SyncCropRect: Codable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
}

enum SyncOverlayPosition: String, Codable, CaseIterable {
    case topLeft      = "top_left"
    case topCenter    = "top_center"
    case topRight     = "top_right"
    case centerLeft   = "center_left"
    case center       = "center"
    case centerRight  = "center_right"
    case bottomLeft   = "bottom_left"
    case bottomCenter = "bottom_center"
    case bottomRight  = "bottom_right"
    case none         = "none"

    var displayName: String {
        switch self {
        case .topLeft:      return "Top Left"
        case .topCenter:    return "Top Center"
        case .topRight:     return "Top Right"
        case .centerLeft:   return "Middle Left"
        case .center:       return "Center"
        case .centerRight:  return "Middle Right"
        case .bottomLeft:   return "Bottom Left"
        case .bottomCenter: return "Bottom Center"
        case .bottomRight:  return "Bottom Right"
        case .none:         return "No Overlay"
        }
    }
}

// MARK: - Sync Job (Background processing)

struct AmenSyncJob: Identifiable, Codable {
    @DocumentID var id: String?
    var projectId: String
    var authorId: String
    var jobType: SyncJobType
    var status: SyncJobStatus
    var progress: Double                // 0.0 – 1.0
    var startedAt: Date?
    var completedAt: Date?
    var errorMessage: String?
    var resultPayload: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id, projectId, authorId, jobType, status, progress
        case startedAt, completedAt, errorMessage, resultPayload
    }
}

enum SyncJobType: String, Codable {
    case transcodeVideo  = "transcode_video"
    case cropImage       = "crop_image"
    case generateCaption = "generate_caption"
    case generateThumb   = "generate_thumbnail"
    case moderateContent = "moderate_content"
    case publish         = "publish"
    case extractAudio    = "extract_audio"
}

enum SyncJobStatus: String, Codable {
    case queued     = "queued"
    case running    = "running"
    case completed  = "completed"
    case failed     = "failed"
    case cancelled  = "cancelled"
}

// MARK: - Publish Summary

struct SyncPublishSummary: Codable {
    var totalPlatforms: Int
    var successCount: Int
    var failedCount: Int
    var platformResults: [String: SyncPlatformResult]
}

struct SyncPlatformResult: Codable {
    var platform: String
    var success: Bool
    var postURL: String?
    var errorMessage: String?
    var publishedAt: Date?
}

// MARK: - Caption Suggestion

struct SyncCaptionSuggestion: Identifiable {
    let id = UUID()
    var text: String
    var tone: CaptionTone
    var platformFit: SyncPlatform?
    var hashtags: [String]
    var characterCount: Int { text.count }
}

enum CaptionTone: String, CaseIterable, Identifiable {
    case devotional  = "devotional"
    case uplifting   = "uplifting"
    case teaching    = "teaching"
    case bold        = "bold"
    case conversational = "conversational"
    case professional = "professional"

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .devotional:     return "hands.sparkles.fill"
        case .uplifting:      return "sun.max.fill"
        case .teaching:       return "graduationcap.fill"
        case .bold:           return "bolt.fill"
        case .conversational: return "bubble.left.and.bubble.right.fill"
        case .professional:   return "briefcase.fill"
        }
    }
}

// MARK: - Connected Account

struct SyncConnectedAccount: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var platform: SyncPlatform
    var accountHandle: String
    var accountDisplayName: String
    var avatarURL: String?
    var accessToken: String             // Encrypted server-side; opaque to client
    var scopes: [String]
    var isActive: Bool
    var connectedAt: Date
    var expiresAt: Date?
    var followerCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, userId, platform, accountHandle, accountDisplayName
        case avatarURL, accessToken, scopes, isActive
        case connectedAt, expiresAt, followerCount
    }
}

// MARK: - Analytics

struct SyncProjectAnalytics: Codable {
    var projectId: String
    var totalReach: Int
    var totalEngagement: Int
    var platformBreakdown: [String: PlatformAnalytics]
    var updatedAt: Date
}

struct PlatformAnalytics: Codable {
    var platform: String
    var views: Int
    var likes: Int
    var comments: Int
    var shares: Int
    var saves: Int
    var reach: Int
    var clickThroughs: Int
}
