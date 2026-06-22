// AmenBeforeShareCheckView.swift
// AMEN Connect + Spaces — Before-Share Warning Sheet
// Agent 8 — built 2026-06-01
//
// Shows detected before-share warnings to the user and lets them choose to
// edit their message or share anyway.  The sheet never auto-blocks and never
// pronounces judgment — it surfaces what was detected and puts the choice
// with the user.
//
// Hard safety rule honoured:
//   No auto-block: always two choices — edit or share anyway.

import SwiftUI

// MARK: - Warning row model

private struct AmenBeforeShareWarningRow: Identifiable {
    let id: AmenConnectSpacesBeforeShareWarning
    let warning: AmenConnectSpacesBeforeShareWarning
    let title: String
    let detail: String
    let systemImage: String
    let iconColor: Color
}

private extension AmenConnectSpacesBeforeShareWarning {
    var row: AmenBeforeShareWarningRow {
        switch self {
        case .gossip:
            return AmenBeforeShareWarningRow(
                id: self, warning: self,
                title: "Is this about someone who isn't here?",
                detail: "Titus 3:2",
                systemImage: "person.2.slash",
                iconColor: Color.accentColor
            )
        case .slander:
            return AmenBeforeShareWarningRow(
                id: self, warning: self,
                title: "Could this damage someone's reputation unfairly?",
                detail: "James 3:16",
                systemImage: "exclamationmark.triangle.fill",
                iconColor: Color.red
            )
        case .divisiveness:
            return AmenBeforeShareWarningRow(
                id: self, warning: self,
                title: "Could this create division in the body?",
                detail: "Romans 16:17",
                systemImage: "arrow.trianglehead.branch",
                iconColor: Color.accentColor
            )
        case .pii:
            return AmenBeforeShareWarningRow(
                id: self, warning: self,
                title: "This may contain personal information",
                detail: "Personal details detected",
                systemImage: "shield.fill",
                iconColor: Color(red: 0.141, green: 0.357, blue: 0.561) // amenBlue
            )
        case .phi:
            return AmenBeforeShareWarningRow(
                id: self, warning: self,
                title: "This may contain health information",
                detail: "Health details detected",
                systemImage: "cross.case.fill",
                iconColor: Color(red: 0.141, green: 0.357, blue: 0.561) // amenBlue
            )
        case .financial:
            return AmenBeforeShareWarningRow(
                id: self, warning: self,
                title: "This may contain financial details",
                detail: "Financial information detected",
                systemImage: "banknote.fill",
                iconColor: Color(red: 0.141, green: 0.357, blue: 0.561) // amenBlue
            )
        }
    }
}

// MARK: - Main View

struct AmenBeforeShareCheckView: View {

    let warnings: [AmenConnectSpacesBeforeShareWarning]
    let onProceed: () -> Void
    let onEdit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Glass drag handle chrome
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 12)
                .accessibilityHidden(true)

            ScrollView {
                VStack(spacing: 20) {
                    // Title
                    Text("Before you share\u{2026}")
                        .font(.systemScaled(22, weight: .bold))
                        .foregroundStyle(Color(.label))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 20)
                        .padding(.horizontal, 20)
                        .accessibilityAddTraits(.isHeader)

                    // Warning cards
                    VStack(spacing: 10) {
                        ForEach(warnings.map(\.row)) { row in
                            warningCard(row)
                        }
                    }
                    .padding(.horizontal, 16)

                    // Action buttons
                    VStack(spacing: 10) {
                        // Primary — edit
                        Button {
                            onEdit()
                        } label: {
                            Text("Edit my message")
                                .font(.systemScaled(16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color(red: 0.431, green: 0.294, blue: 0.710)) // amenPurple
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit my message")

                        // Secondary — share anyway
                        Button {
                            onProceed()
                        } label: {
                            Text("Share anyway")
                                .font(.systemScaled(15, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Share anyway")
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                }
                .ignoresSafeArea()
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden) // we render our own handle
    }

    // MARK: - Warning card

    private func warningCard(_ row: AmenBeforeShareWarningRow) -> some View {
        HStack(alignment: .center, spacing: 14) {
            // Icon
            Image(systemName: row.systemImage)
                .font(.systemScaled(20))
                .foregroundStyle(row.iconColor)
                .frame(width: 32)
                .accessibilityHidden(true)

            // Text content
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(row.detail)
                    .font(.systemScaled(12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground).opacity(0.85))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(row.iconColor.opacity(0.2), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.title) — \(row.detail)")
    }
}
