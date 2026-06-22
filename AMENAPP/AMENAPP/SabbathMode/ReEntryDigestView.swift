// ReEntryDigestView.swift
// AMENAPP — SabbathMode
//
// Shown exactly once at re-entry after Sabbath (digest.showOnce = true).
// NO infinite catch-up scroll, NO unread counts, NO "you missed X" language.
// Items capped at SabbathModeDefaults.Digest.maxItems (6) — model enforces.
// Faithful port of ReEntryDigestView.tsx.
//
// BANNED tokens: gold, purple, dark gradients, serif fonts, streaks, counts.

import SwiftUI

struct ReEntryDigestView: View {
    let digest: SabbathDigest
    var onDismiss: (String) -> Void  // Called with reflection text (may be empty)

    @State private var reflectionText = ""
    @Environment(\.openURL) private var openURL

    // Cap at maxItems (model is server-enforced, UI also caps defensively)
    private var cappedItems: [SabbathDigestItem] {
        Array(digest.items.prefix(SabbathModeDefaults.Digest.maxItems))
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: 48)

                    // White card
                    VStack(alignment: .leading, spacing: 20) {

                        // Header — summary line (no counts, no "you missed X")
                        Text(digest.summaryLine)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)

                        // Digest items — capped, tappable
                        if !cappedItems.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("WHILE YOU RESTED")
                                    .font(.caption2.weight(.semibold))
                                    .tracking(1)
                                    .foregroundStyle(.tertiary)
                                    .padding(.bottom, 8)

                                ForEach(cappedItems, id: \.deeplink) { item in
                                    SabbathDigestItemRow(item: item) { deeplink in
                                        if let url = URL(string: deeplink) {
                                            openURL(url)
                                        }
                                    }
                                }
                            }
                        }

                        Divider()

                        // Reflection section
                        VStack(alignment: .leading, spacing: 10) {
                            Text("One thought before you dive back in")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)

                            ZStack(alignment: .topLeading) {
                                if reflectionText.isEmpty {
                                    Text("Your reflection stays private...")
                                        .font(.subheadline)
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 12)
                                        .padding(.horizontal, 14)
                                }
                                TextEditor(text: $reflectionText)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .frame(minHeight: 80)
                                    .padding(8)
                                    .scrollContentBackground(.hidden)
                                    .background(Color(.systemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .accessibilityLabel("Private reflection")
                        }

                        // Continue button
                        Button {
                            onDismiss(reflectionText.trimmingCharacters(in: .whitespacesAndNewlines))
                        } label: {
                            Text("Continue")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.primary, in: Capsule())
                                .foregroundStyle(Color(uiColor: .systemBackground))
                        }
                        .accessibilityLabel("Continue to the full app")
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)

                    Spacer().frame(height: 40)
                }
            }
        }
    }
}

// MARK: - SabbathDigestItemRow

private struct SabbathDigestItemRow: View {
    let item: SabbathDigestItem
    let onTap: (String) -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            onTap(item.deeplink)
        } label: {
            HStack(spacing: 8) {
                Text(item.label)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Never bold or highlighted — equal weight, no ranking implied

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isPressed ? Color.black.opacity(0.03) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.label)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded   { _ in isPressed = false }
        )
    }
}

#Preview {
    ReEntryDigestView(
        digest: SabbathDigest(
            sessionDate: "2026-06-07",
            summaryLine: "A peaceful Sabbath. You visited 3 surfaces.",
            items: [
                SabbathDigestItem(label: "Sermon notes from this morning", deeplink: "amenapp://church-notes/abc123"),
                SabbathDigestItem(label: "Prayer you started during rest", deeplink: "amenapp://prayer/def456"),
            ]
        ),
        onDismiss: { text in print("Reflection: \(text)") }
    )
}
