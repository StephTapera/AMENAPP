import SwiftUI
import FirebaseFunctions

struct CatalogEntitlementGateView: View {

    let feature: CatalogGateFeature

    @State private var isLoadingCheckout = false
    @State private var errorMessage: String? = nil

    private let functions = Functions.functions()

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: feature.icon)
                    .font(.systemScaled(44, weight: .ultraLight))
                    .foregroundStyle(.primary)

                VStack(spacing: 6) {
                    Text(feature.displayName)
                        .font(.systemScaled(22, weight: .bold))
                    Text(feature.unlockDescription)
                        .font(.systemScaled(15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }

                benefitsList
            }
            .padding(28)
            .amenGlassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 24)

            upgradeButton

            if let error = errorMessage {
                Text(error)
                    .font(.systemScaled(12))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
    }

    // MARK: - Benefits

    private var benefitsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(feature.benefits, id: \.self) { benefit in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.systemScaled(12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 16)
                    Text(benefit)
                        .font(.systemScaled(14))
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Upgrade Button

    private var upgradeButton: some View {
        Button {
            Task { await startCheckout() }
        } label: {
            HStack(spacing: 8) {
                if isLoadingCheckout {
                    ProgressView()
                        .scaleEffect(0.9)
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.systemScaled(16))
                }
                Text(isLoadingCheckout ? "Opening..." : "Upgrade to \(feature.planName)")
                    .font(.systemScaled(16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.primary)
            )
            .foregroundStyle(Color(UIColor.systemBackground))
        }
        .buttonStyle(.plain)
        .disabled(isLoadingCheckout)
        .padding(.horizontal, 24)
    }

    // MARK: - Checkout

    private func startCheckout() async {
        isLoadingCheckout = true
        errorMessage = nil
        defer { isLoadingCheckout = false }
        do {
            _ = try await functions.httpsCallable("createCatalogCheckoutSession").call(["feature": feature.rawValue])
        } catch {
            errorMessage = "Could not start checkout. Please try again."
        }
    }
}

// MARK: - CatalogGateFeature

enum CatalogGateFeature: String {
    case catalog
    case knowledgeMap
    case catalogCreate
    case askCreator

    var displayName: String {
        switch self {
        case .catalog:       return "Creator Catalog"
        case .knowledgeMap:  return "Knowledge Map"
        case .catalogCreate: return "Catalog Management"
        case .askCreator:    return "Ask This Creator"
        }
    }

    var icon: String {
        switch self {
        case .catalog:       return "books.vertical"
        case .knowledgeMap:  return "network"
        case .catalogCreate: return "arrow.up.doc"
        case .askCreator:    return "bubble.left.and.bubble.right"
        }
    }

    var unlockDescription: String {
        switch self {
        case .catalog:
            return "Access this creator's full catalog of books, sermons, music, courses, and more."
        case .knowledgeMap:
            return "Explore topics across this creator's entire body of work."
        case .catalogCreate:
            return "Import, organize, and publish your works to your creator catalog."
        case .askCreator:
            return "Ask questions and get answers grounded in this creator's published works."
        }
    }

    var planName: String {
        switch self {
        case .catalog, .knowledgeMap, .askCreator: return "Amen+"
        case .catalogCreate:                       return "CreatorPro"
        }
    }

    var benefits: [String] {
        switch self {
        case .catalog:
            return ["Browse all published works", "Filter by type", "Direct links to buy or listen"]
        case .knowledgeMap:
            return ["Topic clusters across all works", "Filter by subject", "Discover hidden connections"]
        case .catalogCreate:
            return ["Connect Spotify, YouTube, Substack", "Manual work entry", "Review and publish workflow"]
        case .askCreator:
            return ["AI-powered answers", "Grounded in published works", "Source citations included"]
        }
    }
}
