import SwiftUI

// MARK: - TextRewriteView
//
// Inline "Rewrite Instead" panel shown when a user's text is blocked by moderation.
// Presents AI-generated alternative phrasings so users can express themselves
// constructively rather than being hard-blocked.
//
// Usage:
//   TextRewriteView(
//     blockedText: $draftText,
//     harmCategoryId: result.harmCategoryId ?? "harassment",
//     contentType: "post"
//   ) { accepted in
//     if accepted { submitPost() }
//   }

struct TextRewriteView: View {
    @Binding var blockedText: String
    let harmCategoryId: String
    let contentType: String
    let onDecision: (Bool) -> Void  // true = accepted a suggestion, false = cancelled

    @State private var suggestions: [String] = []
    @State private var rationale: String = ""
    @State private var isLoading = false
    @State private var selectedSuggestion: String? = nil
    @State private var loadError: String? = nil

    private let safety = AmenSafetyOSClientService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection
            if isLoading {
                loadingSection
            } else if let error = loadError {
                errorSection(error)
            } else if suggestions.isEmpty {
                emptySection
            } else {
                rationaleSection
                suggestionsSection
                actionButtons
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .task { await loadSuggestions() }
    }

    // MARK: - Sections

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "pencil.and.sparkles")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text("Try a Different Approach")
                    .font(.headline)
                Text("This message needs some adjustments. Here are a few ways to express it differently.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var loadingSection: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Finding better ways to say this…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private func errorSection(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Try Again") {
                Task { await loadSuggestions() }
            }
            .buttonStyle(.bordered)
        }
    }

    private var emptySection: some View {
        VStack(spacing: 12) {
            Text("No suggestions available right now.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Cancel") { onDecision(false) }
                .buttonStyle(.bordered)
        }
    }

    private var rationaleSection: some View {
        Text(rationale)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.bottom, 2)
    }

    private var suggestionsSection: some View {
        VStack(spacing: 10) {
            ForEach(suggestions, id: \.self) { suggestion in
                SuggestionCard(
                    text: suggestion,
                    isSelected: selectedSuggestion == suggestion
                ) {
                    selectedSuggestion = (selectedSuggestion == suggestion) ? nil : suggestion
                }
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button("Cancel") {
                onDecision(false)
            }
            .buttonStyle(.bordered)
            .foregroundStyle(.secondary)

            Spacer()

            Button("Use This") {
                if let selected = selectedSuggestion {
                    blockedText = selected
                    onDecision(true)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedSuggestion == nil)
        }
    }

    // MARK: - Data Loading

    private func loadSuggestions() async {
        isLoading = true
        loadError = nil
        do {
            let result = try await safety.requestTextRewrite(
                text: blockedText,
                harmCategoryId: harmCategoryId,
                contentType: contentType
            )
            suggestions = result.suggestions
            rationale = result.rationale
        } catch {
            loadError = "Couldn't load suggestions. Please try again."
        }
        isLoading = false
    }
}

// MARK: - SuggestionCard

private struct SuggestionCard: View {
    let text: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color(uiColor: .secondaryLabel))
                    .font(.body)
                    .padding(.top, 2)
                Text(text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ToneCheckBanner

/// Lightweight proactive tone banner shown inline above the composer.
/// Appears when getToneCheckSuggestion returns a non-nil suggestion.
struct ToneCheckBanner: View {
    let suggestion: String
    let onApply: (String) -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.yellow)
                .font(.callout)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text("Tone suggestion")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Text(suggestion)
                    .font(.callout)
                    .foregroundStyle(.primary)
                HStack(spacing: 8) {
                    Button("Apply") { onApply(suggestion) }
                        .font(.caption)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                    Button("Dismiss") { onDismiss() }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.yellow.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal)
    }
}

// MARK: - InteractionModePicker

/// Sheet for the user to change their interaction mode.
struct InteractionModePickerSheet: View {
    @Binding var currentMode: InteractionMode
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var selectedMode: InteractionMode

    private let safety = AmenSafetyOSClientService.shared

    init(currentMode: Binding<InteractionMode>) {
        _currentMode = currentMode
        _selectedMode = State(initialValue: currentMode.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(InteractionMode.allCases.filter { $0 != .youth }) { mode in
                        ModeRow(mode: mode, isSelected: selectedMode == mode) {
                            selectedMode = mode
                        }
                    }
                } header: {
                    Text("Choose how you want to exist on Amen")
                        .textCase(.none)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Interaction Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Save") { Task { await saveMode() } }
                            .fontWeight(.semibold)
                            .disabled(selectedMode == currentMode)
                    }
                }
            }
        }
    }

    private func saveMode() async {
        isSaving = true
        do {
            _ = try await safety.setInteractionMode(selectedMode)
            currentMode = selectedMode
            dismiss()
        } catch {
            // Silently revert — user can retry
        }
        isSaving = false
    }
}

private struct ModeRow: View {
    let mode: InteractionMode
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: modeIcon)
                    .frame(width: 28)
                    .foregroundStyle(isSelected ? Color.accentColor : Color(uiColor: .secondaryLabel))
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.displayName)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(mode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var modeIcon: String {
        switch mode {
        case .social:     return "person.2.fill"
        case .discussion: return "text.bubble.fill"
        case .study:      return "book.closed.fill"
        case .quiet:      return "moon.fill"
        case .youth:      return "shield.fill"
        case .campus:     return "building.columns.fill"
        case .family:     return "house.fill"
        }
    }
}

extension InteractionMode: Identifiable {
    var id: String { rawValue }
}
