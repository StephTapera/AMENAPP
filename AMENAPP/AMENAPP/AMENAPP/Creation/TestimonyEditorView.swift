// TestimonyEditorView.swift
// AMEN App — Three-panel guided testimony editor
//
// Presents a three-panel guided editor for testimonies:
//   Panel 1 (Before): What was life like before?
//   Panel 2 (Encounter): What happened? How did God move?
//   Panel 3 (After): How has life changed?
//
// C2PA provenance manifest is non-negotiable — publish is blocked until
// TestimonyPublishService.prepareManifest() returns a valid manifestRef.
//
// SelahMoment fires on publish: testimonies are vulnerable content.
//
// Flag-gated: AMENFeatureFlags.shared.testimonies

import SwiftUI

struct TestimonyEditorView: View {

    // MARK: - Flag gate

    @ObservedObject private var flags = AMENFeatureFlags.shared

    var body: some View {
        if !flags.testimonies {
            EmptyView()
        } else {
            TestimonyEditorContent()
        }
    }
}

// MARK: - Main content (only built when flag is ON)

@MainActor
private struct TestimonyEditorContent: View {

    // MARK: - State

    @State private var currentPanel: Int = 0   // 0, 1, 2

    // Panel content
    @State private var beforeText: String = ""
    @State private var beforeMediaRef: String? = nil
    @State private var encounterText: String = ""
    @State private var encounterMediaRef: String? = nil
    @State private var afterText: String = ""
    @State private var afterMediaRef: String? = nil

    // Publish state
    @State private var manifestRef: String? = nil
    @State private var isPreparingManifest: Bool = false
    @State private var isPublishing: Bool = false
    @State private var publishError: String? = nil
    @State private var publishSuccess: Bool = false
    @State private var showMediaPicker: Bool = false

    @StateObject private var publishService = TestimonyPublishService()
    @StateObject private var selahService = SelahMomentService()

    @Environment(\.dismiss) private var dismiss

    // MARK: - Computed

    private var allSectionsHaveContent: Bool {
        !beforeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !encounterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !afterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var currentPanelHasContent: Bool {
        switch currentPanel {
        case 0: return !beforeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 1: return !encounterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 2: return !afterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: return false
        }
    }

    private var panelTitles: [String] {
        ["Before", "Encounter", "After"]
    }

    private var panelPrompts: [String] {
        [
            "What was life like before?",
            "What happened? How did God move?",
            "How has life changed?"
        ]
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressDots
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                panelView
                    .animation(.easeInOut(duration: 0.3), value: currentPanel)

                Spacer()

                bottomActions
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
            }
            .navigationTitle("Your Testimony")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { publishError != nil },
                set: { if !$0 { publishError = nil } }
            )) {
                Button("OK", role: .cancel) { publishError = nil }
            } message: {
                Text(publishError ?? "")
            }
        }
        .selahMoment(trigger: selahService.isActive)
    }

    // MARK: - Progress dots (no numbers — no gamification)

    private var progressDots: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index == currentPanel ? Color.primary : Color.secondary.opacity(0.3))
                    .frame(width: index == currentPanel ? 10 : 8,
                           height: index == currentPanel ? 10 : 8)
                    .animation(.spring(response: 0.3), value: currentPanel)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(currentPanel + 1) of 3")
    }

    // MARK: - Panel

    @ViewBuilder
    private var panelView: some View {
        switch currentPanel {
        case 0:
            testimonyPanel(
                prompt: panelPrompts[0],
                text: $beforeText,
                mediaRef: $beforeMediaRef,
                panelIndex: 0
            )
        case 1:
            testimonyPanel(
                prompt: panelPrompts[1],
                text: $encounterText,
                mediaRef: $encounterMediaRef,
                panelIndex: 1
            )
        default:
            testimonyPanel(
                prompt: panelPrompts[2],
                text: $afterText,
                mediaRef: $afterMediaRef,
                panelIndex: 2
            )
        }
    }

    private func testimonyPanel(
        prompt: String,
        text: Binding<String>,
        mediaRef: Binding<String?>,
        panelIndex: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(prompt)
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 20)

            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text("Share what's on your heart…")
                        .foregroundStyle(.tertiary)
                        .font(.body)
                        .padding(.top, 12)
                        .padding(.leading, 20)
                        .allowsHitTesting(false)
                }
                TextEditor(text: text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 180)
                    .padding(.horizontal, 16)
            }

            if let ref = mediaRef.wrappedValue {
                HStack(spacing: 8) {
                    Image(systemName: "paperclip")
                        .foregroundStyle(.secondary)
                    Text(ref)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        mediaRef.wrappedValue = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Remove attached media")
                }
                .padding(.horizontal, 20)
            } else {
                Button {
                    showMediaPicker = true
                } label: {
                    Label("Attach media (optional)", systemImage: "photo.badge.plus")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
            }
        }
        .id(panelIndex)
    }

    // MARK: - Bottom actions

    @ViewBuilder
    private var bottomActions: some View {
        if currentPanel < 2 {
            // Navigation between panels
            HStack {
                if currentPanel > 0 {
                    Button("Back") {
                        withAnimation { currentPanel -= 1 }
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
                Button("Continue") {
                    withAnimation { currentPanel += 1 }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!currentPanelHasContent)
            }
        } else {
            // Final panel — prepare manifest and publish
            VStack(spacing: 12) {
                HStack {
                    Button("Back") {
                        withAnimation { currentPanel -= 1 }
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }

                if isPreparingManifest {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Preparing your testimony's provenance record…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                } else if let ref = manifestRef {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text("Provenance record ready")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    Button {
                        Task { await publishTestimony(manifestRef: ref) }
                    } label: {
                        if isPublishing {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Publishing…")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Text("Publish")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isPublishing)
                } else {
                    Button {
                        Task { await prepareManifest() }
                    } label: {
                        Text("Prepare to Publish")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!allSectionsHaveContent)
                }
            }
        }
    }

    // MARK: - Actions

    private func prepareManifest() async {
        isPreparingManifest = true
        defer { isPreparingManifest = false }

        let testimony = buildTestimony(manifestRef: "")
        do {
            let ref = try await publishService.prepareManifest(for: testimony)
            manifestRef = ref
        } catch {
            publishError = error.localizedDescription
        }
    }

    private func publishTestimony(manifestRef: String) async {
        isPublishing = true
        defer { isPublishing = false }

        var testimony = buildTestimony(manifestRef: manifestRef)
        do {
            try await publishService.publish(testimony)
            selahService.trigger()
            dismiss()
        } catch {
            publishError = error.localizedDescription
        }
    }

    private func buildTestimony(manifestRef: String) -> CreationTestimony {
        CreationTestimony(
            id: UUID().uuidString,
            authorUid: "",   // resolved at publish layer from Auth.currentUser
            before: TestimonySection(richText: beforeText, mediaRef: beforeMediaRef),
            encounter: TestimonySection(richText: encounterText, mediaRef: encounterMediaRef),
            after: TestimonySection(richText: afterText, mediaRef: afterMediaRef),
            c2paManifestRef: manifestRef,
            visibility: .connections,
            createdAt: Date()
        )
    }
}

// selahMoment(trigger:) is defined canonically in BreathMotion.swift; removed local duplicate.
