import SwiftUI

/// A pill that morphs into a horizontal action bar (and back),
/// mirroring the "Select → [options] → Done" interaction.
/// The glass container physically resizes via matchedGeometryEffect so the
/// user stays oriented; content cross-fades on top.
struct MorphingGlassBar: View {

    struct Action: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let tint: Color
        let handler: () -> Void
    }

    let collapsedTitle: String
    let collapsedSymbol: String
    let actions: [Action]
    var onConfirm: () -> Void = {}

    @State private var expanded = false
    @Namespace private var ns

    var body: some View {
        ZStack {
            if expanded {
                expandedBar
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.92)),
                        removal: .opacity))
            } else {
                collapsedPill
                    .transition(.opacity)
            }
        }
        .animation(.amenSpring, value: expanded)
    }

    private var collapsedPill: some View {
        Button { expanded = true } label: {
            HStack(spacing: 8) {
                Image(systemName: collapsedSymbol)
                Text(collapsedTitle).fontWeight(.semibold)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .foregroundStyle(.white)
            .liquidGlass(cornerRadius: 26)
            .matchedGeometryEffect(id: "bar", in: ns)
        }
        .buttonStyle(.plain)
    }

    private var expandedBar: some View {
        HStack(spacing: 14) {
            ForEach(actions) { action in
                Button {
                    action.handler()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: action.symbol)
                            .font(.system(size: 18, weight: .semibold))
                        Text(action.title).font(.caption2)
                    }
                    .foregroundStyle(action.tint)
                    .frame(width: 56)
                }
                .buttonStyle(.plain)
            }

            Divider().frame(height: 28).overlay(.white.opacity(0.18))

            Button {
                onConfirm()
                expanded = false
            } label: {
                Text("Done")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.white, in: Capsule())
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .liquidGlass(cornerRadius: 26)
        .matchedGeometryEffect(id: "bar", in: ns)
    }
}
