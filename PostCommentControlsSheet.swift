//
//  PostCommentControlsSheet.swift
//  AMENAPP
//
//  Per-post comment permission controls
//  "Who can comment on this post?"
//

import SwiftUI

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
            List {
                Section {
                    ForEach(CommentPermissionLevel.allCases, id: \.self) { level in
                        Button {
                            tempSelection = level
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(level.displayName)
                                        .font(.custom("OpenSans-SemiBold", size: 16))
                                        .foregroundStyle(.primary)
                                    
                                    Text(level.description)
                                        .font(.custom("OpenSans-Regular", size: 13))
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                if tempSelection == level {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                        .font(.system(size: 20))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("WHO CAN COMMENT")
                        .font(.custom("OpenSans-Bold", size: 12))
                } footer: {
                    Text("You can change this for each post when you create it.")
                        .font(.custom("OpenSans-Regular", size: 12))
                }
            }
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
                    .font(.custom("OpenSans-SemiBold", size: 16))
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
