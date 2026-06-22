// CreatorTestimonyFeedView.swift
// AMENAPP — Creator Spotlight / Wave 2
//
// Displays approved reflections and Berean theme summary.
// CONSTITUTION LOCK: no sort-by-rating; no score; no numeric rating anywhere.
// Fail-closed: EmptyView when creatorTestimonyEnabled is false.

import SwiftUI

struct CreatorTestimonyFeedView: View {

    @ObservedObject var viewModel: CreatorTestimonyViewModel

    @State private var showingHowGenerated: Bool = false

    var body: some View {
        if !AMENFeatureFlags.shared.creatorTestimonyEnabled {
            EmptyView()
        } else {
            content
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let summary = viewModel.bereanSummary {
                BereanSummaryCard(summary: summary) {
                    showingHowGenerated = true
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)
            }

            if viewModel.testimonies.isEmpty {
                emptyState
            } else {
                reflectionsList
            }
        }
        .sheet(isPresented: $showingHowGenerated) {
            HowGeneratedSheet()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Be the first to share a reflection")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
    }

    // MARK: - Reflections List

    private var reflectionsList: some View {
        LazyVStack(spacing: 10) {
            ForEach(viewModel.testimonies) { reflection in
                ReflectionCard(reflection: reflection)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Berean Summary Card

private struct BereanSummaryCard: View {
    let summary: BereanReflectionSummary
    let onHowGenerated: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.blue)
                Text(summary.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.blue)
                Spacer()
                Text("\(summary.analyzedCount) reflections")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Text(summary.themeSummary)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onHowGenerated) {
                Text("How was this generated?")
                    .font(.system(size: 12))
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
        )
    }
}

// MARK: - Reflection Card

private struct ReflectionCard: View {
    let reflection: CommunityReflection

    private var formattedDate: String {
        let date = Date(timeIntervalSince1970: reflection.submittedAt)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Tags
            if !reflection.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(reflection.tags, id: \.self) { tag in
                            Text(tag.displayLabel)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color(.secondarySystemBackground))
                                )
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }

            // Written reflection
            if let written = reflection.writtenReflection, !written.isEmpty {
                Text(written)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Date
            Text(formattedDate)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 1)
        )
    }
}

// MARK: - How Generated Sheet

private struct HowGeneratedSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Berean reads approved reflections and identifies recurring themes — without storing personal data about who wrote what. It never invents sentiment or assigns numeric ratings.")
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                    Text("Only reflections that have passed human moderation are included in this summary.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .navigationTitle("How summaries work")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - ReflectionTag Display (local)

private extension ReflectionTag {
    var displayLabel: String {
        switch self {
        case .scriptureHelpful:       return "Scripture was helpful"
        case .encouragedDeeperStudy:  return "Encouraged deeper study"
        case .practical:              return "Practical"
        case .goodForGroups:          return "Good for groups"
        case .helpfulForNewBelievers: return "Helpful for new believers"
        case .clear:                  return "Clear teaching"
        }
    }
}
