import SwiftUI

struct AmenCreatorKitHome: View {
    let actions = ["Mic", "Captions", "Translate", "Explain", "Summarize", "Improve", "Create Graphic", "Prayer Points", "Action Items", "Discussion Questions"]

    var body: some View {
        VStack(spacing: 12) {
            Text("Amen Creator Kit")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.black)
            AmenLiquidGlassControlDock(placement: .top) {
                ForEach(actions, id: \.self) { action in
                    AmenLiquidGlassPillButton(title: action, systemImage: "sparkles", isLoading: false, isDisabled: false, action: {})
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top)
        .background(Color.white)
    }
}
