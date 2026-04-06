import Foundation

@MainActor
final class CreatorBrandKitViewModel: ObservableObject {
    @Published private(set) var kits: [CreatorBrandKit] = []
    @Published private(set) var errorMessage: String?

    private let brandKitService: CreatorBrandKitServicing

    init(brandKitService: CreatorBrandKitServicing = CreatorBrandKitService()) {
        self.brandKitService = brandKitService
    }

    func load(ownerID: String) async {
        do {
            kits = try await brandKitService.fetchBrandKits(ownerID: ownerID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
