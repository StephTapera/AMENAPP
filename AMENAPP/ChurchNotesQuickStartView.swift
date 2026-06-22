// ChurchNotesQuickStartView.swift
// Quick launcher sheet for Church Notes from church context
// AMENAPP

import SwiftUI

// MARK: - ChurchNoteTemplate

enum ChurchNoteTemplate: String, CaseIterable {
    case blank      = "Blank Note"
    case structured = "Sermon Template"
    case verse      = "Scripture Focus"
    case prayer     = "Prayer Guide"

    var icon: String {
        switch self {
        case .blank:      return "note.text"
        case .structured: return "list.bullet.clipboard"
        case .verse:      return "text.book.closed.fill"
        case .prayer:     return "hands.sparkles.fill"
        }
    }

    var description: String {
        switch self {
        case .blank:
            return "Open canvas — write freely"
        case .structured:
            return "Pre-structured with title, points, and application"
        case .verse:
            return "Center on a scripture passage"
        case .prayer:
            return "Capture prayer requests and praise"
        }
    }
}

// MARK: - TemplateCard (private subview)

private struct ChurchNoteTemplateCard: View {
    let template: ChurchNoteTemplate
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: template.icon)
                    .font(.systemScaled(28, weight: .medium))
                    .foregroundStyle(.primary)

                Text(template.rawValue)
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(.primary)

                Text(template.description)
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.07), lineWidth: 0.5)
                    )
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ChurchNotesQuickStartView

struct ChurchNotesQuickStartView: View {

    let churchId: String
    let churchName: String
    let serviceDate: Date?

    @Environment(\.dismiss) var dismiss
    var onStartNote: (ChurchNoteTemplate) -> Void

    // MARK: - Reminder State
    @State private var reminderEnabled = false
    @State private var selectedReminderOffset: ReminderOffset = .twentyFourHours

    enum ReminderOffset: String, CaseIterable {
        case twentyFourHours = "24h"
        case threeDays       = "3 days"
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color.black.opacity(0.12))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title + capsule
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Start a Note")
                            .font(AMENFont.bold(20))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 20)

                        ChurchCapsuleView(
                            churchName: churchName,
                            serviceDate: serviceDate,
                            onTap: nil
                        )
                        .padding(.horizontal, 20)
                    }

                    // Template grid
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(ChurchNoteTemplate.allCases, id: \.rawValue) { template in
                            ChurchNoteTemplateCard(template: template) {
                                onStartNote(template)
                                dismiss()
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    // Reminder row
                    VStack(alignment: .leading, spacing: 10) {
                        reminderToggleRow

                        if reminderEnabled {
                            reminderOffsetPicker
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 20)
                    .animation(Motion.adaptive(Motion.springRelease), value: reminderEnabled)

                    Spacer(minLength: 20)
                }
                .padding(.bottom, 24)
            }
        }
        .background(Color(.systemBackground))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Reminder Subviews

    private var reminderToggleRow: some View {
        HStack {
            Label("Set follow-up reminder?", systemImage: "bell.fill")
                .font(AMENFont.semiBold(14))
                .foregroundStyle(.primary)
            Spacer()
            Toggle("", isOn: $reminderEnabled)
                .labelsHidden()
                .tint(.black)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                )
        }
    }

    private var reminderOffsetPicker: some View {
        HStack {
            Text("Remind me in:")
                .font(AMENFont.regular(13))
                .foregroundStyle(.secondary)

            Spacer()

            Picker("Reminder offset", selection: $selectedReminderOffset) {
                ForEach(ReminderOffset.allCases, id: \.rawValue) { offset in
                    Text(offset.rawValue).tag(offset)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.03))
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    Text("Host")
        .sheet(isPresented: .constant(true)) {
            ChurchNotesQuickStartView(
                churchId: "abc123",
                churchName: "Antioch Church",
                serviceDate: Date(),
                onStartNote: { _ in }
            )
        }
}
#endif
