// StudioModels.swift
// AMEN Studio — Creator Showcase & Ethical Monetization
// Data models for all Studio feature modules

import SwiftUI
import FirebaseFirestore

// MARK: - Studio Profile

struct StudioProfile: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var displayName: String
    var handle: String                          // @handle
    var tagline: String                         // Short creator tagline
    var bio: String
    var avatarURL: String?
    var bannerURL: String?
    var bannerColor: String                     // Hex fallback
    var creatorType: CreatorType
    var categories: [StudioCategory]
    var specialties: [String]                   // Free-form tags
    var location: String?
    var locationVisible: Bool
    var websiteURL: String?
    var socialLinks: [String: String]           // platform: url
    var isVerified: Bool
    var verifiedAs: VerificationLevel
    var isOpenForWork: Bool
    var isOpenForCommissions: Bool
    var availabilityNote: String?               // "Available from Jan 2026"
    var inquiryPolicy: InquiryPolicy
    var trustScore: Double                      // 0.0 – 1.0 computed by platform
    var moderationState: ModerationState
    var planTier: StudioPlanTier
    var isPublished: Bool
    var createdAt: Date
    var updatedAt: Date
    var analyticsOptIn: Bool

    // Discovery fields
    var searchKeywords: [String]
    var featuredOrder: Int?                     // Non-nil = featured placement
    var boostExpiry: Date?                      // Paid boost expiry

    enum CodingKeys: String, CodingKey {
        case id, userId, displayName, handle, tagline, bio, avatarURL, bannerURL
        case bannerColor, creatorType, categories, specialties, location, locationVisible
        case websiteURL, socialLinks, isVerified, verifiedAs, isOpenForWork
        case isOpenForCommissions, availabilityNote, inquiryPolicy, trustScore
        case moderationState, planTier, isPublished, createdAt, updatedAt, analyticsOptIn
        case searchKeywords, featuredOrder, boostExpiry
    }
}

// MARK: - Studio Enums

enum CreatorType: String, Codable, CaseIterable, Identifiable {
    case individual, church, ministry, nonprofit, agency, brand, mediaTeam

    var id: String { rawValue }

    var label: String {
        switch self {
        case .individual:  return "Individual Creator"
        case .church:      return "Church"
        case .ministry:    return "Ministry"
        case .nonprofit:   return "Nonprofit"
        case .agency:      return "Agency / Studio"
        case .brand:       return "Ethical Brand"
        case .mediaTeam:   return "Media Team"
        }
    }

    var icon: String {
        switch self {
        case .individual:  return "person.fill"
        case .church:      return "building.columns.fill"
        case .ministry:    return "cross.fill"
        case .nonprofit:   return "heart.fill"
        case .agency:      return "building.2.fill"
        case .brand:       return "seal.fill"
        case .mediaTeam:   return "video.fill"
        }
    }
}

