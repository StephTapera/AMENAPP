// DiscussionActionSheet.swift — AMEN App
import SwiftUI

struct DiscussionActionSheet: View {
    let comment: DiscussionComment
    let threadTitle: String?
    let onShareToSpaces: (DiscussionComment) -> Void
    @State private var actionStates: [DiscussionAction: ActionState] = [:]
    @Environment(\.dismiss) private var dismiss

    enum ActionState { case idle, loading, done, failed }

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 6) {
                Text(comment.authorDisplayName)
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(comment.body)
                    .font(.systemScaled(13))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .lineLimit(3)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1))
            )
            .padding(.horizontal, 20)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(DiscussionAction.allCases, id: \.self) { action in
                    actionButton(action)
                }
            }
            .padding(.horizontal, 20)
            Spacer()
        }
        .presentationDetents([.height(380)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private func actionButton(_ action: DiscussionAction) -> some View {
        let state = actionStates[action] ?? .idle
        return Button {
            guard state == .idle else { return }
            if action == .shareToSpaces {
                onShareToSpaces(comment)
                dismiss()
                return
            }
            Task {
                actionStates[action] = .loading
                let ok = (try? await DiscussionActionRouter.shared.perform(action, comment: comment, threadTitle: threadTitle)) ?? false
                actionStates[action] = ok ? .done : .failed
                if ok {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    actionStates[action] = .idle
                }
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    if state == .loading {
                        ProgressView().tint(Color.accentColor).scaleEffect(0.7)
                    } else if state == .done {
                        Image(systemName: "checkmark")
                            .font(.systemScaled(18, weight: .bold))
                            .foregroundStyle(.green)
                    } else if state == .failed {
                        Image(systemName: "xmark")
                            .font(.systemScaled(18))
                            .foregroundStyle(.red)
                    } else {
                        Image(systemName: action.icon)
                            .font(.systemScaled(20))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.1), in: Circle())
                .accessibilityHidden(true)

                Text(action.label)
                    .font(.systemScaled(10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(state == .loading)
        .accessibilityLabel(action.label)
    }
}
