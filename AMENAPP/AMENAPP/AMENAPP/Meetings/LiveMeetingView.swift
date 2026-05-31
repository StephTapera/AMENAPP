import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - LiveMeetingView
// Live-meeting screen. Reuses:
//   - CommunalChatView for the group chat panel
//   - ScriptureLinkChip for the study passage
//   - MeetingService for RSVP + status
//   - BereanSmartChannelHook (host-only) for discussion questions

struct LiveMeetingView: View {
    let meeting: Meeting
    let group: AmenGroup

    @StateObject private var vm: LiveMeetingViewModel
    @State private var showHostQuestions = false
    @State private var hostQuestions: [String] = []
    @State private var scriptureExpanded = false

    init(meeting: Meeting, group: AmenGroup) {
        self.meeting = meeting
        self.group = group
        _vm = StateObject(wrappedValue: LiveMeetingViewModel(meeting: meeting))
    }

    private var currentMeeting: Meeting { vm.liveMeeting ?? meeting }
    private var isHost: Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        return meeting.hostUids.contains(uid)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Live badge
                liveBadge

                // Title + passage
                VStack(alignment: .leading, spacing: 10) {
                    Text(meeting.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)

                    if let passage = meeting.studyPassage {
                        ScriptureLinkChip(reference: passage, isExpanded: scriptureExpanded) {
                            withAnimation(.spring(response: 0.3)) { scriptureExpanded.toggle() }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)

                // RSVP row
                RSVPRowView(rsvps: currentMeeting.rsvps) { status in
                    Task { try? await MeetingService.shared.rsvp(meetingId: meeting.id ?? "", status: status) }
                }
                .padding(.horizontal, 20)

                // Agenda
                if !meeting.agendaBlocks.isEmpty {
                    LiveMeetingGlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Agenda", systemImage: "list.bullet.rectangle")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AmenTheme.Colors.textSecondary)
                            ForEach(meeting.agendaBlocks.sorted { $0.order < $1.order }) { block in
                                AgendaBlockRow(block: block)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }

                // Host-only: discussion questions from Berean
                if isHost, let passage = meeting.studyPassage {
                    hostQuestionsButton(passage: passage)
                        .padding(.horizontal, 20)
                }

                // Open group chat
                if let channel = vm.groupChannel {
                    NavigationLink {
                        CommunalChatView(channel: channel, groupName: group.name)
                    } label: {
                        Label("Open Group Chat", systemImage: "bubble.left.and.bubble.right")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AmenTheme.Colors.accentPrimary)
                            }
                    }
                    .padding(.horizontal, 20)
                }

                // Host controls
                if isHost {
                    hostControls
                        .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 40)
            .padding(.top, 8)
        }
        .navigationTitle(meeting.title)
        .navigationBarTitleDisplayMode(.inline)
        .background(AmenTheme.Colors.backgroundPrimary.ignoresSafeArea())
        .sheet(isPresented: $showHostQuestions) {
            HostQuestionsSheet(questions: hostQuestions)
        }
        .task { await vm.start() }
        .onDisappear { vm.stop() }
    }

    // MARK: - Sub-views

    private var liveBadge: some View {
        HStack {
            if currentMeeting.status == .live {
                Circle().fill(Color.red).frame(width: 8, height: 8)
                Text("LIVE · \(group.name)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            } else {
                Image(systemName: "calendar")
                    .font(.caption)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                Text(meeting.startAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }
            Spacer()
            Text(meeting.startAt, style: .time)
                .font(.caption)
                .foregroundStyle(AmenTheme.Colors.textTertiary)
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func hostQuestionsButton(passage: String) -> some View {
        Button {
            Task {
                guard let groupId = group.id else { return }
                hostQuestions = (try? await BereanSmartChannelHook.shared
                    .generateDiscussionQuestions(passage: passage, groupId: groupId)) ?? []
                showHostQuestions = true
            }
        } label: {
            Label("Get Discussion Questions", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.accentPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(AmenTheme.Colors.accentPrimary.opacity(0.35), lineWidth: 0.5)
                        }
                }
        }
    }

    private var hostControls: some View {
        HStack(spacing: 12) {
            if currentMeeting.status == .scheduled {
                Button { Task { try? await MeetingService.shared.goLive(meetingId: meeting.id ?? "") } } label: {
                    Label("Go Live", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.green)
                        }
                }
            } else if currentMeeting.status == .live {
                Button { Task { try? await MeetingService.shared.endMeeting(meetingId: meeting.id ?? "") } } label: {
                    Label("End Meeting", systemImage: "stop.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5)
                                }
                        }
                }
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
final class LiveMeetingViewModel: ObservableObject {
    @Published var liveMeeting: Meeting?
    @Published var groupChannel: AmenChannel?

    private let meetingId: String
    private let groupId: String
    private var listener: ListenerRegistration?
    private let db = Firestore.firestore()

    init(meeting: Meeting) {
        self.meetingId = meeting.id ?? ""
        self.groupId = meeting.groupId
        self.liveMeeting = meeting
    }

    deinit {
        listener?.remove()
    }

    func start() async {
        guard !meetingId.isEmpty else { return }
        listener = db.collection("meetings").document(meetingId)
            .addSnapshotListener { [weak self] snap, _ in
                self?.liveMeeting = try? snap?.data(as: Meeting.self)
            }
        groupChannel = try? await ChannelService.shared.openOrCreateGroupChannel(groupId: groupId)
    }

    func stop() {
        listener?.remove()
        listener = nil
    }
}

// MARK: - RSVP Row

private struct RSVPRowView: View {
    let rsvps: [MeetingRSVP]
    let onSelect: (MeetingRSVPStatus) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(MeetingRSVPStatus.allCases, id: \.self) { status in
                Button { onSelect(status) } label: {
                    Label(status.displayLabel, systemImage: status.systemImage)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background {
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay { Capsule().strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5) }
                        }
                }
            }
            Spacer()
            let going = rsvps.filter { $0.status == .going }.count
            Text("\(going) going")
                .font(.caption)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
    }
}

// MARK: - Agenda Block Row (display only)

private struct AgendaBlockRow: View {
    let block: AgendaBlock

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: block.type.systemImage)
                .font(.caption)
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .frame(width: 16)
                .padding(.top, 2)
            Text(block.content.isEmpty ? "—" : block.content)
                .font(block.type == .heading ? .subheadline.weight(.semibold) : .body)
                .foregroundStyle(block.type == .heading
                    ? AmenTheme.Colors.textPrimary
                    : AmenTheme.Colors.textSecondary)
        }
    }
}

// MARK: - Host Questions Sheet

private struct HostQuestionsSheet: View {
    let questions: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(questions.indices, id: \.self) { i in
                Text("\(i + 1). \(questions[i])")
                    .font(.body)
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
            }
            .navigationTitle("Discussion Questions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }
}

// MARK: - LiveMeetingGlassCard

private struct LiveMeetingGlassCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content.padding(16).background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5)
                }
        }
    }
}
