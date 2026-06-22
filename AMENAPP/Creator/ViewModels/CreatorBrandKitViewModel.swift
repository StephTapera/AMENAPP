import Foundation

@MainActor
final class CreatorBrandKitViewModel: ObservableObject {
    @Published private(set) var kits: [CreatorBrandKit] = []
    @Published private(set) var errorMessage: String?

    private let brandKitService: CreatorBrandKitServicing

    init(brandKitService: CreatorBrandKitServicing? = nil) {
        self.brandKitService = brandKitService ?? CreatorBrandKitService()
    }

    func load(ownerID: String) async {
        do {
            kits = try await brandKitService.fetchBrandKits(ownerID: ownerID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
