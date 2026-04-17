//
//  ChurchNotesTabSystem.swift
//  AMENAPP
//
//  Data models and ViewModel for the tabbed Church Note detail experience.
//  Designed to be embedded in ChurchNoteDetailTabView (does not modify existing views).
//

import Foundation
import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth

// MARK: - Tab Definitions

enum ChurchNoteTab: String, CaseIterable {
    case journal    = "Journal"
    case transcript = "Transcript"
    case summary    = "Summary"
    case scriptures = "Scriptures"
    case reflection = "Reflection"
    case audio      = "Audio"

    var icon: String {
        switch self {
        case .journal:    return "pencil"
        case .transcript: return "text.alignleft"
        case .summary:    return "sparkles"
        case .scriptures: return "book"
        case .reflection: return "heart"
        case .audio:      return "waveform"
        }
    }
}

// MARK: - Reflection Answer

struct ReflectionAnswer: Codable, Identifiable {
    var id: String = UUID().uuidString
    var noteId: String
    var promptIndex: Int
    var answer: String
    var answeredAt: Date = Date()
}

// MARK: - ViewModel

@MainActor
final class ChurchNoteTabViewModel: ObservableObject {
    let note: ChurchNote

    @Published var activeTab: ChurchNoteTab = .journal
    @Published var organizedNote: OrganizedSermonNote?
    @Published var reflectionAnswers: [ReflectionAnswer] = []
    @Published var reflectionPrompts: ReflectionPromptSet?
    @Published var captureSession: SermonCaptureSession?
    @Published var isOrganizing: Bool = false
    @Published var organizationComplete: Bool = false

    private let organizeService = ChurchNotesOrganizeService.shared
    private let captureService = ChurchNotesSermonCaptureService.shared
    private lazy var db = Firestore.firestore()

    init(note: ChurchNote) {
        self.note = note
        // Surface active capture session if it matches this note
        if let session = ChurchNotesSermonCaptureService.shared.currentSession,
           session.noteId == note.id {
            self.captureSession = session
        }
    }

    // MARK: - Organize with Berean

    func organizeWithBerean() async {
        isOrganizing = true
        do {
            organizedNote = try await organizeService.organizeNote(
                rawContent: note.content,
                transcript: note.richContentJSON,
                churchName: note.churchName,
                speakerName: note.pastor,
                serviceDate: note.createdAt
            )
            if let organized = organizedNote {
                reflectionPrompts = await organizeService.generateReflectionPrompts(for: organized)
            }
            organizationComplete = true
        } catch {
            dlog("ChurchNoteTabViewModel organizeWithBerean error: \(error)")
        }
        isOrganizing = false
    }

    // MARK: - Reflection Answers

    func saveReflectionAnswer(_ answer: String, for promptIndex: Int) async {
        guard let uid = Auth.auth().currentUser?.uid,
              let noteId = note.id else { return }

        let docId = "\(noteId)_\(promptIndex)"
        let entry = ReflectionAnswer(
            noteId: noteId,
            promptIndex: promptIndex,
            answer: answer
        )

        do {
            try db.collection("users")
                .document(uid)
                .collection("churchNoteReflections")
                .document(docId)
                .setData(from: entry, merge: true)

            // Update local state
            if let idx = reflectionAnswers.firstIndex(where: { $0.promptIndex == promptIndex }) {
                reflectionAnswers[idx] = entry
            } else {
                reflectionAnswers.append(entry)
            }
        } catch {
            dlog("ChurchNoteTabViewModel saveReflectionAnswer error: \(error)")
        }
    }

    func loadReflectionAnswers() async {
        guard let uid = Auth.auth().currentUser?.uid,
              let noteId = note.id else { return }
        do {
            let snapshot = try await db.collection("users")
                .document(uid)
                .collection("churchNoteReflections")
                .whereField("noteId", isEqualTo: noteId)
                .getDocuments()
            reflectionAnswers = snapshot.documents.compactMap { try? $0.data(as: ReflectionAnswer.self) }
        } catch {
            dlog("ChurchNoteTabViewModel loadReflectionAnswers error: \(error)")
        }
    }

