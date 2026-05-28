import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct AmenSafetyCenterView: View {
    @State private var showPanicFlow = false
    @State private var safetyModeState: AmenSafetyModeDisplayState?
    @State private var safetyModeListener: ListenerRegistration?

    var body: some View {
        List {
            if let safetyModeState {
                Section("Safety Mode") {
                    AmenSafetyModeStatusCard(state: safetyModeState) {
                        exitSafetyMode()
                    }
                }
            }

            Section {
                NavigationLink {
                    AlgorithmControlCenterView()
                } label: {
                    safetyRow("My Feed Controls", icon: "slider.horizontal.3", subtitle: "Modes, quiet mode, muted risks, and reset")
                }

                NavigationLink {
                    FeedIntelligenceSettingsView()
                } label: {
                    safetyRow("Healthy Use Dashboard", icon: "heart.text.square", subtitle: "Feed health, time boundaries, and signals")
                }
            }

            Section("Protection") {
                NavigationLink {
                    VictimShieldControlsView()
                } label: {
                    safetyRow("Shield Controls", icon: "checkmark.shield", subtitle: "Limit harm, reduce exposure, and get help")
                }

                NavigationLink {
                    TrustedContactSetupView()
                } label: {
                    safetyRow("Trusted Contacts", icon: "person.badge.shield.checkmark", subtitle: "People who can be alerted if you choose")
                }

                Button(role: .destructive) {
                    showPanicFlow = true
                } label: {
                    safetyRow("Emergency Panic Flow", icon: "sos", subtitle: "Preserve evidence and request urgent review")
                }
            }

            Section("Reports And Appeals") {
                SafetyReviewRequestView()
            }

            Section("Trust And Transparency") {
                SafetyPolicySnapshotView()
                SafetyPartnerResourcesView()
            }

            Section("Reviewer Tools") {
                FabricModerationQueueView()
                SafetyReviewAdminConsoleView()
            }
        }
        .navigationTitle("Safety Center")
        .sheet(isPresented: $showPanicFlow) {
            SextortionPanicFlowView()
        }
        .onAppear { startSafetyModeListener() }
        .onDisappear {
            safetyModeListener?.remove()
            safetyModeListener = nil
        }
    }

    private func safetyRow(_ title: String, icon: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func startSafetyModeListener() {
        guard safetyModeListener == nil, let uid = Auth.auth().currentUser?.uid else { return }
        safetyModeListener = Firestore.firestore()
            .collection("amenSafetyModeStates")
            .document(uid)
            .addSnapshotListener { snapshot, _ in
                let newState = snapshot?.data().map(AmenSafetyModeDisplayState.init(data:))
                Task { @MainActor in
                    safetyModeState = newState
                }
            }
    }

    private func exitSafetyMode() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Task {
            try? await Firestore.firestore()
                .collection("amenSafetyModeStates")
                .document(uid)
                .delete()
        }
    }
}

private struct FabricModerationQueueItem: Identifiable {
    let id: String
    let source: String
    let contentId: String
    let contentType: String
    let policyLevel: String
    let safetyTreatment: String
    let status: String
    let priority: Int

    init(id: String, data: [String: Any]) {
        self.id = id
        source = data["source"] as? String ?? "amenIntelligenceFabric"
        contentId = data["contentId"] as? String ?? ""
        contentType = data["contentType"] as? String ?? "content"
        policyLevel = data["policyLevel"] as? String ?? "review"
        safetyTreatment = data["safetyTreatment"] as? String ?? "normal"
        status = data["status"] as? String ?? "pending"
        priority = data["priority"] as? Int ?? 3
    }
}

