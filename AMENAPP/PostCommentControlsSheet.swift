//
//  PostCommentControlsSheet.swift
//  AMENAPP
//
//  Per-post comment permission controls
//  "Who can comment on this post?"
//

import SwiftUI
import Combine

struct PostCommentControlsSheet: View {
    @Binding var selectedPermission: CommentPermissionLevel
    @Environment(\.dismiss) var dismiss
    @State private var tempSelection: CommentPermissionLevel

    init(selectedPermission: Binding<CommentPermissionLevel>) {
        self._selectedPermission = selectedPermission
        self._tempSelection = State(initialValue: selectedPermission.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Section header
                    Text("WHO CAN COMMENT")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    // Glass card
                    VStack(spacing: 0) {
                        ForEach(Array(CommentPermissionLevel.allCases.enumerated()), id: \.element) { index, level in
                            Button {
                                tempSelection = level
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(level.displayName)
                                            .font(AMENFont.semiBold(16))
                                            .foregroundStyle(.primary)

                                        Text(level.description)
                                            .font(AMENFont.regular(13))
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    if tempSelection == level {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.blue)
                                            .font(.system(size: 20))
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if index < CommentPermissionLevel.allCases.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    // Footer note
                    Text("You can change this for each post when you create it.")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 32)
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Comment Controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        selectedPermission = tempSelection
                        dismiss()
                    }
                    .font(AMENFont.semiBold(16))
                }
            }
        }
        .presentationDetents([.medium])
    }
}

extension CommentPermissionLevel {
    var description: String {
        switch self {
        case .everyone:
            return "Anyone can comment on this post"
        case .followersOnly:
            return "Only people who follow you"
        case .mutualsOnly:
            return "Only people you both follow"
        case .nobody:
            return "No one can comment"
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var permission: CommentPermissionLevel = .everyone

        var body: some View {
            PostCommentControlsSheet(selectedPermission: $permission)
        }
    }

    return PreviewWrapper()
}
