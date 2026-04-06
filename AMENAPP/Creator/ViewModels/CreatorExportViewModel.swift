import Foundation

@MainActor
final class CreatorExportViewModel: ObservableObject {
    @Published private(set) var activeJob: CreatorProcessingJob?
    @Published private(set) var errorMessage: String?

    private let exportService: CreatorExportServicing

    init(exportService: CreatorExportServicing = CreatorExportService()) {
        self.exportService = exportService
    }

    func render(projectID: String, preset: CreatorExportPreset) async {
        do {
            activeJob = try await exportService.renderExport(projectID: projectID, preset: preset)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
