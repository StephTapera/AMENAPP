import SwiftUI
import FirebaseAuth

struct CreatorBrandKitView: View {
    @StateObject private var viewModel = CreatorBrandKitViewModel()
    @State private var ownerID: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                CreatorTopBar(title: "Brand Kits", subtitle: "Church + personal")

                if viewModel.kits.isEmpty {
                    CreatorEmptyStateView(title: "No brand kits", subtitle: "Create your first kit")
                } else {
                    ForEach(viewModel.kits) { kit in
                        CreatorGlassCard {
                            Text(kit.name)
                                .font(AMENFont.semiBold(14))
                        }
                    }
                }
            }
            .padding(20)
        }
        .task {
            ownerID = Auth.auth().currentUser?.uid ?? ""
            if !ownerID.isEmpty {
                await viewModel.load(ownerID: ownerID)
            }
        }
        .background(Color.white)
    }
}
