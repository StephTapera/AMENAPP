import SwiftUI

struct SpiritualJourneySelectionView: View {
    @State private var selectedPeriod: JourneyPeriod = .monthly
    @State private var showWrapped = false

    var body: some View {
        VStack(spacing: 0) {
            header
            periodPicker
                .padding(.top, 24)
            Spacer()
            startButton
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 20)
        .background(Color.white.ignoresSafeArea())
        .navigationTitle("Spiritual Journey")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showWrapped) {
            FaithWrappedView(period: selectedPeriod)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your journey, gently told back to you")
                .font(AMENFont.bold(20))
                .foregroundStyle(.black)
            Text("Choose a period and we’ll build a calm, personal reflection story.")
                .font(AMENFont.medium(13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 24)
    }

    private var periodPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Period")
                .font(AMENFont.semiBold(12))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(1.2)

            HStack(spacing: 8) {
                ForEach(JourneyPeriod.allCases, id: \.self) { period in
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            selectedPeriod = period
                        }
                    } label: {
                        Text(period.rawValue.capitalized)
                            .font(AMENFont.semiBold(12))
                            .foregroundStyle(selectedPeriod == period ? .white : .black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(selectedPeriod == period ? Color.black : Color.black.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var startButton: some View {
        Button {
            showWrapped = true
        } label: {
            Text("Start Faith Wrapped")
                .font(AMENFont.semiBold(15))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}