enum StudioCategory: String, Codable, CaseIterable, Identifiable {
    case art, music, design, branding, uiux, photography, videography, film
    case editing, socialMedia, sermonMedia, writing, speaking, workshops
    case devotionals, digitalResources, templates, courses, coaching
    case worshipMedia, churchCreative, christianBusiness, productivity
    case commissions, eventServices, customWork, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .art:                return "Art"
        case .music:              return "Music"
        case .design:             return "Design"
        case .branding:           return "Branding"
        case .uiux:               return "UI/UX"
        case .photography:        return "Photography"
        case .videography:        return "Videography"
        case .film:               return "Film"
        case .editing:            return "Editing"
        case .socialMedia:        return "Social Media"
        case .sermonMedia:        return "Sermon/Media"
        case .writing:            return "Writing"
        case .speaking:           return "Speaking"
        case .workshops:          return "Workshops"
        case .devotionals:        return "Devotionals"
        case .digitalResources:   return "Digital Resources"
        case .templates:          return "Templates"
        case .courses:            return "Courses"
        case .coaching:           return "Coaching"
        case .worshipMedia:       return "Worship Media"
        case .churchCreative:     return "Church Creative"
        case .christianBusiness:  return "Christian Business"
        case .productivity:       return "Productivity"
        case .commissions:        return "Commissions"
        case .eventServices:      return "Event Services"
        case .customWork:         return "Custom Work"
        case .other:              return "Other"
        }
    }

    var icon: String {
        switch self {
        case .art:                return "paintbrush.fill"
        case .music:              return "music.note"
        case .design:             return "pencil.and.ruler.fill"
        case .branding:           return "seal.fill"
        case .uiux:               return "rectangle.on.rectangle"
        case .photography:        return "camera.fill"
        case .videography:        return "video.fill"
        case .film:               return "film.fill"
        case .editing:            return "scissors"
        case .socialMedia:        return "megaphone.fill"
        case .sermonMedia:        return "speaker.wave.3.fill"
        case .writing:            return "doc.text.fill"
        case .speaking:           return "mic.fill"
        case .workshops:          return "person.2.fill"
        case .devotionals:        return "book.fill"
        case .digitalResources:   return "folder.fill"
        case .templates:          return "doc.on.doc.fill"
        case .courses:            return "graduationcap.fill"
        case .coaching:           return "figure.stand"
        case .worshipMedia:       return "music.quarternote.3"
        case .churchCreative:     return "building.columns.fill"
        case .christianBusiness:  return "briefcase.fill"
        case .productivity:       return "checklist"
        case .commissions:        return "pencil.line"
        case .eventServices:      return "calendar.badge.plus"
        case .customWork:         return "wand.and.stars"
        case .other:              return "square.grid.2x2.fill"
        }
    }

    var color: Color {
        switch self {
        case .art, .design, .branding:            return Color(red: 0.55, green: 0.25, blue: 0.88)
        case .music, .worshipMedia:               return Color(red: 0.15, green: 0.45, blue: 0.90)
        case .photography, .videography, .film:   return Color(red: 0.18, green: 0.62, blue: 0.55)
        case .writing, .devotionals:              return Color(red: 0.88, green: 0.55, blue: 0.15)
        case .speaking, .workshops, .coaching:    return Color(red: 0.20, green: 0.58, blue: 0.36)
        case .templates, .digitalResources:       return Color(red: 0.15, green: 0.45, blue: 0.82)
        case .churchCreative, .sermonMedia:       return Color(red: 0.62, green: 0.28, blue: 0.82)
        default:                                   return Color(red: 0.40, green: 0.40, blue: 0.45)
        }
    }
}

enum VerificationLevel: String, Codable {
    case none, creator, church, ministry, organization, pro

    var badge: String? {
        switch self {
        case .none:         return nil
        case .creator:      return "checkmark.seal.fill"
        case .church:       return "building.columns.fill"
        case .ministry:     return "cross.circle.fill"
        case .organization: return "star.seal.fill"
        case .pro:          return "crown.fill"
        }
    }

    var label: String {
        switch self {
        case .none:         return ""
        case .creator:      return "Verified Creator"
        case .church:       return "Verified Church"
        case .ministry:     return "Verified Ministry"
        case .organization: return "Verified Organization"
        case .pro:          return "Studio Pro"
        }
    }
}

enum StudioPlanTier: String, Codable {
    case free, pro, church, ministry

    var label: String {
        switch self {
        case .free:     return "Studio Free"
        case .pro:      return "Studio Pro"
        case .church:   return "Church Plan"
        case .ministry: return "Ministry Plan"
        }
    }

    var monthlyPrice: Double {
        switch self {
        case .free:     return 0.0
        case .pro:      return 9.99
        case .church:   return 29.99
        case .ministry: return 19.99
        }
    }
}

enum InquiryPolicy: String, Codable {
    case everyone, followersOnly, approvedOnly, closed

    var label: String {
        switch self {
        case .everyone:     return "Open to Everyone"
        case .followersOnly: return "Followers Only"
        case .approvedOnly:  return "Approved Only"
        case .closed:        return "Not Accepting Inquiries"
        }
    }
}

enum ModerationState: String, Codable {
    case active, underReview, warned, restricted, suspended

    var isVisible: Bool {
        switch self {
        case .active, .warned:  return true
        default:                 return false
        }
    }
}

// MARK: - Studio Work Item (Showcase)

