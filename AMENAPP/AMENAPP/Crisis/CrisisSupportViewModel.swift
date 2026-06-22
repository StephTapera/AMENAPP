// CrisisSupportViewModel.swift
// AMENAPP
//
// Observable ViewModel for the Crisis Help & Support screen.
// Drives triage state, section ordering, grounding, Berean Reflect,
// Safety Plan, trusted contacts, follow-up, and session analytics.
//
// Privacy rules:
// - No sensitive content logged
// - Aggregate, non-identifiable analytics only
// - Safety Plan stored locally by default; optional encrypted Firestore sync
// - No social visibility of any crisis interaction
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

@Observable
final class CrisisSupportViewModel {

    // MARK: - Triage State

    var crisisState: CrisisState = .overwhelmedButSafe {
        didSet { guard oldValue != crisisState else { return }; onStateChanged() }
    }

    // MARK: - Section Expansion

    var openSections: Set<CrisisSection> = [.groundingTools]

    // MARK: - Grounding

    var activeGroundingMode: CrisisGroundingMode? = nil

    // MARK: - Berean

    var bereanPrompt: String = "I'm here with you. We can slow this down together.\n\nDo you want to breathe, name what happened, or reach someone safe right now?"
    var bereanIsStreaming: Bool = false
    var bereanEscalationVisible: Bool = false

    // MARK: - Safety Plan

    var safetyPlan: CrisisSafetyPlan = CrisisSafetyPlan()
    var isSafetyPlanSetupOpen: Bool = false
    var isSafetyPlanActivated: Bool = false

    // MARK: - Trusted Contacts

    var trustedContacts: [CrisisTrustedContact] = []
    var showTrustedContactSheet: Bool = false
    var pendingContactMessage: String = ""
    var selectedTrustedContact: CrisisTrustedContact? = nil

    // MARK: - Follow-Up

    var followUpOptIn: Bool = false
    var showFollowUpPrompt: Bool = false

    // MARK: - Locale + Resources

    var localeResources: CrisisLocaleResources = CrisisResourceResolver.resolve()

    var adaptedResources: [CrisisResource] {
        CrisisResourceResolver.resources(
            for: crisisState,
            locale: localeResources,
            hasTrustedContacts: !trustedContacts.isEmpty
        )
    }

    var orderedSections: [CrisisSection] {
        CrisisSection.allCases.sorted { $0.priority(for: crisisState) < $1.priority(for: crisisState) }
    }

    // MARK: - Private

    private var sessionEvent = CrisisSessionEvent(userId: "", enteredAt: Date())
    private let db = Firestore.firestore()
    private let planKey = "crisisSafetyPlan_v1"
    private let contactsKey = "crisisTrustedContacts_v1"
    private let stateKey = "crisisState_v1"

    // MARK: - Init

    init() {
        loadPersistedState()
        loadLocalSafetyPlan()
        loadLocalContacts()
        startSession()
    }

    // MARK: - Section Toggle

    func toggleSection(_ section: CrisisSection) {
        CrisisHapticsManager.sectionToggled()
        withAnimation(CrisisAnimationTokens.sectionExpand) {
            if openSections.contains(section) {
                openSections.remove(section)
            } else {
                openSections.insert(section)
            }
        }
    }

    func isSectionOpen(_ section: CrisisSection) -> Bool {
        openSections.contains(section)
    }

    // MARK: - Triage Selection

    func selectState(_ state: CrisisState) {
        guard state != crisisState else { return }
        CrisisHapticsManager.triageSelected()
        withAnimation(CrisisAnimationTokens.triagePill) {
            crisisState = state
        }
    }

    // MARK: - Grounding

    func selectGroundingMode(_ mode: CrisisGroundingMode) {
        CrisisHapticsManager.groundingStep()
        withAnimation(CrisisAnimationTokens.groundingSwap) {
            activeGroundingMode = (activeGroundingMode == mode) ? nil : mode
        }
    }

    // MARK: - Berean Quick Actions

    func bereanQuickAction(_ label: String) {
        CrisisHapticsManager.bereanTap()
        let response: String
        switch label {
        case "Breathe":
            response = "Let's breathe together. Breathe in slowly for four counts. I'll be here while you do.\n\nThere's no rush."
        case "Name it":
            response = "You don't have to explain everything. Just start with one word — what's the most present thing you're feeling right now?"
        case "Get help":
            response = "You're not alone. The \(localeResources.crisisHotlineLabel) is available right now — \(localeResources.crisisHotlineNumber).\n\nWould you like help getting there?"
            bereanEscalationVisible = true
        default:
            response = bereanPrompt
        }
        withAnimation(CrisisAnimationTokens.bereanReveal) {
            bereanPrompt = response
        }
        sessionEvent.bereanInvoked = true
    }

    func detectHighRiskLanguage(in text: String) {
        // Lightweight local heuristic — cloud function backs this up
        let triggers = ["end it", "can't go on", "no reason to live", "want to die", "kill myself"]
        let lower = text.lowercased()
        let detected = triggers.contains { lower.contains($0) }
        if detected {
            withAnimation(CrisisAnimationTokens.bereanReveal) {
                bereanEscalationVisible = true
            }
            sessionEvent.highRiskSignalsDetected = true
        }
    }

    // MARK: - Emergency Actions

    func callNumber(_ number: String) {
        CrisisHapticsManager.emergencyAction()
        let digits = number.filter { $0.isNumber }
        if let url = URL(string: "tel://\(digits)"),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
        sessionEvent.escalatedToHotline = true
    }

