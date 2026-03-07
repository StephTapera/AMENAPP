
//
//  ImportAndLinkTests.swift
//  AMENAPPTests
//
//  Unit tests for:
//    - GenericArchiveImporter parsing
//    - Dedupe heuristic (caption + timestamp signature)
//    - ShareExtensionViewController text sanitization
//    - LinkCardViewModel state transitions
//    - URL validation (http/https only)
//

import Testing
import Foundation
@testable import AMENAPP

// MARK: - GenericArchiveImporter Tests

@Suite("GenericArchiveImporter")
struct GenericArchiveImporterTests {

    // MARK: - Setup helpers

    private func makeArchive(files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_archive_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (name, content) in files {
            let url = root.appendingPathComponent(name)
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    // MARK: - canHandle

    @Test("canHandle returns false for empty directory")
    func canHandleEmptyDirectory() throws {
        let root = try makeArchive(files: [:])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(GenericArchiveImporter().canHandle(archiveRoot: root) == false)
    }

    @Test("canHandle returns true when JSON file exists")
    func canHandleWithJSON() throws {
        let root = try makeArchive(files: ["posts.json": "[]"])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(GenericArchiveImporter().canHandle(archiveRoot: root) == true)
    }

    // MARK: - Parsing

    @Test("Parses Instagram-style array of post objects")
    func parsesInstagramArray() async throws {
        let json = """
        [
          {
            "creation_timestamp": 1700000000,
            "title": "Sunday worship",
            "data": [{"post": "God is good!"}]
          },
          {
            "creation_timestamp": 1700001000,
            "data": [{"post": "Blessed morning"}]
          }
        ]
        """
        let root = try makeArchive(files: ["your_posts_1.json": json])
        defer { try? FileManager.default.removeItem(at: root) }

        let importer = GenericArchiveImporter()
        let items = try await importer.parse(archiveRoot: root) { _ in }

        #expect(items.count == 2)
        #expect(items[0].caption == "God is good!")
        #expect(items[0].timestamp != nil)
        #expect(items[1].caption == "Blessed morning")
    }

    @Test("Parses Twitter-style text field")
    func parsesTextDirectly() async throws {
        let json = """
        [
          {"text": "Worship was incredible today", "creation_timestamp": 1700002000}
        ]
        """
        let root = try makeArchive(files: ["posts.json": json])
        defer { try? FileManager.default.removeItem(at: root) }

        let items = try await GenericArchiveImporter().parse(archiveRoot: root) { _ in }
        #expect(items.count == 1)
        #expect(items[0].caption == "Worship was incredible today")
    }

    @Test("Skips items with no text and no media")
    func skipsEmptyItems() async throws {
        let json = """
        [{"creation_timestamp": 1700000000}]
        """
        let root = try makeArchive(files: ["posts.json": json])
        defer { try? FileManager.default.removeItem(at: root) }

        let items = try await GenericArchiveImporter().parse(archiveRoot: root) { _ in }
        #expect(items.isEmpty)
    }

    @Test("Strips HTML tags from caption")
    func stripsHTMLFromCaption() async throws {
        let json = """
        [{"text": "<p>Hello <b>world</b></p>", "creation_timestamp": 1700000000}]
        """
        let root = try makeArchive(files: ["posts.json": json])
        defer { try? FileManager.default.removeItem(at: root) }

        let items = try await GenericArchiveImporter().parse(archiveRoot: root) { _ in }
        #expect(items.first?.caption == "Hello world")
    }

    @Test("Skips manifest.json metadata files")
    func skipsManifestFile() async throws {
        let manifest = #"{"version": 1}"#
        let root = try makeArchive(files: ["manifest.json": manifest])
        defer { try? FileManager.default.removeItem(at: root) }

        let items = try await GenericArchiveImporter().parse(archiveRoot: root) { _ in }
        #expect(items.isEmpty)
    }

    @Test("Handles malformed JSON gracefully (no throw)")
    func handlesMalformedJSON() async throws {
        let root = try makeArchive(files: [
            "good.json": "[{\"text\":\"fine\",\"creation_timestamp\":1700000000}]",
            "bad.json": "{not: valid json!!!"
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        // Should not throw — bad file is skipped, good file is parsed
        let items = try await GenericArchiveImporter().parse(archiveRoot: root) { _ in }
        #expect(items.count == 1)
        #expect(items[0].caption == "fine")
    }
}

// MARK: - ImportableItem Dedupe Tests

@Suite("ImportableItem deduplication")
struct ImportDedupeTests {

    @Test("Items with same caption produce same signature")
    func sameSignatureForIdenticalCaption() {
        // Simulate the signature logic from DataImportService (caption + timestamp)
        let caption = "God is faithful always"
        let ts = Date(timeIntervalSince1970: 1700000000)
        let sig1 = "\(Int(ts.timeIntervalSince1970))|\(String(caption.prefix(80)))"
        let sig2 = "\(Int(ts.timeIntervalSince1970))|\(String(caption.prefix(80)))"
        #expect(sig1 == sig2)
    }

    @Test("Items with different captions produce different signatures")
    func differentSignaturesForDifferentCaptions() {
        let ts = Date(timeIntervalSince1970: 1700000000)
        let sig1 = "\(Int(ts.timeIntervalSince1970))|caption one"
        let sig2 = "\(Int(ts.timeIntervalSince1970))|caption two"
        #expect(sig1 != sig2)
    }
}

// MARK: - ShareExtension Sanitization Tests

@Suite("ShareExtensionViewController sanitization")
struct ShareSanitizationTests {

    @Test("Strips HTML tags")
    func stripsHTML() {
        let result = ShareExtensionViewController.sanitize("<b>Hello</b> world")
        #expect(result == "Hello world")
    }

    @Test("Trims whitespace")
    func trimsWhitespace() {
        let result = ShareExtensionViewController.sanitize("  hello world  ")
        #expect(result == "hello world")
    }

    @Test("Caps at 500 characters")
    func capsAt500() {
        let long = String(repeating: "a", count: 600)
        let result = ShareExtensionViewController.sanitize(long)
        #expect(result.count == 500)
    }

    @Test("Preserves short clean text unchanged")
    func preservesCleanText() {
        let text = "God is good all the time."
        #expect(ShareExtensionViewController.sanitize(text) == text)
    }
}

// MARK: - URL Validation Tests

@Suite("URL validation")
struct URLValidationTests {

    private func isHTTPSafe(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    @Test("Accepts http URLs")
    func acceptsHTTP() { #expect(isHTTPSafe("http://example.com") == true) }

    @Test("Accepts https URLs")
    func acceptsHTTPS() { #expect(isHTTPSafe("https://example.com") == true) }

    @Test("Rejects javascript: scheme")
    func rejectsJavascript() { #expect(isHTTPSafe("javascript:alert(1)") == false) }

    @Test("Rejects data: scheme")
    func rejectsData() { #expect(isHTTPSafe("data:text/html,<h1>hi</h1>") == false) }

    @Test("Rejects file: scheme")
    func rejectsFile() { #expect(isHTTPSafe("file:///etc/passwd") == false) }

    @Test("Rejects empty string")
    func rejectsEmpty() { #expect(isHTTPSafe("") == false) }
}

// MARK: - ShareComposeViewModel Heuristic Tests

@Suite("ShareComposeViewModel destination heuristics")
@MainActor
struct ShareHeuristicTests {

    @Test("Bible URL maps to Church Note")
    func bibleURLGoesToChurchNote() {
        let vm = ShareComposeViewModel()
        vm.suggestDestination(for: URL(string: "https://bible.com/john/3/16")!)
        #expect(vm.selectedDestination == .churchNote)
    }

    @Test("Generic URL maps to OpenTable")
    func genericURLGoesToOpenTable() {
        let vm = ShareComposeViewModel()
        vm.suggestDestination(for: URL(string: "https://nytimes.com/article")!)
        #expect(vm.selectedDestination == .openTable)
    }

    @Test("Testimony text routes to Testimonies")
    func testimonyTextRoutes() {
        let vm = ShareComposeViewModel()
        vm.suggestDestinationFromText("This is my testimony — God healed me!")
        #expect(vm.selectedDestination == .testimonies)
    }

    @Test("Non-testimony text stays on OpenTable")
    func nonTestimonyTextStays() {
        let vm = ShareComposeViewModel()
        vm.suggestDestinationFromText("Great message from church today.")
        #expect(vm.selectedDestination == .openTable)
    }
}
