import Foundation
import FirebaseStorage
import FirebaseFirestore
import FirebaseFunctions
import FirebaseAuth

/// Manages the full Church Notes media intelligence pipeline:
/// local recording/capture → Storage upload → processing job → AI draft.
///
/// All server-authoritative fields (status, transcripts, drafts) are
/// read from Firestore listeners — never trusted from local state.
@MainActor
final class ChurchNotesMediaProcessingService: ObservableObject {

    // MARK: - Published state

    @Published private(set) var uploadState: ChurchNoteUploadState = .init()
    @Published private(set) var activeJobs: [ChurchNoteProcessingJob] = []
    @Published private(set) var error: String?

    // MARK: - Private

    private let db        = Firestore.firestore()
    private let storage   = Storage.storage()
    private let functions = Functions.functions()
    private var jobListeners: [String: ListenerRegistration] = [:]

    private var currentUID: String? { Auth.auth().currentUser?.uid }

    // MARK: - Upload audio

    /// Uploads a recorded audio file to Firebase Storage and creates a processing job.
    /// The feature flag must be checked by the caller before invoking.
    func uploadAudioAndCreateJob(fileURL: URL, noteId: String, durationSeconds: Double) async {
        guard !uploadState.isInFlight else { return }
        guard let uid = currentUID else {
            uploadState.phase = .failed(message: "Not signed in.")
            return
        }

        uploadState = ChurchNoteUploadState(phase: .preparing, localFileURL: fileURL, mediaSourceType: .audio)
        error = nil

        let sizeBytes: Int
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            sizeBytes = (attrs[.size] as? Int) ?? 0
        } catch {
            uploadState.phase = .failed(message: "Could not read file.")
            return
        }

        guard sizeBytes <= 100 * 1024 * 1024 else {
            uploadState.phase = .failed(message: "Recording is too large. Maximum is 100 MB.")
            return
        }

        let filename    = "\(UUID().uuidString).m4a"
        let storagePath = "churchNotes/\(uid)/\(noteId)/audio/\(filename)"
        let ref         = storage.reference(withPath: storagePath)
        let metadata    = StorageMetadata()
        metadata.contentType = "audio/mp4"

        uploadState.phase = .uploading(progress: 0)

        let uploadTask = ref.putFile(from: fileURL, metadata: metadata)
        uploadTask.observe(.progress) { [weak self] snapshot in
            let fraction = snapshot.progress.map {
                Double($0.completedUnitCount) / Double(max($0.totalUnitCount, 1))
            } ?? 0
            Task { @MainActor [weak self] in
                self?.uploadState.phase = .uploading(progress: fraction)
            }
        }

        do {
            _ = try await uploadTask.completion()
        } catch {
            uploadState.phase = .failed(message: "Upload failed. Tap to retry.")
            self.error = "Upload failed."
            return
        }

        uploadState.phase = .uploading100

