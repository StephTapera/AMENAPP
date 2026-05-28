// BereanCarPlayTemplates.swift
// AMEN — Berean Drive CarPlay
//
// Factory for all CarPlay CPTemplate objects.
// Uses ONLY Apple CarPlay framework templates — no custom views.
// CPListTemplate is the backbone for all menu/list screens.
// CPNowPlayingTemplate.shared is used for active prayer/audio sessions.
// CPAlertTemplate is used for safety messages and confirmations.
//
// Template hierarchy (max 5 levels deep per Apple guidelines):
//   Root (Tab or List) → Mode List → Sub-actions → Church/Prayer detail

import CarPlay
import UIKit

@MainActor
final class BereanCarPlayTemplates: NSObject {

    // Weak ref to the coordinator so templates can invoke actions
    weak var coordinator: BereanCarPlayCoordinator?

    init(coordinator: BereanCarPlayCoordinator? = nil) {
        self.coordinator = coordinator
    }

    // MARK: - Root Template

    /// Builds the Berean Drive home list — the root template.
    func makeHomeTemplate() -> CPListTemplate {
        let items: [CPListItem] = BereanDriveMode.allCases
            .filter { $0 != .home }
            .map { mode in
                let item = CPListItem(
                    text: mode.displayTitle,
                    detailText: subtitleForMode(mode)
                )
                item.accessoryType = .disclosureIndicator
                item.handler = { [weak self] _, completion in
                    self?.coordinator?.didSelectMode(mode)
                    completion()
                }
                return item
            }

        let section = CPListSection(items: items, header: "How can Berean help?", sectionIndexTitle: nil)
        let template = CPListTemplate(title: "Berean Drive", sections: [section])
        template.tabTitle = "Berean Drive"
        template.tabImage = UIImage(systemName: "car.fill")
        return template
    }

    // MARK: - Prayer Ride Template

    func makePrayerModeTemplate() -> CPListTemplate {
        let items: [CPListItem] = BereanPrayerMode.allCases.map { mode in
            let item = CPListItem(text: mode.displayTitle, detailText: mode.prayerPrompt)
            item.accessoryType = .disclosureIndicator
            item.handler = { [weak self] _, completion in
                self?.coordinator?.didSelectPrayerMode(mode)
                completion()
            }
            return item
        }

        let section = CPListSection(items: items, header: "Choose a prayer focus", sectionIndexTitle: nil)
        return CPListTemplate(title: "Prayer Ride", sections: [section])
    }

    // MARK: - Berean Voice Template

    func makeBereanVoiceTemplate(isListening: Bool = false) -> CPListTemplate {
        let statusText = isListening ? "Listening…" : "Tap to ask Berean a question"
        let voiceItem = CPListItem(text: statusText, detailText: "Examples: \"Explain Romans 8\" · \"Pray with me\"")
        voiceItem.handler = { [weak self] _, completion in
            self?.coordinator?.didTapBereanVoiceButton()
            completion()
        }

        let quickItems: [CPListItem] = [
            makeQuickItem(title: "Continue my Berean session", action: { [weak self] in
                self?.coordinator?.didTapContinueSession()
            }),
            makeQuickItem(title: "Summarize my Church Notes", action: { [weak self] in
                self?.coordinator?.didTapChurchNotesRecap()
            }),
            makeQuickItem(title: "Scripture Reflection", action: { [weak self] in
                self?.coordinator?.didSelectMode(.scriptureReflect)
            })
        ]

        let listenSection = CPListSection(items: [voiceItem], header: "Ask Berean", sectionIndexTitle: nil)
        let quickSection = CPListSection(items: quickItems, header: "Quick Actions", sectionIndexTitle: nil)
        return CPListTemplate(title: "Ask Berean", sections: [listenSection, quickSection])
    }

    // MARK: - Church Finder Template

