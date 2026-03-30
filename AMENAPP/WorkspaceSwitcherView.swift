// WorkspaceSwitcherView.swift
// AMENAPP — Cadence Workspace Switcher sheet

import SwiftUI
import FirebaseAuth

struct WorkspaceSwitcherView: View {

    @ObservedObject var vm: WorkspaceViewModel
    @Environment(\.dismiss) private var dismiss

    // Create workspace inline state
    @State private var showCreate = false
    @State private var newName = ""
    @State private var newDescription = ""
    @State private var isCreating = false
    @State private var createError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0A0A0F").ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        // ── Workspace list ───────────────────────────────────
                        ForEach(vm.workspaces) { workspace in
                            WorkspaceRow(
                                workspace: workspace,
                                isCurrent: vm.currentWorkspace?.id == workspace.id
                            ) {
                                vm.selectWorkspace(workspace)
                                dismiss()
                            }
                        }

                        if vm.workspaces.isEmpty && !vm.isLoading {
                            emptyState
                        }

                        Divider()
                            .background(Color.white.opacity(0.1))
                            .padding(.vertical, 8)

                        // ── Create workspace section ─────────────────────────
                        if showCreate {
                            createWorkspaceForm
                        } else {
                            createWorkspaceButton
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Your Workspaces")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(AMENFont.semiBold(15))
                        .foregroundColor(Color(hex: "6B48FF"))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Workspace row

    // Defined as a nested private view below the main body

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 36))
                .foregroundColor(.white.opacity(0.2))
            Text("No workspaces yet")
                .font(AMENFont.semiBold(15))
                .foregroundColor(.white.opacity(0.4))
            Text("Create one below to get started with KORA, VERGE & HELIX.")
                .font(AMENFont.regular(13))
                .foregroundColor(.white.opacity(0.3))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Create workspace button

    private var createWorkspaceButton: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                showCreate = true
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(Color(hex: "6B48FF").opacity(0.5), lineWidth: 1.5)
                        .frame(width: 36, height: 36)
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(hex: "6B48FF"))
                }
                Text("Create Workspace")
                    .font(AMENFont.semiBold(15))
                    .foregroundColor(Color(hex: "6B48FF"))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(hex: "6B48FF").opacity(0.2), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(CoCreationPressStyle())
    }

    // MARK: - Create workspace inline form

    private var createWorkspaceForm: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Workspace Name")
                    .font(AMENFont.semiBold(12))
                    .foregroundColor(.white.opacity(0.5))
                TextField("e.g. Grace Fellowship", text: $newName)
                    .font(AMENFont.regular(15))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Description")
                    .font(AMENFont.semiBold(12))
                    .foregroundColor(.white.opacity(0.5))
                TextField("What does this workspace support?", text: $newDescription)
                    .font(AMENFont.regular(15))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
            }

            if let err = createError {
                Text(err)
                    .font(AMENFont.regular(12))
                    .foregroundColor(.red.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                Button("Cancel") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        showCreate = false
                        newName = ""
                        newDescription = ""
                        createError = nil
                    }
                }
                .font(AMENFont.semiBold(15))
                .foregroundColor(.white.opacity(0.5))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    Task { await handleCreate() }
                } label: {
                    if isCreating {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    } else {
                        Text("Create")
                            .font(AMENFont.semiBold(15))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
                .background(
                    LinearGradient(
                        colors: [Color(hex: "6B48FF"), Color(hex: "8B68FF")],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                .opacity(newName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1.0)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "6B48FF").opacity(0.2), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal:   .move(edge: .bottom).combined(with: .opacity)
        ))
    }

    // MARK: - Create action

    private func handleCreate() async {
        let trimmedName = newName.trimmingCharacters(in: .whitespaces)
        let trimmedDesc = newDescription.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        isCreating = true
        createError = nil

        do {
            let workspace = try await vm.createWorkspace(name: trimmedName, description: trimmedDesc)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                showCreate = false
                newName = ""
                newDescription = ""
            }
            vm.selectWorkspace(workspace)
            dismiss()
        } catch {
            createError = error.localizedDescription
        }

        isCreating = false
    }
}

// MARK: - WorkspaceRow

private struct WorkspaceRow: View {
    let workspace: Workspace
    let isCurrent: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Org logo / initials avatar
                ZStack {
                    if let logoURL = workspace.logoURL, !logoURL.isEmpty {
                        AsyncImage(url: URL(string: logoURL)) { phase in
                            if let img = phase.image {
                                img.resizable().scaledToFill()
                            } else {
                                initialsView
                            }
                        }
                    } else {
                        initialsView
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())

                // Name + member count
                VStack(alignment: .leading, spacing: 4) {
                    Text(workspace.name)
                        .font(AMENFont.semiBold(15))
                        .foregroundColor(.white)
                    Text("\(workspace.memberCount) member\(workspace.memberCount == 1 ? "" : "s")")
                        .font(AMENFont.regular(12))
                        .foregroundColor(.white.opacity(0.45))
                }

                Spacer()

                // Enabled platform badges
                HStack(spacing: 4) {
                    ForEach(workspace.enabledPlatforms, id: \.self) { platform in
                        PlatformBadge(platform: platform)
                    }
                }

                // Checkmark if selected
                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Color(hex: "6B48FF"))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isCurrent ? Color(hex: "6B48FF").opacity(0.3) : Color.white.opacity(0.07),
                        lineWidth: isCurrent ? 1.0 : 0.5
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(CoCreationPressStyle())
    }

    private var initialsView: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "6B48FF"), Color(hex: "F59E0B")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(initials)
                .font(AMENFont.bold(16))
                .foregroundColor(.white)
        }
    }

    private var initials: String {
        let words = workspace.name.split(separator: " ")
        if words.count >= 2 {
            return "\(words[0].prefix(1))\(words[1].prefix(1))".uppercased()
        }
        return String(workspace.name.prefix(2)).uppercased()
    }
}

// MARK: - PlatformBadge

private struct PlatformBadge: View {
    let platform: String

    var body: some View {
        Text(label)
            .font(AMENFont.bold(10))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.25))
            .overlay(
                Capsule().stroke(color.opacity(0.5), lineWidth: 0.5)
            )
            .clipShape(Capsule())
    }

    private var label: String {
        switch platform {
        case "kora":  return "K"
        case "verge": return "V"
        case "helix": return "H"
        default:      return platform.prefix(1).uppercased()
        }
    }

    private var color: Color {
        switch platform {
        case "kora":  return Color(hex: "F59E0B")
        case "verge": return Color(hex: "06B6D4")
        case "helix": return Color(hex: "10B981")
        default:      return Color(hex: "6B48FF")
        }
    }
}
