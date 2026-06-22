// BereanOSSearchService.swift
// AMENAPP — Berean OS
//
// Lightweight, debounced client-side search across Berean OS
// projects and (future) memory entries, reports, documents, and nodes.
// All searches are purely local — no Firestore reads are made per keystroke.

import Foundation
import FirebaseAuth

// MARK: - BereanOSSearchService

@MainActor
final class BereanOSSearchService: ObservableObject {
    static let shared = BereanOSSearchService()

    @Published private(set) var results = BereanOSSearchResults(
        projects: [],
        memoryEntries: [],
        researchReports: [],
        documents: [],
        knowledgeNodes: []
    )
    @Published private(set) var isSearching = false

    private var debounceTask: Task<Void, Never>?
    private let projectService = BereanProjectService.shared

    private init() {}

    // MARK: - Public API

    /// Triggers a debounced (400 ms) search across all local Berean OS data.
    /// Passing an empty or whitespace-only string clears results immediately.
    func search(_ query: String) {
        debounceTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = BereanOSSearchResults(
                projects: [],
                memoryEntries: [],
                researchReports: [],
                documents: [],
                knowledgeNodes: []
            )
            return
        }
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await performSearch(query)
        }
    }

    // MARK: - Private

    private func performSearch(_ query: String) async {
        isSearching = true
        defer { isSearching = false }

        let q = query.lowercased()

        let matchedProjects = projectService.projects.filter {
            $0.title.lowercased().contains(q) ||
            $0.description.lowercased().contains(q) ||
            $0.tags.contains { $0.lowercased().contains(q) }
        }

        results = BereanOSSearchResults(
            projects: matchedProjects,
            memoryEntries: [],
            researchReports: [],
            documents: [],
            knowledgeNodes: []
        )
    }
}
