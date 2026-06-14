// BereanAgentPermissionCard.swift
// AMEN — Berean Agent Surface · Wave 1 Lane A
//
// Overlay card surfaced whenever a permission request needs user review.
// Design: .glassEffect() container, warm paper bg, 24pt corners, wine-red accent.
// §7: wontAccess line is MANDATORY — never hidden, never conditional.
// §2: reduceMotion guard on all animations; one wine-red element per screen.

import SwiftUI

// MARK: - Permission Card

@MainActor
struct BereanAgentPermissionCard: View {

    let request: BASPermissionRequest
    let onGrant: (BASGrantType) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            // Semi-transparent scrim behind the card
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    onGrant(.deny)
                }
                .accessibilityHidden(true)

            cardContent
                .padding(.horizontal, 20)
                .scaleEffect(appeared ? 1 : 0.94)
                .opacity(appeared ? 1 : 0)
                .onAppear {
                    withAnimation(
                        reduceMotion ? .none : Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8))
                    ) {
                        appeared = true
                    }
                }
        }
    }

    // MARK: Card Content

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {

            // 1. App icon + display name header
            appHeader
                .padding(.bottom, 20)

            Divider()
                .padding(.bottom, 16)

            // 2. Why Berean needs this
            whySection
                .padding(.bottom, 14)

            // 3. Won't Access (MANDATORY — never conditional)
            wontAccessSection
                .padding(.bottom, 16)

            // 4. Scope chip
            scopeChipRow
                .padding(.bottom, 20)

            Divider()
                .padding(.bottom, 16)

            // 5. Action buttons
            actionButtons
        }
        .padding(24)
        .background(
            Color.basWarmPaper,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.basTan, lineWidth: 1)
        )
        .shadow(color: Color.basInk.opacity(0.12), radius: 12, x: 0, y: 6)
        .glassEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: App Header

    private var appHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.basTan)
                    .frame(width: 52, height: 52)

                Image(systemName: iconName(for: request.targetApp))
                    .font(.title2)
                    .foregroundStyle(Color.basInk)
            }
            .accessibilityHidden(true)

            Text(request.targetApp)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(Color.basInk)
                .minimumScaleFactor(0.8)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Permission request from \(request.targetApp)")
    }

    // MARK: Why Section

    private var whySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Why Berean needs this:")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.basInk)

            Text(request.why)
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Won't Access (MANDATORY)

    private var wontAccessSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Won't access:")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.basWineRed)

            Text(request.wontAccess)
                .font(.subheadline)
                .foregroundStyle(Color.basInk.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Won't access: \(request.wontAccess)")
    }

    // MARK: Scope Chip

    private var scopeChipRow: some View {
        HStack {
            Text(scopeLabel(request.scope))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Color.basInk)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.basTan, in: Capsule())
                .accessibilityLabel("Requested scope: \(scopeLabel(request.scope))")

            Spacer()
        }
    }

    // MARK: Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 8) {
            actionButton(
                title: "Allow Once",
                grantType: .allowOnce,
                filled: true
            )

            actionButton(
                title: "For Task",
                grantType: .allowForThisTask,
                filled: true
            )

            actionButton(
                title: "Always",
                grantType: .alwaysAllow,
                filled: true
            )

            denyButton
        }
    }

    @ViewBuilder
    private func actionButton(title: String, grantType: BASGrantType, filled: Bool) -> some View {
        let label = accessibilityLabel(for: grantType, appName: request.targetApp)

        Button {
            withAnimation(
                reduceMotion ? .none : Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))
            ) {
                onGrant(grantType)
            }
        } label: {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.basInk)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(Color.basTan, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .accessibilityLabel(label)
    }

    private var denyButton: some View {
        Button {
            withAnimation(
                reduceMotion ? .none : Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))
            ) {
                onGrant(.deny)
            }
        } label: {
            Text("Deny")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.basInk)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.basInk.opacity(0.3), lineWidth: 1.5)
                )
        }
        .accessibilityLabel("Deny \(request.targetApp) access")
    }

    // MARK: Helpers

    private func scopeLabel(_ scope: BASScopeMode) -> String {
        switch scope {
        case .askEveryTime:         return "Ask Every Time"
        case .importantActionsOnly: return "Important Actions Only"
        case .readOnly:             return "Read Only"
        case .never_:               return "Never"
        case .privateMode:          return "Private Mode"
        }
    }

    private func accessibilityLabel(for grantType: BASGrantType, appName: String) -> String {
        switch grantType {
        case .allowOnce:        return "Allow \(appName) once"
        case .allowForThisTask: return "Allow \(appName) for this task"
        case .alwaysAllow:      return "Always allow \(appName)"
        case .deny:             return "Deny \(appName) access"
        }
    }

    /// Best-effort SF symbol lookup for a connected app name.
    private func iconName(for appName: String) -> String {
        let lower = appName.lowercased()
        if lower.contains("music")    { return "music.note.list" }
        if lower.contains("spotify")  { return "headphones.circle.fill" }
        if lower.contains("bible")    { return "text.book.closed.fill" }
        if lower.contains("calendar") { return "calendar" }
        if lower.contains("notes")    { return "note.text" }
        if lower.contains("church")   { return "building.columns.fill" }
        if lower.contains("files")    { return "folder.fill" }
        if lower.contains("giving")   { return "dollarsign.circle.fill" }
        if lower.contains("messages") { return "message.fill" }
        return "app.badge.fill"
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Permission Card") {
    BereanAgentPermissionCard(
        request: BASPermissionRequest(
            id: UUID(),
            targetApp: "Apple Music",
            why: "Berean needs to read your library to suggest worship songs during prayer sessions.",
            wontAccess: "Your purchase history, payment info, or listening data outside of this session.",
            scope: .readOnly
        ),
        onGrant: { grant in
            print("Grant: \(grant)")
        }
    )
}

#Preview("Apps Settings") {
    BereanAgentAppsSettingsView()
}
#endif
