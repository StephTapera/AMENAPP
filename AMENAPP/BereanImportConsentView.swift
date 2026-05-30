
//
//  BereanImportConsentView.swift
//  AMENAPP
//
//  Entry point for the Berean Import pipeline.
//  Flow: Consent screen → File picker → Upload with progress → Processing watch.
//
//  The "Berean Import" is distinct from the simple client-side ImportLauncherView:
//  it uploads the archive to Firebase Storage, triggers a server-side parsing
//  + Berean classification worker, then presents the review UI when ready.
//

import SwiftUI
import UniformTypeIdentifiers
import FirebaseAuth
import FirebaseStorage

// MARK: - BereanImportConsentView

struct BereanImportConsentView: View {

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = BereanImportUploadViewModel()
    @State private var showFilePicker = false
    @State private var showStepsExpander = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    heroCard
                    consentCard
                    howToGetArchiveCard
                    Spacer(minLength: 0)
                    actionButton
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Import Your Content")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.secondary)
                }
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [UTType.zip],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task { await vm.beginUpload(archiveURL: url) }
        }
        .sheet(isPresented: $vm.showProcessingView) {
            if let job = vm.activeJob {
                BereanImportProcessingView(
                    jobId: job.id ?? "",
                    onReviewReady: {
                        vm.showProcessingView = false
                    }
                )
                .interactiveDismissDisabled()
            }
        }
        .alert("Upload Error", isPresented: $vm.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage)
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.accentColor, Color.purple],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: 60, height: 60)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.white.opacity(0.2), lineWidth: 0.8)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Bring your story to AMEN")
                    .font(.headline)
                Text("Import posts from Instagram, Threads, or Facebook and let Berean help you re-consecrate them.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(.white.opacity(0.15), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
        .padding(.top, 12)
    }

    // MARK: - Consent Card

    private var consentCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("How it works", systemImage: "info.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 10) {
                ConsentStep(
                    number: "1",
                    title: "Your data only",
                    description: "You export your own archive from Instagram/Threads/Facebook. AMEN has no relationship with those platforms and never accesses them on your behalf."
                )
                ConsentStep(
                    number: "2",
                    title: "Processed then deleted",
                    description: "AMEN reads the archive to extract your posts, then immediately deletes the raw file. We never store the original export permanently."
                )
                ConsentStep(
                    number: "3",
                    title: "Berean reviews first",
                    description: "Berean reads each post and suggests which ones are worth bringing over, strips performance-driven framing, and offers a plain re-write. You decide what to keep."
                )
                ConsentStep(
                    number: "4",
                    title: "You choose every post",
                    description: "Nothing is published without your review. You keep, edit, or discard each item before it becomes an AMEN post."
                )
            }
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.blue.opacity(0.15), lineWidth: 0.8)
        )
    }

    // MARK: - How To Get Archive Card

    private var howToGetArchiveCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showStepsExpander.toggle()
                }
            } label: {
                HStack {
                    Label("How to download your archive", systemImage: "arrow.down.doc.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: showStepsExpander ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            }

            if showStepsExpander {
                Divider().padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 14) {
                    ArchiveStep(
                        platform: "Instagram / Threads / Facebook",
                        icon: "camera.filters",
                        steps: [
                            "Open the app → Profile → Menu (☰) → Settings",
                            "Accounts Centre → Your information and permissions",
                            "Download your information → Download or transfer information",
                            "Select the account → All available information (or specific)",
                            "Format: JSON (NOT HTML) · Media quality: High",
                            "Date range: All time",
                            "Request a download → wait for email → Download ZIP"
                        ]
                    )
                }
                .padding(16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.8)
        )
        .clipped()
    }

    // MARK: - Action Button

    @ViewBuilder
    private var actionButton: some View {
        if vm.uploadState == .idle {
            Button {
                showFilePicker = true
            } label: {
                Label("Choose Archive (.zip)", systemImage: "folder.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [Color.accentColor, Color.purple.opacity(0.85)],
                            startPoint: .leading, endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 10, x: 0, y: 4)
            }
        } else if vm.uploadState == .uploading {
            UploadProgressView(progress: vm.uploadProgress, bytesLabel: vm.uploadBytesLabel)
        }
    }
}

// MARK: - BereanImportUploadViewModel

@MainActor
final class BereanImportUploadViewModel: ObservableObject {

    enum UploadState { case idle, uploading, done }

    @Published var uploadState: UploadState = .idle
    @Published var uploadProgress: Double = 0
    @Published var uploadBytesLabel: String = ""
    @Published var showProcessingView = false
    @Published var showError = false
    @Published var errorMessage = ""

    private(set) var activeJob: ImportJob?
    private var uploadTask: StorageUploadTask?

    func beginUpload(archiveURL: URL) async {
        guard let uid = Auth.auth().currentUser?.uid else {
            showErrorMessage("Please sign in to use this feature.")
            return
        }

        // Detect source from archive filename heuristic
        let filename = archiveURL.lastPathComponent.lowercased()
        let source: ImportJobSource
        if filename.contains("instagram") { source = .instagram }
        else if filename.contains("thread") { source = .threads }
        else if filename.contains("facebook") { source = .facebook }
        else { source = .generic }

        do {
            // Create job doc (status=uploading)
            let job = try await FirestoreImportJobStore.shared.createJob(uid: uid, source: source)
            activeJob = job
            guard let jobId = job.id else { return }

            // Start upload
            uploadState = .uploading
            _ = archiveURL.startAccessingSecurityScopedResource()
            defer { archiveURL.stopAccessingSecurityScopedResource() }

            guard let fileSize = try? archiveURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                throw NSError(domain: "ImportError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Cannot read archive file size."])
            }

