import SwiftUI

struct ModerationCaseDetailView: View {
    let moderationCase: ModerationCase
    let service: ModerationService
    @Environment(\.dismiss) private var dismiss
    @State private var moderatorNote = ""
    @State private var isActing = false
    @State private var showActionConfirm: ModerationAction? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    caseHeaderSection
                    flagDetailsSection
                    noteSection
                    actionsSection
                }
                .padding(16).padding(.bottom, 32)
            }
            .navigationTitle("Case Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }.font(.custom("OpenSans-Regular", size: 16))
                }
            }
            .confirmationDialog(
                "Confirm Action",
                isPresented: Binding(get: { showActionConfirm != nil }, set: { if !$0 { showActionConfirm = nil } })
            ) {
                if let action = showActionConfirm {
                    Button(action.displayName, role: action.isDestructive ? .destructive : .none) {
                        isActing = true
                        Task {
                            await service.resolveCase(caseId: moderationCase.id ?? "", action: action, note: moderatorNote)
                            dismiss()
                        }
                    }
                    Button("Cancel", role: .cancel) { showActionConfirm = nil }
                }
            }
        }
    }

    private var caseHeaderSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(moderationCase.type.displayName).font(.custom("OpenSans-Bold", size: 18)).foregroundStyle(AmenTheme.Colors.textPrimary)
                Text(moderationCase.status.displayName).font(.custom("OpenSans-Regular", size: 13)).foregroundStyle(AmenTheme.Colors.textSecondary)
            }
            Spacer()
            Circle().fill(moderationCase.flag.severity == 3 ? Color.red : moderationCase.flag.severity == 2 ? Color.orange : Color.green).frame(width: 14, height: 14)
        }
        .padding(14).background(AmenTheme.Colors.surfaceCard).cornerRadius(14)
    }

    private var flagDetailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Flag Details").font(.custom("OpenSans-Bold", size: 15)).foregroundStyle(AmenTheme.Colors.textPrimary)
            detailRow(label: "Reason", value: moderationCase.flag.reason)
            detailRow(label: "Severity", value: "Level \(moderationCase.flag.severity)")
            detailRow(label: "Flagged by", value: moderationCase.flag.flaggedBy)
            if let context = moderationCase.flag.context { detailRow(label: "Context", value: context) }
            if let ts = moderationCase.flag.flaggedAt?.dateValue() { detailRow(label: "Flagged at", value: ts.formatted()) }
        }
        .padding(14).background(AmenTheme.Colors.surfaceCard).cornerRadius(14)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.custom("OpenSans-Regular", size: 13)).foregroundStyle(AmenTheme.Colors.textTertiary).frame(width: 80, alignment: .leading)
            Text(value).font(.custom("OpenSans-Regular", size: 13)).foregroundStyle(AmenTheme.Colors.textPrimary)
            Spacer()
        }
        .accessibilityElement(children: .combine).accessibilityLabel("\(label): \(value)")
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Moderator Note").font(.custom("OpenSans-Bold", size: 15)).foregroundStyle(AmenTheme.Colors.textPrimary)
            TextEditor(text: $moderatorNote)
                .font(.custom("OpenSans-Regular", size: 14)).frame(minHeight: 80).padding(8)
                .background(AmenTheme.Colors.surfaceInput).cornerRadius(10)
                .accessibilityLabel("Moderator note")
        }
    }

    private var actionsSection: some View {
        VStack(spacing: 10) {
            Text("Actions").font(.custom("OpenSans-Bold", size: 15)).foregroundStyle(AmenTheme.Colors.textPrimary)
            ForEach([ModerationAction.approve, .hide, .escalateToTeam, .contactUser], id: \.self) { action in
                Button { showActionConfirm = action } label: {
                    HStack {
                        Image(systemName: action.icon).foregroundStyle(action.isDestructive ? .red : Color(red: 0.10, green: 0.60, blue: 0.56))
                        Text(action.displayName).font(.custom("OpenSans-Bold", size: 15))
                            .foregroundStyle(action.isDestructive ? .red : AmenTheme.Colors.textPrimary)
                        Spacer()
                    }
                    .padding(12).background(AmenTheme.Colors.surfaceCard).cornerRadius(10)
                }
                .disabled(isActing)
                .accessibilityLabel(action.displayName)
            }
        }
    }
}
