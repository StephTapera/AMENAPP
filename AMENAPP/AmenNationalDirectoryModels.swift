import Foundation
import FirebaseFunctions

enum AmenNationalDirectoryKind: String, CaseIterable, Codable, Identifiable {
    case publicK12School
    case higherEducation
    case church
    case nonprofit
    case ministry
    case business
    case campusGroup

    var id: String { rawValue }

    var organizationType: AmenContextualOrganizationType {
        switch self {
        case .publicK12School: return .school
        case .higherEducation: return .university
        case .church: return .church
        case .nonprofit: return .nonprofit
        case .ministry: return .ministry
        case .business: return .business
        case .campusGroup: return .campusGroup
        }
    }
}

enum AmenNationalDirectorySource: String, CaseIterable, Codable, Identifiable {
    case ncesCCD
    case ncesIPEDS
    case irsEOBMF
    case claimedAmenProfile
    case partnerImport

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ncesCCD: return "NCES Common Core of Data"
        case .ncesIPEDS: return "NCES IPEDS"
        case .irsEOBMF: return "IRS Exempt Organizations Business Master File"
        case .claimedAmenProfile: return "Claimed AMEN Profile"
        case .partnerImport: return "Partner Import"
        }
    }

    var isOfficialPublicDataset: Bool {
        switch self {
        case .ncesCCD, .ncesIPEDS, .irsEOBMF: return true
        case .claimedAmenProfile, .partnerImport: return false
        }
    }
}

enum AmenNationalDirectoryAction: String, CaseIterable, Codable {
    case openProfile = "Open"
    case claim = "Claim"
    case startGroup = "Start Group"
    case startSpace = "Start Space"
    case subscribe = "Subscribe"
}

struct AmenNationalDirectorySourceDescriptor: Identifiable, Hashable {
    let id: AmenNationalDirectorySource
    let name: String
    let datasetPurpose: String
    let allowedKinds: Set<AmenNationalDirectoryKind>
    let refreshCadence: String

    static let officialUSSources: [AmenNationalDirectorySourceDescriptor] = [
        AmenNationalDirectorySourceDescriptor(
            id: .ncesCCD,
            name: "NCES Common Core of Data",
            datasetPurpose: "Public elementary and secondary schools and districts.",
            allowedKinds: [.publicK12School],
            refreshCadence: "Annual public release"
        ),
        AmenNationalDirectorySourceDescriptor(
            id: .ncesIPEDS,
            name: "NCES IPEDS",
            datasetPurpose: "Postsecondary institutions and campuses.",
            allowedKinds: [.higherEducation],
            refreshCadence: "Annual public release"
        ),
        AmenNationalDirectorySourceDescriptor(
            id: .irsEOBMF,
            name: "IRS Exempt Organizations Business Master File",
            datasetPurpose: "Tax-exempt churches, ministries, nonprofits, schools, and organizations.",
            allowedKinds: [.church, .nonprofit, .ministry],
            refreshCadence: "IRS public extract update"
        )
    ]
}

struct AmenNationalDirectoryItem: Identifiable, Hashable, Codable {
    var id: String
    var source: AmenNationalDirectorySource
    var sourceRecordId: String
    var kind: AmenNationalDirectoryKind
    var displayName: String
    var normalizedName: String
    var city: String?
    var state: String?
    var postalCode: String?
    var websiteURL: String?
    var phone: String?
    var latitude: Double?
    var longitude: Double?
    var verificationStatus: String
    var claimStatus: String
    var amenProfileId: String?
    var amenSpaceId: String?
    var subscriptionEligible: Bool
    var lastSourceRefreshAt: Date?

    var canStartPaidSpace: Bool {
        subscriptionEligible && claimStatus == "claimed" && amenProfileId != nil
    }
}

enum AmenNationalDirectoryCallable: String, CaseIterable {
    case searchAmenNationalDirectory
    case getAmenNationalDirectorySources
    case claimAmenNationalDirectoryProfile
    case createAmenSpaceFromDirectoryProfile
    case createDirectorySubscriptionCheckout
}

enum AmenNationalDirectoryNormalizer {
    static func normalizedName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .split(separator: " ")
            .joined(separator: " ")
    }
}

@MainActor
final class AmenNationalDirectoryService {
    static let callableContracts = AmenNationalDirectoryCallable.allCases

    private let functions = Functions.functions()

    func search(query: String, kind: AmenNationalDirectoryKind?, state: String?) async throws -> [AmenNationalDirectoryItem] {
        let payload: [String: Any?] = [
            "query": query,
            "kind": kind?.rawValue,
            "state": state
        ]

        let result = try await functions.httpsCallable(AmenNationalDirectoryCallable.searchAmenNationalDirectory.rawValue).call(payload.compactMapValues { $0 })
        guard let rows = result.data as? [[String: Any]] else { return [] }
        return rows.compactMap(Self.decodeItem)
    }

    func claim(profileId: String, role: String) async throws {
        _ = try await functions.httpsCallable(AmenNationalDirectoryCallable.claimAmenNationalDirectoryProfile.rawValue).call([
            "profileId": profileId,
            "role": role
        ])
    }

    func createSpace(profileId: String, groupName: String) async throws -> String? {
        let result = try await functions.httpsCallable(AmenNationalDirectoryCallable.createAmenSpaceFromDirectoryProfile.rawValue).call([
            "profileId": profileId,
            "groupName": groupName
        ])
        return (result.data as? [String: Any])?["spaceId"] as? String
    }

    func listReviewQueue() async throws -> [String: Any] {
        let result = try await functions.httpsCallable("listAmenOrganizationReviewQueue").call([:])
        return result.data as? [String: Any] ?? [:]
    }

    func resolveReview(_ item: AmenOrganizationAdminReviewItem, approve: Bool) async throws {
        _ = try await functions.httpsCallable("resolveAmenOrganizationReview").call([
            "itemId": item.id,
            "kind": item.kind.rawValue,
            "approve": approve
        ])
    }

    private static func decodeItem(_ data: [String: Any]) -> AmenNationalDirectoryItem? {
        guard
            let id = data["id"] as? String,
            let sourceRaw = data["source"] as? String,
            let source = AmenNationalDirectorySource(rawValue: sourceRaw),
            let sourceRecordId = data["sourceRecordId"] as? String,
            let kindRaw = data["kind"] as? String,
            let kind = AmenNationalDirectoryKind(rawValue: kindRaw),
            let displayName = data["displayName"] as? String
        else { return nil }

        return AmenNationalDirectoryItem(
            id: id,
            source: source,
            sourceRecordId: sourceRecordId,
            kind: kind,
            displayName: displayName,
            normalizedName: data["normalizedName"] as? String ?? AmenNationalDirectoryNormalizer.normalizedName(displayName),
            city: data["city"] as? String,
            state: data["state"] as? String,
            postalCode: data["postalCode"] as? String,
            websiteURL: data["websiteURL"] as? String,
            phone: data["phone"] as? String,
            latitude: data["latitude"] as? Double,
            longitude: data["longitude"] as? Double,
            verificationStatus: data["verificationStatus"] as? String ?? "sourceImported",
            claimStatus: data["claimStatus"] as? String ?? "unclaimed",
            amenProfileId: data["amenProfileId"] as? String,
            amenSpaceId: data["amenSpaceId"] as? String,
            subscriptionEligible: data["subscriptionEligible"] as? Bool ?? false,
            lastSourceRefreshAt: nil
        )
    }
}
