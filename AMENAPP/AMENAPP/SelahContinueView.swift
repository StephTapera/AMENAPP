import SwiftUI

// MARK: - Selah Continue View
// Next-best-action continuations ranked by the intelligence engine.
// Each card presents a single spiritual action prompt with context.

struct SelahContinueView: View {
    @ObservedObject var service: SelahMediaService
    let contextWindow: SelahContextWindow?

    @Environment(\.colorScheme) private var colorScheme

    @State private var completingId: String?
    @State private var completedNoteTarget: SelahMediaContinuation?
    @State private var showOutcomeSheet = false
    @State private var outcomeNote = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                if let window = contextWindow {
                    contextBanner(window)
                }
                continuationsList
                Spacer(minLength: 40)
            }
        }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Continue")
                .font(.largeTitle.weight(.bold))
            Text("Your next step on this journey")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private func contextBanner(_ window: SelahContextWindow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.systemScaled(14, weight: .medium))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(window.sessionSummary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                if let cat = window.dominantCategory {
                    Text("Dominant theme: \(cat.emoji) \(cat.rawValue)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.20), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 16)
    }

    private var continuationsList: some View {
        LazyVStack(spacing: 14) {
            ForEach(service.continuations) { continuation in
                SelahContinuationCard(
                    continuation: continuation,
                    isCompleting: completingId == continuation.id
                ) {
                    startContinuation(continuation)
                } onComplete: {
                    completedNoteTarget = continuation
                    showOutcomeSheet = true
                }
                .padding(.horizontal, 16)
            }

            if service.continuations.isEmpty {
                emptyState
                    .padding(.horizontal, 16)
            }
        }
        .sheet(isPresented: $showOutcomeSheet, onDismiss: {
            if let target = completedNoteTarget {
                Task {
                    try? await service.completeContinuation(
                        id: target.id ?? "",
                        noteText: outcomeNote.isEmpty ? nil : outcomeNote,
                        scriptureRef: target.scriptureRef
                    )
                    outcomeNote = ""
                    completedNoteTarget = nil
                }
            }
        }) {
            SelahOutcomeSheet(
                continuation: completedNoteTarget,
                note: $outcomeNote
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.forward.circle")
                .font(.systemScaled(48, weight: .ultraLight))
                .foregroundStyle(.secondary)
            Text("All caught up")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Engage with media or Pause mode to generate your next spiritual action.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Actions

    private func startContinuation(_ continuation: SelahMediaContinuation) {
        // Mark as in-progress visually; open outcome sheet on complete
        HapticManager.impact(style: .light)
        completingId = continuation.id
    }
}

// MARK: - Continuation Card

struct SelahContinuationCard: View {
    let continuation: SelahMediaContinuation
    let isCompleting: Bool
    let onStart: () -> Void
    let onComplete: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var accentColor: Color {
        switch continuation.actionEnum {
        case .reflect:  return .purple
        case .pray:     return .blue
        case .share:    return .orange
        case .study:    return .teal
        case .create:   return .pink
        case .journal:  return .green
        case .rest:     return .indigo
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accentColor.opacity(0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: continuation.actionEnum.icon)
                        .font(.systemScaled(18, weight: .medium))
                        .foregroundStyle(accentColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(continuation.actionEnum.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accentColor)
                    Text(continuation.promptText)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !continuation.contextSummary.isEmpty {
                Text(continuation.contextSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let ref = continuation.scriptureRef, !ref.isEmpty {
                Label(ref, systemImage: "book.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.purple)
            }

            HStack(spacing: 10) {
                relevancePips

                Spacer()

                if isCompleting {
                    Button(action: onComplete) {
                        Label("Mark Complete", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(accentColor))
                    }
                } else {
                    Button(action: onStart) {
                        Label("Begin", systemImage: "play.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accentColor)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(accentColor.opacity(0.12)))
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(accentColor.opacity(isCompleting ? 0.4 : 0.10), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.12 : 0.05),
                        radius: 6, y: 2)
        )
        .animation(.easeInOut(duration: 0.2), value: isCompleting)
    }

    private var relevancePips: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .fill(Double(i) / 4.0 < continuation.relevanceScore ? accentColor : accentColor.opacity(0.15))
                    .frame(width: 5, height: 5)
            }
        }
    }
}

// MARK: - Outcome Sheet

struct SelahOutcomeSheet: View {
    let continuation: SelahMediaContinuation?
    @Binding var note: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                if let cont = continuation {
                    HStack(spacing: 12) {
                        Image(systemName: cont.actionEnum.icon)
                            .font(.systemScaled(20))
                            .foregroundStyle(.purple)
                        Text(cont.promptText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("How did it go?")
                        .font(.headline)
                        .padding(.horizontal, 20)
                    TextField("Optional: add a note or insight…", text: $note, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(3...8)
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )
                        .padding(.horizontal, 20)
                }

                Spacer()
            }
            .navigationTitle("Complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
