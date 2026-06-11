// AmenExportView.swift
// AMEN Universal Migration & Context System — Wave 5 (export-engineer)
//
// The canonical UI for .amen v0.1 portable file export and import.
//
// CONTRACT COMPLIANCE
// ────────────────────
//   • Flag-gated on `contextSystemEnabled && contextExportEnabled`.
//   • Visibility-filtered facet list: Tier-P facets never shown / never included.
//   • Public facets pre-selected; all others explicit opt-in only.
//   • Export calls AmenExportService (never directly touches the CF layer).
//   • Import path: `.amen` JSON → AmenExportService.importFile → FacetApprovalView.
//   • Approval before persistence: imported facets always route through FacetApprovalView.
//   • GlassKit only (AmenLiquidGlassPillButton + .ultraThinMaterial surfaces).
//   • All animation via Motion.adaptive — reduce-motion safe.
//   • Reverse-trust copy: "Your context is yours. Export it anytime, take it anywhere."
//
// IMPORTANT: OperatingManualView.swift and LifeCapsuleView.swift already exist — do not modify.

import SwiftUI
import FirebaseAuth

// MARK: - AmenExportView

struct AmenExportView: View {

    // MARK: Dependencies

    @StateObject private var flags    = AMENFeatureFlags.shared
    @StateObject private var service  = AmenExportService.shared
    @StateObject private var store    = ContextStoreService.shared

    // MARK: Export state

    /// Facets eligible for inclusion (non-Tier-P only).
    @State private var eligibleFacets: [ContextFacet] = []
    /// IDs of facets the user has explicitly opted in. Public-visibility facets start pre-checked.
    @State private var selectedIds: Set<UUID> = []

    // MARK: Share sheet state
    @State private var shareItems: [Any] = []
    @State private var showingShareSheet = false
    @State private var exportResult: (amenJSON: String, signature: String)? = nil

    // MARK: Import state
    @State private var showingFilePicker = false
    @State private var importCandidates: [ContextFacet] = []
    @State private var showingApprovalForImport = false
    @State private var importOwner: String? = nil
    @State private var importVerified: Bool = false

    // MARK: UI state
    @State private var showExportSuccess = false
    @State private var confirmExportAlert = false

