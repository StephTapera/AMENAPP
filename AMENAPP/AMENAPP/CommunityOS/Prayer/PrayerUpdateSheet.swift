// PrayerUpdateSheet.swift
// AMEN App — Community OS / Prayer OS (A7)
//
// A bottom sheet for posting a prayer update or testimony.
// Presented from PrayerRoomView when the user taps "Add Update" or "Mark Answered".
//
// Design contract (C3):
//   - White card sheet, 28pt continuous corner radius
//   - AmenShadow.card spec
//   - System colors only
//   - 44x44pt touch targets minimum

import SwiftUI

// MARK: - PrayerUpdateSheet

/// Bottom sheet for composing and submitting a prayer update or testimony.
struct PrayerUpdateSheet: View {

    /// Firestore ID of the prayer being updated
    let prayerId: String
    /// The type to post — should be `.update` or `.testimony`
    let updateType: PrayerType
    /// Binding that controls sheet presentation
    @Binding var isPresented: Bool
    /// Called with the composed text when the user submits
    var onSubmit: ((String) -> Void)?

    @State private var bodyText = ""
    @State private var selectedType: PrayerType
    @State private var isSubmitting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        prayerId: String,
        updateType: PrayerType,
        isPresented: Binding<Bool>,
        onSubmit: ((String) -> Void)? = nil
    ) {
        self.prayerId = prayerId
        self.updateType = updateType
        self._isPresented = isPresented
        self.onSubmit = onSubmit
        self._selectedType = State(initialValue: updateType)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Sheet drag indicator
            Capsule()
                .fill(Color(uiColor: .quaternaryLabel))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 20)
                .accessibilityHidden(true)

            // Header
            VStack(spacing: 6) {
                Text(sheetTitle)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(uiColor: .label))

                Text(sheetSubtitle)
                    .font(.footnote)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            // Type selector — only shown when both update and testimony are relevant
            typePicker
                .padding(.horizontal, 20)
                .padding(.top, 20)

            // Text editor
            ZStack(alignment: .topLeading) {
                if bodyText.isEmpty {
                    Text(composerPlaceholder)
                        .font(.body)
                        .foregroundStyle(Color(uiColor: .placeholderText))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $bodyText)
                    .font(.body)
                    .foregroundStyle(Color(uiColor: .label))
                    .tint(Color.accentColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(minHeight: 120, maxHeight: 200)
                    .scrollContentBackground(.hidden)
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemFill))
            )
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .accessibilityLabel(composerPlaceholder)

            // Character count
            HStack {
                Spacer()
                Text("\(bodyText.count) / 500")
                    .font(.caption2)
                    .foregroundStyle(
                        bodyText.count > 450
                            ? Color.orange
                            : Color(uiColor: .tertiaryLabel)
                    )
                    .padding(.trailing, 24)
                    .padding(.top, 4)
            }
            .accessibilityLabel("Character count: \(bodyText.count) of 500")

            Spacer(minLength: 20)

            // Action buttons
            VStack(spacing: 10) {
                submitButton

                cancelButton
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(Color.white)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(28)
    }

    // MARK: - Type Picker

    @ViewBuilder
    private var typePicker: some View {
        if updateType == .update || updateType == .testimony {
            HStack(spacing: 0) {
                ForEach([PrayerType.update, PrayerType.testimony], id: \.self) { type in
                    Button {
                        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.15)) {
                            selectedType = type
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: type.systemImage)
                                .font(.system(size: 12))
                            Text(type.displayName)
                                .font(.system(size: 13, weight: selectedType == type ? .semibold : .regular))
                        }
                        .foregroundStyle(
                            selectedType == type ? Color(uiColor: .label) : Color(uiColor: .secondaryLabel)
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selectedType == type ? Color.white : Color.clear)
                                .shadow(
                                    color: selectedType == type ? .black.opacity(0.07) : .clear,
                                    radius: 4,
                                    x: 0,
                                    y: 2
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "\(type.displayName)\(selectedType == type ? ", selected" : "")"
                    )
                }
            }
            .padding(4)
            .background(
                Capsule()
                    .fill(Color(uiColor: .secondarySystemFill))
            )
        }
    }

    // MARK: - Submit Button

    private var submitButton: some View {
        Button {
            guard !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !isSubmitting else { return }
            isSubmitting = true
            let text = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
            onSubmit?(text)
            withAnimation(reduceMotion ? .none : .easeOut(duration: 0.18)) {
                isPresented = false
            }
        } label: {
            Group {
                if isSubmitting {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.85)
                } else {
                    Text(submitLabel)
                        .font(.callout)
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                Capsule()
                    .fill(canSubmit ? Color.accentColor : Color(uiColor: .secondarySystemFill))
            )
            .foregroundStyle(
                canSubmit ? Color.white : Color(uiColor: .secondaryLabel)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit || isSubmitting)
        .accessibilityLabel(submitLabel)
    }

    // MARK: - Cancel Button

    private var cancelButton: some View {
        Button {
            withAnimation(reduceMotion ? .none : .easeOut(duration: 0.18)) {
                isPresented = false
            }
        } label: {
            Text("Cancel")
                .font(.callout)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cancel and close sheet")
    }

    // MARK: - Helpers

    private var canSubmit: Bool {
        let trimmed = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 500
    }

    private var sheetTitle: String {
        selectedType == .testimony ? "Share Testimony" : "Add Update"
    }

    private var sheetSubtitle: String {
        selectedType == .testimony
            ? "Share how God answered this prayer."
            : "Share how this prayer is progressing."
    }

    private var composerPlaceholder: String {
        selectedType == .testimony
            ? "Share how God answered this prayer…"
            : "What's happening with this prayer request…"
    }

    private var submitLabel: String {
        selectedType == .testimony ? "Share Testimony" : "Post Update"
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Update sheet") {
    PrayerUpdateSheetPreview()
}

private struct PrayerUpdateSheetPreview: View {
    @State private var isPresented = true
    var body: some View {
        Button("Show sheet") { isPresented = true }
            .sheet(isPresented: $isPresented) {
                PrayerUpdateSheet(
                    prayerId: "prayer_001",
                    updateType: .update,
                    isPresented: $isPresented,
                    onSubmit: { text in
                        print("Submitted: \(text)")
                    }
                )
            }
    }
}
#endif
