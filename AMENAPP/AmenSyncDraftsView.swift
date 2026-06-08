// AmenSyncDraftsView.swift
// AMEN Sync — Drafts + Activity History

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct AmenSyncDraftsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var projects: [AmenSyncProject] = []
    @State private var isLoading = true
    @State private var selectedProject: AmenSyncProject?
    @State private var showStudio = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading your projects...")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if projects.isEmpty {
                    CreationEmptyState(
                        icon: "arrow.triangle.2.circlepath",
                        title: "No Sync Projects",
                        message: "Your AMEN Sync projects will appear here. Tap + to create one.",
                        actionLabel: "Create Project"
                    ) {
                        dismiss()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(projects) { project in
                            SyncProjectRow(project: project) {
                                selectedProject = project
                                showStudio = true
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Sync Projects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "plus")
                            .font(.systemScaled(16, weight: .semibold))
                    }
                }
            }
            .task { await loadProjects() }
        }
        .fullScreenCover(isPresented: $showStudio) {
            AmenSyncEntryView()
        }
    }

    private func loadProjects() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            isLoading = false
            return
        }
        do {
            let snap = try await Firestore.firestore()
                .collection("amenSyncProjects")
                .whereField("authorId", isEqualTo: uid)
                .order(by: "updatedAt", descending: true)
                .limit(to: 30)
                .getDocuments()
            projects = snap.documents.compactMap { try? $0.data(as: AmenSyncProject.self) }
        } catch {
            dlog("⚠️ [AmenSyncDrafts] Failed to load projects: \(error.localizedDescription)")
        }
        isLoading = false
    }
}

// MARK: - Project Row

struct SyncProjectRow: View {
    let project: AmenSyncProject
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 14) {
                // Status icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(project.status.color.opacity(0.1))
                        .frame(width: 50, height: 50)
                    Image(systemName: project.mediaType.icon)
                        .font(.systemScaled(22))
                        .foregroundStyle(project.status.color)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(project.title)
                        .font(.custom("OpenSans-Bold", size: 14))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        // Status badge
                        Text(project.status.displayName)
                            .font(.custom("OpenSans-SemiBold", size: 11))
                            .foregroundStyle(project.status.color)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(project.status.color.opacity(0.1)))

                        // Platform count
                        Text("\(project.selectedPlatforms.count) platforms")
                            .font(.custom("OpenSans-Regular", size: 11))
                            .foregroundStyle(.secondary)

                        // Date
                        Text(relativeDate(project.updatedAt))
                            .font(.custom("OpenSans-Regular", size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.black.opacity(0.07), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func relativeDate(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 60 { return "Just now" }
        if diff < 3600 { return "\(Int(diff/60))m ago" }
        if diff < 86400 { return "\(Int(diff/3600))h ago" }
        return "\(Int(diff/86400))d ago"
    }
}

// MARK: - Activity View

struct AmenSyncActivityView: View {
    @ObservedObject var vm: AmenSyncViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if vm.jobs.isEmpty {
                    CreationEmptyState(
                        icon: "clock.fill",
                        title: "No Activity",
                        message: "Processing jobs will appear here when you prepare content.",
                        actionLabel: nil, action: nil
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(vm.jobs) { job in
                            JobRow(job: job)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Job Row

struct JobRow: View {
    let job: AmenSyncJob

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(statusColor.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: jobIcon)
                    .font(.systemScaled(18))
                    .foregroundStyle(statusColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(jobTitle)
                    .font(.custom("OpenSans-Bold", size: 13))
                HStack(spacing: 6) {
                    Text(job.status.rawValue.capitalized)
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(statusColor)
                    if let platform = job.resultPayload?["platform"] {
                        Text("· \(platform)")
                            .font(.custom("OpenSans-Regular", size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if job.status == .running {
                ProgressView(value: job.progress)
                    .progressViewStyle(.circular)
                    .scaleEffect(0.7)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.gray.opacity(0.04))
        )
    }

    private var statusColor: Color {
        switch job.status {
        case .queued:    return .gray
        case .running:   return .teal
        case .completed: return .green
        case .failed:    return .red
        case .cancelled: return .secondary
        }
    }

    private var jobIcon: String {
        switch job.jobType {
        case .cropImage:       return "crop"
        case .generateCaption: return "text.bubble.fill"
        case .moderateContent: return "shield.fill"
        case .generateThumb:   return "photo.fill"
        case .publish:         return "paperplane.fill"
        case .transcodeVideo:  return "video.fill"
        case .extractAudio:    return "waveform"
        }
    }

    private var jobTitle: String {
        switch job.jobType {
        case .cropImage:       return "Smart Crop"
        case .generateCaption: return "Caption Generation"
        case .moderateContent: return "Safety Check"
        case .generateThumb:   return "Thumbnail"
        case .publish:         return "Publishing"
        case .transcodeVideo:  return "Video Processing"
        case .extractAudio:    return "Audio Extraction"
        }
    }
}
