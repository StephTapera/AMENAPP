import XCTest

final class SelahBibleEngineContractTests: XCTestCase {
    func testButtonInventoryUsesRealCurrentHandlers() throws {
        let inventory = try read("Selah/_contracts/ButtonInventory.md")

        XCTAssertTrue(inventory.contains("SelahLensBar.dispatch(.understand)"))
        XCTAssertTrue(inventory.contains("GuidedSelahSessionViewModel.advance()"))
        XCTAssertTrue(inventory.contains("GuidedSelahSessionViewModel.skip()"))
        XCTAssertTrue(inventory.contains("GuidedSelahSessionViewModel.finishSession()"))
        XCTAssertTrue(inventory.contains("GuidedSelahSessionViewModel.openCrossReference(_:)"))

        XCTAssertFalse(inventory.contains("goNext()"))
        XCTAssertFalse(inventory.contains("skipCurrentStep()"))
        XCTAssertFalse(inventory.contains("GuidedSelahSessionViewModel.finish()"))
    }

    func testGuidedStudySheetCrossReferenceHasObservableEffect() throws {
        let viewSource = try read("AMENAPP/SelahScripture/GuidedSelahSessionView.swift")
        let viewModelSource = try read("AMENAPP/SelahScripture/GuidedSelahSessionViewModel.swift")

        XCTAssertTrue(viewSource.contains("onCrossRefTapped: { viewModel.openCrossReference($0) }"))
        XCTAssertTrue(viewSource.contains(".alert(\"Cross-reference\""))
        XCTAssertTrue(viewModelSource.contains("@Published var selectedCrossReference: String?"))
        XCTAssertTrue(viewModelSource.contains("func openCrossReference(_ verseId: String)"))
        XCTAssertFalse(viewSource.contains("onCrossRefTapped: { _ in"))
    }

    func testRemoteBibleProviderLoadsFromFirestoreInsteadOfPermanentUnavailable() throws {
        let source = try read("AMENAPP/SelahScripture/SelahBibleTranslationProvider.swift")

        XCTAssertTrue(source.contains("import FirebaseFirestore"))
        XCTAssertTrue(source.contains("db.document(path).getDocument()"))
        XCTAssertTrue(source.contains("scriptureTranslations/\\(translation.id)/books/\\(bookId)/chapters/\\(chapter)"))
        XCTAssertTrue(source.contains("scriptureVerseIndex"))
        XCTAssertFalse(source.contains("is not yet enabled in this build"))
        XCTAssertFalse(source.contains("Always returns"))
    }

    func testSelahCriticalPathHasNoTodoConsoleOrStubMarkers() throws {
        let paths = [
            "AMENAPP/SelahScripture/SelahLensBar.swift",
            "AMENAPP/SelahScripture/BereanStudySheetView.swift",
            "AMENAPP/SelahScripture/SelahReflectionComposerView.swift",
            "AMENAPP/SelahScripture/SelahReflectionViewModel.swift",
            "AMENAPP/SelahScripture/GuidedSelahSessionView.swift",
            "AMENAPP/SelahScripture/GuidedSelahSessionViewModel.swift",
            "AMENAPP/SelahScripture/SelahBibleTranslationProvider.swift",
            "Backend/functions/src/selah/bereanStudySheet.ts",
            "Backend/functions/src/selah/classifyVerseTheme.ts",
            "Backend/functions/src/selah/classifySafety.ts",
            "Backend/functions/src/selahBibleEngine/index.ts"
        ]

        let forbidden = ["TODO", "FIXME", "print(", "console.log", "fatalError(", "@ts-ignore", "stub"]
        for path in paths {
            let source = try read(path)
            for marker in forbidden {
                XCTAssertFalse(source.contains(marker), "\(path) contains forbidden marker \(marker)")
            }
        }
    }

    private func read(_ relativePath: String) throws -> String {
        let file = URL(fileURLWithPath: #filePath)
        let repoRoot = file
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repoRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
