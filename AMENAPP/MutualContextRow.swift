//
//  MutualContextRow.swift
//  AMENAPP
//
//  Compact social context row: overlapping avatar stack + "Followed by X and N others"
//  or "Shared church" or "Shared interests" text.
//  Tappable to expand a detail sheet with all context signals.
//

import SwiftUI

struct MutualContextRow: View {
    let userId: String
    @StateObject private var viewModel = MutualContextViewModel()
    @State private var showDetailSheet = false

    var body: some View {
        Group {
            if viewModel.isLoading {
                shimmerPlaceholder
            } else if !viewModel.isEmpty {
                contextContent
            }
            // When idle or empty, render nothing
        }
        .task(id: userId) {
            await viewModel.load(profileUID: userId)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contextContent: some View {
        Button {
            if viewModel.signals.count > 1 {
                showDetailSheet = true
            }
        } label: {
            HStack(spacing: 8) {
                // Avatar stack for mutual followers
                if let mutualsSignal = viewModel.signals.first(where: { isMutualFollowers($0) }),
                   case .mutualFollowers(let connections, _) = mutualsSignal.type {
                    avatarStack(connections: connections)
                }

                // Primary signal text
                if let primary = viewModel.primarySignal {
                    signalText(primary)
                        .font(.systemScaled(13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if viewModel.signals.count > 1 {
                    Image(systemName: "chevron.right")
                        .font(.systemScaled(10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .sheet(isPresented: $showDetailSheet) {
            MutualContextDetailSheet(signals: viewModel.signals)
        }
    }

    // MARK: - Avatar Stack

    private static let avatarDiameter: CGFloat = 28

    @ViewBuilder
    private func avatarStack(connections: [MutualConnection]) -> some View {
        HStack(spacing: -8) {
            ForEach(Array(connections.prefix(3).enumerated()), id: \.element.id) { index, connection in
                if let photoURL = connection.profilePhotoURL {
                    CachedAsyncImage(url: photoURL, size: CGSize(width: Self.avatarDiameter, height: Self.avatarDiameter)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        initialCircle(name: connection.displayName, index: index)
                    }
                    .frame(width: Self.avatarDiameter, height: Self.avatarDiameter)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                    .zIndex(Double(3 - index))
                } else {
                    initialCircle(name: connection.displayName, index: index)
                        .zIndex(Double(3 - index))
                }
            }
        }
    }

    @ViewBuilder
    private func initialCircle(name: String, index: Int) -> some View {
        let fills: [Color] = [
            Color(.systemGray2),
            Color(.systemGray3),
            Color(.systemGray4)
        ]
        Circle()
            .fill(fills[min(index, fills.count - 1)])
            .frame(width: Self.avatarDiameter, height: Self.avatarDiameter)
            .overlay(
                Text(String(name.prefix(1)).uppercased())
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
    }

    // MARK: - Signal Text

    @ViewBuilder
    private func signalText(_ signal: MutualContextSignal) -> some View {
        switch signal.type {
        case .mutualFollowers(let connections, let totalCount):
            let names = connections.map { $0.displayName }
            mutualFollowersText(names: names, totalCount: totalCount)
        case .sharedChurch(let name):
            Text("Shared church: \(name)")
        case .sharedInterests(let topics):
            Text("Shared interests: \(topics.joined(separator: ", "))")
        }
    }

    @ViewBuilder
    private func mutualFollowersText(names: [String], totalCount: Int) -> some View {
        let firstName = names.first ?? ""
        if totalCount == 1 {
            Text("Followed by \(firstName)")
        } else if totalCount == 2 {
            let secondName = names.count > 1 ? names[1] : ""
            Text("Followed by \(firstName) and \(secondName)")
        } else {
            let othersCount = totalCount - 1
            Text("Followed by \(firstName) and \(othersCount) other\(othersCount == 1 ? "" : "s")")
        }
    }

    // MARK: - Shimmer

    private var shimmerPlaceholder: some View {
        HStack(spacing: 8) {
            HStack(spacing: -8) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: Self.avatarDiameter, height: Self.avatarDiameter)
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                }
            }
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(width: 160, height: 12)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func isMutualFollowers(_ signal: MutualContextSignal) -> Bool {
        if case .mutualFollowers = signal.type { return true }
        return false
    }
}

// MARK: - Detail Sheet

private struct MutualContextDetailSheet: View {
    @Environment(\.dismiss) var dismiss
    let signals: [MutualContextSignal]

    var body: some View {
        NavigationStack {
            List {
                ForEach(signals) { signal in
                    signalRow(signal)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Connection Context")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.systemScaled(16, weight: .semibold))
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func signalRow(_ signal: MutualContextSignal) -> some View {
        HStack(spacing: 12) {
            signalIcon(signal)
                .frame(width: 36, height: 36)
                .background(Color(.systemGray5))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                signalTitle(signal)
                    .font(.systemScaled(15, weight: .medium))
                    .foregroundStyle(.primary)
                signalSubtitle(signal)
                    .font(.systemScaled(13))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func signalIcon(_ signal: MutualContextSignal) -> some View {
        switch signal.type {
        case .mutualFollowers:
            Image(systemName: "person.2.fill")
                .font(.systemScaled(14))
                .foregroundStyle(.secondary)
        case .sharedChurch:
            Image(systemName: "building.columns.fill")
                .font(.systemScaled(14))
                .foregroundStyle(.secondary)
        case .sharedInterests:
            Image(systemName: "heart.fill")
                .font(.systemScaled(14))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func signalTitle(_ signal: MutualContextSignal) -> some View {
        switch signal.type {
        case .mutualFollowers(_, let totalCount):
            Text("\(totalCount) Mutual Follower\(totalCount == 1 ? "" : "s")")
        case .sharedChurch:
            Text("Shared Church")
        case .sharedInterests:
            Text("Shared Interests")
        }
    }

    @ViewBuilder
    private func signalSubtitle(_ signal: MutualContextSignal) -> some View {
        switch signal.type {
        case .mutualFollowers(let connections, let totalCount):
            let names = connections.map { $0.displayName }
            let display = names.prefix(3).joined(separator: ", ")
            if totalCount > 3 {
                Text("\(display), and \(totalCount - 3) more")
            } else {
                Text(display)
            }
        case .sharedChurch(let name):
            Text(name)
        case .sharedInterests(let topics):
            Text(topics.joined(separator: ", "))
        }
    }
}
