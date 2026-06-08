// ProvenanceTrustPanel.swift
// AMENAPP
//
// Full provenance and authenticity trust panel.
// Shows media origin, edit history, AI action chain, and authenticity confidence.
// Gated by AMENFeatureFlags.shared.provenanceTrustPanelEnabled.

import SwiftUI

// MARK: - ProvenanceTrustPanel

/// Bottom sheet that explains where a piece of media came from and what AI did (if anything).
struct ProvenanceTrustPanel: View {
    let provenance: MediaProvenance?
    let aiDisclosures: [AIDisclosureRecord]
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab: Tab = .authenticity
    @State private var showReport = false

    enum Tab: String, CaseIterable {
        case authenticity = "Authenticity"
        case origin       = "Origin"
        case aiHistory    = "AI History"
    }

    var body: some View {
        VStack(spacing: 0) {
            handle
            headerSection
            tabPicker
                .padding(.top, 12)

            Divider().padding(.top, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    switch selectedTab {
                    case .authenticity: authenticitySection
                    case .origin:       originSection
                    case .aiHistory:    aiHistorySection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 20, y: -4)
        .sheet(isPresented: $showReport) {
            AmenReportContentSheet(
                contentType: "media",
                contentId: provenance?.mediaId ?? provenance?.postId ?? "",
                covenantId: nil
            )
        }
    }

    // MARK: Handle

    private var handle: some View {
        Capsule()
            .fill(Color(.tertiarySystemFill))
            .frame(width: 36, height: 4)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    // MARK: Header

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Media Origin")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("Understand where this came from and what AI did")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
            }
            .accessibilityLabel("Close provenance panel")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: Tab Picker

    private var tabPicker: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.82)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            selectedTab == tab
                                ? Color(.secondarySystemFill)
                                : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: Authenticity Section

    private var authenticitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let provenance {
                // Confidence bar
                ProvenanceConfidenceRow(confidence: provenance.authenticityConfidence)

                // Authenticity labels
                let labels = AuthenticityLabel.labels(for: provenance)
                ForEach(labels) { label in
                    ProvenanceLabelRow(label: label)
                }

                // Synthetic risk warning
                if provenance.syntheticMediaStatus == .deepfakeRisk {
                    ProvenanceSafetyWarningCard()
                }

                // Disclosure status
                if provenance.disclosureRequired && !provenance.disclosureSatisfied {
                    ProvenanceDisclosureRequiredCard()
                }
            } else {
                ProvenanceUnavailableCard(reason: "Authenticity data is not available for this media.")
            }

            reportButton
        }
    }

    // MARK: Origin Section

    private var originSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let provenance {
                ProvenanceMetadataCard(provenance: provenance)
                ProvenanceEditChain(editEvents: provenance.editEvents)
            } else {
                ProvenanceUnavailableCard(reason: "Origin information is not available for this media.")
            }
        }
    }

    // MARK: AI History Section

    private var aiHistorySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if aiDisclosures.isEmpty && (provenance?.aiEvents.isEmpty ?? true) {
                ProvenanceUnavailableCard(reason: "No AI assistance was recorded for this media.")
            } else {
                Text("AI was involved in the following ways:")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ForEach(aiDisclosures) { disclosure in
                    AIDisclosureRow(disclosure: disclosure)
                }

                // Raw AI events from provenance
                if let events = provenance?.aiEvents, !events.isEmpty {
                    ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                        AIEventRow(event: event)
                    }
                }

                ProvenanceAIDisclaimer()
            }
        }
    }

    // MARK: Report Button

    private var reportButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showReport = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "flag.fill")
                    .font(.footnote)
                Text("Report authenticity concern")
                    .font(.footnote.weight(.medium))
            }
            .foregroundStyle(.secondary)
            .padding(.top, 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Report an authenticity concern about this media")
    }
}

// MARK: - Provenance Confidence Row

private struct ProvenanceConfidenceRow: View {
    let confidence: Double  // 0–1

    private var color: Color {
        if confidence >= 0.8 { return .green }
        if confidence >= 0.5 { return .orange }
        return .red
    }

    private var label: String {
        if confidence >= 0.8 { return "High confidence" }
        if confidence >= 0.5 { return "Moderate confidence" }
        return "Low confidence"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Authenticity confidence")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(Int(confidence * 100))%")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.tertiarySystemFill))
                        .frame(height: 6)
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * confidence, height: 6)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: confidence)
                }
            }
            .frame(height: 6)

            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Authenticity confidence: \(Int(confidence * 100)) percent. \(label).")
    }
}

// MARK: - Provenance Label Row

