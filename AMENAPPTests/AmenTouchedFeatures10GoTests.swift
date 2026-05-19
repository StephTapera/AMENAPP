import Foundation
import Testing
@testable import AMENAPP

@Suite("Touched Features 10 GO Guards")
struct AmenTouchedFeatures10GoTests {
    @Test("Paid mentorship plans declare StoreKit product IDs")
    func paidMentorshipPlansDeclareStoreKitProductIds() {
        let paidPlans = MentorshipPlan.defaultPlans().filter { !$0.isFree }

        #expect(!paidPlans.isEmpty)
        #expect(paidPlans.allSatisfy { $0.storeKitProductId.hasPrefix("amen.mentorship.") })
        #expect(paidPlans.allSatisfy { $0.storeKitProductId.hasSuffix(".monthly") })
    }

    @Test("Legacy PDF export creates a non-empty shareable artifact")
    @MainActor
    func legacyPDFExportCreatesShareableArtifact() throws {
        let viewModel = LegacyStudioViewModel()
        viewModel.save(entry: LegacyEntry(
            type: .memory,
            title: "Testimony Milestone",
            body: "A preserved story entry used to verify export output.",
            eventYear: 2026
        ))

        let url = try viewModel.makeStoryBookPDF()
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int ?? 0

        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(url.pathExtension.lowercased() == "pdf")
        #expect(fileSize > 0)
    }

    @Test("Berean attachment picker results feed usable composer prompts")
    func bereanAttachmentResultsHaveComposerPrompts() {
        let result = BereanAttachmentResult(displayName: "notes.pdf", promptPrefix: "Use this attached file as context: ")

        #expect(!result.displayName.isEmpty)
        #expect(result.promptPrefix.contains("context") || result.promptPrefix.contains("image"))
    }
}
