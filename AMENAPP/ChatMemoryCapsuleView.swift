import SwiftUI

// MARK: - Chat Memory Capsule View
/// Floating liquid glass capsule that appears in the chat header area
/// when memory items or suggestions exist. Tap to open the memory sheet.

struct ChatMemoryCapsuleView: View {
    @ObservedObject var memoryService: ChatMemoryService
    @ObservedObject var extractionEngine: ChatMemoryExtractionEngine
    let onTap: () -> Void

    private var totalCount: Int {
        memoryService.activeCount + extractionEngine.pendingSuggestions.count
    }

    private var hasCalendarSuggestion: Bool {
        memoryService.calendarSuggestionCount > 0 ||
        extractionEngine.pendingSuggestions.contains { $0.extractedDate != nil }
    }

    private var sublabel: String {
        if hasCalendarSuggestion {
            return "Calendar suggestion"
        }
        let active = memoryService.activeCount
        let pending = extractionEngine.pendingSuggestions.count
        let total = active + pending
        if total == 1 { return "1 item" }
        return "\(total) items"
    }

    var body: some View {
        if totalCount > 0 {
            Button(action: onTap) {
                HStack(spacing: 6) {
                    Image(systemName: hasCalendarSuggestion ? "calendar.badge.clock" : "brain.head.profile")
                        .font(.systemScaled(12, weight: .semibold))
                        .foregroundStyle(hasCalendarSuggestion
                            ? Color(hex: "FF3B30")
                            : Color(hex: "6B48FF"))

                    Text(sublabel)
                        .font(AMENFont.semiBold(12))
                        .foregroundStyle(Color.primary.opacity(0.72))

                    if totalCount > 1 {
                        Text("\(totalCount)")
                            .font(AMENFont.bold(10))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color(hex: "6B48FF").opacity(0.80))
                            )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.55), Color.white.opacity(0.10)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.5
                                )
                        )
                )
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
            }
            .buttonStyle(ScaleButtonStyle())
            .transition(.asymmetric(
                insertion: .scale(scale: 0.85).combined(with: .opacity),
                removal: .opacity
            ))
            .animation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.78)), value: totalCount)
        }
    }
}
