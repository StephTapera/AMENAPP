import SwiftUI
import FirebaseAnalytics

// MARK: - External Context Sheet (Flow 4)
//
// Shows public discussion clusters and viewpoints.
// NEVER presented as Scripture or Berean-verified doctrine.
// "Compare with Scripture" routes to Berean pipeline.

struct BereanExternalContextSheet: View {
    let query: String
    let onCompareWithScripture: (String) -> Void
    let onAskFollowUp: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var result: BereanExternalContextResult? = nil
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if let result {
                    contentView(result)
                } else {
                    errorView
                }
            }
            .navigationTitle("Public Discussion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(reduceTransparency ? .thickMaterial : .regularMaterial)
        .task { await load() }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView().tint(.secondary)
            Text("Summarizing public discussion…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .accessibilityLabel("Loading external context, please wait")
    }

    // MARK: - Error

    private var errorView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "globe")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Couldn't load external context")
                .font(.headline)
            Text("Ask Berean directly for a Scripture-grounded answer.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Ask Berean") { onCompareWithScripture(query); dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(.black)
            Spacer()
        }
        .padding(24)
    }

    // MARK: - Content

    private func contentView(_ result: BereanExternalContextResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                externalWarningBanner
                summarySection(result)
                viewpointSection(result)
                if !result.cautionNotes.isEmpty { cautionSection(result) }
                scriptureAnglesSection(result)
                actions(result)
            }
            .padding(20)
        }
    }

    // Banner: external context is not Scripture
    private var externalWarningBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "globe")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("External context — not Scripture")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("This summarizes public discussion. It is not a Berean-verified response and does not represent biblical teaching.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func summarySection(_ result: BereanExternalContextResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Public discussion summary")
            Text(result.publicSummary)
                .font(.body)
                .foregroundStyle(.primary)
        }
    }

    private func viewpointSection(_ result: BereanExternalContextResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Common viewpoints")
            ForEach(result.viewpointClusters) { cluster in
                viewpointCard(cluster)
            }
        }
    }

    private func viewpointCard(_ cluster: BereanViewpointCluster) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if cluster.isControversial {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text(cluster.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            Text(cluster.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(cluster.label). \(cluster.summary)")
    }

    private func cautionSection(_ result: BereanExternalContextResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Where Christians may disagree")
            ForEach(result.cautionNotes, id: \.self) { note in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func scriptureAnglesSection(_ result: BereanExternalContextResult) -> some View {
        if result.suggestedScriptureAngles.isEmpty { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Scripture angles to explore")
                FlowLayout(spacing: 8) {
                    ForEach(result.suggestedScriptureAngles, id: \.self) { angle in
                        Text(angle)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.06), in: Capsule())
                    }
                }
            }
        )
    }

    private func actions(_ result: BereanExternalContextResult) -> some View {
        VStack(spacing: 10) {
            Button {
                let prompt = "Compare these public views with what Scripture says: \(result.publicSummary)"
                onCompareWithScripture(prompt)
                Analytics.logEvent("berean_scripture_check_started", parameters: ["source": "external_context"])
                dismiss()
            } label: {
                Label("Compare with Scripture", systemImage: "book.closed")
                    .font(.body.bold())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.black)

            Button {
                onAskFollowUp("Ask Berean a follow-up about: \(query)")
                dismiss()
            } label: {
                Text("Ask Berean a follow-up")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }

    private func load() async {
        isLoading = true
        result = await BereanGrokService.shared.fetchExternalContext(query: query)
        isLoading = false
    }
}
