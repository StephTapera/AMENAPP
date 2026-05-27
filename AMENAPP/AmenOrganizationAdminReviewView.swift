import SwiftUI

struct AmenOrganizationAdminReviewItem: Identifiable, Hashable {
    enum ReviewKind: String {
        case claim
        case suggestedEdit
        case banner

        var title: String {
            switch self {
            case .claim: return "Claim"
            case .suggestedEdit: return "Suggested Edit"
            case .banner: return "Banner"
            }
        }
    }

    let id: String
    var organizationName: String
    var kind: ReviewKind
    var submittedBy: String
    var detail: String
    var profileId: String?
    var uid: String?
    var editId: String?
}

struct AmenOrganizationDirectoryAdminConsoleView: View {
    @StateObject private var viewModel = AmenOrganizationAdminReviewViewModel()

    var body: some View {
        AmenOrganizationAdminReviewView(
            items: viewModel.items,
            onApprove: { item in Task { await viewModel.approve(item) } },
            onReject: { item in Task { await viewModel.reject(item) } }
        )
        .overlay {
            if viewModel.isLoading {
                ProgressView()
                    .padding(20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .safeAreaInset(edge: .bottom) {
            if let status = viewModel.statusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.black.opacity(0.62))
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
    }
}

struct AmenOrganizationAdminReviewView: View {
    var items: [AmenOrganizationAdminReviewItem]
    var onApprove: (AmenOrganizationAdminReviewItem) -> Void
    var onReject: (AmenOrganizationAdminReviewItem) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if items.isEmpty {
                    Text("No organization reviews are pending.")
                        .font(.subheadline)
                        .foregroundStyle(.black.opacity(0.62))
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(reviewBackground)
                }

                ForEach(items) { item in
                    reviewCard(item)
                }
            }
            .padding(16)
        }
        .background(Color.white.ignoresSafeArea())
        .navigationTitle("Organization Review")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func reviewCard(_ item: AmenOrganizationAdminReviewItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: symbol(for: item.kind))
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.black.opacity(0.06)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.organizationName)
                        .font(.headline)
                        .foregroundStyle(.black)
                    Text("\(item.kind.title) · \(item.submittedBy)")
                        .font(.caption)
                        .foregroundStyle(.black.opacity(0.58))
                }

                Spacer(minLength: 0)
            }

            Text(item.detail)
                .font(.subheadline)
                .foregroundStyle(.black.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Approve") { onApprove(item) }
                    .buttonStyle(.borderedProminent)
                Button("Reject") { onReject(item) }
                    .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(reviewBackground)
    }

    private var reviewBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.58)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 4)
    }

    private func symbol(for kind: AmenOrganizationAdminReviewItem.ReviewKind) -> String {
        switch kind {
        case .claim: return "checkmark.seal"
        case .suggestedEdit: return "pencil.and.list.clipboard"
        case .banner: return "photo"
        }
    }
}

@MainActor
final class AmenOrganizationAdminReviewViewModel: ObservableObject {
    @Published var items: [AmenOrganizationAdminReviewItem] = []
    @Published var isLoading = false
    @Published var statusMessage: String?

    private let service = AmenNationalDirectoryService()

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let payload = try await service.listReviewQueue()
            items = Self.decodeItems(payload)
            statusMessage = items.isEmpty ? "Review queue is clear." : "Loaded \(items.count) pending reviews."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func approve(_ item: AmenOrganizationAdminReviewItem) async {
        do {
            try await service.resolveReview(item, approve: true)
            statusMessage = "Approved \(item.kind.title.lowercased())."
            await load()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func reject(_ item: AmenOrganizationAdminReviewItem) async {
        do {
            try await service.resolveReview(item, approve: false)
            statusMessage = "Rejected \(item.kind.title.lowercased())."
            await load()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private static func decodeItems(_ payload: [String: Any]) -> [AmenOrganizationAdminReviewItem] {
        let claims = decodeRows(payload["claims"] as? [[String: Any]], kind: .claim)
        let edits = decodeRows(payload["suggestedEdits"] as? [[String: Any]], kind: .suggestedEdit)
        let banners = decodeRows(payload["banners"] as? [[String: Any]], kind: .banner)
        return claims + edits + banners
    }

    private static func decodeRows(_ rows: [[String: Any]]?, kind: AmenOrganizationAdminReviewItem.ReviewKind) -> [AmenOrganizationAdminReviewItem] {
        (rows ?? []).map { row in
            let path = row["path"] as? String
            let ids = identifiers(from: path)
            let id = row["id"] as? String ?? ids.leaf ?? UUID().uuidString
            let profileId = row["profileId"] as? String ?? ids.profileId ?? row["id"] as? String
            let uid = row["uid"] as? String ?? ids.leaf
            let name = row["displayName"] as? String ?? row["organizationName"] as? String ?? profileId ?? "Organization"
            let detail: String
            switch kind {
            case .claim:
                detail = "Role: \(row["role"] as? String ?? "representative")"
            case .suggestedEdit:
                detail = "Suggested fields: \((row["fields"] as? [String: Any])?.keys.sorted().joined(separator: ", ") ?? "profile update")"
            case .banner:
                detail = "Banner is waiting for moderation."
            }
            return AmenOrganizationAdminReviewItem(
                id: id,
                organizationName: name,
                kind: kind,
                submittedBy: uid ?? "unknown",
                detail: detail,
                profileId: profileId,
                uid: uid,
                editId: kind == .suggestedEdit ? id : nil
            )
        }
    }

    private static func identifiers(from path: String?) -> (profileId: String?, leaf: String?) {
        guard let parts = path?.split(separator: "/").map(String.init) else { return (nil, nil) }
        let profileId = parts.count > 1 && parts[0] == "amenNationalDirectory" ? parts[1] : nil
        return (profileId, parts.last)
    }
}
