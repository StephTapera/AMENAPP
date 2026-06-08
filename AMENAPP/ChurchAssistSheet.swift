// ChurchAssistSheet.swift
// Bottom sheet for church contextual actions
// AMENAPP

import SwiftUI

// MARK: - ChurchAssistActionRow

struct ChurchAssistActionRow: View {
    let icon: String
    let iconTint: Color
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Icon container
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(iconTint.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.systemScaled(17, weight: .medium))
                        .foregroundStyle(iconTint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                    )
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ChurchAssistSheet

struct ChurchAssistSheet: View {

    let state: ChurchVisitState
    let churchName: String
    let visitSession: ChurchVisitSession?
    let onAction: (ChurchAssistPromptType) -> Void

    @Environment(\.dismiss) private var dismiss

    // MARK: - Computed

    private var sheetTitle: String {
        switch state {
        case .planning:         return "Before You Go"
        case .arrived:          return "You're Here!"
        case .inService:        return "In Service"
        case .postVisit:        return "After the Service"
        case .revisitSuggested: return "Plan Your Return"
        default:                return churchName
        }
    }

    private var sheetSubtitle: String {
        switch state {
        case .planning:         return "Prepare for your visit to \(churchName)"
        case .arrived:          return "Welcome to \(churchName)"
        case .inService:        return "Capture what God is speaking to you"
        case .postVisit:        return "Reflect on your time at \(churchName)"
        case .revisitSuggested: return "You've been here before — go again?"
        default:                return ""
        }
    }

    private var actions: [(icon: String, tint: Color, title: String, subtitle: String, prompt: ChurchAssistPromptType)] {
        switch state {
        case .planning:
            return [
                ("info.circle.fill",           .blue,   "First Visit Guide",    "What to expect when you arrive",    .firstVisitCompanion),
                ("calendar.badge.checkmark",   .green,  "Compare Services",     "See service times and styles",      .compareServices),
                ("bookmark.fill",              .orange, "Save This Church",     "Add to your saved churches",        .planningToAttend)
            ]
        case .arrived:
            return [
                ("note.text",                  .blue,   "Start Church Notes",   "Capture the sermon as it unfolds",  .arrivedNeedsNotes),
                ("checklist",                  .teal,   "Arrival Checklist",    "Find your seat, kidscheck-in, etc",.arrivedChecklist),
                ("hands.sparkles.fill",        .purple, "Add a Prayer",         "Pray before service begins",       .inServicePrayerThought)
            ]
        case .inService:
            return [
                ("text.quote",                 .blue,   "Capture a Verse",      "Record scripture references",       .inServiceCaptureVerse),
                ("hands.sparkles.fill",        .purple, "Prayer Thought",       "Note a prayer for later",          .inServicePrayerThought),
                ("bookmark.fill",              .orange, "Save Takeaway",        "Quick note on what stood out",     .postVisitReflection)
            ]
        case .postVisit:
            return [
                ("heart.text.square.fill",     .red,    "Write a Reflection",   "What did you take away today?",     .postVisitReflection),
                ("lock.fill",                  .gray,   "Save Privately",       "For your eyes only",               .postVisitReflection),
                ("bubble.left.and.bubble.right.fill", .blue, "Share to #OpenTable", "Post to the community feed",  .postVisitShare)
            ]
        case .revisitSuggested:
            return [
                ("arrow.counterclockwise",     .teal,   "Plan Another Visit",   "Add to your calendar",             .revisitSuggestion),
                ("calendar.badge.checkmark",   .green,  "Compare Services",     "See all upcoming service times",   .compareServices),
                ("bookmark.fill",              .orange, "Save Church",          "Keep this church in your list",    .planningToAttend)
            ]
        default:
            return []
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 6) {
                        Capsule()
                            .fill(Color.black.opacity(0.12))
                            .frame(width: 36, height: 4)
                            .padding(.top, 8)

                        Text(sheetTitle)
                            .font(AMENFont.bold(20))
                            .foregroundStyle(.primary)

                        Text(sheetSubtitle)
                            .font(AMENFont.regular(14))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    // Action rows
                    VStack(spacing: 10) {
                        ForEach(actions, id: \.title) { action in
                            ChurchAssistActionRow(
                                icon: action.icon,
                                iconTint: action.tint,
                                title: action.title,
                                subtitle: action.subtitle
                            ) {
                                onAction(action.prompt)
                                dismiss()
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    // Dismiss
                    Button("Dismiss") {
                        dismiss()
                    }
                    .font(AMENFont.regular(15))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 16)
                }
            }
            .background(Color(.systemBackground))
            .navigationBarHidden(true)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    Text("Preview Host")
        .sheet(isPresented: .constant(true)) {
            ChurchAssistSheet(
                state: .arrived,
                churchName: "Grace Chapel",
                visitSession: nil,
                onAction: { _ in }
            )
        }
}
#endif
