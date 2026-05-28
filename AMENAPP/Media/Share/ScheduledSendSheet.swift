import SwiftUI
import FirebaseFirestore

struct ScheduledSendSheet: View {
    @Binding var isPresented: Bool
    var messageId: String
    var onScheduled: (Date) -> Void

    @State private var selectedDate = Date.now.addingTimeInterval(3600)
    @State private var isScheduling = false
    @State private var showConfirm = false

    private var minDate: Date { .now.addingTimeInterval(5 * 60) }
    private var maxDate: Date { Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                DatePicker(
                    "Send at",
                    selection: $selectedDate,
                    in: minDate...maxDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .padding(.horizontal, 16)

                scheduleButton
                    .padding(.horizontal, 20)

                Spacer()
            }
            .padding(.top, 16)
            .navigationTitle("Schedule Send")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
        .presentationDetents([.fraction(0.55)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(.regularMaterial)
    }

    private var scheduleButton: some View {
        Button {
            Task { await scheduleMessage() }
        } label: {
            HStack {
                if isScheduling {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("Schedule Send")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(Color.amenGold)
            )
        }
        .buttonStyle(.plain)
        .disabled(isScheduling)
        .accessibilityLabel("Schedule message to send at \(selectedDate.formatted())")
    }

    @MainActor
    private func scheduleMessage() async {
        isScheduling = true
        defer { isScheduling = false }

        do {
            let db = Firestore.firestore()
            try await db.collection("scheduledMessages").document(messageId).setData([
                "scheduledFor": Timestamp(date: selectedDate),
                "status": "pending",
                "createdAt": FieldValue.serverTimestamp()
            ], merge: true)
            onScheduled(selectedDate)
            isPresented = false
        } catch {
            // Silently fail in prototype; production would show error state
        }
    }
}
