// AmenCreateSpaceEnhancedSheet.swift — AMEN App / Spiritual OS
// Agent E: Enhanced Create Space sheet view.
// Gated by Remote Config flag `spiritualOS_create_space_enhanced_enabled`.

import SwiftUI
import FirebaseFirestore
import PhotosUI

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
    @State private var selectedCoverImage: UIImage? = nil
    @State private var memberPresentingRolePicker: String? = nil  // member id

    // MARK: - Expand/collapse state per section
    @State private var expandedSpaceType: Bool = true
    @State private var expandedNameDesc: Bool = true
    @State private var expandedCoverPhoto: Bool = false
    @State private var expandedMembers: Bool = false
    @State private var expandedPrivacy: Bool = false
    @State private var expandedFeatures: Bool = false

    // MARK: - Body

    var body: some View {
        GlassSheet(title: "Create Space", tint: .accentColor, showDismissButton: true, onDismiss: onDismiss) {
            ScrollView {
                VStack(spacing: 20) {
                    spaceTypeSection
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
        .onChange(of: viewModel.isSubmitted) { _, submitted in
            if submitted {
                onCreated("")
                onDismiss()
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            CreateSpaceImagePickerRepresentable(image: $selectedCoverImage)
                .ignoresSafeArea()
        }
        .onChange(of: selectedCoverImage) { _, newImage in
            viewModel.coverImageData = newImage?.jpegData(compressionQuality: 0.8)
        }
    }

    // MARK: - Expandable section helper

    @ViewBuilder
    private func expandableSection(
        title: String,
        icon: String,
        isExpanded: Binding<Bool>,
        badge: String? = nil,
        @ViewBuilder content: () -> some View
    ) -> some View {
        GlassCard(tint: .accentColor) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        isExpanded.wrappedValue.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: icon)
                            .font(.systemScaled(14, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 22)
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.amenBlack)
                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.accentColor, in: Capsule())
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.systemScaled(12, weight: .semibold))
                            .foregroundStyle(Color.amenSlate)
                            .rotationEffect(.degrees(isExpanded.wrappedValue ? 0 : -90))
                            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isExpanded.wrappedValue)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title) section, \(isExpanded.wrappedValue ? "expanded" : "collapsed")")
                .accessibilityAddTraits(.isButton)

                if isExpanded.wrappedValue {
                    Divider().padding(.horizontal, 16)
                    content()
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    // MARK: - Section: Space Type

    private var spaceTypeSection: some View {
        expandableSection(title: "Space Type", icon: "square.grid.2x2", isExpanded: $expandedSpaceType) {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(AmenCreatorSpaceType.allCases) { type in
                    spaceTypeChip(type)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    @ViewBuilder
    private func spaceTypeChip(_ type: AmenCreatorSpaceType) -> some View {
        let isSelected = viewModel.spaceType == type
        Button {
            viewModel.spaceType = type
        } label: {
            HStack(spacing: 8) {
                Image(systemName: type.systemIcon)
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundStyle(isSelected ? .white : type.accentColor)
                Text(type.displayName)
                    .font(.systemScaled(13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : Color.amenBlack)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? type.accentColor : type.accentColor.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                isSelected ? type.accentColor : type.accentColor.opacity(0.35),
                                lineWidth: 1.5
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(type.displayName)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Section: Name & Description

    private var nameDescriptionSection: some View {
        expandableSection(title: "Name & Description", icon: "pencil.line", isExpanded: $expandedNameDesc) {
            VStack(spacing: 0) {
                TextField("Space name…", text: $viewModel.spaceName)
                    .font(.systemScaled(15))
                    .foregroundStyle(Color.amenBlack)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .accessibilityLabel("Space name")

                Divider()
                    .padding(.horizontal, 16)

                ZStack(alignment: .topLeading) {
                    if viewModel.spaceDescription.isEmpty {
                        Text("Add description…")
                            .font(.systemScaled(14))
                            .foregroundStyle(Color.amenSlate.opacity(0.6))
                            .padding(.top, 12)
                            .padding(.leading, 16)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $viewModel.spaceDescription)
                        .font(.systemScaled(14))
                        .foregroundStyle(Color.amenSlate)
                        .frame(minHeight: 56, maxHeight: 80)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .accessibilityLabel("Space description")
                }
                .padding(.bottom, 4)
            }
        }
    }

    // MARK: - Section: Cover Photo

    private var coverPhotoSection: some View {
        expandableSection(
            title: "Cover Photo",
            icon: "photo",
            isExpanded: $expandedCoverPhoto,
            badge: selectedCoverImage != nil ? "Added" : nil
        ) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.amenSlate.opacity(0.08))
                        .frame(width: 60, height: 60)
                    if let picked = selectedCoverImage {
                        Image(uiImage: picked)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        Image(systemName: "photo")
                            .font(.systemScaled(22))
                            .foregroundStyle(Color.amenSlate.opacity(0.5))
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedCoverImage != nil ? "Tap to change" : "Optional space header image")
                        .font(.caption)
                        .foregroundStyle(Color.amenSlate)
                }
                Spacer()
                GlassChip(
                    label: selectedCoverImage != nil ? "Change" : "Add cover",
                    icon: selectedCoverImage != nil ? "pencil" : "plus",
                    tint: .accentColor,
                    size: .compact,
                    isActive: selectedCoverImage != nil,
                    action: { showingImagePicker = true }
                )
                .accessibilityLabel(selectedCoverImage != nil ? "Change cover photo" : "Add cover photo")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Section: Members

    private var membersSection: some View {
        expandableSection(
            title: "Members",
            icon: "person.2",
            isExpanded: $expandedMembers,
            badge: viewModel.members.isEmpty ? nil : "\(viewModel.members.count)"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        // Add-member button as first item
                        Button {
                            // TODO: present member search sheet
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle()
                                        .fill(Color.accentColor.opacity(0.12))
                                        .frame(width: 44, height: 44)
                                        .overlay(
                                            Circle().strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1.5)
                                        )
                                    Image(systemName: "person.badge.plus")
                                        .font(.systemScaled(16))
                                        .foregroundStyle(Color.accentColor)
                                }
                                Text("Add")
                                    .font(.systemScaled(11))
                                    .foregroundStyle(Color.amenSlate)
                                    .lineLimit(1)
                            }
                            .frame(width: 52)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add member")
                        .accessibilityHint("Opens member search to invite people to this Space")

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
                                .font(.systemScaled(18))
                                .foregroundStyle(Color.amenSlate)
                        )
                }
            }

            Text(member.displayName)
                .font(.systemScaled(11))
                .foregroundStyle(Color.amenBlack)
                .lineLimit(1)
                .frame(maxWidth: 60)

            // Role chip — tap to open role picker
            let isLeaderOrPastor = (member.role == .leader || member.role == .pastor)
            GlassChip(
                label: member.role.displayLabel,
                tint: isLeaderOrPastor ? .accentColor : .amenSlate,
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
        expandableSection(
            title: "Privacy",
            icon: "lock.fill",
            isExpanded: $expandedPrivacy,
            badge: viewModel.isPrivate ? "Private" : nil
        ) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.body)
                        .foregroundStyle(Color.accentColor)
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
                        .tint(.accentColor)
                        .accessibilityLabel("Make this space private")
                }
                .padding(16)

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
        expandableSection(title: "Features", icon: "star.fill", isExpanded: $expandedFeatures) {
            VStack(alignment: .leading, spacing: 14) {
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
            tint: .accentColor,
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
                        .font(.systemScaled(17, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .amenGlassEffect(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                .foregroundStyle(Color.amenError)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.top, 6)
        }
    }
}

// MARK: - PHPicker Representable
private struct CreateSpaceImagePickerRepresentable: UIViewControllerRepresentable {
    @Binding var image: UIImage?

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: CreateSpaceImagePickerRepresentable
        init(_ parent: CreateSpaceImagePickerRepresentable) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let result = results.first else { return }
            result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                DispatchQueue.main.async {
                    self.parent.image = object as? UIImage
                }
            }
        }
    }
}
