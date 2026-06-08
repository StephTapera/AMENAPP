// BereanSmartNotesView.swift
// AMEN App — Berean AI-enhanced sermon/study smart notes
//
// Live note-taking with real-time scripture detection via BereanLiveTranscriptService.
// Gated by bereanSmartNotesEnabled feature flag.

import SwiftUI
import FirebaseFunctions

struct BereanSmartNotesView: View {
    @StateObject private var manager = BereanRealtimeSessionManager.shared
    @StateObject private var transcriptService = BereanLiveTranscriptService()
    @ObservedObject private var flags = AMENFeatureFlags.shared

    @State private var noteText = ""
    @State private var detectedScriptures: [BereanScriptureReference] = []
    @State private var isCapturing = false
    @State private var isSaving = false
    @State private var saveSuccess = false
    @State private var errorMessage: String?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let functions = Functions.functions()

    var body: some View {
        if !flags.bereanSmartNotesEnabled {
            ContentUnavailableView("Smart Notes not available", systemImage: "note.text.badge.plus")
        } else {
            content
        }
    }

    // MARK: - Main content

    private var content: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Toolbar row
                captureToggleBar
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                Divider().padding(.horizontal, 18)

                // Note editor
                ZStack(alignment: .topLeading) {
                    if noteText.isEmpty {
                        Text("Start typing your notes…")
                            .foregroundStyle(.tertiary)
                            .font(.body)
                            .padding(.top, 14)
                            .padding(.leading, 22)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $noteText)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 18)
                }
                .frame(maxHeight: .infinity)
                .onChange(of: transcriptService.scriptures) { _, refs in
                    detectedScriptures = refs
                }

                // Scripture chips
                if !detectedScriptures.isEmpty {
                    Divider().padding(.horizontal, 18)
                    scriptureChipsSection
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                }

                Divider()

                // Bottom bar
                bottomBar
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
            }
            .navigationTitle("Smart Notes")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onDisappear { stopCapture() }
    }

    // MARK: - Capture toggle bar

    private var captureToggleBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: isCapturing ? "record.circle.fill" : "record.circle")
                    .foregroundStyle(isCapturing ? .red : .secondary)
                    .font(.system(size: 14, weight: .semibold))
                Text(isCapturing ? "Live Capture On" : "Live Capture Off")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isCapturing ? .red : .secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { isCapturing },
                set: { newVal in
                    if newVal { startCapture() } else { stopCapture() }
                }
            ))
            .labelsHidden()
            .tint(Color.red)
            .disabled(manager.isConnecting)
            .accessibilityLabel(isCapturing ? "Disable live capture" : "Enable live capture")
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isCapturing
                      ? Color.red.opacity(0.07)
                      : Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isCapturing ? Color.red.opacity(0.22) : Color.black.opacity(0.06),
                            lineWidth: 0.8
                        )
                )
        )
        .animation(.easeOut(duration: 0.18), value: isCapturing)
    }

    // MARK: - Scripture chips

    private var scriptureChipsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Detected Scriptures", systemImage: "book.closed")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(detectedScriptures) { ref in
                        scriptureChip(ref)
                    }
                }
            }
        }
    }

    private func scriptureChip(_ ref: BereanScriptureReference) -> some View {
        HStack(spacing: 5) {
            Image(systemName: ref.isUnverified ? "questionmark.circle" : "book.closed.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ref.isUnverified ? .orange : .accentColor)
            Text(ref.reference)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(ref.isUnverified
                      ? Color.orange.opacity(0.10)
                      : Color.accentColor.opacity(0.10))
                .overlay(
                    Capsule()
                        .strokeBorder(
                            ref.isUnverified
                                ? Color.orange.opacity(0.25)
                                : Color.accentColor.opacity(0.22),
                            lineWidth: 0.7
                        )
                )
        )
        .accessibilityLabel(ref.reference + (ref.isUnverified ? ", unverified" : ""))
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if manager.isConnecting {
                ProgressView("Connecting…")
                    .font(.subheadline)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                // Word count chip
                Text("\(noteText.split(separator: " ").count) words")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color(.secondarySystemBackground)))

                Spacer()

                // Save button
                Button(action: saveNotes) {
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: saveSuccess ? "checkmark" : "square.and.arrow.down")
                        }
                        Text(isSaving ? "Saving…" : saveSuccess ? "Saved" : "Save Notes")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(saveSuccess ? Color.green : Color.accentColor)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isSaving || noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(isSaving ? "Saving notes" : "Save notes")
            }
        }
    }

    // MARK: - Session control

    private func startCapture() {
        errorMessage = nil
        Task {
            do {
                let secret = try await manager.createSession(type: .smartNotes)
                transcriptService.start(sessionId: secret.sessionId, language: .english)
                isCapturing = true
            } catch {
                errorMessage = error.localizedDescription
                isCapturing = false
            }
        }
    }

    private func stopCapture() {
        guard isCapturing else { return }
        Task {
            if let sessionId = manager.currentSession?.id {
                await manager.pause(sessionId: sessionId)
            }
            transcriptService.stop()
            isCapturing = false
        }
    }

    private func saveNotes() {
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        errorMessage = nil
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let callable = functions.httpsCallable("saveBereanSmartNotes")
                _ = try await callable.call(["notes": trimmed])
                saveSuccess = true
                // Reset success badge after 2 seconds
                try? await Task.sleep(for: .seconds(2))
                saveSuccess = false
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
