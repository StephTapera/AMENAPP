import SwiftUI

struct FeedHealthDashboardView: View {
    @State private var summary: FeedIntelligenceSummary? = nil
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView().tint(.secondary)
            } else if let summary {
                contentView(summary)
            } else {
                Text("Unable to load feed health.").foregroundStyle(.secondary)
            }
        }
        .task { await loadSummary() }
    }

    private func contentView(_ summary: FeedIntelligenceSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if !summary.boostedTopics.isEmpty {
                topicSection(title: "More of", topics: summary.boostedTopics, isBoost: true)
            }
            if !summary.suppressedTopics.isEmpty {
                topicSection(title: "Less of", topics: summary.suppressedTopics, isBoost: false)
            }
            healthToggles(summary.feedHealth)
        }
    }

    private func topicSection(title: String, topics: [String: Double], isBoost: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            AMENFlowLayout(spacing: 6) {
                ForEach(Array(topics.keys.sorted()), id: \.self) { topic in
                    HStack(spacing: 4) {
                        Image(systemName: isBoost ? "arrow.up" : "arrow.down")
                            .font(.system(size: 9, weight: .bold))
                        Text(topic).font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(isBoost ? .primary : .secondary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color(.secondarySystemBackground), in: Capsule())
                }
            }
        }
    }

    private func healthToggles(_ health: FeedHealthState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Feed health").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if health.reduceOutrage {
                healthRow(icon: "flame.slash", label: "Reducing outrage content")
            }
            if health.preferCalmContent {
                healthRow(icon: "leaf", label: "Preferring calmer content")
            }
            if health.reduceRapidCuts {
                healthRow(icon: "play.slash", label: "Reducing rapid-cut media")
            }
            if health.preserveDiversity {
                healthRow(icon: "circle.grid.2x2", label: "Healthy diversity preserved")
            }
        }
    }

    private func healthRow(icon: String, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.caption).foregroundStyle(.secondary).frame(width: 16)
            Text(label).font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }

    private func loadSummary() async {
        isLoading = true
        summary = try? await AmenFeedDirectionService.shared.getFeedIntelligenceSummary()
        isLoading = false
    }
}