struct StudioWorkItem: Identifiable, Codable {
    @DocumentID var id: String?
    var creatorId: String
    var title: String
    var subtitle: String?
    var description: String
    var mediaURLs: [String]                     // Images / video thumbnails
    var videoURL: String?
    var category: StudioCategory
    var tags: [String]
    var isFeatured: Bool
    var featuredOrder: Int?
    var projectDate: Date?
    var clientName: String?                     // Anonymous by default
    var clientVisible: Bool
    var projectURL: String?
    var servicesUsed: [String]                  // Cross-link to service IDs
    var isPublic: Bool
    var moderationState: ModerationState
    var viewCount: Int
    var saveCount: Int
    var shareCount: Int
    var createdAt: Date
    var updatedAt: Date
}

// MARK: - Studio Service

struct StudioService: Identifiable, Codable {
    @DocumentID var id: String?
    var creatorId: String
    var title: String
    var category: StudioCategory
    var shortDescription: String
    var fullDescription: String
    var pricingType: ServicePricingType
    var startingPrice: Double?              // nil = contact only
    var currency: String                    // "USD"
    var turnaroundDays: Int?
    var revisionsIncluded: Int
    var deliveryMethod: DeliveryMethod
    var sampleWorkIds: [String]             // References to StudioWorkItems
    var isAvailable: Bool
    var availabilityNote: String?
    var requiresDeposit: Bool
    var depositPercent: Int                 // e.g. 50
    var moderationState: ModerationState
    var inquiryCount: Int
    var completionCount: Int
    var responseRatePercent: Int
    var createdAt: Date
    var updatedAt: Date

    // Discovery
    var searchKeywords: [String]
    var isPromoted: Bool
    var promotionExpiry: Date?
}

enum ServicePricingType: String, Codable, CaseIterable {
    case fixed, startingAt, customQuote, free

    var label: String {
        switch self {
        case .fixed:        return "Fixed Price"
        case .startingAt:   return "Starting At"
        case .customQuote:  return "Custom Quote"
        case .free:         return "Free"
        }
    }
}

enum DeliveryMethod: String, Codable, CaseIterable {
    case digital, inPerson, remote, hybrid

    var label: String {
        switch self {
        case .digital:      return "Digital Delivery"
        case .inPerson:     return "In-Person"
        case .remote:       return "Remote / Virtual"
        case .hybrid:       return "Hybrid"
        }
    }

    var icon: String {
        switch self {
        case .digital:      return "arrow.down.circle.fill"
        case .inPerson:     return "mappin.circle.fill"
        case .remote:       return "video.circle.fill"
        case .hybrid:       return "circle.grid.2x1.fill"
        }
    }
}

// MARK: - Digital Product

struct StudioProduct: Identifiable, Codable {
    @DocumentID var id: String?
    var creatorId: String
    var title: String
    var category: StudioCategory
    var description: String
    var coverImageURL: String?
    var previewImageURLs: [String]
    var fileURLs: [String]                  // Actual downloadable files
    var fileTypes: [String]                 // "PDF", "ZIP", "PNG", etc.
    var fileSizeKB: Int
    var price: Double
    var isFree: Bool
    var currency: String
    var version: String                     // "1.0", "2.1"
    var downloadCount: Int
    var purchaseCount: Int
    var saveCount: Int
    var refundPolicy: String
    var licenseType: ProductLicense
    var moderationState: ModerationState
    var isPublished: Bool
    var searchKeywords: [String]
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date
}

enum ProductLicense: String, Codable, CaseIterable {
    case personal, commercial, churchLicense, extended

    var label: String {
        switch self {
        case .personal:       return "Personal Use"
        case .commercial:     return "Commercial License"
        case .churchLicense:  return "Church License"
        case .extended:       return "Extended License"
        }
    }

    var description: String {
        switch self {
        case .personal:       return "For personal, non-commercial use only."
        case .commercial:     return "For commercial projects and client work."
        case .churchLicense:  return "For use in your church or ministry."
        case .extended:       return "Broadest rights — includes resale."
        }
    }
}

// MARK: - Commission Profile

struct StudioCommissionProfile: Identifiable, Codable {
    @DocumentID var id: String?
    var creatorId: String
    var isOpen: Bool
    var queueNote: String?                  // "Currently 3 in queue — 2 week wait"
    var exampleWorkIds: [String]
    var commissionTypes: [CommissionType]
    var basePrice: Double?
    var priceNote: String?                  // "Price varies by complexity"
    var turnaroundWeeks: Int
    var requiresDeposit: Bool
    var depositPercent: Int
    var maxQueueSize: Int
    var currentQueueSize: Int
    var termsAndConditions: String
    var moderationState: ModerationState
    var updatedAt: Date
}

