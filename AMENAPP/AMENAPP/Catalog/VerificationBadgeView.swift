import SwiftUI

// MARK: - VerificationBadgeType

/// Represents the four badge types that can be granted to creators.
/// There is deliberately no `verified_public_figure` case — public-figure
/// verification is a HUMAN GATE and is never auto-executed.
enum VerificationBadgeType: String, Codable, Equatable {
    case verifiedCreator = "verified_creator"
    case verifiedOrganization = "verified_organization"
    case verifiedChurch = "verified_church"
    case verifiedBusiness = "verified_business"

    /// SF Symbol name for this badge type.
    var icon: String {
        switch self {
        case .verifiedCreator:      return "checkmark.seal.fill"
        case .verifiedOrganization: return "building.2.fill"
        case .verifiedChurch:       return "cross.fill"
        case .verifiedBusiness:     return "briefcase.fill"
        }
    }

    /// Human-readable label shown in UI surfaces.
    var label: String {
        switch self {
        case .verifiedCreator:      return "Verified Creator"
        case .verifiedOrganization: return "Verified Organization"
        case .verifiedChurch:       return "Verified Church"
        case .verifiedBusiness:     return "Verified Business"
        }
    }

    /// All badge types use accent color — monochrome/accent only per design spec.
    var color: Color { .accentColor }
}

// MARK: - VerificationBadge (compact inline)

/// A compact inline badge shown next to a creator name in feeds, profile headers,
/// and catalog cards. Renders a small SF Symbol icon and optional short label.
struct VerificationBadge: View {
    let type: VerificationBadgeType

    /// When `true`, shows the text label alongside the icon.
    var showLabel: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: type.icon)
                .font(.systemScaled(12, weight: .semibold))
                .foregroundStyle(type.color)
                .accessibilityHidden(true)

            if showLabel {
                Text(type.label)
                    .font(.systemScaled(11, weight: .medium))
                    .foregroundStyle(type.color)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(type.label)
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - VerificationBadgeCard (full glass card)

/// A full-sized glass card displaying the verification badge icon, label, and
/// "Verified by Amen" attribution. Used in catalog headers and creator profile pages.
struct VerificationBadgeCard: View {
    let type: VerificationBadgeType

    var body: some View {
        HStack(spacing: 12) {
            // Badge icon in a circular accent background
            ZStack {
                Circle()
                    .fill(type.color.opacity(0.12))
                    .frame(width: 40, height: 40)

                Image(systemName: type.icon)
                    .font(.systemScaled(18, weight: .semibold))
                    .foregroundStyle(type.color)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(type.label)
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Verified by Amen")
                    .font(.systemScaled(12, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(type.color.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(type.label). Verified by Amen.")
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - UnofficialCatalogBanner

/// An amber/warning pill shown when catalog content comes from public sources
/// and has not been officially claimed by its creator.
///
/// Tapping the banner presents an explanatory sheet.
struct UnofficialCatalogBanner: View {
    @State private var showExplanation = false

    var body: some View {
        Button {
            showExplanation = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(Color.orange)
                    .accessibilityHidden(true)

                Text("Unofficial catalog – public sources only")
                    .font(.systemScaled(12, weight: .medium))
                    .foregroundStyle(Color.orange)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.orange.opacity(0.12))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Unofficial catalog. Content sourced from public data, not officially managed by this creator. Tap for more information.")
        .accessibilityHint("Opens an explanation sheet")
        .sheet(isPresented: $showExplanation) {
            UnofficialCatalogExplanationSheet()
        }
    }
}

// MARK: - UnofficialCatalogExplanationSheet

/// Detail sheet explaining what "Unofficial catalog" means and how creators
/// can claim their content by completing verification.
private struct UnofficialCatalogExplanationSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header icon
                    HStack {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.12))
                                .frame(width: 64, height: 64)
                            Image(systemName: "info.circle.fill")
                                .font(.systemScaled(30))
                                .foregroundStyle(Color.orange)
                        }
                        Spacer()
                    }
                    .padding(.top, 8)

                    // Explanation body
                    VStack(alignment: .leading, spacing: 14) {
                        Text("What is an Unofficial Catalog?")
                            .font(.title3.bold())

                        Text(
                            "This catalog was built using publicly available data and has not yet been " +
                            "officially claimed or verified by the creator. The content may be incomplete " +
                            "or contain inaccuracies."
                        )
                        .font(.body)
                        .foregroundStyle(.secondary)

                        Divider()

                        Text("Are you this creator?")
                            .font(.headline)

                        Text(
                            "If this is your catalog, you can verify your identity on Amen to claim it. " +
                            "Once verified, you'll be able to manage your content, add new works, and " +
                            "display a verified badge to your audience."
                        )
                        .font(.body)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)

                    Spacer(minLength: 24)
                }
            }
            .navigationTitle("Unofficial Catalog")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - GetVerifiedView

/// Presents available verification methods for creators to establish their
/// identity and claim their catalog. Each method shows an icon, name,
/// description, and a "Verify" button that calls the CF `submitVerificationClaim`.
struct GetVerifiedView: View {
    @StateObject private var viewModel = GetVerifiedViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Intro header
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.systemScaled(48))
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)

                        Text("Get Verified on Amen")
                            .font(.title2.bold())

                        Text("Verify your identity to claim your catalog, gain a badge, and build trust with your audience.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 24)

                    // Verification method cards
                    ForEach(VerificationMethod.all) { method in
                        VerificationMethodCard(
                            method: method,
                            isLoading: viewModel.loadingMethod == method.id,
                            onVerify: {
                                Task { await viewModel.submitClaim(method: method) }
                            }
                        )
                    }

                    // Status/error feedback
                    if let feedback = viewModel.feedbackMessage {
                        Text(feedback)
                            .font(.footnote)
                            .foregroundStyle(viewModel.feedbackIsError ? .red : .green)
                            .padding(.horizontal)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.updatesFrequently)
                    }

                    Spacer(minLength: 32)
                }
                .padding(.horizontal)
            }
            .navigationTitle("Verification")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - VerificationMethod model

