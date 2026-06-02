// AmenCreateSpaceEnhancedSheet.swift — AMEN App / Spiritual OS
// Agent E: Enhanced Create Space sheet view.
// Gated by Remote Config flag `spiritualOS_create_space_enhanced_enabled`.

import SwiftUI
import FirebaseFirestore

// MARK: - Main Sheet

struct AmenCreateSpaceEnhancedSheet: View {

    // MARK: - Inputs
    var userId: String
    var onDismiss: () -> Void
    var onCreated: (String) -> Void

    // MARK: - Feature flag (default OFF)
    @AppStorage("spiritualOS_create_space_enhanced_enabled")
    private var isEnabled: Bool = false

    // MARK: - State
    @StateObject private var viewModel = AmenCreateSpaceViewModel()
    @State private var showingImagePicker: Bool = false
    @State private var memberPresentingRolePicker: String? = nil  // member id

    // MARK: - Body

    var body: some View {
        GlassSheet(title: "Create Space", tint: .amenGold, showDismissButton: true, onDismiss: onDismiss) {
            ScrollView {
                VStack(spacing: 20) {
                    nameDescriptionSection
                    coverPhotoSection
                    membersSection
                    privacySection
                    featuresSection
                    submitSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
        .onChange(of: viewModel.isSubmitted) { submitted in
            if submitted {
                onCreated("")
                onDismiss()
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            // Image picker placeholder — wired by Lead when PHPickerViewController is available
            Text("Image Picker")
                .font(.body)
                .foregroundStyle(Color.amenSlate)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.amenCream)
        }
    }

    // MARK: - Section: Name & Description

    private var nameDescriptionSection: some View {
        GlassCard(tint: .amenGold) {
            VStack(spacing: 0) {
                TextField("Space name…", text: $viewModel.spaceName)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.amenBlack)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .accessibilityLabel("Space name")

                Divider()
                    .padding(.horizontal, 16)

                ZStack(alignment: .topLeading) {
                    if viewModel.spaceDescription.isEmpty {
                        Text("Add description…")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.amenSlate.opacity(0.6))
                            .padding(.top, 12)
                            .padding(.leading, 16)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $viewModel.spaceDescription)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.amenSlate)
                        .frame(minHeight: 56, maxHeight: 80)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .accessibilityLabel("Space description")
                }
            }
        }
    }

    // MARK: - Section: Cover Photo