enum CommissionType: String, Codable, CaseIterable {
    case artwork, illustration, design, music, editing, writing, branding, custom

    var label: String {
        switch self {
        case .artwork:       return "Original Artwork"
        case .illustration:  return "Illustration"
        case .design:        return "Design Work"
        case .music:         return "Music Composition"
        case .editing:       return "Editing"
        case .writing:       return "Writing"
        case .branding:      return "Brand Identity"
        case .custom:        return "Custom Request"
        }
    }
}

struct StudioCommissionRequest: Identifiable, Codable {
    @DocumentID var id: String?
    var creatorId: String
    var requesterId: String
    var requesterName: String
    var commissionType: CommissionType
    var description: String
    var referenceURLs: [String]
    var budgetMin: Double?
    var budgetMax: Double?
    var deadlineDate: Date?
    var status: CommissionStatus
    var creatorNote: String?
    var estimatedPrice: Double?
    var requiresDeposit: Bool
    var depositPaid: Bool
    var threadId: String?                   // Linked inquiry thread
    var moderationFlag: Bool
    var createdAt: Date
    var updatedAt: Date
}

enum CommissionStatus: String, Codable {
    case pending, reviewing, accepted, declined, inProgress, completed, cancelled, disputed

    var label: String {
        switch self {
        case .pending:    return "Awaiting Review"
        case .reviewing:  return "Under Review"
        case .accepted:   return "Accepted"
        case .declined:   return "Declined"
        case .inProgress: return "In Progress"
        case .completed:  return "Completed"
        case .cancelled:  return "Cancelled"
        case .disputed:   return "Disputed"
        }
    }

    var color: Color {
        switch self {
        case .pending:    return .orange
        case .reviewing:  return .blue
        case .accepted:   return Color(red: 0.18, green: 0.62, blue: 0.36)
        case .declined:   return .red
        case .inProgress: return .blue
        case .completed:  return Color(red: 0.18, green: 0.62, blue: 0.36)
        case .cancelled:  return .gray
        case .disputed:   return .red
        }
    }
}

// MARK: - Booking / Inquiry

struct StudioBookingRequest: Identifiable, Codable {
    @DocumentID var id: String?
    var creatorId: String
    var requesterId: String
    var requesterName: String
    var bookingType: BookingType
    var title: String
    var description: String
    var eventDate: Date?
    var eventDurationHours: Double?
    var location: String?
    var isVirtual: Bool
    var budget: Double?
    var budgetNote: String?
    var expectations: String
    var status: BookingStatus
    var creatorResponse: String?
    var threadId: String?
    var reminderDate: Date?
    var moderationFlag: Bool
    var createdAt: Date
    var updatedAt: Date
}

enum BookingType: String, Codable, CaseIterable {
    case speaking, workshop, worshipLeading, photography, consulting, churchMedia
    case eventVideography, ministryTraining, collaboration, custom

    var label: String {
        switch self {
        case .speaking:         return "Speaking Engagement"
        case .workshop:         return "Workshop / Training"
        case .worshipLeading:   return "Worship Leading"
        case .photography:      return "Photography Session"
        case .consulting:       return "Creative Consulting"
        case .churchMedia:      return "Church Media Support"
        case .eventVideography: return "Event Videography"
        case .ministryTraining: return "Ministry Training"
        case .collaboration:    return "Collaboration"
        case .custom:           return "Custom Request"
        }
    }

    var icon: String {
        switch self {
        case .speaking:         return "mic.fill"
        case .workshop:         return "person.2.fill"
        case .worshipLeading:   return "music.quarternote.3"
        case .photography:      return "camera.fill"
        case .consulting:       return "lightbulb.fill"
        case .churchMedia:      return "building.columns.fill"
        case .eventVideography: return "video.fill"
        case .ministryTraining: return "cross.fill"
        case .collaboration:    return "link"
        case .custom:           return "wand.and.stars"
        }
    }
}

