// AmenLegacySaveToReflectionQueueSheet.swift
// AMENAPP
//
// Bottom sheet for saving media to one of the 7 reflection queues.
// Each queue type has its own row with an icon, title, and subtitle.
//
// Gated:
//   - .prayerQueue row: AMENFeatureFlags.shared.mediaPrayerQueueEnabled
//   - All other rows:   AMENFeatureFlags.shared.mediaReflectionQueueEnabled

import FirebaseAuth
import FirebaseFunctions
import SwiftUI

// MARK: - AmenLegacySaveToReflectionQueueSheet

struct AmenLegacySaveToReflectionQueueSheet: View {

    // MARK: Inputs

    let postId: String
    let mediaId: String
    let mediaTitle: String?
    let onSaved: (AmenMediaQueueType) -> Void
    let onDismiss: () -> Void

    // MARK: State

    /// Tracks which queue (if any) is currently being saved.
    @State private var savingQueue: AmenMediaQueueType? = nil
    /// Tracks which queue saved successfully (shows checkmark).
    @State private var savedQueue: AmenMediaQueueType? = nil
    /// Error displayed below the list when a save fails.
    @State private var errorMessage: String? = nil

    // MARK: Derived — visible queues

    private var visibleQueues: [AmenMediaQueueType] {
        var result: [AmenMediaQueueType] = []
        let reflectionEnabled = AMENFeatureFlags.shared.mediaReflectionQueueEnabled
        let prayerEnabled = AMENFeatureFlags.shared.mediaPrayerQueueEnabled

        for queueType in AmenMediaQueueType.allCases {
            if queueType == .prayerQueue {
                if prayerEnabled { result.append(queueType) }
            } else {
                if reflectionEnabled { result.append(queueType) }
            }
        }
        return result
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Save to…")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { onDismiss() }
                            .accessibilityLabel("Cancel")
                    }
                }
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if visibleQueues.isEmpty {
            emptyState
        } else {
            queueList
        }
    }

    // MARK: Queue List

    private var queueList: some View {
        List {
            if let title = mediaTitle {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .listRowBackground(Color(.secondarySystemBackground))
                }
            }

            Section {
                ForEach(visibleQueues) { queueType in
                    queueRow(queueType)
                }
            }

            if let error = errorMessage {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: Queue Row

    @ViewBuilder
    private func queueRow(_ queueType: AmenMediaQueueType) -> some View {
        let isSaving = savingQueue == queueType
        let isSaved = savedQueue == queueType
        let isAnyBusy = savingQueue != nil

        Button {
            guard !isAnyBusy else { return }
            Task { await save(to: queueType) }
        } label: {
            HStack(spacing: 14) {
                // Icon
                Image(systemName: queueType.systemImage)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: 28, alignment: .center)
                    .accessibilityHidden(true)

                // Title + subtitle
                VStack(alignment: .leading, spacing: 2) {
                    Text(queueType.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(subtitle(for: queueType))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Trailing indicator
                if isSaving {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.secondary)
                        .frame(width: 22, height: 22)
                } else if isSaved {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isAnyBusy)
        .accessibilityLabel("Save to \(queueType.title)")
        .accessibilityHint(subtitle(for: queueType))
        .accessibilityAddTraits(isSaved ? .isSelected : [])
        .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isSaved)
    }

    // MARK: Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "tray.2")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No queues available")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("Reflection queues are not enabled for your account.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: Subtitle Copy

    private func subtitle(for queueType: AmenMediaQueueType) -> String {
        switch queueType {
        case .watchLater:        return "For intentional viewing"
        case .prayerQueue:       return "Revisit during prayer time"
        case .churchNotes:       return "Attach to your church notes"
        case .familyWatch:       return "Share with your family"
        case .selahTonight:      return "Wind down with this tonight"
        case .sermonStudy:       return "Deep-dive study resource"
        case .testimonyArchive:  return "Preserve this testimony"
        }
    }

    // MARK: Save Action

    private func save(to queueType: AmenMediaQueueType) async {
        savingQueue = queueType
        errorMessage = nil

        do {
            _ = try await Functions.functions()
                .httpsCallable("saveToMediaQueue")
                .call([
                    "postId": postId,
                    "mediaId": mediaId,
                    "queueType": queueType.rawValue,
                    "sourceSurface": "detail"
                ])

            AMENAnalyticsService.shared.track(
                .feedMeaningfulInteraction(type: "saved_to_queue")
            )

            withAnimation {
                savingQueue = nil
                savedQueue = queueType
            }

            // Give the user a moment to see the checkmark before delegating
            try? await Task.sleep(for: .seconds(0.5))
            onSaved(queueType)

        } catch {
            savingQueue = nil
            errorMessage = "Could not save to \(queueType.title). Please try again."
        }
    }
}
