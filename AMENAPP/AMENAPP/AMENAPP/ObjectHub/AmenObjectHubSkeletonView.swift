import SwiftUI

struct AmenObjectHubSkeletonView: View {
    @State private var shimmerPhase: CGFloat = -1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Header skeleton
                headerSkeleton

                VStack(spacing: 20) {
                    // Action dock skeleton
                    actionDockSkeleton
                        .padding(.horizontal, 16)

                    // Activity strip skeleton
                    activityStripSkeleton

                    // Topic chips skeleton
                    chipStripSkeleton

                    // Content rows
                    VStack(spacing: 12) {
                        ForEach(0..<4, id: \.self) { _ in
                            contentRowSkeleton
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                shimmerPhase = 1.0
            }
        }
    }

    // MARK: - Skeleton Sections

    private var headerSkeleton: some View {
        ZStack(alignment: .bottom) {
            shimmerRect(width: .infinity, height: 300, cornerRadius: 0)

            VStack(spacing: 12) {
                shimmerRect(width: 120, height: 120, cornerRadius: 16)
                shimmerRect(width: 180, height: 22, cornerRadius: 6)
                shimmerRect(width: 120, height: 14, cornerRadius: 5)
                shimmerRect(width: 90, height: 12, cornerRadius: 5)
            }
            .padding(.bottom, 24)
        }
        .frame(height: 300)
    }

    private var actionDockSkeleton: some View {
        HStack(spacing: 12) {
            ForEach(0..<4, id: \.self) { _ in
                VStack(spacing: 6) {
                    shimmerRect(width: 28, height: 28, cornerRadius: 8)
                    shimmerRect(width: 44, height: 10, cornerRadius: 4)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemFill))
        )
    }

    private var activityStripSkeleton: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { _ in
                    shimmerRect(width: 140, height: 56, cornerRadius: 14)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var chipStripSkeleton: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(0..<5, id: \.self) { i in
                    shimmerRect(width: CGFloat([60, 80, 70, 90, 65][i % 5]), height: 32, cornerRadius: 16)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var contentRowSkeleton: some View {
        HStack(spacing: 12) {
            shimmerRect(width: 44, height: 44, cornerRadius: 22)
            VStack(alignment: .leading, spacing: 6) {
                shimmerRect(width: 140, height: 13, cornerRadius: 4)
                shimmerRect(width: 200, height: 11, cornerRadius: 4)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemFill))
        )
    }

    // MARK: - Shimmer Primitive

    @ViewBuilder
    private func shimmerRect(width: CGFloat, height: CGFloat, cornerRadius: CGFloat) -> some View {
        if reduceMotion {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(.systemFill))
                .frame(width: width == .infinity ? nil : width, height: height)
                .frame(maxWidth: width == .infinity ? .infinity : nil)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(shimmerGradient)
                .frame(width: width == .infinity ? nil : width, height: height)
                .frame(maxWidth: width == .infinity ? .infinity : nil)
        }
    }

    private var shimmerGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(.systemFill), location: shimmerPhase - 0.3),
                .init(color: Color(.systemGray4).opacity(0.5), location: shimmerPhase),
                .init(color: Color(.systemFill), location: shimmerPhase + 0.3)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
