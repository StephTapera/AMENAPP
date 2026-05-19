import SwiftUI

struct AmenDiscoverReasonSheet: View {
    let reason: String

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(reason)
                    .font(.body)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .background(Color.white)
            .navigationTitle("Why this?")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