    func makeChurchSearchLoadingTemplate() -> CPListTemplate {
        let item = CPListItem(text: "Finding nearby churches…", detailText: "Using your current location")
        let section = CPListSection(items: [item])
        return CPListTemplate(title: "Find a Church", sections: [section])
    }

    func makeChurchListTemplate(churches: [BereanDriveChurchResult]) -> CPListTemplate {
        guard !churches.isEmpty else {
            return makeChurchEmptyTemplate()
        }

        let items: [CPListItem] = churches.map { church in
            var detail = church.distanceLabel
            if let time = church.nextServiceTime { detail += " · Next: \(time)" }
            let item = CPListItem(text: church.name, detailText: detail.isEmpty ? church.address : detail)
            item.accessoryType = .disclosureIndicator
            item.handler = { [weak self] _, completion in
                self?.coordinator?.didSelectChurch(church)
                completion()
            }
            return item
        }

        let section = CPListSection(items: items, header: "Nearby Churches", sectionIndexTitle: nil)
        return CPListTemplate(title: "Find a Church", sections: [section])
    }

    func makeChurchDetailTemplate(church: BereanDriveChurchResult) -> CPListTemplate {
        var items: [CPListItem] = []

        if let address = church.address {
            let item = CPListItem(text: address, detailText: church.distanceLabel)
            items.append(item)
        }
        if let time = church.nextServiceTime {
            let item = CPListItem(text: "Next Service", detailText: time)
            items.append(item)
        }
        if let denomination = church.denomination {
            let item = CPListItem(text: "Denomination", detailText: denomination)
            items.append(item)
        }

        var actionItems: [CPListItem] = []

        if church.hasNavigation {
            let navItem = makeQuickItem(title: "Navigate There") { [weak self] in
                self?.coordinator?.didTapNavigateToChurch(church)
            }
            actionItems.append(navItem)
        }
        if let phone = church.phoneNumber, !phone.isEmpty {
            let callItem = makeQuickItem(title: "Call Church") { [weak self] in
                self?.coordinator?.didTapCallChurch(phone)
            }
            actionItems.append(callItem)
        }
        let saveItem = makeQuickItem(title: "Save for Later") { [weak self] in
            self?.coordinator?.didTapSaveChurch(church)
        }
        actionItems.append(saveItem)

        let infoSection = CPListSection(items: items, header: church.name, sectionIndexTitle: nil)
        let actionsSection = CPListSection(items: actionItems, header: "Actions", sectionIndexTitle: nil)
        return CPListTemplate(title: church.name, sections: [infoSection, actionsSection])
    }

    private func makeChurchEmptyTemplate() -> CPListTemplate {
        let item = CPListItem(
            text: "No churches found nearby",
            detailText: "Expand your search radius in Berean Drive settings"
        )
        let section = CPListSection(items: [item])
        return CPListTemplate(title: "Find a Church", sections: [section])
    }

    // MARK: - Messages Template

    func makeMessageListTemplate(messages: [BereanDriveMessagePreview]) -> CPListTemplate {
        guard !messages.isEmpty else {
            return makeMessagesEmptyTemplate()
        }

        // Use standard CPListItem (not CPMessageListItem) — keeps us off the
        // communication entitlement requirement for now.
        // CPMessageListItem requires the carplay-communication entitlement
        // and invokes Siri flows outside our safety control.
        let items: [CPListItem] = messages.prefix(BereanDriveResponsePolicy.maxMessagePreviews).map { message in
            let item = CPListItem(
                text: message.senderName,
                detailText: message.previewText
            )
            item.accessoryType = .disclosureIndicator
            item.handler = { [weak self] _, completion in
                self?.coordinator?.didSelectMessage(message)
                completion()
            }
            return item
        }

        let section = CPListSection(items: items, header: "Messages", sectionIndexTitle: nil)
        return CPListTemplate(title: "Small Group Messages", sections: [section])
    }

    private func makeMessagesEmptyTemplate() -> CPListTemplate {
        let item = CPListItem(text: "No new messages", detailText: "Check back when you're parked")
        let section = CPListSection(items: [item])
        return CPListTemplate(title: "Small Group Messages", sections: [section])
    }

