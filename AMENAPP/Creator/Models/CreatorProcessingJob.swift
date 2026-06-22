import Foundation

struct CreatorProcessingJob: Codable, Identifiable, Hashable {
    let id: String
    let projectID: String
    let ownerID: String
    var type: CreatorJobType
    var status: CreatorJobStatus
    var progress: Double
    var inputRefs: [String]
    var outputRefs: [String]
    var outputStoragePath: String?
    var startedAt: Date?
    var finishedAt: Date?
    var createdAt: Date?
    var errorCode: String?
    var errorMessage: String?
    var retryCount: Int
}
