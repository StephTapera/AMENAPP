import SwiftUI

struct ScriptureDriftInsightCard: View {
    let signal: ScriptureDriftSignal
    @StateObject private var service = ScriptureDriftService.shared
    @State private var showDetail = false
    @State private var balancingScriptures: [String] = []
    @State private var isLoadingScriptures = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "book.closed")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Possible Pattern")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.secondary)
                    Text(signal.signalType.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                }
                Spacer()
                confidencePill
            }

            Text(signal.signalType.gentleDescription)
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if showDetail {
                if !balancingScriptures.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Scriptures to consider")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.secondary)
                        ForEach(balancingScriptures, id: \.self) { ref in
                            Text(ref)
                                .font(.subheadline)
                                .foregroundStyle(Color.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            HStack(spacing: 10) {
                Button(action: {
                    withAnimation(.spring(response: 0.35)) { showDetail.toggle() }
                    if showDetail && balancingScriptures.isEmpty {
                        Task { await loadBalancingScriptures() }
                    }
                }) {
                    Text(showDetail ? "Show less" : "See balancing scriptures")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .accessibilityLabel(showDetail ? "Show less" : "See balancing scriptures for this pattern")

                Spacer()

                Button(action: { Task { await service.dismissSignal(signal) } }) {
                    Text("Dismiss")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                .accessibilityLabel("Dismiss this scripture pattern signal")
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var confidencePill: some View {
        let pct = Int(signal.confidence * 100)
        return Text("\(pct)% confidence")
            .font(.caption2)
            .foregroundStyle(Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.1), in: Capsule())
    }

    private func loadBalancingScriptures() async {
        isLoadingScriptures = true
        balancingScriptures = await service.generateBalancingScripture(for: signal)
        isLoadingScriptures = false
    }
}

// MARK: - Balance Sheet

struct BalanceWithScriptureSheet: View {
    let signal: ScriptureDriftSignal
    @Environment(\.dismiss) private var dismiss
    @State private var balancingScriptures: [String] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(signal.signalType.gentleDescription)
                        .font(.body)
                        .foregroundStyle(Color.secondary)
                        .padding(.horizontal, 20)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Balancing Scriptures")
                            .font(.headline)
                            .padding(.horizontal, 20)

                        ForEach(balancingScriptures, id: \.self) { ref in
                            Text(ref)
                                .font(.body)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                                .padding(.horizontal, 20)
                        }

                        if balancingScriptures.isEmpty {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                }
                .padding(.top, 20)
            }
            .navigationTitle("Balance in Scripture")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
