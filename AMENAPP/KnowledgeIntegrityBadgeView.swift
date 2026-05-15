import SwiftUI

struct KnowledgeIntegrityBadgeView: View {
    let badge: KnowledgeIntegrityBadge
    let summary: String

    @State private var showDetail = false

    var body: some View {
        if badge != .none {
            Button {
                showDetail = true
            } label: {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.82))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.05), in: Capsule())
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showDetail) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(title)
                            .font(.system(size: 22, weight: .semibold))
                        Text(summary)
                            .font(.system(size: 15))
                        Spacer()
                    }
                    .padding(20)
                    .navigationTitle("Context")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
    }

    private var title: String {
        switch badge {
        case .none: return ""
        case .bereanVerified: return "Berean Verified"
        case .contextCheck: return "Context Check"
        case .needsDiscernment: return "Needs Discernment"
        case .heldForReview: return "Held for Review"
        }
    }
}

struct KnowledgeIntegrityBadgeLoaderView: View {
    let targetType: String
    let targetId: String

    @State private var record: SharedKnowledgeIntegrityRecord?

    var body: some View {
        Group {
            if let record {
                KnowledgeIntegrityBadgeView(badge: record.badge, summary: record.userVisibleSummary)
            }
        }
        .task(id: targetId) {
            record = await BiblicalAlignmentService.shared.fetchIntegrityRecord(targetType: targetType, targetId: targetId)
        }
    }
}
