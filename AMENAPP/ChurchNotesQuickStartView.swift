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

// MARK: - TemplatePill (private subview)

private struct TemplatePill: View {
    let template: ChurchNoteTemplate
    let isSelected: Bool
    let action: () -> Void

    @GestureState private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let gold = AmenTheme.Colors.amenGold

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: template.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? gold : Color.secondary)

                Text(template.rawValue)
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .padding(.horizontal, 8)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? gold.opacity(0.15) : Color.primary.opacity(0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                isSelected ? gold.opacity(0.5) : Color.primary.opacity(0.12),
                                lineWidth: isSelected ? 1 : 0.5
                            )
                    }
            }
            .amenGlassEffect(isSelected ? gold.opacity(0.15) : .clear, cornerRadius: 14)
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .opacity(isPressed ? 0.88 : 1.0)
            .animation(
                reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.22, dampingFraction: 0.82),
                value: isPressed
            )
            .animation(
                reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.22, dampingFraction: 0.82),
                value: isSelected
            )
        }
        .buttonStyle(.plain)
        .gesture(DragGesture(minimumDistance: 0).updating($isPressed) { _, s, _ in s = true })
        .accessibilityLabel(template.rawValue)
        .accessibilityHint(template.description)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - ChurchNotesQuickStartView

struct ChurchNotesQuickStartView: View {

    let churchId: String
    let churchName: String
    let serviceDate: Date?

    @Environment(\.dismiss) var dismiss
    var onStartNote: (ChurchNoteTemplate) -> Void

    // MARK: - Template highlight (drives description subtitle below grid)
    @State private var highlightedTemplate: ChurchNoteTemplate = .blank

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
                    VStack(spacing: 10) {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(ChurchNoteTemplate.allCases, id: \.rawValue) { template in
                                TemplatePill(
                                    template: template,
                                    isSelected: highlightedTemplate == template
                                ) {
                                    withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                                        highlightedTemplate = template
                                    }
                                    onStartNote(template)
                                    dismiss()
                                }
                            }
                        }

                        // Description of the currently-highlighted template
                        Text(highlightedTemplate.description)
                            .font(AMENFont.regular(12))
                            .foregroundStyle(Color.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 4)
                            .padding(.top, 2)
                            .animation(Motion.adaptive(.spring(response: 0.22, dampingFraction: 0.82)), value: highlightedTemplate)
                            .transition(.opacity)
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