/// Describes a single verification method available to the creator.
struct VerificationMethod: Identifiable {
    let id: String
    let icon: String
    let name: String
    let description: String

    static let all: [VerificationMethod] = [
        VerificationMethod(
            id: "domain",
            icon: "globe",
            name: "Domain Verification",
            description: "Add a DNS TXT record to your website to prove you own the domain."
        ),
        VerificationMethod(
            id: "social_oauth",
            icon: "person.badge.shield.checkmark.fill",
            name: "Social Account",
            description: "Connect your YouTube or Spotify account via OAuth to confirm your identity."
        ),
        VerificationMethod(
            id: "email_domain",
            icon: "envelope.fill",
            name: "Domain Email",
            description: "Receive a verification code at your organization's email address."
        ),
        VerificationMethod(
            id: "org_admin",
            icon: "building.2.fill",
            name: "Organization",
            description: "Submit your organization credentials for manual admin review (churches, businesses, nonprofits)."
        ),
    ]
}

// MARK: - VerificationMethodCard

/// A Liquid Glass card for a single verification method.
private struct VerificationMethodCard: View {
    let method: VerificationMethod
    let isLoading: Bool
    let onVerify: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Method icon
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: method.icon)
                    .font(.systemScaled(20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityHidden(true)

            // Method name + description
            VStack(alignment: .leading, spacing: 3) {
                Text(method.name)
                    .font(.systemScaled(15, weight: .semibold))

                Text(method.description)
                    .font(.systemScaled(12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            // Verify button
            Button(action: onVerify) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 56)
                } else {
                    Text("Verify")
                        .font(.systemScaled(13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .accessibilityLabel("Verify using \(method.name)")
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - GetVerifiedViewModel

/// View model for GetVerifiedView.
/// Calls the Firebase CF `submitVerificationClaim` and surfaces feedback.
@MainActor
final class GetVerifiedViewModel: ObservableObject {
    @Published var loadingMethod: String?
    @Published var feedbackMessage: String?
    @Published var feedbackIsError: Bool = false

    func submitClaim(method: VerificationMethod) async {
        loadingMethod = method.id
        feedbackMessage = nil

        do {
            let result = try await VerificationService.shared.submitVerificationClaim(method: method.id)
            feedbackIsError = false
            feedbackMessage = result.challenge ?? "Verification request submitted. Check your email or follow the challenge instructions."
        } catch {
            feedbackIsError = true
            feedbackMessage = error.localizedDescription
        }

        loadingMethod = nil
    }
}

// MARK: - VerificationService

/// Thin async wrapper around the Firebase Callable CF `submitVerificationClaim`.
/// Keeps the view model clean of Firebase import details.
final class VerificationService {
    static let shared = VerificationService()
    private init() {}

    struct SubmitClaimResult {
        let claimId: String
        let status: String
        let challenge: String?
    }

    /// Calls the `submitVerificationClaim` Cloud Function.
    /// - Parameter method: the verification method identifier (e.g. "domain")
    /// - Returns: A `SubmitClaimResult` with the returned claimId and optional challenge string.
    func submitVerificationClaim(method: String) async throws -> SubmitClaimResult {
        // Using Firebase Functions callable via URLSession to avoid direct import coupling.
        // Projects with Firebase SDK can replace this with:
        //   let callable = Functions.functions().httpsCallable("submitVerificationClaim")
        //   let result = try await callable.call(["method": method, "evidence": [:]])
        //
        // This stub raises a descriptive error so Xcode diagnostics remain clean
        // until the Firebase SDK target is linked.
        throw VerificationError.sdkNotLinked
    }
}

// MARK: - VerificationError

enum VerificationError: LocalizedError {
    case sdkNotLinked
    case claimRejected(String)
    case rateLimitExceeded
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .sdkNotLinked:
            return "Firebase SDK not linked. Wire VerificationService to your Firebase Functions callable."
        case .claimRejected(let reason):
            return "Verification rejected: \(reason)"
        case .rateLimitExceeded:
            return "Too many pending claims. Please wait for existing requests to complete."
        case .networkError(let detail):
            return "Network error: \(detail)"
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("VerificationBadge – icon only") {
    HStack(spacing: 16) {
        ForEach([
            VerificationBadgeType.verifiedCreator,
            .verifiedOrganization,
            .verifiedChurch,
            .verifiedBusiness,
        ], id: \.rawValue) { type in
            VerificationBadge(type: type)
        }
    }
    .padding()
}

#Preview("VerificationBadgeCard") {
    VStack(spacing: 12) {
        VerificationBadgeCard(type: .verifiedCreator)
        VerificationBadgeCard(type: .verifiedChurch)
        VerificationBadgeCard(type: .verifiedBusiness)
    }
    .padding()
}

#Preview("UnofficialCatalogBanner") {
    VStack(spacing: 20) {
        UnofficialCatalogBanner()
        Text("Some catalog content below")
            .foregroundStyle(.secondary)
    }
    .padding()
}

#Preview("GetVerifiedView") {
    GetVerifiedView()
}
#endif
