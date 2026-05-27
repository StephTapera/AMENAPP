import SwiftUI

struct AmenOrganizationDirectorySearchView: View {
    @State private var query = ""
    @State private var selectedKind: AmenNationalDirectoryKind?
    @State private var stateFilter = ""
    @State private var results: [AmenNationalDirectoryItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var actionMessage: String?

    private let service = AmenNationalDirectoryService()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    searchControls

                    if let errorMessage {
                        statusCard(title: "Search Unavailable", message: errorMessage, symbol: "exclamationmark.triangle")
                    } else if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(28)
                    } else if results.isEmpty {
                        statusCard(
                            title: "Find an Organization",
                            message: "Search schools, churches, ministries, nonprofits, businesses, Bible studies, and campus groups.",
                            symbol: "magnifyingglass"
                        )
                    } else {
                        ForEach(results) { item in
                            AmenOrganizationDirectoryResultCard(
                                item: item,
                                onClaim: { Task { await claim(item) } },
                                onStartSpace: { Task { await startSpace(item) } }
                            )
                        }
                    }

                    if let actionMessage {
                        statusCard(title: "Status", message: actionMessage, symbol: "checkmark.circle")
                    }
                }
                .padding(16)
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("Organizations")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var searchControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search churches, schools, groups", text: $query)
                .textInputAutocapitalization(.words)
                .submitLabel(.search)
                .onSubmit { Task { await search() } }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.05)))

            HStack(spacing: 10) {
                Picker("Type", selection: $selectedKind) {
                    Text("All").tag(AmenNationalDirectoryKind?.none)
                    ForEach(AmenNationalDirectoryKind.allCases) { kind in
                        Text(kind.rawValue).tag(Optional(kind))
                    }
                }
                .pickerStyle(.menu)

                TextField("ST", text: $stateFilter)
                    .textInputAutocapitalization(.characters)
                    .frame(width: 54)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.05)))

                Button {
                    Task { await search() }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(Color.black))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search organizations")
            }
        }
        .padding(14)
        .background(directoryGlassBackground)
    }

    private func search() async {
        isLoading = true
        errorMessage = nil
        actionMessage = nil
        do {
            results = try await service.search(
                query: query,
                kind: selectedKind,
                state: stateFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : stateFilter
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func claim(_ item: AmenNationalDirectoryItem) async {
        do {
            try await service.claim(profileId: item.id, role: "representative")
            actionMessage = "Claim request submitted for \(item.displayName)."
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    private func startSpace(_ item: AmenNationalDirectoryItem) async {
        do {
            let spaceId = try await service.createSpace(profileId: item.id, groupName: "\(item.displayName) Community")
            actionMessage = spaceId == nil ? "Space request submitted." : "Space created."
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    private func statusCard(title: String, message: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.black.opacity(0.62))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(directoryGlassBackground)
    }

    private var directoryGlassBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.58)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 4)
    }
}

private struct AmenOrganizationDirectoryResultCard: View {
    let item: AmenNationalDirectoryItem
    let onClaim: () -> Void
    let onStartSpace: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbolName)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color.black.opacity(0.06)))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayName)
                        .font(.headline)
                        .foregroundStyle(.black)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.black.opacity(0.62))
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button("Claim") { onClaim() }
                    .buttonStyle(.borderedProminent)

                Button("Start Space") { onStartSpace() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.58)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 4)
        )
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        [item.kind.rawValue, item.city, item.state, item.claimStatus]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var symbolName: String {
        switch item.kind.organizationType {
        case .school, .university, .campusGroup: return "graduationcap.fill"
        case .church, .ministry, .bibleStudy: return "building.columns.fill"
        case .business, .enterprise: return "briefcase.fill"
        case .nonprofit, .prayerGroup, .creatorCommunity, .communityGroup: return "person.3.fill"
        }
    }
}
