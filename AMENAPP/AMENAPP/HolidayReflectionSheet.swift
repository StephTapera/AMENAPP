//
//  HolidayReflectionSheet.swift
//  AMENAPP
//
//  Full-screen holiday reflection sheet.
//  Shown when the user taps a holiday CTA from the Daily Verse banner.
//  Displays: holiday name, banner message, scripture, expanded reflection,
//  discernment note (when applicable), and action buttons.
//

import SwiftUI

// MARK: - Holiday Reflection Sheet

struct HolidayReflectionSheet: View {
    let content: HolidayBannerContent
    let holidayType: HolidayType?

    @Environment(\.dismiss) private var dismiss
    @State private var showBerean = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // ── Category badge + holiday name ──────────────────────
                    VStack(alignment: .leading, spacing: 6) {
                        Text(content.category.bannerBadgeLabel.uppercased())
                            .font(.custom("OpenSans-SemiBold", size: 10))
                            .tracking(1.5)
                            .foregroundStyle(.secondary)

                        Text(content.canonicalName)
                            .font(.custom("OpenSans-Bold", size: 28))
                            .foregroundStyle(.primary)
                            .lineSpacing(2)
                    }

                    // ── Banner message ─────────────────────────────────────
                    Text(content.shortBannerMessage)
                        .font(.custom("OpenSans-Regular", size: 17))
                        .foregroundStyle(.primary)
                        .lineSpacing(5)

                    // ── Primary scripture card ─────────────────────────────
                    ScriptureCard(reference: content.primaryScriptureReference, isPrimary: true)

                    // ── Additional scriptures ──────────────────────────────
                    if !content.additionalScriptures.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Related Scriptures")
                                .font(.custom("OpenSans-SemiBold", size: 13))
                                .foregroundStyle(.secondary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(content.additionalScriptures, id: \.self) { ref in
                                        ScriptureChip(reference: ref)
                                    }
                                }
                            }
                        }
                    }

                    // ── Divider ────────────────────────────────────────────
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 1)

                    // ── Expanded reflection ────────────────────────────────
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Reflection")
                            .font(.custom("OpenSans-Bold", size: 15))
                            .foregroundStyle(.primary)

                        Text(content.expandedReflection)
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.secondary)
                            .lineSpacing(5)
                    }

                    // ── Discernment note ───────────────────────────────────
                    if content.consistencyLevel == .discernment {
                        DiscernmentNoteCard(holidayName: content.canonicalName)
                    }

                    // ── Theme tag ──────────────────────────────────────────
                    if !content.theme.isEmpty {
                        Text(content.theme)
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.tertiary)
                            .italic()
                    }

                    // ── Action buttons ─────────────────────────────────────
                    actionButtons

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.custom("OpenSans-SemiBold", size: 16))
                }
            }
            .sheet(isPresented: $showBerean) {
                BereanChatRouteView(
                    entryPoint: .dailyVerse,
                    initialQuery: "Help me reflect on \(content.canonicalName): \"\(content.shortBannerMessage)\""
                )
            }
        }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 10) {
            // Reflect with Berean
            Button {
                showBerean = true
            } label: {
                Label("Reflect with Berean", systemImage: "sparkles")
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            // Share verse
            ShareLink(
                item: "\(content.shortBannerMessage)\n\n— \(content.primaryScriptureReference)\n\nShared from AMEN"
            ) {
                Label("Share This", systemImage: "square.and.arrow.up")
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            // Open study deep link (if available and not a discernment holiday)
            if content.consistencyLevel != .discernment,
               let type = holidayType,
               type.priorityWeight >= 7 {
                Button {
                    openDeepLink(content.callToActionRoute)
                    dismiss()
                } label: {
                    Label("Open Study", systemImage: "book.fill")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }

    private func openDeepLink(_ route: String) {
        guard let url = URL(string: route) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Scripture Card

private struct ScriptureCard: View {
    let reference: String
    var isPrimary: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.primary.opacity(isPrimary ? 0.8 : 0.3))
                .frame(width: 3)

            Text(reference)
                .font(.custom(isPrimary ? "OpenSans-SemiBold" : "OpenSans-Regular",
                              size: isPrimary ? 15 : 13))
                .foregroundStyle(isPrimary ? .primary : .secondary)
        }
        .padding(.vertical, isPrimary ? 12 : 8)
        .padding(.horizontal, isPrimary ? 12 : 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(isPrimary ? 0.45 : 0.25))
        )
    }
}

// MARK: - Scripture Chip

private struct ScriptureChip: View {
    let reference: String

    var body: some View {
        Text(reference)
            .font(.custom("OpenSans-SemiBold", size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.4))
            )
    }
}

// MARK: - Discernment Note Card

private struct DiscernmentNoteCard: View {
    let holidayName: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "scale.3d")
                .font(.system(size: 14))
                .foregroundStyle(.orange.opacity(0.85))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("A pastoral note")
                    .font(.custom("OpenSans-SemiBold", size: 12))
                    .foregroundStyle(.orange.opacity(0.85))

                Text(HolidaySpiritualGuardrail.discernmentNote(for: holidayName))
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.orange.opacity(0.2), lineWidth: 0.8)
        )
    }
}

// MARK: - Preview

#Preview {
    HolidayReflectionSheet(
        content: HolidayBannerCatalog.content(for: .easter)!,
        holidayType: .easter
    )
}
