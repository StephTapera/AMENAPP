import SwiftUI

/// Live comment-count badge. Backed by the same Firestore snapshot listener
/// as the comments list, so adds/resolves/deletes all update without a refresh.
/// The badge prefers showing OPEN (non-resolved) count to surface active
/// conversation. The total appears in the accessibility label for clarity.
struct ChurchNoteCommentCountBadge: View {
    @ObservedObject var service: ChurchNotesCommentsService
    var onTap: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let open  = service.openCount
        let total = service.totalCount
        Button {
            onTap?()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: open > 0 ? "bubble.left.fill" : "bubble.left")
                    .font(.systemScaled(12, weight: .semibold))
                    .accessibilityHidden(true)
                if total > 0 {
                    Text("\(open > 0 ? open : total)")
                        .font(.systemScaled(12, weight: .semibold))
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, total > 0 ? 8 : 6)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(open > 0 ? Color.accentColor.opacity(0.16) : Color(.secondarySystemFill))
            )
            .foregroundStyle(open > 0 ? Color.accentColor : Color.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel(open: open, total: total))
            .accessibilityHint(onTap == nil ? "" : "Opens the comments thread")
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: open)
    }

    private func accessibilityLabel(open: Int, total: Int) -> String {
        if total == 0 {
            return "No comments"
        }
        if open == 0 {
            return "\(total) resolved comment\(total == 1 ? "" : "s")"
        }
        if open == total {
            return "\(open) open comment\(open == 1 ? "" : "s")"
        }
        return "\(open) open of \(total) total comments"
    }
}