    var body: some View {
        Group {
            if flags.contextSystemEnabled && flags.contextExportEnabled {
                content
            } else {
                ContextUnavailableNotice()
            }
        }
        .navigationTitle("Export & Import")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadEligibleFacets() }
        .sheet(isPresented: $showingShareSheet) {
            if let result = exportResult {
                AmenExportShareSheet(amenJSON: result.amenJSON, signature: result.signature)
            }
        }
        .sheet(isPresented: $showingApprovalForImport) {
            NavigationStack {
                FacetApprovalView(candidates: $importCandidates)
                    .navigationTitle("Review imported context")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showingApprovalForImport = false }
                        }
                    }
            }
        }
    }

    // MARK: - Main content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                trustHeader
                exportSection
                importSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
    }

    // MARK: - Trust header

    private var trustHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "lock.doc")
                    .font(.title2)
                    .foregroundStyle(.primary)
                Text("Your context is yours.")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Text("Your context is yours. Export it anytime, take it anywhere.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Your exported file includes only the facets you select — never your messages, posts, photos, or private (Tier-P) data.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(glassSurface(cornerRadius: AmenGlassMetrics.cornerRadiusLarge))
    }

    // MARK: - Export section

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("Export your context", symbol: "square.and.arrow.up")

            if eligibleFacets.isEmpty {
                emptyFacetsNotice
            } else {
                facetSelectionList
                exportActionRow
            }

            if let err = service.lastExportError {
                errorBanner(err)
            }

            if showExportSuccess {
                successBanner("Export complete. Your .amen file is ready to share.")
            }
        }
    }

    // MARK: - Facet selection list

    private var facetSelectionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Choose what to include")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Select all") { selectAll() }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                Text("·").foregroundStyle(.tertiary)
                Button("Deselect all") { deselectAll() }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
            }

            Text("Public facets are pre-selected. Others require your explicit opt-in.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            VStack(spacing: 6) {
                ForEach(orderedEligibleCategories, id: \.self) { category in
                    categoryExportSection(category)
                }
            }
        }
        .padding(16)
        .background(glassSurface(cornerRadius: AmenGlassMetrics.cornerRadiusMedium))
    }

    @ViewBuilder
    private func categoryExportSection(_ category: FacetCategory) -> some View {
        let items = eligibleFacets.filter { $0.category == category }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName(category).uppercased())
                    .font(.caption2.weight(.bold))
                    .kerning(0.6)
                    .foregroundStyle(.secondary)

                ForEach(items) { facet in
                    facetExportRow(facet)
                }
            }
        }
    }

    private func facetExportRow(_ facet: ContextFacet) -> some View {
        HStack(spacing: 10) {
            // Checkbox
            Image(systemName: selectedIds.contains(facet.id) ? "checkmark.circle.fill" : "circle")
                .font(.body)
                .foregroundStyle(selectedIds.contains(facet.id) ? Color.accentColor : Color.secondary)
                .animation(Motion.adaptive(Motion.popToggle), value: selectedIds.contains(facet.id))
                .onTapGesture { toggleSelection(facet) }
                .accessibilityLabel(selectedIds.contains(facet.id) ? "Deselect \(facet.label)" : "Select \(facet.label)")

            VStack(alignment: .leading, spacing: 2) {
                Text(facet.label)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Text(facet.value.displaySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // Visibility badge
            visibilityBadge(facet.visibility)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { toggleSelection(facet) }
    }

    private func visibilityBadge(_ visibility: Visibility) -> some View {
        Text(visibilityLabel(visibility))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(visibility == .publicVisibility ? Color.green : Color.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(visibility == .publicVisibility
                          ? Color.green.opacity(0.12)
                          : Color(.secondarySystemBackground))
            )
    }

    // MARK: - Export action row

    private var exportActionRow: some View {
        HStack(spacing: 10) {
            AmenLiquidGlassPillButton(
                title: service.isExporting ? "Exporting…" : "Export (\(selectedIds.count))",
                systemImage: "square.and.arrow.up",
                isLoading: service.isExporting,
                isDisabled: selectedIds.isEmpty || service.isExporting
            ) {
                confirmExportAlert = true
            }
        }
        .alert("Export your context?", isPresented: $confirmExportAlert) {
            Button("Export", role: .none) { performExport() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will build a portable .amen file with \(selectedIds.count) context item\(selectedIds.count == 1 ? "" : "s"). Private (Tier-P) data is never included.")
        }
    }

    // MARK: - Import section

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("Import from an .amen file", symbol: "square.and.arrow.down")

            Text("Import a .amen file from another AMEN account or a compatible app. All imported items go through your approval queue — nothing is saved until you review it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            AmenLiquidGlassPillButton(
                title: service.isImporting ? "Importing…" : "Open .amen file",
                systemImage: "doc.badge.plus",
                isLoading: service.isImporting,
                isDisabled: service.isImporting
            ) {
                showingFilePicker = true
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.json],    // .amen files are JSON; no custom UTI yet
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }

            if let err = service.lastImportError {
                errorBanner(err)
            }

            if !importCandidates.isEmpty {
                importReadyBanner
            }
        }
        .padding(16)
        .background(glassSurface(cornerRadius: AmenGlassMetrics.cornerRadiusMedium))
    }

    private var importReadyBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: importVerified ? "checkmark.seal.fill" : "exclamationmark.triangle")
                    .foregroundStyle(importVerified ? .green : .orange)
                Text(importVerified ? "Signature verified" : "Unverified file")
                    .font(.subheadline.weight(.semibold))
            }
            if let owner = importOwner {
                Text("From: \(owner)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(importCandidates.count) item\(importCandidates.count == 1 ? "" : "s") ready for review. Nothing is saved until you approve each one.")
                .font(.caption)
                .foregroundStyle(.secondary)

            AmenLiquidGlassPillButton(
                title: "Review \(importCandidates.count) item\(importCandidates.count == 1 ? "" : "s")",
                systemImage: "checkmark.circle",
                isLoading: false,
                isDisabled: false
            ) {
                withAnimation(Motion.adaptive(Motion.springRelease)) {
                    showingApprovalForImport = true
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AmenGlassMetrics.cornerRadiusMedium, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: AmenGlassMetrics.cornerRadiusMedium, style: .continuous)
                        .stroke(importVerified ? Color.green.opacity(0.25) : Color.orange.opacity(0.25), lineWidth: 0.8)
                )
        )
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .animation(Motion.adaptive(Motion.popToggle), value: importCandidates.isEmpty)
    }

    // MARK: - Empty notice

    private var emptyFacetsNotice: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No context items yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Add context items in Identity Blueprint or via the Universal Import, then come back to export them.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Small reusable pieces

    private func sectionLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.headline)
            .foregroundStyle(.primary)
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.caption)
            .foregroundStyle(.red)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.red.opacity(0.08))
            )
            .transition(.opacity)
    }

    private func successBanner(_ message: String) -> some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.caption)
            .foregroundStyle(.green)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.green.opacity(0.08))
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    private func glassSurface(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: AmenGlassMetrics.borderWidth)
            )
            .shadow(color: .black.opacity(0.06), radius: AmenGlassMetrics.shadowRadius, y: 4)
    }

    // MARK: - Actions

    private func loadEligibleFacets() {
        Task {
            // Load from the shared ContextStoreService cache (non-Tier-P only).
            if store.facets.isEmpty {
                try? await store.loadFacets()
            }
            let all = store.facets.filter { $0.tier != .p }
            withAnimation(Motion.adaptive(Motion.appearEase)) {
                eligibleFacets = all
                // Pre-select public-visibility facets.
                selectedIds = Set(all.filter { $0.visibility == .publicVisibility }.map { $0.id })
            }
        }
    }

    private func toggleSelection(_ facet: ContextFacet) {
        withAnimation(Motion.adaptive(Motion.popToggle)) {
            if selectedIds.contains(facet.id) {
                selectedIds.remove(facet.id)
            } else {
                selectedIds.insert(facet.id)
            }
        }
    }

    private func selectAll() {
        withAnimation(Motion.adaptive(Motion.springRelease)) {
            selectedIds = Set(eligibleFacets.map { $0.id })
        }
    }

    private func deselectAll() {
        withAnimation(Motion.adaptive(Motion.unpopToggle)) {
            selectedIds.removeAll()
        }
    }

    private func performExport() {
        Task {
            do {
                let result = try await service.export(selectedFacetIds: Array(selectedIds))
                exportResult = result
                withAnimation(Motion.adaptive(Motion.popToggle)) {
                    showExportSuccess = true
                    showingShareSheet = true
                }
            } catch {
                // lastExportError is set on the service; errorBanner renders it.
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        Task {
            switch result {
            case .failure:
                return
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    let jsonString: String
                    // Security-scoped resource access (required for file picker results).
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    jsonString = try String(contentsOf: url, encoding: .utf8)

                    let importResult = try await service.importFile(jsonString)
                    withAnimation(Motion.adaptive(Motion.springRelease)) {
                        importCandidates = importResult.proposed
                        importVerified   = importResult.signatureVerified
                        importOwner      = importResult.ownerUserId.isEmpty ? nil : importResult.ownerUserId
                    }
                } catch {
                    // lastImportError is set on the service; errorBanner renders it.
                }
            }
        }
    }

    // MARK: - Helpers

    private var orderedEligibleCategories: [FacetCategory] {
        FacetCategory.allCases.filter { cat in eligibleFacets.contains { $0.category == cat } }
    }

    private func displayName(_ category: FacetCategory) -> String {
        switch category {
        case .interests:      return "Interests"
        case .values:         return "Values"
        case .goals:          return "Goals"
        case .skills:         return "Skills"
        case .communities:    return "Communities"
        case .relationships:  return "Relationships"
        case .communication:  return "Communication"
        case .learning:       return "Learning"
        case .faith_journey:  return "Faith journey"
        case .current_focus:  return "Current focus"
        case .family:         return "Family"
        case .work:           return "Work"
        case .health:         return "Health"
        }
    }

    private func visibilityLabel(_ visibility: Visibility) -> String {
        switch visibility {
        case .publicVisibility:   return "Public"
        case .friends:            return "Friends"
        case .groups:             return "Groups"
        case .church:             return "Church"
        case .privateVisibility:  return "Private"
        }
    }
}

// MARK: - AmenExportShareSheet

/// Wraps UIActivityViewController to share the .amen file as an attachment.
/// Presented as a sheet from AmenExportView when the export is complete.
struct AmenExportShareSheet: UIViewControllerRepresentable {
    let amenJSON: String
    let signature: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        // Build the shareable items:
        //   1. The .amen JSON file (named amen-context.amen)
        //   2. The signature as a plain-text companion (named amen-context.sig)
        var items: [Any] = []

        if let jsonData = amenJSON.data(using: .utf8) {
            let tmpDir = FileManager.default.temporaryDirectory
            let jsonURL = tmpDir.appendingPathComponent("amen-context.amen")
            if (try? jsonData.write(to: jsonURL)) != nil {
                items.append(jsonURL)
            } else {
                items.append(amenJSON)  // fallback: share raw string
            }
        }

        if !signature.isEmpty {
            items.append("Signature: \(signature)")
        }

        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
