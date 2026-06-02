import SwiftUI
import FirebaseFirestore

struct ChurchLivingNotesView: View {
    let churchId: String
    let churchName: String
    var note: ChurchNote?

    @State private var entries: [LivingEntry] = []
    @State private var listener: ListenerRegistration?

    struct GroupedEntries {
        let duringService: [LivingEntry]
        let afterService: [LivingEntry]
        let thisWeek: [LivingEntry]
        let reflections: [LivingEntry]
    }

    static func group(entries: [LivingEntry]) -> GroupedEntries {
        GroupedEntries(
            duringService: entries.filter { $0.type == .churchNote || $0.type == .sermonInsight },
            afterService: entries.filter { $0.type == .followUp || $0.type == .prayer },
            thisWeek: entries.filter { $0.intent == .spiritualGrowth || $0.intent == .churchVisit },
            reflections: entries.filter { $0.state == .needsReflection || $0.type == .reflection }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !duringService.isEmpty {
                section("During Service", entries: duringService)
            }
            if !afterService.isEmpty {
                section("After Service", entries: afterService)
            }
            if !thisWeek.isEmpty {
                section("This Week", entries: thisWeek)
            }
            if !reflections.isEmpty {
                section("Reflections", entries: reflections)
            }
        }
        .task {
            do {
                listener = try LivingEntryService.shared.observeChurchEntries(churchId: churchId) { updated in
                    entries = updated
                }
            } catch {
            }
        }
        .onDisappear {
            listener?.remove()
            listener = nil
        }
    }

    private var duringService: [LivingEntry] {
        entries.filter { $0.type == .churchNote || $0.type == .sermonInsight }
    }

    private var afterService: [LivingEntry] {
        entries.filter { $0.type == .followUp || $0.type == .prayer }
    }

    private var thisWeek: [LivingEntry] {
        entries.filter { $0.intent == .spiritualGrowth || $0.intent == .churchVisit }
    }

    private var reflections: [LivingEntry] {
        entries.filter { $0.state == .needsReflection || $0.type == .reflection }
    }

    @ViewBuilder
    private func section(_ title: String, entries: [LivingEntry]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            ForEach(entries.prefix(3)) { entry in
                LiquidGlassEntryCard(entry: entry, triggerReason: LivingEntryContextEngine.evaluate(entry: entry, context: .current()).matchedReasons.first)
            }
        }
    }
}
