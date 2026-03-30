import SwiftUI

/// Testimony strength bar + chip row shown above the Conversation section
/// on testimony posts only.
struct StrengthMeterView: View {
    @ObservedObject var service: TestimonyStrengthService

    private let fillColor = Color(red: 0.784, green: 0.447, blue: 0.165) // #c8722a

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Track + fill bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(.systemFill))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(fillColor)
                        .frame(width: max(0, geo.size.width * CGFloat(service.strength) / 100), height: 4)
                        .animation(.easeInOut(duration: 1.5), value: service.strength)
                }
            }
            .frame(height: 4)

            // Chips row
            HStack(spacing: 6) {
                StrengthChip(count: service.witnessCount,    label: "witnesses",        color: .green)
                StrengthChip(count: service.prayerEchoCount, label: "prayers echoed",   color: .blue)
                StrengthChip(count: service.scriptureCount,  label: "scriptures",        color: fillColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct StrengthChip: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(count) \(label)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color(.secondarySystemBackground))
        )
    }
}