    // MARK: - Message Reply Template

    /// Presents voice-dictation reply options for a single message in CarPlay.
    /// `isListening` controls the subtitle shown on the dictate item.
    func makeMessageReplyTemplate(
        message: BereanDriveMessagePreview,
        isListening: Bool = false
    ) -> CPListTemplate {
        let dictateItem = CPListItem(
            text: "Dictate Reply",
            detailText: isListening ? "Listening…" : "Tap to speak your reply"
        )
        dictateItem.accessoryType = .none
        dictateItem.handler = { [weak self] _, completion in
            self?.coordinator?.didTapDictateReply(for: message)
            completion()
        }

        let skipItem = CPListItem(text: "Skip — can't reply right now", detailText: nil)
        skipItem.accessoryType = .none
        skipItem.handler = { _, completion in
            completion()
        }

        let section = CPListSection(
            items: [dictateItem, skipItem],
            header: "Reply to \(message.senderName)",
            sectionIndexTitle: nil
        )
        return CPListTemplate(title: "Reply", sections: [section])
    }

    // MARK: - Now Playing Template (audio entitlement required)

    /// Configures the shared CPNowPlayingTemplate for an active prayer/audio session.
    /// Caller must hold the carplay-audio entitlement for this to display.
    /// Without entitlement, this is gracefully unused and CPListTemplate handles UI.
    func configureNowPlayingTemplate(
        mode: BereanDriveMode,
        onPause: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) {
        let nowPlaying = CPNowPlayingTemplate.shared
        nowPlaying.isUpNextButtonEnabled = false
        nowPlaying.isAlbumArtistButtonEnabled = false

        let pauseButton = CPNowPlayingImageButton(image: UIImage(systemName: "pause.fill")!) { _ in
            onPause()
        }
        let skipButton = CPNowPlayingImageButton(image: UIImage(systemName: "forward.fill")!) { _ in
            onSkip()
        }
        nowPlaying.updateNowPlayingButtons([pauseButton, skipButton])
    }

    // MARK: - Alert Templates

    /// Calm, generic safety alert — never explains what was blocked.
    func makeSafetyAlertTemplate(
        message: String = BereanCarPlaySafetyGate.calmDefaultMessage,
        onDismiss: @escaping () -> Void
    ) -> CPAlertTemplate {
        let action = CPAlertAction(title: "OK", style: .default) { _ in onDismiss() }
        return CPAlertTemplate(titleVariants: [message], actions: [action])
    }

    /// Handoff prompt — directs user to their iPhone for visual detail.
    func makeHandoffAlertTemplate(reason: String, onDismiss: @escaping () -> Void) -> CPAlertTemplate {
        let message = "More detail is available on your iPhone."
        let action = CPAlertAction(title: "Continue on iPhone", style: .default) { _ in onDismiss() }
        let dismiss = CPAlertAction(title: "Dismiss", style: .cancel) { _ in onDismiss() }
        return CPAlertTemplate(titleVariants: [message], actions: [action, dismiss])
    }

    // MARK: - Helpers

    private func makeQuickItem(title: String, action: @escaping () -> Void) -> CPListItem {
        let item = CPListItem(text: title, detailText: nil)
        item.accessoryType = .disclosureIndicator
        item.handler = { _, completion in
            action()
            completion()
        }
        return item
    }

    private func subtitleForMode(_ mode: BereanDriveMode) -> String {
        switch mode {
        case .home:             return ""
        case .prayerRide:       return "Guided prayer for your drive"
        case .bereanVoice:      return "Ask scripture questions by voice"
        case .scriptureReflect: return "Meditate on today's passage"
        case .sermonAudio:      return "Listen to a recent sermon"
        case .churchNoteRecap:  return "Hear your last sermon notes"
        case .findChurch:       return "Discover churches near you"
        case .messageGroup:     return "Listen to small group messages"
        }
    }
}
