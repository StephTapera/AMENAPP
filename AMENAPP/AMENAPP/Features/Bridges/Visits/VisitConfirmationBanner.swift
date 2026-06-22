import SwiftUI

/// Swipe-up style confirmation banner shown when the user enters a saved church geofence
/// during a service window. Requires explicit user confirmation — never auto-logs visits.
struct VisitConfirmationBanner: View {
    @ObservedObject var service = VisitVerificationService.shared
    @State private var isConfirming = false

    var body: some View {
        if let visit = service.pendingVisitConfirmation {
            VStack(spacing: 12) {
                Text("You appear to be at a saved church")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Text("Count this as a visit?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    Button("Not Now") {
                        service.dismissVisit()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Dismiss visit confirmation")

                    Button {
                        guard !isConfirming else { return }
                        isConfirming = true
                        Task {
                            await service.confirmVisit(visit)
                            isConfirming = false
                        }
                    } label: {
                        if isConfirming {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Text("Yes, log visit")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isConfirming)
                    .accessibilityLabel("Confirm and log this church visit")
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding()
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: service.pendingVisitConfirmation != nil)
        }
    }
}
