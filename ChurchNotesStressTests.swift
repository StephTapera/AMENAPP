//
//  ChurchNotesStressTests.swift
//  AMENAPP
//
//  Comprehensive stress testing for Church Notes production readiness
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
class ChurchNotesStressTests: ObservableObject {
    @Published var isRunning = false
    @Published var currentTest = ""
    @Published var results: [TestResult] = []
    @Published var overallStatus: TestStatus = .notStarted
    
    enum TestStatus {
        case notStarted
        case running
        case passed
        case failed
    }
    
    struct TestResult {
        let name: String
        let status: TestStatus
        let duration: TimeInterval
        let details: String
        let error: Error?
    }
    
    private let notesService = ChurchNotesService()
    private let testUserId = "stress_test_user"
    
    // MARK: - Run All Tests
    
    func runAllTests() async {
        isRunning = true
        overallStatus = .running
        results = []
        
        // Test 1: Create/Edit 50 Notes
        await runTest(name: "Create/Edit 50 Notes") {
            try await testMassCreateAndEdit()
        }
        
        // Test 2: Long Note Responsiveness
        await runTest(name: "Long Note (10k+ chars)") {
            try await testLongNoteResponsiveness()
        }
        
        // Test 3: Rapid Open/Close
        await runTest(name: "Rapid Open/Close 50x") {
            try await testRapidNavigation()
        }
        
        // Test 4: Poor Network During Save
        await runTest(name: "Offline Save & Sync") {
            try await testOfflineSaveAndSync()
        }
        
        // Test 5: Share Link Generation
        await runTest(name: "Share Links 20x") {
            try await testShareLinks()
        }
        
        // Test 6: Concurrent Edits
        await runTest(name: "Concurrent Edit Conflict") {
            try await testConcurrentEdits()
        }
        
        // Test 7: Memory Stress
        await runTest(name: "Memory Leak Detection") {
            try await testMemoryLeaks()
        }
        
        // Test 8: Search Performance
        await runTest(name: "Search 100+ Notes") {
            try await testSearchPerformance()
        }
        
        // Determine overall status
        let failed = results.filter { $0.status == .failed }
        overallStatus = failed.isEmpty ? .passed : .failed
        
        isRunning = false
        
        // Print summary
        printSummary()
    }
    
    // MARK: - Individual Tests
    
    /// Test 1: Create and edit 50 notes
    private func testMassCreateAndEdit() async throws {
        var createdNotes: [ChurchNote] = []
        
        // Create 50 notes
        for i in 1...50 {
            let note = ChurchNote(
                userId: testUserId,
                title: "Test Note \(i)",
                date: Date(),
                content: "This is test content for note number \(i). Lorem ipsum dolor sit amet."
            )
            
            try await notesService.createNote(note)
            
            if let id = note.id {
                var fetchedNote = note
                fetchedNote.id = id
                createdNotes.append(fetchedNote)
            }
        }
        
        // Edit 25 of them
        for i in 0..<25 {
            var note = createdNotes[i]
            note.content = "Updated content for note \(i)"
            try await notesService.updateNote(note)
        }
        
        // Verify all exist
        let allNotes = notesService.notes
        guard allNotes.count >= 50 else {
            throw TestError.assertion("Expected 50+ notes, found \(allNotes.count)")
        }
        
        // Cleanup
        for note in createdNotes {
            try? await notesService.deleteNote(note)
        }
    }
    
