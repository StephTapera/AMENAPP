//
//  StartCoCreationSheet.swift
//  AMENAPP
//
//  Sheet for creating a new co-creation session.
//

import SwiftUI

// MARK: - StartCoCreationSheet

struct StartCoCreationSheet: View {

    @ObservedObject var vm: CoCreationViewModel
    let onCreated: (CoCreationSession) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title              = ""
    @State private var selectedType: CoCreationSession.SessionType = .prayer
    @State private var maxCollaborators   = 4
    @State private var isOpen             = true
    @State private var errorMessage: String? = nil

    private let amenPurple = Color(red: 0.42, green: 0.28, blue: 1.00)
    private let amenDark   = Color(red: 0.06, green: 0.06, blue: 0.09)

    // 2-column grid
    private let typeColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)

    var body: some View {
        NavigationStack {
            ZStack {
                amenDark.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {

                        // ── Title Field ───────────────────────────────
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Session Title", systemImage: "pencil")
                                .font(AMENFont.semiBold(13))
                                .foregroundStyle(.white.opacity(0.65))
                                .symbolRenderingMode(.hierarchical)

                            TextField("Give your session a title…", text: $title)
                                .font(AMENFont.regular(16))
                                .foregroundStyle(.white)
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                        )
                                )
                        }

                        // ── Session Type ──────────────────────────────
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Type", systemImage: "square.grid.2x2.fill")
                                .font(AMENFont.semiBold(13))
                                .foregroundStyle(.white.opacity(0.65))
                                .symbolRenderingMode(.hierarchical)

                            LazyVGrid(columns: typeColumns, spacing: 12) {
                                ForEach(CoCreationSession.SessionType.allCases, id: \.self) { type in
                                    SessionTypeButton(
                                        type: type,
                                        isSelected: selectedType == type
                                    ) {
                                        withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                                            selectedType = type
                                        }
                                    }
                                }
                            }
                        }

                        // ── Max Collaborators ─────────────────────────
                        glassRow {
                            HStack {
                                Label("Max collaborators", systemImage: "person.3.fill")
                                    .font(AMENFont.semiBold(15))
                                    .foregroundStyle(.white)
                                    .symbolRenderingMode(.hierarchical)
                                Spacer()
                                Stepper(
                                    "\(maxCollaborators)",
                                    value: $maxCollaborators,
                                    in: 2...8
                                )
                                .font(AMENFont.semiBold(15))
                                .foregroundStyle(.white)
                                .labelsHidden()

                                Text("\(maxCollaborators)")
                                    .font(AMENFont.bold(16))
                                    .foregroundStyle(amenPurple)
                                    .frame(minWidth: 24)
                            }
                        }

                        // ── Open to Anyone ────────────────────────────
                        glassRow {
                            Toggle(isOn: $isOpen) {
                                Label("Open to anyone", systemImage: "globe")
                                    .font(AMENFont.semiBold(15))
                                    .foregroundStyle(.white)
                                    .symbolRenderingMode(.hierarchical)
                            }
                            .tint(amenPurple)
                        }

                        // ── Error ─────────────────────────────────────
                        if let err = errorMessage {
                            Text(err)
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.red.opacity(0.85))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }

                        // ── Start Button ──────────────────────────────
                        Button {
                            guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
                                withAnimation { errorMessage = "Please enter a title." }
                                return
                            }
                            errorMessage = nil
                            Task {
                                do {
                                    let session = try await vm.createSession(
                                        title: title,
                                        type: selectedType,
                                        maxCollaborators: maxCollaborators,
                                        isOpen: isOpen
                                    )
                                    dismiss()
                                    onCreated(session)
                                } catch {
                                    withAnimation { errorMessage = error.localizedDescription }
                                }
                            }
                        } label: {
                            ZStack {
                                if vm.isCreatingSession {
                                    ProgressView()
                                        .tint(.white)
                                        .scaleEffect(0.9)
                                } else {
                                    Text("Start Session")
                                        .font(AMENFont.bold(17))
                                        .foregroundStyle(.white)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [amenPurple, Color(red: 0.60, green: 0.28, blue: 0.90)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .shadow(color: amenPurple.opacity(0.45), radius: 16, y: 6)
                            )
                        }
                        .disabled(vm.isCreatingSession)
                        .buttonStyle(CoCreationPressStyle())
                        .padding(.top, 4)

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .navigationTitle("New Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white.opacity(0.7))
                            .font(.systemScaled(22))
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    // MARK: - Glass Row Helper

    @ViewBuilder
    private func glassRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
    }
}

// MARK: - Session Type Button

private struct SessionTypeButton: View {

    let type: CoCreationSession.SessionType
    let isSelected: Bool
    let action: () -> Void

    private let amenPurple = Color(red: 0.42, green: 0.28, blue: 1.00)

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                // Gradient dot / icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: type.gradient.map { Color(hex: $0) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    Image(systemName: type.icon)
                        .font(.systemScaled(20, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                }

                Text(type.label)
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                isSelected ? amenPurple : Color.white.opacity(0.08),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
            )
        }
        .buttonStyle(CoCreationPressStyle())
    }
}
