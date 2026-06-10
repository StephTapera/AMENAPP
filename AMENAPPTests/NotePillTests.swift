import Testing
@testable import AMENAPP

@Suite("Note Pill")
struct NotePillTests {
    @Test("Only available state is tappable")
    func availableStateIsTappable() {
        #expect(NotePillPresentation.isEnabled(for: .available))
        #expect(!NotePillPresentation.isEnabled(for: .unavailable))
        #expect(!NotePillPresentation.isEnabled(for: .loading))
    }

    @Test("State icons are stable")
    func stateIconsAreStable() {
        #expect(NotePillPresentation.iconName(for: .available) == "note.text")
        #expect(NotePillPresentation.iconName(for: .unavailable) == "lock.slash")
        #expect(NotePillPresentation.iconName(for: .loading) == "hourglass")
    }

    @Test("Accessibility labels include trimmed context and state")
    func accessibilityLabelsIncludeContextAndState() {
        #expect(
            NotePillPresentation.accessibilityLabel(
                title: "Sunday Notes",
                context: "  Romans 8  ",
                state: .available
            ) == "Open note, Sunday Notes, Romans 8"
        )
        #expect(
            NotePillPresentation.accessibilityLabel(
                title: "Sunday Notes",
                context: " ",
                state: .unavailable
            ) == "Note unavailable, Sunday Notes"
        )
        #expect(
            NotePillPresentation.accessibilityLabel(
                title: "Sunday Notes",
                context: nil,
                state: .loading
            ) == "Loading note, Sunday Notes"
        )
    }

    @Test("Accessibility hints describe state outcome")
    func accessibilityHintsDescribeStateOutcome() {
        #expect(NotePillPresentation.accessibilityHint(for: .available) == "Opens the shared note")
        #expect(NotePillPresentation.accessibilityHint(for: .unavailable) == "This shared note cannot be opened right now")
        #expect(NotePillPresentation.accessibilityHint(for: .loading) == "The shared note is still loading")
    }
}
