// BereanCommunityActionsBar.swift
// AMENAPP — Berean OS
//
// Horizontal action bar showing community action type counts for a
// Berean project entry. Replaces simple likes with rich typed actions.

import SwiftUI

// MARK: - Main View

struct BereanCommunityActionsBar: View {

    let projectId: String
    let entryId: String

    @StateObject private var service = BereanSocialProjectService.shared
    @State private var showActionSheet = false
    @State private var selectedAction: BereanCommunityActionType?

    // MARK: - Guard

    var body: some View {
        guard AMENFeatureFlags.shared.bereanOSCommunityIntelligenceEnabled else {
            return AnyView(EmptyView())
        }
        return AnyView(barContent)
    }

    // MARK: - Bar

    private var barContent: some View {
        HStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(usedActionTypes, id: \.self) { actionType in
                        actionChip(for: actionType)
                    }
                }
                .padding(.horizontal, 2)
            }

            Button {
                showActionSheet = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.systemScaled(22))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Add community action")
        }
        .task {
            try? await service.fetchCommunityActions(
                projectId: projectId,
                entryId: entryId
            )
        }
        .sheet(isPresented: $showActionSheet) {
            BereanCommunityActionSheet(
                projectId: projectId,
                entryId: entryId,
                isPresented: $showActionSheet
            )
        }
    }

    // MARK: - Chip

    private func actionChip(for actionType: BereanCommunityActionType) -> some View {
        let count = service.communityActions.filter { $0.actionType == actionType }.count
        return HStack(spacing: 4) {
            Image(systemName: actionType.systemIcon)
                .font(.systemScaled(12, weight: .medium))
            Text("\(count)")
                .font(.systemScaled(12, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.thinMaterial, in: Capsule())
        .foregroundStyle(.primary)
        .accessibilityLabel("\(actionType.displayName): \(count)")
    }

    // MARK: - Computed

    private var usedActionTypes: [BereanCommunityActionType] {
        let used = Set(service.communityActions.map(\.actionType))
        return BereanCommunityActionType.allCases.filter { used.contains($0) }
    }
}

// MARK: - Action Sheet

private struct BereanCommunityActionSheet: View {

    let projectId: String
    let entryId: String
    @Binding var isPresented: Bool

    @StateObject private var service = BereanSocialProjectService.shared
    @State private var selectedAction: BereanCommunityActionType?
    @State private var content: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 12)]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                // Action type picker grid
                Text("Choose an action")
                    .font(.headline)
                    .padding(.horizontal)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(BereanCommunityActionType.allCases) { actionType in
                        actionTypeChip(actionType)
                    }
                }
                .padding(.horizontal)

                // Content input
                if let action = selectedAction {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(contentLabel(for: action))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if !requiresContent(action) {
                                Text("(optional)")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        TextEditor(text: $content)
                            .frame(minHeight: 80, maxHeight: 160)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(.quaternary)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(.separator, lineWidth: 1)
                            )
                            .accessibilityLabel(contentLabel(for: action))
                    }
                    .padding(.horizontal)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                Spacer()
            }
            .padding(.top)
            .navigationTitle("Community Action")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        Task { await submit() }
                    }
                    .disabled(!canSubmit || isSubmitting)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Action Chip

    private func actionTypeChip(_ actionType: BereanCommunityActionType) -> some View {
        let isSelected = selectedAction == actionType
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if selectedAction == actionType {
                    selectedAction = nil
                } else {
                    selectedAction = actionType
                    content = ""
                }
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: actionType.systemIcon)
                    .font(.systemScaled(20))
                Text(actionType.displayName)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.15)
                    : Color(.secondarySystemBackground)
                , in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Logic

    private var canSubmit: Bool {
        guard let action = selectedAction else { return false }
        if requiresContent(action) { return !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return true
    }

    private func requiresContent(_ action: BereanCommunityActionType) -> Bool {
        switch action {
        case .addSource, .addContext, .factCheck:
            return true
        default:
            return false
        }
    }

    private func contentLabel(for action: BereanCommunityActionType) -> String {
        switch action {
        case .addSource:     return "Source URL or citation"
        case .addContext:    return "Additional context"
        case .factCheck:     return "Fact-check details"
        case .challenge:     return "Your challenge"
        case .askQuestion:   return "Your question"
        case .flagIssue:     return "Describe the issue"
        case .expand:        return "Expansion notes"
        case .summarize:     return "Your summary"
        default:             return "Comment (optional)"
        }
    }

    private func submit() async {
        guard let action = selectedAction else { return }
        isSubmitting = true
        errorMessage = nil
        do {
            try await service.recordCommunityAction(
                action,
                content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                projectId: projectId,
                targetEntryId: entryId
            )
            try? await service.fetchCommunityActions(projectId: projectId, entryId: entryId)
            isPresented = false
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}