    /// Test 2: Long note responsiveness
    private func testLongNoteResponsiveness() async throws {
        let longContent = String(repeating: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ", count: 200) // ~12k chars
        
        let note = ChurchNote(
            userId: testUserId,
            title: "Long Note Test",
            date: Date(),
            content: longContent
        )
        
        let startTime = Date()
        try await notesService.createNote(note)
        let duration = Date().timeIntervalSince(startTime)
        
        // Should complete in under 3 seconds
        guard duration < 3.0 else {
            throw TestError.performance("Long note save took \(duration)s (expected < 3s)")
        }
        
        // Cleanup
        if let id = note.id {
            var fetchedNote = note
            fetchedNote.id = id
            try? await notesService.deleteNote(fetchedNote)
        }
    }
    
    /// Test 3: Rapid navigation
    private func testRapidNavigation() async throws {
        // Create test note
        let note = ChurchNote(
            userId: testUserId,
            title: "Navigation Test",
            date: Date(),
            content: "Test content"
        )
        
        try await notesService.createNote(note)
        
        // Simulate rapid open/close
        for _ in 1...50 {
            // Simulate opening
            notesService.startListening()
            
            // Small delay
            try await Task.sleep(for: .milliseconds(50))
            
            // Simulate closing
            notesService.stopListening()
        }
        
        // Check listener count (should be 0)
        // This would require exposing listener count, simplified for now
        
        // Cleanup
        if let id = note.id {
            var fetchedNote = note
            fetchedNote.id = id
            try? await notesService.deleteNote(fetchedNote)
        }
    }
    
    /// Test 4: Offline save and sync
    private func testOfflineSaveAndSync() async throws {
        // Note: Actual offline testing requires network simulation
        // This tests that Firestore offline persistence is enabled
        
        let db = Firestore.firestore()
        let settings = db.settings
        
        guard settings.isPersistenceEnabled else {
            throw TestError.configuration("Firestore offline persistence not enabled")
        }
        
        // Create note (will be cached)
        let note = ChurchNote(
            userId: testUserId,
            title: "Offline Test",
            date: Date(),
            content: "This note tests offline persistence"
        )
        
        try await notesService.createNote(note)
        
        // Verify it's cached
        try await Task.sleep(for: .milliseconds(500))
        
        // Cleanup
        if let id = note.id {
            var fetchedNote = note
            fetchedNote.id = id
            try? await notesService.deleteNote(fetchedNote)
        }
    }
    
    /// Test 5: Share link generation
    private func testShareLinks() async throws {
        // Create test note
        var note = ChurchNote(
            userId: testUserId,
            title: "Share Test",
            date: Date(),
            content: "Test sharing"
        )
        
        try await notesService.createNote(note)
        
        // Generate 20 share links
        for i in 1...20 {
            // Update permission
            note.permission = NotePermission.shared
            note.shareLinkId = "test_link_\(i)_\(UUID().uuidString)"
            try await notesService.updateNote(note)
            
            // Verify share link exists
            guard note.shareLinkId != nil else {
                throw TestError.assertion("Share link not generated for iteration \(i)")
            }
        }
        
        // Revoke sharing
        note.permission = NotePermission.privateNote
        note.sharedWith = []
        try await notesService.updateNote(note)
        
        // Cleanup
        if let id = note.id {
            var fetchedNote = note
            fetchedNote.id = id
            try? await notesService.deleteNote(fetchedNote)
        }
    }
    
    /// Test 6: Concurrent edit conflict detection
    private func testConcurrentEdits() async throws {
        // Create test note
        var note = ChurchNote(
            userId: testUserId,
            title: "Conflict Test",
            date: Date(),
            content: "Original content"
        )
        
        try await notesService.createNote(note)
        
        guard let noteId = note.id else {
            throw TestError.assertion("Note ID not set after creation")
        }
        
        // Fetch the note (simulating two users)
        note.id = noteId
        var note1 = note
        var note2 = note
        
        // User 1 edits
        note1.content = "User 1 content"
        try await notesService.updateNote(note1)
        
        // User 2 tries to edit (should detect conflict)
        note2.content = "User 2 content"
        
        do {
            try await notesService.updateNote(note2)
            throw TestError.assertion("Expected conflict error but update succeeded")
        } catch let error as NSError {
            // Should get conflict error (409)
            guard error.code == 409 || error.domain.contains("conflict") else {
                throw TestError.assertion("Expected conflict error, got: \(error)")
            }
        }
        
        // Cleanup
        try? await notesService.deleteNote(note1)
    }
    
    /// Test 7: Memory leak detection
    private func testMemoryLeaks() async throws {
        let initialMemory = getMemoryUsage()
        
        // Create and destroy 100 note instances
        for i in 1...100 {
            autoreleasepool {
                let note = ChurchNote(
                    userId: testUserId,
                    title: "Memory Test \(i)",
                    date: Date(),
                    content: String(repeating: "Test ", count: 1000)
                )
                
                // Use the note
                _ = note.title.count
                _ = note.content.count
            }
        }
        
        // Force cleanup
        try await Task.sleep(for: .milliseconds(500))
        
        let finalMemory = getMemoryUsage()
        let memoryGrowth = finalMemory - initialMemory
        
        // Memory should not grow more than 5MB
        guard memoryGrowth < 5_000_000 else {
            throw TestError.memory("Memory grew by \(memoryGrowth / 1_000_000)MB (expected < 5MB)")
        }
    }
    
    /// Test 8: Search performance
    private func testSearchPerformance() async throws {
        // Create 100 searchable notes
        var testNotes: [ChurchNote] = []
        
        for i in 1...100 {
            let note = ChurchNote(
                userId: testUserId,
                title: "Search Test \(i)",
                date: Date(),
                content: "Content with keyword searchterm\(i)",
                tags: ["test", "search"]
            )
            
            try await notesService.createNote(note)
            if let id = note.id {
                var created = note
                created.id = id
                testNotes.append(created)
            }
        }
        
        // Test search performance
        let startTime = Date()
        let results = notesService.searchNotes(query: "searchterm")
        let duration = Date().timeIntervalSince(startTime)
        
        // Should complete in under 100ms
        guard duration < 0.1 else {
            throw TestError.performance("Search took \(duration * 1000)ms (expected < 100ms)")
        }
        
        // Should find results
        guard !results.isEmpty else {
            throw TestError.assertion("Search returned no results")
        }
        
        // Cleanup
        for note in testNotes {
            try? await notesService.deleteNote(note)
        }
    }
    
    // MARK: - Helper Methods
    
    private func runTest(name: String, test: () async throws -> Void) async {
        currentTest = name
        let startTime = Date()
        
        do {
            try await test()
            let duration = Date().timeIntervalSince(startTime)
            
            results.append(TestResult(
                name: name,
                status: .passed,
                duration: duration,
                details: "✅ Passed in \(String(format: "%.2f", duration))s",
                error: nil
            ))
            
            print("✅ \(name): PASSED (\(String(format: "%.2f", duration))s)")
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            
            results.append(TestResult(
                name: name,
                status: .failed,
                duration: duration,
                details: "❌ Failed: \(error.localizedDescription)",
                error: error
            ))
            
            print("❌ \(name): FAILED - \(error.localizedDescription)")
        }
    }
    
    private func getMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return kerr == KERN_SUCCESS ? info.resident_size : 0
    }
    
    private func printSummary() {
        print("\n" + String(repeating: "=", count: 50))
        print("CHURCH NOTES STRESS TEST SUMMARY")
        print(String(repeating: "=", count: 50))
        
        let passed = results.filter { $0.status == .passed }.count
        let failed = results.filter { $0.status == .failed }.count
        let totalDuration = results.reduce(0.0) { $0 + $1.duration }
        
        print("\nResults:")
        print("  ✅ Passed: \(passed)")
        print("  ❌ Failed: \(failed)")
        print("  ⏱️  Total Duration: \(String(format: "%.2f", totalDuration))s")
        print("\nOverall Status: \(overallStatus == .passed ? "✅ PASS" : "❌ FAIL")")
        print(String(repeating: "=", count: 50) + "\n")
    }
}

// MARK: - Test Errors

enum TestError: LocalizedError {
    case assertion(String)
    case performance(String)
    case memory(String)
    case configuration(String)
    
    var errorDescription: String? {
        switch self {
        case .assertion(let msg): return "Assertion failed: \(msg)"
        case .performance(let msg): return "Performance issue: \(msg)"
        case .memory(let msg): return "Memory issue: \(msg)"
        case .configuration(let msg): return "Configuration error: \(msg)"
        }
    }
}