private struct ProvenanceLabelRow: View {
    let label: AuthenticityLabel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: label.systemIcon)
                .font(.systemScaled(16, weight: .semibold))
                .foregroundStyle(label.kind == .syntheticWarning ? .orange : .green)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(label.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(label.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Provenance Metadata Card

private struct ProvenanceMetadataCard: View {
    let provenance: MediaProvenance

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            metaRow("Source", value: provenance.sourceType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized, icon: "square.and.arrow.up.fill")
            if let createdAt = provenance.createdAt {
                metaRow("Uploaded", value: createdAt.formatted(date: .abbreviated, time: .shortened), icon: "calendar")
            }
            metaRow("Credentials", value: provenance.contentCredentialsStatus.rawValue.replacingOccurrences(of: "_", with: " ").capitalized, icon: "checkmark.shield.fill")
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func metaRow(_ label: String, value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.systemScaled(13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Edit Chain

private struct ProvenanceEditChain: View {
    let editEvents: [ProvenanceEditEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Edit history")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            if editEvents.isEmpty {
                Text("No edits recorded.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(editEvents.enumerated()), id: \.offset) { _, event in
                    HStack(spacing: 10) {
                        Image(systemName: event.aiAssisted ? "wand.and.stars" : "pencil")
                            .font(.systemScaled(12))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.editType.capitalized)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        if event.aiAssisted {
                            Text("AI-assisted")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.blue.opacity(0.1), in: Capsule())
                        }
                    }
                    if editEvents.indices.contains(editEvents.firstIndex(where: { $0.timestamp == event.timestamp })! + 1) {
                        Divider().padding(.leading, 30)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - AI Disclosure Row

private struct AIDisclosureRow: View {
    let disclosure: AIDisclosureRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)
                Text(disclosure.userVisibleLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if !disclosure.modelProvider.isEmpty {
                    Text(disclosure.modelProvider)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Text(disclosure.userVisibleExplanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - AI Event Row

private struct AIEventRow: View {
    let event: ProvenanceAIEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.userApproved ? "checkmark.circle.fill" : "clock.fill")
                .font(.systemScaled(14))
                .foregroundStyle(event.userApproved ? .green : .orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.purpose.capitalized)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)
                Text(event.userApproved ? "Approved by creator" : "Pending approval")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Supporting Info Cards

private struct ProvenanceUnavailableCard: View {
    let reason: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "questionmark.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(reason)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ProvenanceSafetyWarningCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Synthetic media risk detected")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("This media may have been synthetically altered. Review carefully before sharing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 0.8)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Warning: Synthetic media risk detected. This media may have been synthetically altered.")
    }
}

private struct ProvenanceDisclosureRequiredCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.title2)
                .foregroundStyle(.blue)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Disclosure required")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("This media requires an AI disclosure label that has not yet been confirmed by the creator.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ProvenanceAIDisclaimer: View {
    var body: some View {
        Text("AI disclosure information is recorded server-side and cannot be modified by users after creation. Labels are determined by Amen's trust system, not by the creator.")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.top, 8)
    }
}

// MARK: - Convenience Sheet Modifier

extension View {
    /// Presents ProvenanceTrustPanel as a sheet when `isPresented` is true.
    func provenanceTrustSheet(
        isPresented: Binding<Bool>,
        provenance: MediaProvenance?,
        aiDisclosures: [AIDisclosureRecord] = []
    ) -> some View {
        self.sheet(isPresented: isPresented) {
            ProvenanceTrustPanel(
                provenance: provenance,
                aiDisclosures: aiDisclosures,
                onDismiss: { isPresented.wrappedValue = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(24)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Provenance Panel — Real Media") {
    ProvenanceTrustPanel(
        provenance: MediaProvenance(
            id: "prov_001",
            postId: "post_001",
            mediaId: "media_001",
            ownerUid: "uid_001",
            capturedOnDevice: true,
            sourceType: .deviceCamera,
            uploadedAt: Date(),
            editEvents: [
                .init(editType: "color_grade", tool: "Photos", aiAssisted: false, timestamp: Date()),
            ],
            aiEvents: [
                .init(actionType: "alt_text_generation", provider: "Amen AI", purpose: "Accessibility description", userApproved: true, timestamp: Date()),
            ],
            authenticityConfidence: 0.92,
            contentCredentialsStatus: .verified,
            syntheticMediaStatus: .clean,
            disclosureRequired: false,
            disclosureSatisfied: true,
            moderationStatus: "approved"
        ),
        aiDisclosures: [
            .init(
                id: "disc_001",
                postId: "post_001",
                mediaId: "media_001",
                ownerUid: "uid_001",
                actionType: "alt_text_generation",
                modelProvider: "Amen AI",
                purpose: "Accessibility alt text",
                userVisibleLabel: "Alt Text Assisted",
                userVisibleExplanation: "Amen AI helped create accessibility text for this media.",
                confidence: 0.96
            )
        ],
        onDismiss: {}
    )
}
#endif