            if fileSize > 600_000_000 {
                showErrorMessage("Archive is too large (max 600 MB for v1). Please request a smaller date range from the platform, or contact us for large-archive support.")
                try? await FirestoreImportJobStore.shared.updateJobStatus(uid: uid, jobId: jobId, status: .failed)
                return
            }

            let ref = Storage.storage().reference()
                .child("imports/\(uid)/\(jobId)/archive.zip")

            let meta = StorageMetadata()
            meta.contentType = "application/zip"

            // Upload with progress tracking
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let task = ref.putFile(from: archiveURL, metadata: meta)
                self.uploadTask = task

                task.observe(.progress) { [weak self] snapshot in
                    guard let self else { return }
                    let completed = Double(snapshot.progress?.completedUnitCount ?? 0)
                    let total = Double(snapshot.progress?.totalUnitCount ?? 1)
                    Task { @MainActor in
                        self.uploadProgress = total > 0 ? completed / total : 0
                        self.uploadBytesLabel = "\(Self.formatBytes(Int64(completed))) / \(Self.formatBytes(Int64(total)))"
                    }
                }

                task.observe(.success) { _ in
                    continuation.resume()
                }

                task.observe(.failure) { snapshot in
                    continuation.resume(throwing: snapshot.error ?? NSError(domain: "StorageError", code: -1))
                }
            }

            // Mark job as queued (server Storage trigger picks it up)
            try await FirestoreImportJobStore.shared.updateJobStatus(uid: uid, jobId: jobId, status: .queued)
            uploadState = .done
            showProcessingView = true

        } catch {
            uploadState = .idle
            showErrorMessage(error.localizedDescription)
        }
    }

    private func showErrorMessage(_ msg: String) {
        errorMessage = msg
        showError = true
        uploadState = .idle
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_000_000
        if mb < 1 { return "\(bytes / 1000) KB" }
        return String(format: "%.1f MB", mb)
    }
}

// MARK: - BereanImportProcessingView

struct BereanImportProcessingView: View {

    let jobId: String
    let onReviewReady: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var job: ImportJob?
    @State private var showReview = false

    private var uid: String { Auth.auth().currentUser?.uid ?? "" }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Animated status indicator
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 100, height: 100)

                if job?.status == .ready {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: true)
                } else if job?.status == .failed {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.red)
                } else {
                    ProgressView()
                        .scaleEffect(1.8)
                        .tint(.accentColor)
                }
            }

            VStack(spacing: 8) {
                Text(job?.status.displayLabel ?? "Processing…")
                    .font(.title3.weight(.semibold))

                if let counts = job?.counts, counts.found > 0 {
                    Text("\(counts.found) items found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let error = job?.error {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }

            // Status timeline
            statusTimeline

            Spacer()

            if job?.status == .ready {
                Button {
                    showReview = true
                } label: {
                    Text("Review Posts")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if job?.status == .failed {
                Button("Dismiss") { dismiss() }
                    .padding(.bottom, 32)
            }
        }
        .padding(.horizontal, 24)
        .task {
            for await updatedJob in FirestoreImportJobStore.shared.observeJob(uid: uid, jobId: jobId) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    job = updatedJob
                }
                if updatedJob?.status == .ready || updatedJob?.status == .failed {
                    break
                }
            }
        }
        .sheet(isPresented: $showReview) {
            if let job {
                BereanImportReviewView(job: job)
            }
        }
    }

    private var statusTimeline: some View {
        let steps: [(ImportJobStatus, String)] = [
            (.uploading,   "Archive uploaded"),
            (.parsing,     "Posts extracted"),
            (.classifying, "Berean reviewed"),
            (.ready,       "Ready for you"),
        ]
        let currentRaw = job?.status ?? .uploading
        let order: [ImportJobStatus] = [.uploading, .queued, .parsing, .classifying, .ready, .done]
        let currentIndex = order.firstIndex(of: currentRaw) ?? 0

        return VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                let stepIndex = order.firstIndex(of: step.0) ?? 0
                let isDone = currentIndex > stepIndex
                let isActive = currentIndex == stepIndex

                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(isDone ? Color.green.opacity(0.15) : isActive ? Color.accentColor.opacity(0.15) : Color(.tertiarySystemBackground))
                            .frame(width: 28, height: 28)
                        if isDone {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.green)
                        } else if isActive {
                            ProgressView()
                                .scaleEffect(0.6)
                                .tint(.accentColor)
                        } else {
                            Circle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }
                    }
                    Text(step.1)
                        .font(.subheadline)
                        .foregroundStyle(isDone ? .primary : isActive ? .primary : .tertiary)
                }
            }
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Small Components

private struct ConsentStep: View {
    let number: String
    let title: String
    let description: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ArchiveStep: View {
    let platform: String
    let icon: String
    let steps: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(platform, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(i + 1).")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, alignment: .trailing)
                    Text(step)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct UploadProgressView: View {
    let progress: Double
    let bytesLabel: String
    var body: some View {
        VStack(spacing: 10) {
            ProgressView(value: progress)
                .tint(.accentColor)
                .scaleEffect(x: 1, y: 1.5)
            HStack {
                Text("Uploading…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(bytesLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }
}