    // MARK: - Computed Properties

    var detectedScriptures: [String] {
        organizeService.detectScriptureReferences(in: note.content)
    }

    var transcriptText: String {
        note.richContentJSON ?? ""
    }

    func answer(for promptIndex: Int) -> String {
        reflectionAnswers.first { $0.promptIndex == promptIndex }?.answer ?? ""
    }
}

// MARK: - ChurchNoteDetailTabView

struct ChurchNoteDetailTabView: View {
    @StateObject private var vm: ChurchNoteTabViewModel

    init(note: ChurchNote) {
        _vm = StateObject(wrappedValue: ChurchNoteTabViewModel(note: note))
    }

    var body: some View {
        VStack(spacing: 0) {
            tabPillRow
            Divider().opacity(0.15)
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await vm.loadReflectionAnswers() }
    }

    // MARK: - Tab Pill Row

    private var tabPillRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ChurchNoteTab.allCases, id: \.self) { tab in
                    tabPill(tab)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(.ultraThinMaterial)
    }

    private func tabPill(_ tab: ChurchNoteTab) -> some View {
        Button {
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                vm.activeTab = tab
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.systemScaled(12, weight: .medium))
                Text(tab.rawValue)
                    .font(.systemScaled(13, weight: .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                if vm.activeTab == tab {
                    Capsule()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
                } else {
                    Capsule()
                        .fill(Color.white.opacity(0.35))
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.5), lineWidth: 0.5)
                        )
                }
            }
            .foregroundColor(vm.activeTab == tab ? .black : .black.opacity(0.55))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab Content Router

    @ViewBuilder
    private var tabContent: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                switch vm.activeTab {
                case .journal:    journalTabContent
                case .transcript: transcriptTabContent
                case .summary:    summaryTabContent
                case .scriptures: scripturesTabContent
                case .reflection: reflectionTabContent
                case .audio:      audioTabContent
                }
            }
            .padding(16)
        }
    }

    // MARK: - Journal Tab

    private var journalTabContent: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Your Notes", systemImage: "pencil")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundColor(.black.opacity(0.45))

                Text(vm.note.content.isEmpty ? "No notes yet. Open the editor to start writing." : vm.note.content)
                    .font(.systemScaled(15))
                    .foregroundColor(vm.note.content.isEmpty ? .black.opacity(0.35) : .black)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Transcript Tab

    private var transcriptTabContent: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Sermon Transcript", systemImage: "text.alignleft")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundColor(.black.opacity(0.45))

                if vm.transcriptText.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "waveform.slash")
                            .font(.systemScaled(32))
                            .foregroundColor(.black.opacity(0.2))
                        Text("No transcript yet.")
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundColor(.black.opacity(0.5))
                        Text("Start recording to capture sermon audio.")
                            .font(.systemScaled(13))
                            .foregroundColor(.black.opacity(0.35))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    Text(vm.transcriptText)
                        .font(.systemScaled(15))
                        .foregroundColor(.black)
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Summary Tab

    private var summaryTabContent: some View {
        VStack(spacing: 14) {
            if let organized = vm.organizedNote {
                organizedSummaryView(organized)
            } else {
                bereanOrganizePromptCard(
                    title: "Organize with Berean",
                    subtitle: "Turn your raw notes into a structured sermon summary, complete with key points, themes, and action steps.",
                    icon: "sparkles"
                )
            }
        }
    }

    // MARK: - Scriptures Tab

    private var scripturesTabContent: some View {
        VStack(spacing: 12) {
            if vm.detectedScriptures.isEmpty {
                glassCard {
                    VStack(spacing: 8) {
                        Image(systemName: "book.closed")
                            .font(.systemScaled(32))
                            .foregroundColor(.black.opacity(0.2))
                        Text("No scriptures detected yet.")
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundColor(.black.opacity(0.5))
                        Text("Scripture references in your notes will appear here automatically.")
                            .font(.systemScaled(13))
                            .foregroundColor(.black.opacity(0.35))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else {
                ForEach(vm.detectedScriptures, id: \.self) { ref in
                    scriptureCard(ref)
                }
            }

            // Also show scriptures from organized note if available
            if let organized = vm.organizedNote {
                let extra = organized.scriptures.filter { !vm.detectedScriptures.contains($0) }
                if !extra.isEmpty {
                    glassCard {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("From Berean Summary")
                                .font(.systemScaled(11, weight: .semibold))
                                .foregroundColor(.black.opacity(0.35))
                                .padding(.bottom, 4)
                            ForEach(extra, id: \.self) { ref in
                                HStack {
                                    Image(systemName: "book.fill")
                                        .font(.systemScaled(12))
                                        .foregroundColor(.black.opacity(0.4))
                                    Text(ref)
                                        .font(.systemScaled(14, weight: .medium))
                                        .foregroundColor(.black)
                                    Spacer()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Reflection Tab

    private var reflectionTabContent: some View {
        VStack(spacing: 14) {
            if let prompts = vm.reflectionPrompts {
                reflectionPromptsView(prompts)
            } else if vm.organizedNote == nil {
                bereanOrganizePromptCard(
                    title: "Generate Reflection Prompts",
                    subtitle: "Berean will create personalized questions to help you internalize what God said through this message.",
                    icon: "heart.text.square.fill"
                )
            } else {
                glassCard {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                            .font(.systemScaled(28))
                            .foregroundColor(.black.opacity(0.25))
                        Text("Generating reflection prompts...")
                            .font(.systemScaled(14))
                            .foregroundColor(.black.opacity(0.45))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            }
        }
    }

    // MARK: - Audio Tab

    private var audioTabContent: some View {
        glassCard {
            VStack(spacing: 16) {
                if let session = vm.captureSession {
                    waveformSessionView(session)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "waveform")
                            .font(.systemScaled(36))
                            .foregroundColor(.black.opacity(0.18))
                        Text("No recording yet.")
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundColor(.black.opacity(0.5))
                        Text("Start Sermon Capture to record audio while you take notes.")
                            .font(.systemScaled(13))
                            .foregroundColor(.black.opacity(0.35))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            }
        }
    }

    // MARK: - Component Views

    @ViewBuilder
    private func organizedSummaryView(_ organized: OrganizedSermonNote) -> some View {
        // Title
        glassCard {
            VStack(alignment: .leading, spacing: 4) {
                Text(organized.title)
                    .font(.systemScaled(18, weight: .bold))
                    .foregroundColor(.black)
                if let subtitle = organized.subtitle {
                    Text(subtitle)
                        .font(.systemScaled(13, weight: .medium))
                        .foregroundColor(.black.opacity(0.5))
                }
                Text(organized.mainMessage)
                    .font(.systemScaled(14))
                    .foregroundColor(.black.opacity(0.7))
                    .lineSpacing(4)
                    .padding(.top, 4)
            }
        }

        // Key Points
        if !organized.keyPoints.isEmpty {
            glassCard {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("Key Points", icon: "list.bullet")
                    ForEach(Array(organized.keyPoints.enumerated()), id: \.offset) { index, point in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.systemScaled(12, weight: .bold))
                                .foregroundColor(.black.opacity(0.4))
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Color.black.opacity(0.07)))
                            Text(point)
                                .font(.systemScaled(14))
                                .foregroundColor(.black)
                                .lineSpacing(3)
                        }
                    }
                }
            }
        }

        // Themes
        if !organized.themes.isEmpty {
            glassCard {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("Themes", icon: "tag")
                    AMENFlowLayout(spacing: 8) {
                        ForEach(organized.themes, id: \.self) { theme in
                            Text(theme.capitalized)
                                .font(.systemScaled(12, weight: .medium))
                                .foregroundColor(.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.06))
                                        .overlay(Capsule().strokeBorder(Color.black.opacity(0.1), lineWidth: 0.5))
                                )
                        }
                    }
                }
            }
        }

        // Takeaways & Action Steps
        if !organized.personalTakeaways.isEmpty || !organized.actionSteps.isEmpty {
            glassCard {
                VStack(alignment: .leading, spacing: 12) {
                    if !organized.personalTakeaways.isEmpty {
                        sectionHeader("Personal Takeaways", icon: "heart.text.square")
                        ForEach(organized.personalTakeaways, id: \.self) { item in
                            bulletRow(item)
                        }
                    }
                    if !organized.actionSteps.isEmpty {
                        sectionHeader("Action Steps", icon: "checkmark.circle")
                        ForEach(organized.actionSteps, id: \.self) { item in
                            bulletRow(item)
                        }
                    }
                }
            }
        }

        // Prayer Response
        if !organized.prayerResponse.isEmpty {
            glassCard {
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("Prayer Response", icon: "hands.sparkles")
                    Text(organized.prayerResponse)
                        .font(.systemScaled(14).italic())
                        .foregroundColor(.black.opacity(0.7))
                        .lineSpacing(4)
                }
            }
        }

        // Questions to Revisit
        if !organized.questionsToRevisit.isEmpty {
            glassCard {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("Questions to Revisit", icon: "questionmark.circle")
                    ForEach(organized.questionsToRevisit, id: \.self) { q in
                        bulletRow(q)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func reflectionPromptsView(_ promptSet: ReflectionPromptSet) -> some View {
        ForEach(Array(promptSet.prompts.enumerated()), id: \.offset) { index, prompt in
            ChurchNotesReflectionPromptCard(
                prompt: prompt,
                promptIndex: index,
                existingAnswer: vm.answer(for: index),
                onSave: { answer in
                    Task { await vm.saveReflectionAnswer(answer, for: index) }
                }
            )
        }

        // Growth Loop info card
        glassCard {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Growth Loop", icon: "arrow.triangle.2.circlepath")
                Text("Come back to this note:")
                    .font(.systemScaled(12))
                    .foregroundColor(.black.opacity(0.4))
                growthLoopRow("24 hours", prompt: promptSet.growthLoopSchedule.day1Prompt)
                growthLoopRow("3 days", prompt: promptSet.growthLoopSchedule.day3Prompt)
                growthLoopRow("7 days", prompt: promptSet.growthLoopSchedule.day7Prompt)
            }
        }
    }

    private func growthLoopRow(_ label: String, prompt: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.systemScaled(11, weight: .semibold))
                .foregroundColor(.black.opacity(0.4))
                .frame(width: 54, alignment: .leading)
            Text(prompt)
                .font(.systemScaled(13))
                .foregroundColor(.black.opacity(0.7))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func scriptureCard(_ ref: String) -> some View {
        glassCard {
            HStack {
                Image(systemName: "book.fill")
                    .font(.systemScaled(14))
                    .foregroundColor(.black.opacity(0.4))
                Text(ref)
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundColor(.black)
                Spacer()
                Button {
                    // "Study with Berean" — open Berean with this reference
                } label: {
                    Text("Study")
                        .font(.systemScaled(12, weight: .medium))
                        .foregroundColor(.black.opacity(0.6))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.6))
                                .overlay(Capsule().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func waveformSessionView(_ session: SermonCaptureSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Recorded Session", icon: "waveform")
            if let church = session.churchName {
                infoRow("Church", value: church)
            }
            if let speaker = session.speakerName {
                infoRow("Speaker", value: speaker)
            }
            infoRow("Duration", value: formatDuration(session.durationSeconds))
            infoRow("Date", value: session.serviceDate.formatted(date: .abbreviated, time: .omitted))

            if let transcript = session.transcript, !transcript.isEmpty {
                Divider().opacity(0.15)
                Text("Transcript")
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundColor(.black.opacity(0.4))
                Text(transcript)
                    .font(.systemScaled(13))
                    .foregroundColor(.black.opacity(0.7))
                    .lineSpacing(3)
            }
        }
    }

    private func bereanOrganizePromptCard(title: String, subtitle: String, icon: String) -> some View {
        glassCard {
            VStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.systemScaled(30))
                    .foregroundColor(.black.opacity(0.25))
                VStack(spacing: 6) {
                    Text(title)
                        .font(.systemScaled(16, weight: .semibold))
                        .foregroundColor(.black)
                    Text(subtitle)
                        .font(.systemScaled(13))
                        .foregroundColor(.black.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
                Button {
                    Task { await vm.organizeWithBerean() }
                } label: {
                    Group {
                        if vm.isOrganizing {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.black)
                                Text("Organizing...")
                            }
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                Text("Organize with Berean")
                            }
                        }
                    }
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 3)
                    )
                }
                .buttonStyle(.plain)
                .disabled(vm.isOrganizing)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Small Helpers

    @ViewBuilder
    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.55))
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.6), lineWidth: 0.5)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.systemScaled(12, weight: .semibold))
            .foregroundColor(.black.opacity(0.4))
    }

    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color.black.opacity(0.25))
                .frame(width: 5, height: 5)
                .padding(.top, 5)
            Text(text)
                .font(.systemScaled(14))
                .foregroundColor(.black)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.systemScaled(12, weight: .semibold))
                .foregroundColor(.black.opacity(0.4))
            Spacer()
            Text(value)
                .font(.systemScaled(13))
                .foregroundColor(.black.opacity(0.7))
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Reflection Prompt Card

