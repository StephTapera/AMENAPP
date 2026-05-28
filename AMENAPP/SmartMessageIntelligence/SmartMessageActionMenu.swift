import EventKit
import SwiftUI
import UIKit

struct SmartMessageActionMenu: View {
    let actions: [SmartMessageAction]
    var onOpenScripture: (String) -> Void = { _ in }
    var onPrayerRequest: (SmartMessageAction) -> Void = { _ in }
    var onStudyMode: (SmartMessageAction) -> Void = { _ in }
    var onSearchRelated: (String) -> Void = { _ in }

    @State private var confirmationAction: SmartMessageAction?
    @State private var errorMessage: String?
    @State private var showActionSheet = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        Button {
            showActionSheet = true
        } label: {
            Label("Smart actions", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(actionButtonBackground, in: Capsule())
                .overlay(Capsule().strokeBorder(colorSchemeContrast == .increased ? Color.black.opacity(0.16) : Color.black.opacity(0.06), lineWidth: colorSchemeContrast == .increased ? 1.1 : 0.7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Smart message actions")
        .sheet(isPresented: $showActionSheet) {
            AmenSmartActionGlassMenuSheet(actions: actions) { action in
                showActionSheet = false
                handle(action)
            }
            .presentationDetents([.height(360), .medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(.clear)
        }
        .confirmationDialog(
            confirmationAction?.title ?? "Confirm Action",
            isPresented: Binding(get: { confirmationAction != nil }, set: { if !$0 { confirmationAction = nil } }),
            presenting: confirmationAction
        ) { action in
            Button(action.title) {
                AmenSmartMessageIntelligenceService.shared.trackActionConfirmed(action)
                performConfirmed(action)
                confirmationAction = nil
            }
            Button("Cancel", role: .cancel) { confirmationAction = nil }
        } message: { action in
            Text(action.subtitle)
        }
        .alert("Action unavailable", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var actionButtonBackground: some ShapeStyle {
        reduceTransparency ? AnyShapeStyle(Color.white) : AnyShapeStyle(.ultraThinMaterial)
    }

    private func handle(_ action: SmartMessageAction) {
        AmenSmartMessageIntelligenceService.shared.trackActionTapped(action)
        if action.requiresConfirmation {
            confirmationAction = action
        } else {
            performConfirmed(action)
        }
    }

    private func performConfirmed(_ action: SmartMessageAction) {
        switch action.actionType {
        case .openScripture:
            onOpenScripture(action.payload["scriptureReference"] ?? action.subtitle)
        case .askBerean:
            let payload = BereanContextPayload(
                selectedText: action.payload["selectedText"] ?? action.subtitle,
                sourceSurface: "smart_message",
                contentType: .message,
                scriptureReference: action.payload["scriptureReference"]
            )
            BereanContextMenuManager.shared.activate(payload: payload, action: .askBerean)
        case .addToCalendar:
            requestEventAccess(reminder: false, action: action)
        case .addReminder:
            if action.title == "Copy Event" {
                copyToPasteboard(action.subtitle, message: "Event text copied.")
            } else {
                requestEventAccess(reminder: true, action: action)
            }
        case .createPrayerRequest:
            onPrayerRequest(action)
        case .prayNow:
            onPrayerRequest(action)
        case .summarizeThread:
            activateBerean(action: .summarize, smartAction: action)
        case .startStudyMode, .createStudyGuide:
            onStudyMode(action)
        case .saveToJournal:
            activateBerean(action: .saveToChurchNotes, smartAction: action)
        case .createTopic:
            onSearchRelated(action.payload["topic"] ?? action.subtitle)
        case .searchRelated:
            if action.title == "Share With Space" {
                copyToPasteboard(action.subtitle, message: "Share-ready event text copied.")
            } else {
                onSearchRelated(action.payload["query"] ?? action.subtitle)
            }
        case .openKnowledgeGraph:
            onSearchRelated(action.payload["query"] ?? action.subtitle)
        case .transcribeVoice:
            activateBerean(action: .voiceExplain, smartAction: action)
        }
    }

    private func requestEventAccess(reminder: Bool, action: SmartMessageAction) {
        let store = EKEventStore()
        Task {
            do {
                if reminder {
                    let granted = try await store.requestFullAccessToReminders()
                    guard granted else {
                        await MainActor.run { errorMessage = "Reminder access was denied. You can enable reminder access in Settings." }
                        return
                    }
                    await MainActor.run { copyToPasteboard(action.subtitle, message: "Reminder access granted. Reminder text copied for review before saving.") }
                } else {
                    let granted = try await store.requestWriteOnlyAccessToEvents()
                    guard granted else {
                        await MainActor.run { errorMessage = "Calendar access was denied. You can enable calendar access in Settings." }
                        return
                    }
                    await MainActor.run { copyToPasteboard(action.subtitle, message: "Calendar access granted. Event text copied for review before saving.") }
                }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    private func activateBerean(action: BereanContextAction, smartAction: SmartMessageAction) {
        let payload = BereanContextPayload(
            selectedText: smartAction.payload["sourceText"] ?? smartAction.subtitle,
            sourceSurface: "smart_message",
            contentType: .message,
            scriptureReference: smartAction.payload["scriptureReference"]
        )
        BereanContextMenuManager.shared.activate(payload: payload, action: action)
    }

    private func copyToPasteboard(_ value: String, message: String) {
        UIPasteboard.general.string = value
        errorMessage = message
    }
}

private struct AmenSmartActionGlassMenuSheet: View {
    let actions: [SmartMessageAction]
    let onSelect: (SmartMessageAction) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.black.opacity(0.22))
                .frame(width: 38, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 14)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.black, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Smart Actions")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                    Text("Choose what to do next. Amen does not expose private message text in analytics.")
                        .font(.caption)
                        .foregroundStyle(.black.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black.opacity(0.58))
                        .frame(width: 32, height: 32)
                        .background(Color.black.opacity(0.055), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close smart actions")
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(actions.prefix(8)) { action in
                        Button {
                            onSelect(action)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: action.iconSystemName)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                                    .frame(width: 36, height: 36)
                                    .background(Color.black.opacity(0.055), in: Circle())

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(action.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                                    Text(action.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.black.opacity(0.58))
                                        .lineLimit(2)
                                }

                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.black.opacity(0.30))
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(colorSchemeContrast == .increased ? Color.black.opacity(0.16) : Color.black.opacity(0.055), lineWidth: colorSchemeContrast == .increased ? 1.1 : 0.7))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(action.title)
                        .accessibilityHint(action.subtitle)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .background(sheetBackground, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private var sheetBackground: some ShapeStyle {
        reduceTransparency ? AnyShapeStyle(Color.white) : AnyShapeStyle(.ultraThinMaterial)
    }
}