private struct FabricModerationQueueView: View {
    @State private var items: [FabricModerationQueueItem] = []
    @State private var isLoading = false
    @State private var status: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                load()
            } label: {
                Label("Load Amen Intelligence Queue", systemImage: "brain.head.profile")
            }

            if isLoading {
                ProgressView()
            } else if items.isEmpty {
                Text("No fabric-generated review items loaded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.policyLevel.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(item.priority <= 1 ? .red : .orange)
                            Spacer()
                            Text(item.status.capitalized)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text("\(item.contentType) · \(item.contentId)")
                            .font(.caption)
                            .lineLimit(1)
                        Text(item.safetyTreatment.capitalized)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Mark In Review") { update(item, status: "in_review") }
                            Button("Resolve") { update(item, status: "resolved") }
                        }
                        .font(.caption.weight(.semibold))
                    }
                    .padding(.vertical, 6)
                }
            }

            if let status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func load() {
        isLoading = true
        status = nil
        Task {
            do {
                let snapshot = try await Firestore.firestore()
                    .collection("moderationQueue")
                    .whereField("source", in: ["amenIntelligenceFabric", "amenIntelligenceAuditEvent"])
                    .order(by: "priority")
                    .limit(to: 25)
                    .getDocuments()
                items = snapshot.documents.map { FabricModerationQueueItem(id: $0.documentID, data: $0.data()) }
            } catch {
                status = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func update(_ item: FabricModerationQueueItem, status nextStatus: String) {
        Task {
            do {
                try await Firestore.firestore()
                    .collection("moderationQueue")
                    .document(item.id)
                    .setData([
                        "status": nextStatus,
                        "updatedAt": FieldValue.serverTimestamp()
                    ], merge: true)
                status = "Updated \(item.id)."
                load()
            } catch {
                status = error.localizedDescription
            }
        }
    }
}

private struct AmenSafetyModeDisplayState: Equatable {
    let sourceContentType: String
    let pauseNotifications: Bool
    let disableStrangerDMs: Bool
    let trustedCircleEligible: Bool
    let safetyTreatment: String

    init(data: [String: Any]) {
        sourceContentType = data["sourceContentType"] as? String ?? "content"
        pauseNotifications = data["pauseNotifications"] as? Bool ?? false
        disableStrangerDMs = data["disableStrangerDMs"] as? Bool ?? false
        trustedCircleEligible = data["trustedCircleEligible"] as? Bool ?? false
        safetyTreatment = data["safetyTreatment"] as? String ?? "support"
    }
}

private struct AmenSafetyModeStatusCard: View {
    let state: AmenSafetyModeDisplayState
    let onExit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "lifepreserver")
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Safety Mode Active")
                        .font(.headline)
                    Text(state.safetyTreatment.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                if state.pauseNotifications {
                    Label("Noisy notifications are quieted", systemImage: "bell.slash")
                }
                if state.disableStrangerDMs {
                    Label("Stranger DMs should stay limited", systemImage: "lock.shield")
                }
                if state.trustedCircleEligible {
                    Label("Trusted-circle support is available", systemImage: "person.2.badge.gearshape")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                NavigationLink {
                    TrustedContactSetupView()
                } label: {
                    Label("Trusted Contacts", systemImage: "person.badge.shield.checkmark")
                }
                Spacer()
                Button("Exit") { onExit() }
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.vertical, 4)
    }
}

private struct SafetyReviewRequestView: View {
    @State private var contentId = ""
    @State private var reason = ""
    @State private var status: String?
    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Post, comment, user, or conversation ID", text: $contentId)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Reason", text: $reason, axis: .vertical)
                .lineLimit(2...4)
            Button {
                submit()
            } label: {
                Label(isSubmitting ? "Submitting" : "Request Human Review", systemImage: "person.crop.circle.badge.questionmark")
            }
            .disabled(contentId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)

            if let status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func submit() {
        isSubmitting = true
        status = nil
        Task {
            do {
                try await AmenSocialSafetyService.shared.requestHumanReview(
                    contentId: contentId.trimmingCharacters(in: .whitespacesAndNewlines),
                    reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                status = "Review request submitted."
                contentId = ""
                reason = ""
            } catch {
                status = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}

private struct SafetyPolicySnapshotView: View {
    @State private var snapshot: [String: Any] = [:]
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                load()
            } label: {
                Label("View Community Standards", systemImage: "doc.text.magnifyingglass")
            }

            if isLoading {
                ProgressView()
            } else if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            } else if !snapshot.isEmpty {
                ForEach(snapshot.keys.sorted(), id: \.self) { key in
                    Text("\(key): \(String(describing: snapshot[key] ?? ""))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func load() {
        isLoading = true
        error = nil
        Task {
            do {
                snapshot = try await AmenSocialSafetyService.shared.getSafetyPolicySnapshot()
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }
}

private struct SafetyPartnerResourcesView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Link("NCMEC CyberTipline", destination: URL(string: "https://www.missingkids.org/gethelpnow/cybertipline") ?? URL(fileURLWithPath: "/"))
            Link("988 Suicide & Crisis Lifeline", destination: URL(string: "tel:988") ?? URL(fileURLWithPath: "/"))
            Link("StopItNow Helpline", destination: URL(string: "tel:18887738368") ?? URL(fileURLWithPath: "/"))
        }
        .font(.subheadline)
    }
}

private struct SafetyReviewAdminConsoleView: View {
    @State private var reportId = ""
    @State private var notes = ""
    @State private var resolution: SafetyReviewStatus = .resolved
    @State private var status: String?
    @State private var isResolving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Report ID", text: $reportId)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Picker("Resolution", selection: $resolution) {
                Text("Resolved").tag(SafetyReviewStatus.resolved)
                Text("Escalated").tag(SafetyReviewStatus.escalated)
                Text("In Review").tag(SafetyReviewStatus.inReview)
            }
            TextField("Reviewer notes", text: $notes, axis: .vertical)
                .lineLimit(2...4)
            Button {
                resolve()
            } label: {
                Label(isResolving ? "Resolving" : "Resolve Review", systemImage: "checkmark.seal")
            }
            .disabled(reportId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isResolving)

            if let status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func resolve() {
        isResolving = true
        status = nil
        Task {
            do {
                try await AmenSocialSafetyService.shared.resolveSafetyReview(
                    reportId: reportId.trimmingCharacters(in: .whitespacesAndNewlines),
                    resolution: resolution,
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                status = "Review updated."
                reportId = ""
                notes = ""
            } catch {
                status = error.localizedDescription
            }
            isResolving = false
        }
    }
}
