import SwiftUI

struct AmenGeneratedDraftPreview: View {
    let draft: AmenGeneratedDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AmenAIUsageLabel(text: "AI-assisted draft")
            if let title = draft.title, !title.isEmpty {
                Text(title).font(.headline).foregroundStyle(.black)
            }
            if let body = draft.body, !body.isEmpty {
                Text(body).font(.body).foregroundStyle(.black)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white)
        .amenSpatialMicrodepth(isFocused: true, cornerRadius: 18)
    }
}