private struct ChurchNotesReflectionPromptCard: View {
    let prompt: String
    let promptIndex: Int
    let existingAnswer: String
    let onSave: (String) -> Void

    @State private var answer: String = ""
    @State private var isEditing: Bool = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Text("\(promptIndex + 1)")
                    .font(.systemScaled(11, weight: .bold))
                    .foregroundColor(.black.opacity(0.35))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.black.opacity(0.07)))
                Text(prompt)
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundColor(.black)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isEditing {
                TextEditor(text: $answer)
                    .font(.systemScaled(14))
                    .foregroundColor(.black)
                    .frame(minHeight: 80)
                    .focused($isFocused)
                    .scrollContentBackground(.hidden)
                    .background(Color.black.opacity(0.04))
                    .cornerRadius(10)

                HStack {
                    Spacer()
                    Button("Save") {
                        onSave(answer)
                        isEditing = false
                        isFocused = false
                    }
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
                    )
                    .buttonStyle(.plain)
                }
            } else {
                Button {
                    answer = existingAnswer
                    isEditing = true
                    isFocused = true
                } label: {
                    if existingAnswer.isEmpty {
                        Text("Tap to answer...")
                            .font(.systemScaled(13))
                            .foregroundColor(.black.opacity(0.3))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.black.opacity(0.04))
                            )
                    } else {
                        Text(existingAnswer)
                            .font(.systemScaled(13))
                            .foregroundColor(.black.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.black.opacity(0.04))
                            )
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.55))
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.6), lineWidth: 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - FlowLayout (Tag Cloud)

/// Simple wrapping layout for theme tags.
private struct ChurchNotesFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let height = rows.map { row in row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0 }.reduce(0) { $0 + $1 + spacing }
        return CGSize(width: proposal.width ?? 0, height: max(0, height - spacing))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubview]] {
        var rows: [[LayoutSubview]] = [[]]
        var currentRowWidth: CGFloat = 0
        let maxWidth = proposal.width ?? 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentRowWidth + size.width > maxWidth && !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentRowWidth = 0
            }
            rows[rows.count - 1].append(subview)
            currentRowWidth += size.width + spacing
        }
        return rows
    }
}