    private var coverPhotoSection: some View {
        GlassCard(tint: .amenGold) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.amenSlate.opacity(0.08))
                        .frame(width: 60, height: 60)
                    Image(systemName: "photo")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.amenSlate.opacity(0.5))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cover Photo")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.amenBlack)
                    Text("Optional space header image")
                        .font(.caption)
                        .foregroundStyle(Color.amenSlate)
                }
                Spacer()
                GlassChip(
                    label: "Add cover",
                    icon: "plus",
                    tint: .amenGold,
                    size: .compact,
                    isActive: false,
                    action: { showingImagePicker = true }
                )
                .accessibilityLabel("Add cover photo")
            }
            .padding(16)
        }
    }

    // MARK: - Section: Members

    private var membersSection: some View {
        GlassCard(tint: .amenGold) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Members")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.amenSlate)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        // Add-member button as first item
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(Color.amenGold.opacity(0.12))
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Circle().strokeBorder(Color.amenGold.opacity(0.35), lineWidth: 1.5)
                                    )
                                Image(systemName: "person.badge.plus")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.amenGold)
                            }
                            Text("Add")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.amenSlate)
                                .lineLimit(1)
                        }
                        .frame(width: 52)
                        .accessibilityLabel("Add member")
                        .accessibilityAddTraits(.isButton)

                        ForEach(viewModel.members) { member in
                            memberCell(member)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                }
            }
        }
    }

    @ViewBuilder
    private func memberCell(_ member: SpaceMemberDraft) -> some View {
        VStack(spacing: 6) {
            // Avatar
            ZStack {
                if let url = member.avatarURL {
                    CachedAsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(Color.amenSlate.opacity(0.25))
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.amenSlate.opacity(0.25))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.amenSlate)
                        )
                }
            }

            Text(member.displayName)
                .font(.system(size: 11))
                .foregroundStyle(Color.amenBlack)
                .lineLimit(1)
                .frame(maxWidth: 60)

            // Role chip — tap to open role picker
            let isLeaderOrPastor = (member.role == .leader || member.role == .pastor)
            GlassChip(
                label: member.role.displayLabel,
                tint: isLeaderOrPastor ? .amenGold : .amenSlate,
                size: .compact,
                isActive: true,
                action: { memberPresentingRolePicker = member.id }
            )
            .accessibilityLabel("Role: \(member.role.displayLabel). Tap to change.")
            .confirmationDialog(
                "Change Role for \(member.displayName)",
                isPresented: Binding(
                    get: { memberPresentingRolePicker == member.id },
                    set: { if !$0 { memberPresentingRolePicker = nil } }
                ),
                titleVisibility: .visible
            ) {
                ForEach(SpacePastoralRole.allCases, id: \.rawValue) { role in
                    Button(role.displayLabel) {
                        viewModel.updateRole(memberId: member.id, role: role)
                        memberPresentingRolePicker = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    memberPresentingRolePicker = nil
                }
            }
        }
        .frame(width: 60)
    }

    // MARK: - Section: Privacy

    private var privacySection: some View {
        GlassCard(tint: .amenGold) {
            VStack(spacing: 0) {
                // Private Space toggle
                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.body)
                        .foregroundStyle(Color.amenGold)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Private Space")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.amenBlack)
                        Text("Only invited members can join")
                            .font(.caption)
                            .foregroundStyle(Color.amenSlate)
                    }

                    Spacer()

                    Toggle("", isOn: $viewModel.isPrivate)
                        .labelsHidden()
                        .tint(.amenGold)
                        .accessibilityLabel("Make this space private")
                }
                .padding(16)

                // Encrypted Prayer Wall — animates in when private is ON
                if viewModel.isPrivate {
                    Divider()
                        .padding(.horizontal, 16)

                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield.fill")
                            .font(.body)
                            .foregroundStyle(Color.amenBlue)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Encrypted Prayer Wall")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.amenBlack)
                            Text("Prayer messages are end-to-end encrypted")
                                .font(.caption)
                                .foregroundStyle(Color.amenSlate)
                        }

                        Spacer()

                        Toggle("", isOn: $viewModel.encryptedPrayerWall)
                            .labelsHidden()
                            .tint(.amenBlue)
                            .accessibilityLabel("Encrypted Prayer Wall. Prayer messages are end-to-end encrypted.")
                    }
                    .padding(16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isPrivate)
        }
    }

    // MARK: - Section: Features

    private var featuresSection: some View {
        GlassCard(tint: .amenGold) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Features")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.amenSlate)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                // 2-column chip grid
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    alignment: .leading,
                    spacing: 10
                ) {
                    featureChip(
                        label: "Church Notes",
                        icon: "doc.text",
                        isActive: viewModel.features.churchNotes,
                        accessibilityLabel: "Church Notes feature toggle"
                    ) {
                        viewModel.features.churchNotes.toggle()
                    }

                    featureChip(
                        label: "Berean AI",
                        icon: "sparkles",
                        isActive: viewModel.features.bereanEnabled,
                        accessibilityLabel: "Berean AI feature toggle"
                    ) {
                        viewModel.features.bereanEnabled.toggle()
                    }

                    featureChip(
                        label: "Events",
                        icon: "calendar",
                        isActive: viewModel.features.events,
                        accessibilityLabel: "Events feature toggle"
                    ) {
                        viewModel.features.events.toggle()
                    }

                    featureChip(
                        label: "Resources",
                        icon: "tray.fill",
                        isActive: viewModel.features.resources,
                        accessibilityLabel: "Resources feature toggle"
                    ) {
                        viewModel.features.resources.toggle()
                    }

                    featureChip(
                        label: "Prayer Wall",
                        icon: "hands.sparkles",
                        isActive: viewModel.features.prayerWall,
                        accessibilityLabel: "Prayer Wall feature toggle"
                    ) {
                        viewModel.features.prayerWall.toggle()
                    }
                }
                .padding(.horizontal, 16)

                Divider()
                    .padding(.horizontal, 16)

                // Add Berean as Member row
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.body)
                        .foregroundStyle(Color.amenPurple)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add Berean as a resident member")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.amenBlack)
                        Text("Berean joins your Space and can respond to requests")
                            .font(.caption)
                            .foregroundStyle(Color.amenSlate)
                    }

                    Spacer()

                    Toggle("", isOn: $viewModel.addBereanAsMember)
                        .labelsHidden()
                        .tint(.amenPurple)
                        .accessibilityLabel("Add Berean as a resident member")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
    }

    @ViewBuilder
    private func featureChip(
        label: String,
        icon: String,
        isActive: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        GlassChip(
            label: label,
            icon: icon,
            tint: .amenGold,
            size: .regular,
            isActive: isActive,
            action: action
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isActive ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Section: Submit

    @ViewBuilder
    private var submitSection: some View {
        Button {
            Task {
                await viewModel.submit(creatorUserId: userId)
            }
        } label: {
            ZStack {
                if viewModel.isSubmitting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Create Space")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.amenGold)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(!viewModel.isValid || viewModel.isSubmitting)
        .opacity(viewModel.isValid ? 1.0 : 0.4)
        .accessibilityLabel("Create Space")
        .accessibilityHint("Submits the form and creates your new Space")
        .padding(.top, 4)

        // Inline error banner
        if let error = viewModel.submitError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.top, 6)
        }
    }
}
