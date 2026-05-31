import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - HeyFeedActiveRequestsView

struct HeyFeedActiveRequestsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var service = HeyFeedService.shared
    @State private var selectedType: HeyFeedRequest.HeyFeedRequestType? = nil
    @State private var isRefreshing = false

    private var filteredRequests: [HeyFeedRequest] {
        let active = service.activeRequests.filter { $0.isActive }
        let typed: [HeyFeedRequest]
        if let type = selectedType {
            typed = active.filter { $0.requestType == type }
        } else {
            typed = active
        }
        return typed.sorted { $0.resonanceScore > $1.resonanceScore }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            filterPillsRow
            Divider()
                .opacity(0.4)
                .padding(.top, 4)

            if filteredRequests.isEmpty {
                emptyState
            } else {
                requestList
            }
        }
        .background(Color(.systemGroupedBackground))
        .task {
            service.startListening()
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        VStack(spacing: 2) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .font(.systemScaled(22, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Hey Feed")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            HStack {
                Text("Active community requests")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    // MARK: - Filter Pills Row

    private var filterPillsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterPill(label: "All", icon: "square.grid.2x2", type: nil)
                ForEach(HeyFeedRequest.HeyFeedRequestType.allCases, id: \.self) { type in
                    filterPill(label: type.displayName, icon: type.icon, type: type)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func filterPill(label: String, icon: String, type: HeyFeedRequest.HeyFeedRequestType?) -> some View {
        let isSelected = selectedType == type

        return Button {
            withAnimation(reduceMotion ? nil : Motion.adaptive(.spring(response: 0.38, dampingFraction: 0.72))) {
                selectedType = type
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.systemScaled(12, weight: .medium))
                Text(label)
                    .font(.footnote.weight(.medium))
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Group {
                    if isSelected {
                        Capsule().fill(Color.black)
                    } else {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                            )
                    }
                }
            )
            .shadow(color: .black.opacity(isSelected ? 0.14 : 0.04), radius: isSelected ? 6 : 3, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: isSelected)
    }

    // MARK: - Request List

    private var requestList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredRequests) { request in
                    HeyFeedActiveRequestRow(request: request)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.06))
                    .frame(width: 72, height: 72)
                Image(systemName: "hands.sparkles")
                    .font(.systemScaled(28, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 6) {
                Text("No active requests")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("Be the first to submit one")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - HeyFeedActiveRequestRow

struct HeyFeedActiveRequestRow: View {
    let request: HeyFeedRequest
    @ObservedObject private var service = HeyFeedService.shared
    @State private var showResonanceSheet = false

    private var resonanceCount: Int { request.resonanceCount }
    private var topResonances: [HeyFeedResonanceType] { Array(HeyFeedResonanceType.allCases.prefix(3)) }
    private var isResonating: Bool { service.myResonances.contains(request.postId) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.07), radius: 16, x: 0, y: 6)

            VStack(spacing: 0) {
                mainRow
                Divider()
                    .opacity(0.3)
                    .padding(.horizontal, 14)
                bottomRow
            }
        }
        .confirmationDialog(
            "Add Your Resonance",
            isPresented: $showResonanceSheet,
            titleVisibility: .visible
        ) {
            ForEach(HeyFeedResonanceType.allCases, id: \.self) { resonanceType in
                Button {
                    recordResonance(resonanceType)
                } label: {
                    Label(resonanceType.displayName, systemImage: resonanceType.icon)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Main Row

    private var mainRow: some View {
        HStack(alignment: .top, spacing: 12) {
            typeIconCapsule

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(request.requestType.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    if isResonating {
                        resonatingBadge
                    }

                    Spacer()

                    Text(timeAgo(request.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(intentLabel(for: request.requestType))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                resonanceScoreRow
            }

            resonanceStackIcons
        }
        .padding(14)
    }

    private var typeIconCapsule: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.08))
                .frame(width: 36, height: 36)
            Image(systemName: request.requestType.icon)
                .font(.systemScaled(15, weight: .medium))
                .foregroundStyle(.primary)
        }
    }

    private var resonatingBadge: some View {
        Text("Resonating")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.black)
            )
    }

    private var resonanceScoreRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform")
                .font(.systemScaled(10, weight: .medium))
                .foregroundStyle(.secondary)
            Text("\(resonanceCount) resonances")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            if request.resonanceScore > 0 {
                Text("·")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                Text(String(format: "%.1f score", request.resonanceScore))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.top, 2)
    }

    private var resonanceStackIcons: some View {
        HStack(spacing: -6) {
            ForEach(topResonances, id: \.self) { resonanceType in
                ZStack {
                    Circle()
                        .fill(Color(.systemBackground))
                        .frame(width: 24, height: 24)
                        .shadow(color: .black.opacity(0.06), radius: 2, x: 0, y: 1)
                    Image(systemName: resonanceType.icon)
                        .font(.systemScaled(11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Bottom Row

    private var bottomRow: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(HeyFeedResonanceType.allCases, id: \.self) { resonanceType in
                        resonanceChip(resonanceType)
                    }
                }
                .padding(.horizontal, 14)
            }

            Spacer(minLength: 0)

            resonateButton
                .padding(.trailing, 14)
        }
        .padding(.vertical, 10)
    }

    private func resonanceChip(_ type: HeyFeedResonanceType) -> some View {
        let count = service.resonanceMap[request.postId]?
            .filter { $0.type == type }
            .count ?? 0

        return HStack(spacing: 4) {
            Image(systemName: type.icon)
                .font(.systemScaled(11, weight: .medium))
            if count > 0 {
                Text("\(count)")
                    .font(.caption2.weight(.medium))
            }
        }
        .foregroundStyle(count > 0 ? .primary : .secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(count > 0 ? Color.black.opacity(0.07) : Color.black.opacity(0.03))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                )
        )
    }

    private var resonateButton: some View {
        Button {
            showResonanceSheet = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "hands.sparkles")
                    .font(.systemScaled(12, weight: .medium))
                Text("Resonate")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                    )
            )
            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func intentLabel(for type: HeyFeedRequest.HeyFeedRequestType) -> String {
        switch type {
        case .prayer: return "Prayer Request"
        case .question: return "Question"
        case .fellowship: return "Fellowship"
        case .study: return "Bible Study"
        case .testimony: return "Testimony"
        case .care: return "Care Request"
        }
    }

    private func recordResonance(_ type: HeyFeedResonanceType) {
        Task {
            do {
                try await service.recordResonance(
                    postId: request.postId,
                    requestId: request.id,
                    type: type
                )
            } catch {
                dlog("HeyFeedActiveRequestRow: recordResonance failed — \(error)")
            }
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s/60)m" }
        if s < 86400 { return "\(s/3600)h" }
        return "\(s/86400)d"
    }
}
