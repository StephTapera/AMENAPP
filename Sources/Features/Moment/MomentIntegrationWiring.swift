import Foundation

@MainActor
public struct AmenMomentIntegrationWiring {
    public let client: AmenMomentDeepenClient

    public init(client: AmenMomentDeepenClient = .shared) {
        self.client = client
    }

    public func surface(for moment: AmenMoment) -> AmenMomentSurfaceView {
        AmenMomentSurfaceView(moment: moment, client: client)
    }
}
