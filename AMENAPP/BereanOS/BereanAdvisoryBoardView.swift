// BereanAdvisoryBoardView.swift
// AMENAPP — Berean OS
//
// AI Advisory Boards — create boards, select advisors, consult the board
// with a question, and view multi-perspective responses.
// All advisors are AI. Feature-flagged via bereanOSAdvisoryBoardsEnabled.

import SwiftUI

// MARK: - BereanAdvisoryBoardView

struct BereanAdvisoryBoardView: View {

    @StateObject private var service = BereanAdvisoryBoardService.shared

    @State private var showCreateSheet = false
    @State private var fetchError: Error?

    // MARK: - Feature Flag Guard

    var body: some View {
        if !AMENFeatureFlags.shared.bereanOSAdvisoryBoardsEnabled {
            ContentUnavailableView(
                "Advisory Boards",
                systemImage: "person.3.sequence",
                description: Text("Coming soon")
            )
        } else {
            boardListContent
        }
    }

    // MARK: - Board List

    private var boardListContent: some View {
        Group {
            if service.isLoading && service.boards.isEmpty {
                ProgressView("Loading boards\u{2026}")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if service.boards.isEmpty {
                emptyState
            } else {
                boardList
            }
        }
        .navigationTitle("Advisory Boards")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.regularMaterial, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create advisory board")
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            BereanCreateBoardSheet { _ in
                Task { try? await service.fetchBoards() }
            }
        }
        .task {
            try? await service.fetchBoards()
        }
        .alert("Error", isPresented: Binding(
            get: { fetchError != nil },
            set: { if !$0 { fetchError = nil } }
        )) {
            Button("OK") { fetchError = nil }
        } message: {
            Text(fetchError?.localizedDescription ?? "An error occurred.")
        }
    }

    private var boardList: some View {
        List {
            ForEach(service.boards) { board in
                NavigationLink {
                    BereanAdvisoryBoardDetailView(board: board)
                } label: {
                    boardRow(board)
                }
                .accessibilityLabel("\(board.name), \(board.advisors.count) advisors")
            }
        }
        .listStyle(.insetGrouped)
    }