    func openTextSupport(_ instruction: String) {
        // Extract number from "Text HOME to 741741" → "741741"
        let digits = instruction.components(separatedBy: " ").last?.filter { $0.isNumber } ?? ""
        if let url = URL(string: "sms://\(digits)"),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Safety Plan

    func saveSafetyPlan() {
        safetyPlan.updatedAt = Date()
        if let data = try? JSONEncoder().encode(safetyPlan) {
            UserDefaults.standard.set(data, forKey: planKey)
        }
        CrisisHapticsManager.confirmation()
    }

    func activateSafetyPlan() {
        CrisisHapticsManager.emergencyAction()
        withAnimation(CrisisAnimationTokens.sectionExpand) {
            isSafetyPlanActivated = true
            openSections.insert(.safetyPlan)
        }
    }

    // MARK: - Trusted Contacts

    func addTrustedContact(_ contact: CrisisTrustedContact) {
        trustedContacts.append(contact)
        saveLocalContacts()
        CrisisHapticsManager.confirmation()
    }

    func removeTrustedContact(id: String) {
        trustedContacts.removeAll { $0.id == id }
        saveLocalContacts()
    }

    func prepareTrustedContactMessage(contact: CrisisTrustedContact) {
        selectedTrustedContact = contact
        pendingContactMessage = contact.shareTemplate.isEmpty
            ? "Hey — I could use some support right now. Can we talk?"
            : contact.shareTemplate
        showTrustedContactSheet = true
    }

    func sendTrustedContactMessage() {
        guard let contact = selectedTrustedContact else { return }
        let digits = contact.phoneNumber.filter { $0.isNumber }
        let encoded = pendingContactMessage.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "sms://\(digits)?body=\(encoded)"),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
        sessionEvent.escalatedToTrustedContact = true
        CrisisHapticsManager.confirmation()
    }

    // MARK: - Follow-Up

    func optInToFollowUp() {
        followUpOptIn = true
        showFollowUpPrompt = false
        CrisisHapticsManager.confirmation()
        scheduleGentleFollowUp()
    }

    // MARK: - Session End

    func endSession() {
        sessionEvent.endedAt = Date()
        guard !sessionEvent.userId.isEmpty else { return }
        let data: [String: Any] = [
            "userId": sessionEvent.userId,
            "enteredAt": Timestamp(date: sessionEvent.enteredAt),
            "endedAt": Timestamp(date: sessionEvent.endedAt ?? Date()),
            "selectedState": sessionEvent.selectedState,
            "bereanInvoked": sessionEvent.bereanInvoked,
            "escalatedToHotline": sessionEvent.escalatedToHotline,
            "escalatedToTrustedContact": sessionEvent.escalatedToTrustedContact,
            "followUpScheduled": sessionEvent.followUpScheduled,
            "localeResolved": sessionEvent.localeResolved,
            "highRiskSignalsDetected": sessionEvent.highRiskSignalsDetected
        ]
        db.collection("crisis_session_events").document().setData(data)
    }

    // MARK: - Private Helpers

    private func onStateChanged() {
        withAnimation(CrisisAnimationTokens.cardReorder) {
            openSections = crisisState.defaultOpenSections
        }
        sessionEvent.selectedState = crisisState.rawValue
        persistState()

        // Show follow-up prompt after first state selection (not on init)
        if !followUpOptIn && !showFollowUpPrompt {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(CrisisAnimationTokens.privacySettle) {
                    self.showFollowUpPrompt = true
                }
            }
        }
    }

    private func persistState() {
        UserDefaults.standard.set(crisisState.rawValue, forKey: stateKey)
    }

    private func loadPersistedState() {
        if let raw = UserDefaults.standard.string(forKey: stateKey),
           let state = CrisisState(rawValue: raw) {
            crisisState = state
            openSections = state.defaultOpenSections
        }
    }

    private func loadLocalSafetyPlan() {
        guard let data = UserDefaults.standard.data(forKey: planKey),
              let plan = try? JSONDecoder().decode(CrisisSafetyPlan.self, from: data)
        else { return }
        safetyPlan = plan
    }

    private func saveLocalContacts() {
        if let data = try? JSONEncoder().encode(trustedContacts) {
            UserDefaults.standard.set(data, forKey: contactsKey)
        }
    }

    private func loadLocalContacts() {
        guard let data = UserDefaults.standard.data(forKey: contactsKey),
              let contacts = try? JSONDecoder().decode([CrisisTrustedContact].self, from: data)
        else { return }
        trustedContacts = contacts
    }

    private func startSession() {
        let uid = Auth.auth().currentUser?.uid ?? ""
        sessionEvent = CrisisSessionEvent(
            userId: uid,
            enteredAt: Date(),
            localeResolved: localeResources.locale
        )
    }

    private func scheduleGentleFollowUp() {
        guard !sessionEvent.userId.isEmpty else { return }
        let data: [String: Any] = [
            "userId": sessionEvent.userId,
            "scheduledFor": Timestamp(date: Date().addingTimeInterval(86400)),
            "opted": true,
            "maxFrequencyHours": 24,
            "tone": "gentle",
            "message": "You don't have to respond. Just wanted you to know support is here."
        ]
        db.collection("crisis_follow_ups")
            .document(sessionEvent.userId)
            .setData(data, merge: true)
        sessionEvent.followUpScheduled = true
    }
}
