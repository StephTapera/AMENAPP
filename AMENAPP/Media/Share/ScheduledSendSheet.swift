import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - ScheduledSendSheet
// Small glass sheet for scheduling a deferred message send.
// Writes { scheduledFor, status: "pending" } to /scheduledMessages/{messageId}.
// Shows a confirmation toast above the keyboard on success.

struct ScheduledSendSheet: View {
    @Binding var isPresented: Bool
    var messageId: String
    var onScheduled: (Date) -> Void

    @State private var selectedDate: Date = Date().addingTimeInterval(5 * 60)
    @State private var isSaving = false
    @State private var showToast = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var minDate: Date { Date().addingTimeInterval(5 * 60) }
    private var maxDate: Date { Date().addingTimeInterval(30 * 24 * 60 * 60) }

    var body: some View {
        Color.clear
            .glassSheet(isPresented: $isPresented, detent: .small) {
                sheetBody
            }
    }

    private var sheetBody: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 20) {
                header
                datePicker
                scheduleButton
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)

            if showToast {
                toastBanner
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .bottom).combined(with: .opacity)
                    )
                    .padding(.bottom, 16)
            }
        }
        .animation(
            reduceMotion ? .easeOut(duration: LiquidGlassTokens.motionFast)
                         : .spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.82),
            value: showToast
        )
    }

    // MARK: - Header
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Schedule Send")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("Choose when to send this message")
                    .font(.subheadline)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }
            Spacer()
            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    // MARK: - DatePicker
    private var datePicker: some View {
        DatePicker(
            "Send time",
            selection: $selectedDate,
            in: minDate...maxDate,
            displayedComponents: [.date, .hourAndMinute]
        )
        .datePickerStyle(.graphical)
        .tint(Color.amenGold)
        .accessibilityLabel("Select send date and time")
    }

    // MARK: - Schedule button
    private var scheduleButton: some View {
        Button {
            guard !isSaving else { return }
            saveSchedule()
        } label: {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.85)
                } else {
                    Image(systemName: "clock.badge.checkmark.fill")
                }
                Text(isSaving ? "Scheduling…" : "Schedule Send")
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(isSaving ? Color.secondary.opacity(0.4) : Color.amenGold)
            }
            .shadow(
                color: isSaving ? .clear : Color.amenGold.opacity(0.35),
                radius: 10, y: 4
            )
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .animation(
            reduceMotion ? nil : .easeOut(duration: LiquidGlassTokens.motionFast),
            value: isSaving
        )
        .accessibilityLabel("Schedule Send")
        .accessibilityHint("Schedules message to send on the selected date")
    }

    // MARK: - Toast
    private var toastBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.amenGold)
            Text("Scheduled for \(selectedDate, style: .relative) from now")
                .font(.footnote.weight(.medium))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(Color(.systemBackground))
                    .overlay {
                        RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                    }
            } else {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(LiquidGlassTokens.blurElevated)
                    .overlay {
                        RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.44), lineWidth: 0.6)
                    }
            }
        }
        .shadow(
            color: LiquidGlassTokens.shadowFloating.color,
            radius: LiquidGlassTokens.shadowFloating.radius,
            y: LiquidGlassTokens.shadowFloating.y
        )
        .accessibilityLabel("Message scheduled successfully")
    }

    // MARK: - Save to Firestore
    private func saveSchedule() {
        isSaving = true
        let date = selectedDate
        Firestore.firestore()
            .collection("scheduledMessages")
            .document(messageId)
            .setData([
                "scheduledFor": Timestamp(date: date),
                "status": "pending"
            ]) { [self] error in
                isSaving = false
                if error == nil {
                    onScheduled(date)
                    withAnimation { showToast = true }
                    Task {
                        try? await Task.sleep(for: .seconds(2.5))
                        await MainActor.run {
                            withAnimation { showToast = false }
                            isPresented = false
                        }
                    }
                }
            }
    }
}