    private func boardRow(_ board: BereanAdvisoryBoard) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.3.sequence.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(board.name)
                    .font(.headline)
                HStack(spacing: 6) {
                    Text(board.boardType)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\u{00B7}")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("\(board.advisors.count) advisor\(board.advisors.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.3.sequence")
                .font(.systemScaled(56))
                .foregroundStyle(.secondary)
            Text("No Advisory Boards")
                .font(.title3.weight(.semibold))
            Text("Create your first advisory board to get diverse AI perspectives on your projects and decisions.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Create Your First Board") {
                showCreateSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Board Detail View

struct BereanAdvisoryBoardDetailView: View {

    let board: BereanAdvisoryBoard
    @StateObject private var service = BereanAdvisoryBoardService.shared

    @State private var showConsultSheet = false
    @State private var perspectives: [BereanPerspective] = []

    var body: some View {
        List {
            Section("Advisors") {
                ForEach(board.advisors) { advisor in
                    advisorRow(advisor)
                }
                if board.advisors.isEmpty {
                    Text("No advisors added yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    showConsultSheet = true
                } label: {
                    Label("Consult Board", systemImage: "questionmark.bubble.fill")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                }
                .accessibilityLabel("Consult this advisory board")
            }

            if !perspectives.isEmpty {
                Section("Board Perspectives") {
                    ForEach(perspectives) { perspective in
                        BereanPerspectiveCard(perspective: perspective)
                            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                            .listRowBackground(Color.clear)
                    }
                }

                Section {
                    Text("All advisors are AI. For legal, medical, or financial decisions, consult qualified professionals.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(board.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showConsultSheet) {
            BereanConsultBoardSheet(board: board) { newPerspectives in
                perspectives = newPerspectives
            }
        }
    }

    private func advisorRow(_ advisor: BereanAIAdvisor) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(advisor.role)
                .font(.subheadline.weight(.semibold))
            Text(advisor.specialization)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityLabel("\(advisor.role): \(advisor.specialization)")
    }
}

// MARK: - Create Board Sheet

private struct BereanCreateBoardSheet: View {

    let onCreated: (BereanAdvisoryBoard) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = BereanAdvisoryBoardService.shared

    @State private var boardName = ""
    @State private var boardType = "Startup"
    @State private var selectedAdvisorIndices = Set<Int>()
    @State private var isCreating = false
    @State private var createError: Error?

    private let boardTypes = ["Startup", "Family", "Ministry", "Financial", "Health", "Church", "Custom"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Board Details") {
                    TextField("Board Name", text: $boardName)
                        .accessibilityLabel("Board name")

                    Picker("Board Type", selection: $boardType) {
                        ForEach(boardTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    .accessibilityLabel("Board type")
                }

                Section("Select Advisors") {
                    ForEach(BereanAdvisoryBoardService.presetAdvisors.indices, id: \.self) { idx in
                        let advisor = BereanAdvisoryBoardService.presetAdvisors[idx]
                        let isSelected = selectedAdvisorIndices.contains(idx)
                        Button {
                            if isSelected {
                                selectedAdvisorIndices.remove(idx)
                            } else {
                                selectedAdvisorIndices.insert(idx)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(advisor.role)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(advisor.specialization)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(advisor.role)\(isSelected ? ", selected" : "")")
                    }
                }
            }
            .navigationTitle("Create Board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        Task { await createBoard() }
                    }
                    .disabled(boardName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                    .fontWeight(.semibold)
                }
            }
            .alert("Error", isPresented: Binding(
                get: { createError != nil },
                set: { if !$0 { createError = nil } }
            )) {
                Button("OK") { createError = nil }
            } message: {
                Text(createError?.localizedDescription ?? "Could not create board.")
            }
        }
    }

    private func createBoard() async {
        isCreating = true
        defer { isCreating = false }
        do {
            var board = try await service.createBoard(
                name: boardName.trimmingCharacters(in: .whitespaces),
                boardType: boardType,
                projectId: nil
            )
            for idx in selectedAdvisorIndices.sorted() {
                let preset = BereanAdvisoryBoardService.presetAdvisors[idx]
                let advisor = BereanAIAdvisor(
                    id: UUID().uuidString,
                    role: preset.role,
                    specialization: preset.specialization,
                    systemPrompt: preset.systemPrompt,
                    lastResponseAt: nil
                )
                try await service.addAdvisor(advisor, boardId: board.id)
                board.advisors.append(advisor)
            }
            onCreated(board)
            dismiss()
        } catch {
            createError = error
        }
    }
}

// MARK: - Consult Board Sheet

private struct BereanConsultBoardSheet: View {

    let board: BereanAdvisoryBoard
    let onPerspectives: ([BereanPerspective]) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = BereanAdvisoryBoardService.shared

    @State private var question = ""
    @State private var isConsulting = false
    @State private var consultError: Error?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Ask the Board")
                    .font(.title2.weight(.bold))
                    .padding(.horizontal)

                Text("Your question will be sent to all \(board.advisors.count) advisor\(board.advisors.count == 1 ? "" : "s") on this board.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                TextEditor(text: $question)
                    .frame(minHeight: 120)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemFill))
                    )
                    .padding(.horizontal)
                    .accessibilityLabel("Question for the advisory board")

                Spacer()

                Text("All advisors are AI. For legal, medical, or financial decisions, consult qualified professionals.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button {
                    Task { await consultBoard() }
                } label: {
                    HStack {
                        if isConsulting {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        }
                        Text(isConsulting ? "Consulting\u{2026}" : "Ask the Board")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.accentColor)
                    )
                    .foregroundStyle(.white)
                }
                .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || isConsulting)
                .padding(.horizontal)
                .padding(.bottom, 20)
                .accessibilityLabel("Ask the advisory board")
            }
            .navigationTitle("Consult \(board.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Consultation Error", isPresented: Binding(
                get: { consultError != nil },
                set: { if !$0 { consultError = nil } }
            )) {
                Button("OK") { consultError = nil }
            } message: {
                Text(consultError?.localizedDescription ?? "Consultation failed.")
            }
        }
    }

    private func consultBoard() async {
        isConsulting = true
        defer { isConsulting = false }
        do {
            let results = try await service.consultBoard(
                boardId: board.id,
                question: question.trimmingCharacters(in: .whitespaces)
            )
            onPerspectives(results)
            dismiss()
        } catch {
            consultError = error
        }
    }
}

// MARK: - BereanPerspectiveCard

/// Displays a single BereanPerspective from an advisory board consultation.
struct BereanPerspectiveCard: View {

    let perspective: BereanPerspective

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "person.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text(perspective.perspectiveType)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Collapse perspective" : "Expand perspective")
            }

            Text(perspective.summary)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(isExpanded ? nil : 4)

            if isExpanded {
                if !perspective.agreements.isEmpty {
                    perspectiveSection("Key Points", items: perspective.agreements, icon: "checkmark.circle.fill", color: .green)
                }
                if !perspective.tradeoffs.isEmpty {
                    perspectiveSection("Tradeoffs", items: perspective.tradeoffs, icon: "arrow.left.arrow.right.circle.fill", color: .orange)
                }
                if !perspective.unknowns.isEmpty {
                    perspectiveSection("Open Questions", items: perspective.unknowns, icon: "questionmark.circle.fill", color: .blue)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(perspective.perspectiveType) perspective")
    }

    private func perspectiveSection(_ title: String, items: [String], icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)

            ForEach(items.indices, id: \.self) { idx in
                HStack(alignment: .top, spacing: 6) {
                    Text("\u{2022}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(items[idx])
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

