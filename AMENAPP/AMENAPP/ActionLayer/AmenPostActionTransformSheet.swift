// AmenPostActionTransformSheet.swift
// AMEN App — Action Layer: Liquid Glass sheet for turning any post into an action

import SwiftUI
import FirebaseAuth

// MARK: - AmenPostActionTransformSheet

struct AmenPostActionTransformSheet: View {
    let postId: String
    let postText: String
    let authorName: String
    @Binding var isPresented: Bool

    // MARK: State

    @State private var selectedAction: AmenPostTransformAction? = nil
    @State private var scheduledDate: Date = Calendar.current.date(
        byAdding: .day, value: 1, to: Date()
    ) ?? Date()
    @State private var customTitle: String = ""
    @State private var assignedTo: String = ""
    @State private var isSaving = false
    @State private var showDetail = false

    @Environment(\.colorScheme) private var colorScheme

    private let service = AmenPostActionTransformService.shared
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                scrollContent
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    headerTitle
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        withAnimation(.amenSpringStandard) {
                            isPresented = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.systemScaled(24))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Dismiss")
                    .accessibilityHint("Closes this sheet without saving")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(.ultraThinMaterial)
        .onChange(of: selectedAction) { _, newVal in
            withAnimation(.amenSpringStandard) {
                showDetail = newVal != nil
            }
            if let currentUser = Auth.auth().currentUser?.displayName, !currentUser.isEmpty {
                assignedTo = currentUser
            }
        }
        // Surface Settings deep-link if user denied notification permission.
        .alert("Enable Notifications", isPresented: .init(
            get: { service.notificationPermissionDenied },
            set: { _ in }
        )) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("To receive reminders for this post, allow AMEN to send notifications in Settings.")
        }
    }

    // MARK: - Scroll content

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                authorSubtitle
                postPreviewChip
                actionGrid

                if showDetail, let action = selectedAction {
                    inlineDetail(for: action)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            )
                        )
                }

                footerNote
                    .padding(.bottom, 32)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    // MARK: - Header title

    private var headerTitle: some View {
        VStack(spacing: 2) {
            Text("Turn this into action")
                .font(.systemScaled(17, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Author subtitle

    private var authorSubtitle: some View {
        Text("by @\(authorName)")
            .font(.systemScaled(14, weight: .regular))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Post preview chip

    private var postPreviewChip: some View {
        Text(postText)
            .font(.systemScaled(14, weight: .regular))
            .foregroundStyle(.primary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(glassBackground(cornerRadius: 16))
            .accessibilityLabel("Post preview: \(postText)")
    }

    // MARK: - Action grid

    private var actionGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(AmenPostTransformAction.allCases) { action in
                ActionCardButton(
                    action: action,
                    isSelected: selectedAction == action
                ) {
                    withAnimation(.amenSpringBouncy) {
                        if selectedAction == action {
                            selectedAction = nil
                        } else {
                            selectedAction = action
                        }
                    }
                    HapticManager.impact(style: .light)
                }
            }
        }
    }

    // MARK: - Inline detail panel

    @ViewBuilder
    private func inlineDetail(for action: AmenPostTransformAction) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(action.displayName)
                .font(.systemScaled(16, weight: .semibold))
                .foregroundStyle(action.accentColor)

            detailControls(for: action)

            saveButton(for: action)
        }
        .padding(18)
        .background(glassBackground(cornerRadius: 20, tint: action.accentColor))
    }

    @ViewBuilder
    private func detailControls(for action: AmenPostTransformAction) -> some View {
        switch action {
        case .reminder, .event:
            VStack(alignment: .leading, spacing: 8) {
                Label("When", systemImage: "clock")
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundStyle(.secondary)
                DatePicker(
                    "Schedule",
                    selection: $scheduledDate,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
                .labelsHidden()
                .accessibilityLabel("Select date and time")
                .accessibilityHint("Choose when you want to be reminded")
            }

        case .task:
            VStack(alignment: .leading, spacing: 8) {
                Label("Assign to", systemImage: "person")
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Your name", text: $assignedTo)
                    .font(.systemScaled(15))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                    )
                    .accessibilityLabel("Assign task to")
                    .accessibilityHint("Enter who this task is assigned to")
            }

        case .prayerItem, .discussion, .volunteerOpportunity:
            Text(action.description)
                .font(.systemScaled(14, weight: .regular))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Save button

    private func saveButton(for action: AmenPostTransformAction) -> some View {
        Button {
            Task { @MainActor in await performSave(action: action) }
        } label: {
            HStack(spacing: 10) {
                if isSaving {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(0.85)
                } else {
                    Image(systemName: action.icon)
                        .font(.systemScaled(16, weight: .semibold))
                }
                Text(isSaving ? "Saving…" : "Save")
                    .font(.systemScaled(16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSaving ? action.accentColor.opacity(0.6) : action.accentColor)
            )
            .animation(.amenEaseQuick, value: isSaving)
        }
        .disabled(isSaving)
        .accessibilityLabel("Save \(action.displayName)")
        .accessibilityHint("Saves this post as a \(action.displayName.lowercased())")
    }

    // MARK: - Footer

    private var footerNote: some View {
        Label(
            "Actions are private by default. Only you can see this.",
            systemImage: "lock.fill"
        )
        .font(.systemScaled(12, weight: .regular))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 8)
    }

    // MARK: - Save logic

    private func performSave(action: AmenPostTransformAction) async {
        isSaving = true
        let request = AmenPostTransformRequest(
            postId: postId,
            postText: postText,
            authorName: authorName,
            action: action,
            scheduledDate: (action == .reminder || action == .event) ? scheduledDate : nil,
            customTitle: customTitle.isEmpty ? nil : customTitle,
            assignedTo: (action == .task && !assignedTo.isEmpty) ? assignedTo : nil
        )
        do {
            try await service.transformPost(request)
            HapticManager.notification(type: .success)
            ToastManager.shared.showSuccess("Added to your \(action.displayName.lowercased())!")
            withAnimation(.amenSpringStandard) {
                isPresented = false
            }
        } catch {
            HapticManager.notification(type: .error)
            ToastManager.shared.showError(error.localizedDescription)
        }
        isSaving = false
    }

    // MARK: - Glass background helper

    private func glassBackground(cornerRadius: CGFloat, tint: Color? = nil) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
            if let tint {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint.opacity(colorScheme == .dark ? 0.12 : 0.08))
            }
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        }
    }
}

// MARK: - ActionCardButton

private struct ActionCardButton: View {
    let action: AmenPostTransformAction
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(action.accentColor.opacity(isSelected ? 0.22 : 0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: action.icon)
                        .font(.systemScaled(22, weight: .semibold))
                        .foregroundStyle(action.accentColor)
                        .symbolEffect(.bounce, value: isSelected)
                }

                Text(action.displayName)
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(action.description)
                    .font(.systemScaled(11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isSelected ? action.accentColor.opacity(0.45) : Color.white.opacity(0.15),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .animation(.amenSpringBouncy, value: isSelected)
            .animation(.easeOut(duration: 0.12), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
        .accessibilityLabel(action.displayName)
        .accessibilityHint(action.description)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
            if isSelected {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(action.accentColor.opacity(0.08))
            }
        }
    }
}