enum BookingStatus: String, Codable {
    case pending, reviewing, confirmed, declined, completed, cancelled

    var label: String {
        switch self {
        case .pending:   return "Pending"
        case .reviewing: return "Reviewing"
        case .confirmed: return "Confirmed"
        case .declined:  return "Declined"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }

    var color: Color {
        switch self {
        case .pending:   return .orange
        case .reviewing: return .blue
        case .confirmed: return Color(red: 0.18, green: 0.62, blue: 0.36)
        case .declined:  return .red
        case .completed: return .gray
        case .cancelled: return .gray
        }
    }
}

// MARK: - Support / Tips

struct StudioSupportProfile: Identifiable, Codable {
    @DocumentID var id: String?
    var creatorId: String
    var isEnabled: Bool
    var supportMessage: String              // Calm, non-manipulative message
    var suggestedAmounts: [Double]          // e.g. [3.0, 5.0, 10.0]
    var allowRecurring: Bool
    var allowCustomAmount: Bool
    var totalSupportersCount: Int           // Public count, optional
    var showSupportersCount: Bool
    var updatedAt: Date
}

struct StudioSupportTransaction: Identifiable, Codable {
    @DocumentID var id: String?
    var creatorId: String
    var supporterId: String
    var amount: Double
    var currency: String
    var isRecurring: Bool
    var note: String?
    var isAnonymous: Bool
    var status: TransactionStatus
    var platformFee: Double
    var processorFee: Double
    var creatorNet: Double
    var createdAt: Date
}

// MARK: - Transactions & Earnings

enum TransactionStatus: String, Codable {
    case pending, completed, failed, refunded, disputed, onHold

    var label: String {
        switch self {
        case .pending:   return "Pending"
        case .completed: return "Completed"
        case .failed:    return "Failed"
        case .refunded:  return "Refunded"
        case .disputed:  return "Disputed"
        case .onHold:    return "On Hold"
        }
    }

    var color: Color {
        switch self {
        case .pending:   return .orange
        case .completed: return Color(red: 0.18, green: 0.62, blue: 0.36)
        case .failed:    return .red
        case .refunded:  return .blue
        case .disputed:  return .red
        case .onHold:    return .orange
        }
    }
}

struct StudioTransaction: Identifiable, Codable {
    @DocumentID var id: String?
    var creatorId: String
    var buyerId: String?
    var transactionType: TransactionType
    var relatedItemId: String?              // Service, Product, Commission ID
    var relatedItemTitle: String
    var grossAmount: Double
    var platformFeePercent: Double          // e.g. 0.08 = 8%
    var platformFeeAmount: Double
    var processorFeeAmount: Double
    var netAmount: Double
    var currency: String
    var status: TransactionStatus
    var receiptId: String
    var refundStatus: RefundStatus?
    var fraudSignal: Double?                // 0.0 = clean, 1.0 = high risk
    var createdAt: Date
    var completedAt: Date?
}

enum TransactionType: String, Codable {
    case productSale, serviceDeposit, serviceCompletion, commission
    case booking, support, tip, platformFee, payout

    var label: String {
        switch self {
        case .productSale:          return "Product Sale"
        case .serviceDeposit:       return "Service Deposit"
        case .serviceCompletion:    return "Service Completion"
        case .commission:           return "Commission"
        case .booking:              return "Booking"
        case .support:              return "Support"
        case .tip:                  return "Tip"
        case .platformFee:          return "Platform Fee"
        case .payout:               return "Payout"
        }
    }
}

enum RefundStatus: String, Codable {
    case none, requested, approved, denied, processed

