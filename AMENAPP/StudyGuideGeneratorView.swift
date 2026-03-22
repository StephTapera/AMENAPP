// StudyGuideGeneratorView.swift
// AMENAPP
//
// Small Group Study Guide Generator:
//   - Input: any ChurchNote (sermon recording, snap, or manual note)
//   - Calls generateStudyGuide Cloud Function (Claude claude-sonnet-4-6)
//   - Returns structured guide: big idea, discussion questions, scripture passages, action steps
//   - "Save as Note" exports the guide as a new ChurchNote
//   - "Share" lets users share the guide as text
//   - Entry point: StudyGuideButton (added to ChurchNotesEditor toolbar / note detail)

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// MARK: - StudyGuide model

struct StudyGuide {
    var bigIdea: String
    var context: String
    var discussionQuestions: [DiscussionQuestion]
    var scriptureDeep: [String]         // 2–3 passages for deeper study
    var actionSteps: [String]
    var closingPrayer: String

    struct DiscussionQuestion: Identifiable {
        let id = UUID()
        let question: String
        let depth: QuestionDepth
    }

    enum QuestionDepth: String {
        case opening     = "Opening"
        case exploration = "Exploration"
        case application = "Application"
    }

    var isEmpty: Bool { bigIdea.isEmpty && discussionQuestions.isEmpty }
}

// MARK: - StudyGuideService

@MainActor
final class StudyGuideService: ObservableObject {
    @Published var guide: StudyGuide?
    @Published var isGenerating = false
    @Published var error: String?

    private let functions = Functions.functions()

    func generate(from note: ChurchNote) async {
        isGenerating = true
        error        = nil
        defer { isGenerating = false }

        let content = [
            note.title,
            note.content,
            note.keyPoints.joined(separator: "\n"),
            note.scriptureReferences.joined(separator: ", ")
        ].filter { !$0.isEmpty }.joined(separator: "\n\n")

        do {
            let result = try await functions.httpsCallable("generateStudyGuide").call([
                "noteTitle": note.title,
                "noteContent": content
            ])
            guard let data = result.data as? [String: Any] else {
                error = "Unexpected server response."
                return
            }
            guide = parseGuide(data)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func parseGuide(_ d: [String: Any]) -> StudyGuide {
        let rawQuestions = d["discussionQuestions"] as? [[String: String]] ?? []
        let questions = rawQuestions.map { q in
            StudyGuide.DiscussionQuestion(
                question: q["question"] ?? "",
                depth: StudyGuide.QuestionDepth(rawValue: q["depth"]?.capitalized ?? "") ?? .exploration
            )
        }
        return StudyGuide(
            bigIdea:              (d["bigIdea"]          as? String) ?? "",
            context:              (d["context"]          as? String) ?? "",
            discussionQuestions:  questions,
            scriptureDeep:        (d["scriptureDeep"]    as? [String]) ?? [],
            actionSteps:          (d["actionSteps"]      as? [String]) ?? [],
            closingPrayer:        (d["closingPrayer"]    as? String) ?? ""
        )
    }
}

// MARK: - StudyGuideView

struct StudyGuideView: View {
    let sourceNote: ChurchNote
    @StateObject private var service     = StudyGuideService()
    @StateObject private var notesService = ChurchNotesService()
    @State private var savedToNotes = false
    @State private var showShareSheet = false
    @State private var shareText = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Group {
                if service.isGenerating {
                    generatingState
                } else if let g = service.guide, !g.isEmpty {
                    guideContent(g)
                } else if let err = service.error {
                    errorState(err)
                } else {
                    promptState
                }
            }
            .navigationTitle("Study Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                if service.guide != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button {
                                saveAsNote()
                            } label: {
                                Label(savedToNotes ? "Saved" : "Save as Note",
                                      systemImage: savedToNotes ? "checkmark" : "note.text.badge.plus")
                            }
                            .disabled(savedToNotes)

                            Button {
                                buildShareText()
                                showShareSheet = true
                            } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityView(text: shareText)
        }
        .task { await service.generate(from: sourceNote) }
    }

    // MARK: - States

