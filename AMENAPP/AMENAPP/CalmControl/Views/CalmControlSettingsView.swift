import SwiftUI

// MARK: - CalmControlSettingsView
// 7-section settings surface for the CalmControl subsystem.
// Design rules: white backgrounds, black text, native controls only.
// Liquid Glass only on navigation layer — not on content cells.
// Full Dynamic Type, VoiceOver, Reduce Motion, Reduce Transparency support.

struct CalmControlSettingsView: View {

    @StateObject private var service = CalmControlService.shared
    @State private var showAddLayerSheet = false
    @State private var newLayerName = ""

    var body: some View {
        NavigationStack {
            List {
                profileVisibilitySection
                feedAndContentSection
                emotionalAndMediaSection
                presenceSection
                audienceLayersSection
                notificationSection
                topicSaturationSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Your Controls")
            .navigationBarTitleDisplayMode(.large)
            .task {
                service.startListening()
                service.startListeningToLayers()
            }
            .onDisappear {
                service.stopListening()
            }
            .sheet(isPresented: $showAddLayerSheet) {
                addLayerSheet
            }
        }
    }

    // MARK: - Section 1: Profile Visibility

    private var profileVisibilitySection: some View {
        Section {
            Toggle(isOn: $service.privacySettings.hideFollowerCount) {
                Label("Hide Follower Count", systemImage: "eye.slash")
            }
            .accessibilityHint("When on, your follower count is hidden from your profile.")
            .onChange(of: service.privacySettings.hideFollowerCount) { _, _ in
                Task { await service.savePrivacySettings() }
            }

            Toggle(isOn: $service.privacySettings.hideFollowingCount) {
                Label("Hide Following Count", systemImage: "eye.slash.fill")
            }
            .accessibilityHint("When on, the number of people you follow is hidden.")
            .onChange(of: service.privacySettings.hideFollowingCount) { _, _ in
                Task { await service.savePrivacySettings() }
            }

            Toggle(isOn: $service.privacySettings.privateFollowingGraph) {
                Label("Private Following List", systemImage: "lock.fill")
            }
            .accessibilityHint("When on, others cannot see who you follow.")
            .onChange(of: service.privacySettings.privateFollowingGraph) { _, _ in
                Task { await service.savePrivacySettings() }
            }

            Toggle(isOn: $service.privacySettings.quietProfileMode) {
                Label("Quiet Profile Mode", systemImage: "moon.fill")
            }
            .accessibilityHint("Shows only your bio and posts. No stats or activity indicators.")
            .onChange(of: service.privacySettings.quietProfileMode) { _, _ in
                Task { await service.savePrivacySettings() }
            }

            Toggle(isOn: $service.privacySettings.disableReadReceipts) {
                Label("Disable Read Receipts", systemImage: "checkmark.message")
            }
            .accessibilityHint("Others cannot see when you have read their messages.")
            .onChange(of: service.privacySettings.disableReadReceipts) { _, _ in
                Task { await service.savePrivacySettings() }
            }

            Toggle(isOn: $service.privacySettings.allowAnonymousReflectionPosting) {
                Label("Anonymous Reflections", systemImage: "person.fill.questionmark")
            }
            .accessibilityHint("Post reflections anonymously. Your identity is verified internally for safety.")
            .onChange(of: service.privacySettings.allowAnonymousReflectionPosting) { _, _ in
                Task { await service.savePrivacySettings() }
            }
        } header: {
            Text("Profile & Visibility")
        } footer: {
            Text("Counts and activity are private by default. Interactions still work normally.")
                .font(.caption)
        }
    }

    // MARK: - Section 2: Feed & Content

    private var feedAndContentSection: some View {
        Section {
            Toggle(isOn: $service.feedControls.textOnlyFeedMode) {
                Label("Text-Only Mode", systemImage: "text.alignleft")
            }
            .accessibilityHint("Hides photos and videos. Feed shows text, reflections, and discussions.")
            .onChange(of: service.feedControls.textOnlyFeedMode) { newValue, _ in
                if newValue {
                    service.feedControls.disablePhotos = true
                    service.feedControls.disableVideos = true
                }
                Task { await service.saveFeedControls() }
            }

            if !service.feedControls.textOnlyFeedMode {
                Toggle(isOn: $service.feedControls.disablePhotos) {
                    Label("Hide Photos", systemImage: "photo.slash")
                }
                .accessibilityHint("Photos are removed from your feed.")
                .onChange(of: service.feedControls.disablePhotos) { _, _ in
                    Task { await service.saveFeedControls() }
                }

                Toggle(isOn: $service.feedControls.disableVideos) {
                    Label("Hide Videos", systemImage: "video.slash")
                }
                .accessibilityHint("Videos and clips are removed from your feed.")
                .onChange(of: service.feedControls.disableVideos) { _, _ in
                    Task { await service.saveFeedControls() }
                }
            }

            Toggle(isOn: $service.feedControls.hideViralContent) {
                Label("Hide Viral Content", systemImage: "arrow.triangle.2.circlepath")
            }
            .accessibilityHint("Trending and viral posts are hidden. Your feed shows trusted circles.")
            .onChange(of: service.feedControls.hideViralContent) { _, _ in
                Task { await service.saveFeedControls() }
            }

            Toggle(isOn: $service.feedControls.noDebateFilter) {
                Label("No Debate Filter", systemImage: "hand.raised.slash")
            }
            .accessibilityHint("Reduces argumentative and combative discussions in your feed.")
            .onChange(of: service.feedControls.noDebateFilter) { _, _ in
                Task { await service.saveFeedControls() }
            }

            Toggle(isOn: $service.feedControls.aiNoiseCompressionEnabled) {
                Label("AI Feed Compression", systemImage: "wand.and.sparkles")
            }
            .accessibilityHint("Berean summarizes repeated topics instead of showing every post.")
            .onChange(of: service.feedControls.aiNoiseCompressionEnabled) { _, _ in
                Task { await service.saveFeedControls() }
            }
        } header: {
            Text("Feed & Content")
        } footer: {
            Text("Shape what appears in your feed. Your community feed remains intact — you control the noise level.")
                .font(.caption)
        }
    }

    // MARK: - Section 3: Emotional Energy & Media Intensity

    private var emotionalAndMediaSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Emotional Energy")
                    .font(.subheadline)
                Text("Feed intensity: \(energyLabel(service.feedControls.emotionalEnergyLimit))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { Double(service.feedControls.emotionalEnergyLimit) },
                        set: { service.feedControls.emotionalEnergyLimit = Int($0) }
                    ),
                    in: 1...5,
                    step: 1
                ) {
                    Text("Emotional Energy Level")
                } minimumValueLabel: {
                    Text("Calm").font(.caption2)
                } maximumValueLabel: {
                    Text("All").font(.caption2)
                }
                .onChange(of: service.feedControls.emotionalEnergyLimit) { _, _ in
                    Task { await service.saveFeedControls() }
                }
                .accessibilityLabel("Emotional energy filter level \(service.feedControls.emotionalEnergyLimit) of 5")
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("Motion Intensity")
                    .font(.subheadline)
                Text("Animation level: \(intensityLabel(service.feedControls.motionIntensity))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { Double(service.feedControls.motionIntensity) },
                        set: { service.feedControls.motionIntensity = Int($0) }
                    ),
                    in: 0...5,
                    step: 1
                ) {
                    Text("Motion Intensity")
                } minimumValueLabel: {
                    Text("None").font(.caption2)
                } maximumValueLabel: {
                    Text("Full").font(.caption2)
                }
                .onChange(of: service.feedControls.motionIntensity) { _, _ in
                    Task { await service.saveFeedControls() }
                }
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("Audio Intensity")
                    .font(.subheadline)
                Text("Autoplay audio level: \(intensityLabel(service.feedControls.audioIntensity))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { Double(service.feedControls.audioIntensity) },
                        set: { service.feedControls.audioIntensity = Int($0) }
                    ),
                    in: 0...5,
                    step: 1
                ) {
                    Text("Audio Intensity")
                } minimumValueLabel: {
                    Text("Off").font(.caption2)
                } maximumValueLabel: {
                    Text("Full").font(.caption2)
                }
                .onChange(of: service.feedControls.audioIntensity) { _, _ in
                    Task { await service.saveFeedControls() }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Emotional Energy & Media")
        } footer: {
            Text("Tune how much sensory energy your feed carries. Lower settings reduce stimulation and visual noise.")
                .font(.caption)
        }
    }

    // MARK: - Section 4: Presence

    private var presenceSection: some View {
        Section {
            ForEach(AmenCalmPresenceState.allCases) { state in
                HStack {
                    Image(systemName: presenceIcon(state))
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.displayName)
                            .font(.body)
                        Text(presenceDescription(state))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if service.presence.state == state {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.primary)
                            .bold()
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    Task { await service.updatePresence(state) }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(state.displayName). \(presenceDescription(state))")
                .accessibilityAddTraits(service.presence.state == state ? .isSelected : [])
            }
        } header: {
            Text("My Presence")
        } footer: {
            Text("Let your community know how you'd like to engage right now. You can change this any time.")
                .font(.caption)
        }
    }

    // MARK: - Section 5: Audience Layers

    private var audienceLayersSection: some View {
        Section {
            if service.audienceLayers.isEmpty {
                Text("No layers yet. Create one to share content with specific groups.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(service.audienceLayers) { layer in
                    HStack {
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(layer.name).font(.body)
                            Text("\(layer.memberIds.count) members")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let layer = service.audienceLayers[index]
                        Task { await service.deleteAudienceLayer(layer.id) }
                    }
                }
            }
            Button {
                newLayerName = ""
                showAddLayerSheet = true
            } label: {
                Label("New Audience Layer", systemImage: "plus.circle")
            }
        } header: {
            Text("Audience Layers")
        } footer: {
            Text("Share content with specific groups — church, family, mentorship circle — without making it fully public.")
                .font(.caption)
        }
    }

    // MARK: - Section 6: Notification Settings

    private var notificationSection: some View {
        Section {
            Toggle(isOn: $service.notificationSettings.masterPushEnabled) {
                Label("Push Notifications", systemImage: "bell.fill")
            }
            .onChange(of: service.notificationSettings.masterPushEnabled) { _, _ in
                Task { await service.saveNotificationSettings() }
            }

            if service.notificationSettings.masterPushEnabled {
                Picker("Intensity", selection: $service.notificationSettings.intensity) {
                    ForEach(AmenNotificationIntensity.allCases) { intensity in
                        Text(intensity.displayName).tag(intensity)
                    }
                }
                .pickerStyle(.navigationLink)
                .onChange(of: service.notificationSettings.intensity) { _, _ in
                    Task { await service.saveNotificationSettings() }
                }

                Toggle(isOn: $service.notificationSettings.dailyVersePushEnabled) {
                    Label("Daily Verse", systemImage: "text.book.closed")
                }
                .onChange(of: service.notificationSettings.dailyVersePushEnabled) { _, _ in
                    Task { await service.saveNotificationSettings() }
                }

                Toggle(isOn: $service.notificationSettings.adaptiveRemindersEnabled) {
                    Label("Adaptive Reminders", systemImage: "clock.arrow.2.circlepath")
                }
                .onChange(of: service.notificationSettings.adaptiveRemindersEnabled) { _, _ in
                    Task { await service.saveNotificationSettings() }
                }

                Toggle(isOn: $service.notificationSettings.quietHoursEnabled) {
                    Label("Quiet Hours", systemImage: "moon.zzz")
                }
                .onChange(of: service.notificationSettings.quietHoursEnabled) { _, _ in
                    Task { await service.saveNotificationSettings() }
                }

                Toggle(isOn: $service.notificationSettings.inactivityPauseEnabled) {
                    Label("7-Day Inactivity Pause", systemImage: "pause.circle")
                }
                .accessibilityHint("After 7 days away, non-essential notifications are paused respectfully.")
                .onChange(of: service.notificationSettings.inactivityPauseEnabled) { _, _ in
                    Task { await service.saveNotificationSettings() }
                }

                ForEach(AmenRhythmNotificationCategory.allCases.filter { $0 != .quietReturn }) { category in
                    Toggle(isOn: Binding(
                        get: { service.notificationSettings.enabledCategories[category] ?? true },
                        set: { _ in
                            Task { await service.toggleNotificationCategory(
                                category,
                                enabled: !(service.notificationSettings.enabledCategories[category] ?? true)
                            )}
                        }
                    )) {
                        Text(category.displayName)
                    }
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("All reminders are opt-in. Amen will never send guilt-based messages. Quiet Return notifications are system-managed and sent at most once per inactivity period.")
                .font(.caption)
        }
    }

    // MARK: - Section 7: Topic Saturation

    private var topicSaturationSection: some View {
        Section {
            NavigationLink {
                topicSaturationDetail
            } label: {
                HStack {
                    Image(systemName: "dial.medium")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Topic Saturation")
                        Text("Limit how much of any one topic appears")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Topic limit per session")
                    .font(.subheadline)
                Stepper("Up to \(service.feedControls.topicSaturationLimit) posts per topic",
                        value: $service.feedControls.topicSaturationLimit, in: 1...10)
                    .onChange(of: service.feedControls.topicSaturationLimit) { _, _ in
                        Task { await service.saveFeedControls() }
                    }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Topic Controls")
        } footer: {
            Text("See less of any one subject. Discovery still works — you just see more variety.")
                .font(.caption)
        }
    }

    // MARK: - Detail Views

    private var topicSaturationDetail: some View {
        List {
            Section {
                Text("Fine-grained topic controls are coming. For now, use the session limit above to control how many posts about any single topic appear in your feed.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Topic Saturation")
        .listStyle(.insetGrouped)
    }

    // MARK: - Add Layer Sheet

    private var addLayerSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Layer name (e.g. Church, Family)", text: $newLayerName)
                        .textContentType(.name)
                } footer: {
                    Text("You can add members to this layer after creating it.")
                        .font(.caption)
                }
            }
            .navigationTitle("New Audience Layer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddLayerSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let name = newLayerName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        Task {
                            await service.createAudienceLayer(name: name)
                            showAddLayerSheet = false
                        }
                    }
                    .disabled(newLayerName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    private func energyLabel(_ value: Int) -> String {
        switch value {
        case 1: return "Calm only"
        case 2: return "Mostly calm"
        case 3: return "Balanced"
        case 4: return "Engaging"
        default: return "All content"
        }
    }

    private func intensityLabel(_ value: Int) -> String {
        switch value {
        case 0: return "Off"
        case 1: return "Minimal"
        case 2: return "Reduced"
        case 3: return "Standard"
        case 4: return "High"
        default: return "Full"
        }
    }

    private func presenceIcon(_ state: AmenCalmPresenceState) -> String {
        switch state {
        case .visible: return "eye"
        case .quiet: return "moon.fill"
        case .reflecting: return "sparkles"
        case .focused: return "target"
        case .sabbathing: return "sun.max.fill"
        }
    }

    private func presenceDescription(_ state: AmenCalmPresenceState) -> String {
        switch state {
        case .visible: return "Fully present and open to interaction."
        case .quiet: return "Here, but not looking for conversation."
        case .reflecting: return "In a reflective state. Minimal interaction."
        case .focused: return "Deep focus. Distractions are reduced."
        case .sabbathing: return "Resting. Social features are paused."
        }
    }
}