    var label: String {
        switch self {
        case .none:      return "No Refund"
        case .requested: return "Refund Requested"
        case .approved:  return "Refund Approved"
        case .denied:    return "Refund Denied"
        case .processed: return "Refunded"
        }
    }
}

struct StudioEarningsSummary: Identifiable, Codable {
    @DocumentID var id: String?
    var creatorId: String
    var periodStart: Date
    var periodEnd: Date
    var grossRevenue: Double
    var platformFees: Double
    var processorFees: Double
    var netRevenue: Double
    var pendingPayout: Double
    var totalTransactions: Int
    var productRevenue: Double
    var serviceRevenue: Double
    var commissionRevenue: Double
    var supportRevenue: Double
    var bookingRevenue: Double
    var topServiceId: String?
    var topProductId: String?
    var inquiryCount: Int
    var inquiryConversionRate: Double       // 0.0 – 1.0
    var newCollaborators: Int
}

// MARK: - Testimonials / Collaborations

struct StudioTestimonial: Identifiable, Codable {
    @DocumentID var id: String?
    var creatorId: String
    var authorId: String
    var authorName: String
    var authorRole: String?                 // "Pastor, Grace Church"
    var content: String
    var projectId: String?                  // Link to work item
    var isVerified: Bool                    // Must have completed transaction
    var isVisible: Bool
    var moderationState: ModerationState
    var createdAt: Date
}

// MARK: - Inquiry Thread

struct StudioInquiryThread: Identifiable, Codable {
    @DocumentID var id: String?
    var creatorId: String
    var inquirerId: String
    var inquirerName: String
    var subject: String
    var threadType: InquiryType
    var relatedItemId: String?
    var status: InquiryStatus
    var lastMessage: String
    var lastMessageAt: Date
    var isReadByCreator: Bool
    var isReadByInquirer: Bool
    var isArchived: Bool
    var moderationFlag: Bool
    var createdAt: Date
}

enum InquiryType: String, Codable {
    case service, commission, booking, collaboration, general, opportunity

    var label: String {
        switch self {
        case .service:       return "Service Inquiry"
        case .commission:    return "Commission Request"
        case .booking:       return "Booking Request"
        case .collaboration: return "Collaboration"
        case .general:       return "General Inquiry"
        case .opportunity:   return "Opportunity"
        }
    }
}

enum InquiryStatus: String, Codable {
    case open, inProgress, resolved, archived, spam

    var label: String {
        switch self {
        case .open:       return "Open"
        case .inProgress: return "In Progress"
        case .resolved:   return "Resolved"
        case .archived:   return "Archived"
        case .spam:       return "Spam"
        }
    }
}

// MARK: - Studio Analytics Event

struct StudioAnalyticsEvent: Identifiable, Codable {
    @DocumentID var id: String?
    var creatorId: String
    var eventType: AnalyticsEventType
    var targetId: String?                   // Work item, service, product ID
    var targetType: String?
    var viewerId: String?
    var referrerSurface: String?            // "discovery", "profile", "search"
    var sessionId: String
    var createdAt: Date
}

enum AnalyticsEventType: String, Codable {
    case profileView, workItemView, serviceView, productView
    case inquirySent, inquiryConverted, productPurchased, bookingConfirmed
    case workItemSaved, workItemShared, serviceBookmarked
}

// MARK: - Promoted Placement

struct StudioPromotedPlacement: Identifiable, Codable {
    @DocumentID var id: String?
    var creatorId: String
    var placementType: PlacementType
    var targetId: String?                   // Service or product being promoted
    var targetTitle: String
    var startDate: Date
    var endDate: Date
    var budget: Double
    var impressionCount: Int
    var clickCount: Int
    var isActive: Bool
    var moderationState: ModerationState
    var createdAt: Date
}

enum PlacementType: String, Codable {
    case creatorSpotlight, servicesFeatured, productsTop, discoveryBanner

    var label: String {
        switch self {
        case .creatorSpotlight: return "Creator Spotlight"
        case .servicesFeatured: return "Featured Service"
        case .productsTop:      return "Top Product Placement"
        case .discoveryBanner:  return "Discovery Banner"
        }
    }
}

// MARK: - Moderation

struct StudioModerationFlag: Identifiable, Codable {
    @DocumentID var id: String?
    var targetId: String
    var targetType: String
    var reporterId: String
    var reason: ModerationReason
    var flagDescription: String?
    var status: StudioFlagStatus
    var reviewNote: String?
    var reviewedBy: String?
    var actionTaken: String?                // Store as String to avoid enum ambiguity
    var createdAt: Date
    var resolvedAt: Date?
}

enum ModerationReason: String, Codable {
    case inappropriate, misleading, spam, scam, plagiarism, harmful
    case exploitativeFundraising, harassmentInInquiry, offPlatformBait, other