        do {
            let req = ChurchNoteJobCreationRequest(
                noteId: noteId,
                sourceType: .audio,
                storagePath: storagePath,
                fileSizeBytes: sizeBytes,
                durationSeconds: durationSeconds
            )
            let jobId = try await createProcessingJob(request: req)
            uploadState.phase = .complete(storagePath: storagePath)

            // Fire-and-monitor: kick off the callable then listen for status changes.
            Task {
                do {
                    try await callProcessAudio(noteId: noteId, jobId: jobId)
                } catch {
                    // Status is already tracked in the Firestore listener; log the callable failure.
                }
            }
            startListeningToJob(noteId: noteId, jobId: jobId)
        } catch {
            uploadState.phase = .failed(message: "Processing job could not be created. Tap to retry.")
            self.error = error.localizedDescription
        }
    }

    // MARK: - Upload image (OCR)

    /// Uploads a captured/selected photo to Firebase Storage and creates an OCR processing job.
    func uploadImageAndCreateJob(imageData: Data, noteId: String) async {
        guard !uploadState.isInFlight else { return }
        guard let uid = currentUID else {
            uploadState.phase = .failed(message: "Not signed in.")
            return
        }

        uploadState = ChurchNoteUploadState(phase: .preparing, localFileURL: nil, mediaSourceType: .image)
        error = nil

        guard imageData.count <= 20 * 1024 * 1024 else {
            uploadState.phase = .failed(message: "Image is too large. Maximum is 20 MB.")
            return
        }

        let filename    = "\(UUID().uuidString).jpg"
        let storagePath = "churchNotes/\(uid)/\(noteId)/images/\(filename)"
        let ref         = storage.reference(withPath: storagePath)
        let metadata    = StorageMetadata()
        metadata.contentType = "image/jpeg"

        uploadState.phase = .uploading(progress: 0)

        let uploadTask = ref.putData(imageData, metadata: metadata)
        uploadTask.observe(.progress) { [weak self] snapshot in
            let fraction = snapshot.progress.map {
                Double($0.completedUnitCount) / Double(max($0.totalUnitCount, 1))
            } ?? 0
            Task { @MainActor [weak self] in
                self?.uploadState.phase = .uploading(progress: fraction)
            }
        }

        do {
            _ = try await uploadTask.completion()
        } catch {
            uploadState.phase = .failed(message: "Upload failed. Tap to retry.")
            self.error = "Upload failed."
            return
        }

        uploadState.phase = .uploading100

        do {
            let req = ChurchNoteJobCreationRequest(
                noteId: noteId,
                sourceType: .image,
                storagePath: storagePath,
                fileSizeBytes: imageData.count,
                durationSeconds: nil
            )
            let jobId = try await createProcessingJob(request: req)
            uploadState.phase = .complete(storagePath: storagePath)

            Task {
                do {
                    try await callProcessImageOCR(noteId: noteId, jobId: jobId)
                } catch {
                    // Failure reflected in Firestore status listener.
                }
            }
            startListeningToJob(noteId: noteId, jobId: jobId)
        } catch {
            uploadState.phase = .failed(message: "Processing job could not be created. Tap to retry.")
            self.error = error.localizedDescription
        }
    }

    // MARK: - Upload video

    func uploadVideoAndCreateJob(fileURL: URL, noteId: String, durationSeconds: Double?) async {
        await uploadFileAndCreateJob(
            fileURL: fileURL,
            noteId: noteId,
            sourceType: .video,
            folder: "video",
            contentType: "video/mp4",
            maxBytes: 500 * 1024 * 1024,
            durationSeconds: durationSeconds,
            process: callProcessVideo
        )
    }

    // MARK: - Upload document

    func uploadDocumentAndCreateJob(fileURL: URL, noteId: String) async {
        await uploadFileAndCreateJob(
            fileURL: fileURL,
            noteId: noteId,
            sourceType: .document,
            folder: "documents",
            contentType: "application/pdf",
            maxBytes: 50 * 1024 * 1024,
            durationSeconds: nil,
            process: callProcessDocumentPDF
        )
    }

    // MARK: - Draft approval

    func approveDraft(noteId: String, jobId: String, draftField: ChurchNoteDraftField) async throws -> ChurchNoteDraftApprovalResult {
        let result = try await functions
            .httpsCallable("approveChurchNoteAIDraft")
            .call(["noteId": noteId, "jobId": jobId, "draftField": draftField.rawValue])

        guard let data    = result.data as? [String: Any],
              let jobIdR  = data["jobId"]       as? String,
              let noteIdR = data["noteId"]      as? String,
              let fieldStr = data["draftField"] as? String,
              let field   = ChurchNoteDraftField(rawValue: fieldStr),
              let text    = data["approvedText"] as? String,
              let srcType = data["sourceType"]  as? String
        else {
            throw ChurchNotesProcessingError.invalidServerResponse
        }

        return ChurchNoteDraftApprovalResult(
            jobId: jobIdR, noteId: noteIdR,
            draftField: field, approvedText: text, sourceType: srcType
        )
    }

    func rejectDraft(noteId: String, jobId: String, draftField: ChurchNoteDraftField, reason: String = "user_rejected") async throws {
        _ = try await functions
            .httpsCallable("rejectChurchNoteAIDraft")
            .call(["noteId": noteId, "jobId": jobId, "draftField": draftField.rawValue, "reason": reason])
    }

    // MARK: - Content generation

    func generateSummary(noteId: String, jobId: String) async throws {
        _ = try await functions.httpsCallable("generateChurchNoteSummary")
            .call(["noteId": noteId, "jobId": jobId])
    }

    func generateStudyGuide(noteId: String, jobId: String) async throws {
        _ = try await functions.httpsCallable("generateChurchNoteStudyGuide")
            .call(["noteId": noteId, "jobId": jobId])
    }

    func generatePrayerPrompts(noteId: String, jobId: String) async throws {
        _ = try await functions.httpsCallable("generateChurchNotePrayerPrompts")
            .call(["noteId": noteId, "jobId": jobId])
    }

    func generateActionItems(noteId: String, jobId: String) async throws {
        _ = try await functions.httpsCallable("generateChurchNoteActionItems")
            .call(["noteId": noteId, "jobId": jobId])
    }

    func detectScriptures(noteId: String, jobId: String) async throws {
        _ = try await functions.httpsCallable("detectChurchNoteScriptures")
            .call(["noteId": noteId, "jobId": jobId])
    }

    func translateContent(noteId: String, jobId: String, targetLanguage: String) async throws {
        _ = try await functions.httpsCallable("translateChurchNoteContent")
            .call(["noteId": noteId, "jobId": jobId, "targetLanguage": targetLanguage])
    }

    func regenerateSection(noteId: String, jobId: String, draftField: String) async throws {
        _ = try await functions.httpsCallable("regenerateChurchNoteSection")
            .call(["noteId": noteId, "jobId": jobId, "draftField": draftField])
    }

    func createClipSuggestions(noteId: String, jobId: String) async throws {
        _ = try await functions.httpsCallable("createChurchNoteClipSuggestions")
            .call(["noteId": noteId, "jobId": jobId])
    }

    func shareNote(noteId: String, collaboratorUid: String, role: String) async throws {
        _ = try await functions.httpsCallable("shareChurchNoteWithCollaborators")
            .call(["noteId": noteId, "collaboratorUid": collaboratorUid, "role": role])
    }

    func updatePermissions(noteId: String, collaboratorUid: String, role: String?, remove: Bool = false) async throws {
        var payload: [String: Any] = ["noteId": noteId, "collaboratorUid": collaboratorUid, "remove": remove]
        if let role { payload["role"] = role }
        _ = try await functions.httpsCallable("updateChurchNotePermissions").call(payload)
    }

    // MARK: - Real-time job listener

    func startListeningToJob(noteId: String, jobId: String) {
        guard jobListeners[jobId] == nil else { return }
        let ref = db.collection("churchNotes").document(noteId)
            .collection("processingJobs").document(jobId)

        let listener = ref.addSnapshotListener { [weak self] snap, _ in
            guard let self, let snap, snap.exists else { return }
            guard var data = snap.data() else { return }
            // Inject documentID as jobId for Codable decoding.
            data["jobId"] = snap.documentID
            if let job = try? Firestore.Decoder().decode(ChurchNoteProcessingJob.self, from: data) {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let idx = self.activeJobs.firstIndex(where: { $0.id == jobId }) {
                        self.activeJobs[idx] = job
                    } else {
                        self.activeJobs.append(job)
                    }
                }
            }
        }
        jobListeners[jobId] = listener
    }

    func stopListeningToJob(jobId: String) {
        jobListeners[jobId]?.remove()
        jobListeners.removeValue(forKey: jobId)
    }

    func stopAllListeners() {
        jobListeners.values.forEach { $0.remove() }
        jobListeners.removeAll()
    }

    // MARK: - Convenience

    func job(for jobId: String) -> ChurchNoteProcessingJob? {
        activeJobs.first { $0.id == jobId }
    }

    // MARK: - Private

    private func uploadFileAndCreateJob(
        fileURL: URL,
        noteId: String,
        sourceType: ChurchNoteMediaSourceType,
        folder: String,
        contentType: String,
        maxBytes: Int,
        durationSeconds: Double?,
        process: @escaping (String, String) async throws -> Void
    ) async {
        guard !uploadState.isInFlight else { return }
        guard let uid = currentUID else {
            uploadState.phase = .failed(message: "Not signed in.")
            return
        }

        uploadState = ChurchNoteUploadState(phase: .preparing, localFileURL: fileURL, mediaSourceType: sourceType)
        error = nil

        let sizeBytes: Int
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            sizeBytes = (attrs[.size] as? Int) ?? 0
        } catch {
            uploadState.phase = .failed(message: "Could not read file.")
            return
        }

        guard sizeBytes <= maxBytes else {
            uploadState.phase = .failed(message: "File is too large.")
            return
        }

        let fileExtension = fileURL.pathExtension.isEmpty ? (sourceType == .document ? "pdf" : "mp4") : fileURL.pathExtension
        let filename = "\(UUID().uuidString).\(fileExtension)"
        let storagePath = "churchNotes/\(uid)/\(noteId)/\(folder)/\(filename)"
        let ref = storage.reference(withPath: storagePath)
        let metadata = StorageMetadata()
        metadata.contentType = contentType

        uploadState.phase = .uploading(progress: 0)
        let uploadTask = ref.putFile(from: fileURL, metadata: metadata)
        uploadTask.observe(.progress) { [weak self] snapshot in
            let fraction = snapshot.progress.map {
                Double($0.completedUnitCount) / Double(max($0.totalUnitCount, 1))
            } ?? 0
            Task { @MainActor [weak self] in
                self?.uploadState.phase = .uploading(progress: fraction)
            }
        }

        do {
            _ = try await uploadTask.completion()
            uploadState.phase = .uploading100
            let req = ChurchNoteJobCreationRequest(
                noteId: noteId,
                sourceType: sourceType,
                storagePath: storagePath,
                fileSizeBytes: sizeBytes,
                durationSeconds: durationSeconds
            )
            let jobId = try await createProcessingJob(request: req)
            uploadState.phase = .complete(storagePath: storagePath)
            Task {
                do { try await process(noteId, jobId) } catch { }
            }
            startListeningToJob(noteId: noteId, jobId: jobId)
        } catch {
            uploadState.phase = .failed(message: "Processing job could not be created. Tap to retry.")
            self.error = error.localizedDescription
        }
    }

    private func createProcessingJob(request: ChurchNoteJobCreationRequest) async throws -> String {
        var params: [String: Any] = [
            "noteId":        request.noteId,
            "sourceType":    request.sourceType.rawValue,
            "storagePath":   request.storagePath,
            "fileSizeBytes": request.fileSizeBytes,
        ]
        if let dur = request.durationSeconds { params["durationSeconds"] = dur }

        let result = try await functions.httpsCallable("createChurchNoteProcessingJob").call(params)
        guard let data  = result.data as? [String: Any],
              let jobId = data["jobId"] as? String
        else { throw ChurchNotesProcessingError.invalidServerResponse }
        return jobId
    }

    private func callProcessAudio(noteId: String, jobId: String) async throws {
        _ = try await functions.httpsCallable("processChurchNoteAudio")
            .call(["noteId": noteId, "jobId": jobId])
    }

    private func callProcessImageOCR(noteId: String, jobId: String) async throws {
        _ = try await functions.httpsCallable("processChurchNoteImageOCR")
            .call(["noteId": noteId, "jobId": jobId])
    }

    private func callProcessVideo(noteId: String, jobId: String) async throws {
        _ = try await functions.httpsCallable("processChurchNoteVideo")
            .call(["noteId": noteId, "jobId": jobId])
    }

    private func callProcessDocumentPDF(noteId: String, jobId: String) async throws {
        _ = try await functions.httpsCallable("processChurchNoteDocumentPDF")
            .call(["noteId": noteId, "jobId": jobId])
    }
}

// MARK: - Error types

enum ChurchNotesProcessingError: LocalizedError {
    case invalidServerResponse
    case notSignedIn
    case fileTooLarge
    case uploadFailed(String)
    case processingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidServerResponse:     return "Unexpected server response. Please try again."
        case .notSignedIn:               return "You must be signed in."
        case .fileTooLarge:              return "File exceeds the maximum allowed size."
        case .uploadFailed(let msg):     return msg
        case .processingFailed(let msg): return msg
        }
    }
}

// MARK: - StorageUploadTask async bridging

private extension StorageUploadTask {
    func completion() async throws -> StorageMetadata {
        try await withCheckedThrowingContinuation { cont in
            var resumed = false
            observe(.success) { snap in
                guard !resumed else { return }
                resumed = true
                if let meta = snap.metadata {
                    cont.resume(returning: meta)
                } else {
                    cont.resume(throwing: ChurchNotesProcessingError.uploadFailed("Upload finished without metadata."))
                }
            }
            observe(.failure) { snap in
                guard !resumed else { return }
                resumed = true
                cont.resume(throwing: snap.error ?? ChurchNotesProcessingError.uploadFailed("Upload failed."))
            }
        }
    }
}
