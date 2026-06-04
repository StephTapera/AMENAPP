// DiscussionActionSheet.swift — AMEN App
import SwiftUI

struct DiscussionActionSheet: View {
    let comment: DiscussionComment
    let isOwnComment: Bool
    let isElder: Bool
    let onAction: (DiscussionAction) -> Void
    @Environment(\.dismiss) private var dismiss

    private var actions: [DiscussionAction] {
        DiscussionActionRouter.shared.availableActions(isOwnComment: isOwnComment, isElder: isElder)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ForEach(actions, id: \.self) { action in
                    Button {
                        onAction(action)
                        dismiss()
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: action.icon)
                                .font(.system(size: 17))
                                .frame(width: 24)
                                .foregroundStyle(action.isDestructive ? .red : Color(hex: "#C9A84C"))
                            Text(action.label)
                                .font(.system(size: 16))
                                .foregroundStyle(action.isDestructive ? Color.red : Color.white.opacity(0.85))
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    if action != actions.last {
                        Divider().background(Color.white.opacity(0.08))
                    }
                }
            }
            .background(Color(hex: "#111118"))
            .navigationTitle("Comment Actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color(hex: "#C9A84C"))
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(20)
    }
}