    var label: String {
        switch self {
        case .inappropriate:          return "Inappropriate Content"
        case .misleading:             return "Misleading Claims"
        case .spam:                   return "Spam"
        case .scam:                   return "Scam / Fraud"
        case .plagiarism:             return "Plagiarism / Stolen Work"
        case .harmful:                return "Harmful Content"
        case .exploitativeFundraising: return "Exploitative Fundraising"
        case .harassmentInInquiry:    return "Harassment in Inquiry"
        case .offPlatformBait:        return "Off-Platform Payment Bait"
        case .other:                  return "Other"
        }
    }
}

enum StudioFlagStatus: String, Codable {
    case pending, reviewing, resolved, escalated
}

enum StudioModerationAction: String, Codable {
    case noAction, warnCreator, derank, hideFromDiscovery
    case messagingRestriction, commerceRestriction, payoutHold
    case requiresReview, blockAccount

    var label: String {
        switch self {
        case .noAction:              return "No Action Required"
        case .warnCreator:           return "Warning Issued"
        case .derank:                return "De-ranked from Discovery"
        case .hideFromDiscovery:     return "Hidden from Discovery"
        case .messagingRestriction:  return "Messaging Restricted"
        case .commerceRestriction:   return "Commerce Restricted"
        case .payoutHold:            return "Payout Held"
        case .requiresReview:        return "Under Review"
        case .blockAccount:          return "Account Blocked"
        }
    }
}

// MARK: - Trust Score (Computed)

struct StudioTrustScore: Identifiable, Codable {
    @DocumentID var id: String?
    var creatorId: String
    var overallScore: Double                // 0.0 – 1.0
    var responseRateScore: Double
    var completionRateScore: Double
    var verificationScore: Double
    var contentQualityScore: Double
    var moderationHistoryScore: Double
    var collaborationScore: Double
    var updatedAt: Date

    var tier: TrustTier {
        switch overallScore {
        case 0.85...:  return .trusted
        case 0.65...:  return .established
        case 0.40...:  return .developing
        default:        return .new
        }
    }
}

enum TrustTier: String {
    case new, developing, established, trusted

    var label: String {
        switch self {
        case .new:         return "New Creator"
        case .developing:  return "Developing"
        case .established: return "Established"
        case .trusted:     return "Trusted Creator"
        }
    }

    var color: Color {
        switch self {
        case .new:         return .gray
        case .developing:  return .orange
        case .established: return .blue
        case .trusted:     return Color(red: 0.18, green: 0.62, blue: 0.36)
        }
    }

    var icon: String {
        switch self {
        case .new:         return "person.circle"
        case .developing:  return "arrow.up.circle"
        case .established: return "checkmark.circle"
        case .trusted:     return "seal.fill"
        }
    }
}

// MARK: - Product Purchase Record

struct ProductPurchaseRecord: Identifiable, Codable {
    @DocumentID var id: String?
    var buyerId: String
    var productId: String
    var creatorId: String
    var productTitle: String
    var amount: Double
    var currency: String
    var transactionId: String
    var downloadCount: Int
    var maxDownloads: Int                   // -1 = unlimited
    var purchasedAt: Date
    var expiresAt: Date?                    // nil = no expiry
    var licenseType: ProductLicense
    var refundStatus: RefundStatus
}

// MARK: - AMEN Fee Configuration

struct AMENFeeConfig {
    static let productSaleFeePercent: Double = 0.08         // 8%
    static let serviceFeePercent: Double = 0.10             // 10%
    static let commissionFeePercent: Double = 0.10          // 10%
    static let bookingFeePercent: Double = 0.08             // 8%
    static let supportFeePercent: Double = 0.05             // 5%
    static let maxFeeCapUSD: Double = 50.0                  // Fee cap

    static func calculateFee(amount: Double, type: TransactionType) -> (fee: Double, net: Double) {
        let percent: Double
        switch type {
        case .productSale:       percent = productSaleFeePercent
        case .serviceCompletion: percent = serviceFeePercent
        case .commission:        percent = commissionFeePercent
        case .booking:           percent = bookingFeePercent
        case .support, .tip:     percent = supportFeePercent
        default:                 percent = 0.0
        }
        let fee = min(amount * percent, maxFeeCapUSD)
        return (fee: fee, net: amount - fee)
    }
}
