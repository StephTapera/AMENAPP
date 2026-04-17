import SwiftUI

struct CreatorImportSheet: View {
    var body: some View {
        VStack(spacing: 16) {
            CreatorTopBar(title: "Import", subtitle: "Add media")
            Text("Media picker goes here")
                .font(AMENFont.medium(14))
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(Color.white)
    }
}