    private var generatingState: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Generating study guide…")
                .font(.system(size: 14))
                .foregroundStyle(Color(.secondaryLabel))
            Text("This may take a moment.")
                .font(.system(size: 12))
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var promptState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color(.tertiaryLabel))
            Text("Tap Generate to create a small group study guide from this sermon note.")
                .font(.system(size: 14))
                .foregroundStyle(Color(.secondaryLabel))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Generate Guide") {
                Task { await service.generate(from: sourceNote) }
            }
            .font(.system(size: 15, weight: .semibold))
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color(.label), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(Color(.systemBackground))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Text(msg).foregroundStyle(.red).font(.system(size: 14))
            Button("Retry") { Task { await service.generate(from: sourceNote) } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Guide content

    @ViewBuilder
    private func guideContent(_ g: StudyGuide) -> some View {
        List {
            // Big idea
            if !g.bigIdea.isEmpty {
                Section(header: sectionHeader("Big Idea")) {
                    Text(g.bigIdea)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(.label))
                }
            }

            // Context
            if !g.context.isEmpty {
                Section(header: sectionHeader("Background")) {
                    Text(g.context)
                        .font(.system(size: 15))
                        .foregroundStyle(Color(.secondaryLabel))
                }
            }

            // Discussion questions grouped by depth
            let grouped = Dictionary(grouping: g.discussionQuestions) { $0.depth }
            ForEach([StudyGuide.QuestionDepth.opening, .exploration, .application], id: \.rawValue) { depth in
                if let qs = grouped[depth], !qs.isEmpty {
                    Section(header: sectionHeader("\(depth.rawValue) Questions")) {
                        ForEach(qs) { q in
                            HStack(alignment: .top, spacing: 10) {
                                Text("Q")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color(.tertiaryLabel))
                                    .padding(.top, 2)
                                Text(q.question)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color(.label))
                            }
                        }
                    }
                }
            }

            // Scripture for deeper study
            if !g.scriptureDeep.isEmpty {
                Section(header: sectionHeader("Dig Deeper")) {
                    ForEach(g.scriptureDeep, id: \.self) { ref in
                        Text(ref)
                            .font(.system(size: 15))
                            .foregroundStyle(.purple)
                    }
                }
            }

            // Action steps
            if !g.actionSteps.isEmpty {
                Section(header: sectionHeader("This Week")) {
                    ForEach(g.actionSteps, id: \.self) { step in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(.secondaryLabel))
                                .padding(.top, 2)
                            Text(step)
                                .font(.system(size: 15))
                        }
                    }
                }
            }

            // Closing prayer
            if !g.closingPrayer.isEmpty {
                Section(header: sectionHeader("Closing Prayer")) {
                    Text(g.closingPrayer)
                        .font(.system(size: 15))
                        .foregroundStyle(Color(.secondaryLabel))
                        .italic()
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color(.secondaryLabel))
    }

    // MARK: - Actions

    private func saveAsNote() {
        guard let uid = Auth.auth().currentUser?.uid, let g = service.guide else { return }
        var content = ""
        if !g.bigIdea.isEmpty        { content += "Big Idea: \(g.bigIdea)\n\n" }
        if !g.context.isEmpty        { content += "Background: \(g.context)\n\n" }
        if !g.discussionQuestions.isEmpty {
            content += "Discussion Questions:\n" + g.discussionQuestions.map { "• \($0.question)" }.joined(separator: "\n") + "\n\n"
        }
        if !g.actionSteps.isEmpty    { content += "This Week:\n" + g.actionSteps.map { "• \($0)" }.joined(separator: "\n") }

        let note = ChurchNote(
            userId:  uid,
            title:   "Study Guide — \(sourceNote.title)",
            date:    Date(),
            content: content,
            keyPoints: [],
            tags:    ["study-guide", "small-group"],
            scriptureReferences: g.scriptureDeep
        )
        Task {
            try? await notesService.createNote(note)
            await MainActor.run { savedToNotes = true }
        }
    }

    private func buildShareText() {
        guard let g = service.guide else { return }
        var parts = ["📖 \(sourceNote.title) — Study Guide", ""]
        if !g.bigIdea.isEmpty { parts += ["**Big Idea:** \(g.bigIdea)", ""] }
        if !g.discussionQuestions.isEmpty {
            parts += ["Discussion Questions:"]
            parts += g.discussionQuestions.map { "\($0.question)" }
            parts += [""]
        }
        if !g.actionSteps.isEmpty {
            parts += ["This Week:"]
            parts += g.actionSteps.map { "• \($0)" }
        }
        shareText = parts.joined(separator: "\n")
    }
}

// MARK: - StudyGuideButton (entry point)

struct StudyGuideButton: View {
    let note: ChurchNote
    @State private var showGuide = false

    var body: some View {
        Button {
            showGuide = true
        } label: {
            Label("Study Guide", systemImage: "person.3.fill")
                .font(.system(size: 13))
        }
        .sheet(isPresented: $showGuide) {
            StudyGuideView(sourceNote: note)
        }
    }
}

// MARK: - ActivityView (UIActivityViewController wrapper)

private struct ActivityView: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}
