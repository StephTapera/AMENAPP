import SwiftUI

public struct AmenMomentSurfaceView: View {
    public let moment: AmenMoment
    public var client: AmenMomentDeepenClient

    @State private var flags: AmenMomentFlags = .off
    @State private var selectedAction: AmenMomentDeepenAction?
    @State private var result: AmenMomentDeepenResult?
    @State private var errorMessage: String?
    @State private var isRunning = false

    @MainActor
    public init(moment: AmenMoment, client: AmenMomentDeepenClient? = nil) {
        self.moment = moment
        self.client = client ?? .shared
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            summary
            actionRows
            if let result {
                AmenMomentResultPanel(result: result)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
        .padding(18)
        .background(AmenMomentGlass.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .task {
            flags = client.flags()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(moment.type.rawValue.capitalized)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AmenMomentGlass.amenPurple)
                Text(moment.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Text(moment.temporalState.rawValue.capitalized)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .frame(minHeight: 30)
                .background(Capsule().fill(AmenMomentGlass.amenBlue.opacity(0.16)))
                .foregroundStyle(AmenMomentGlass.amenBlue)
        }
    }

    private var summary: some View {
        Text(moment.summary)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var actionRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 148), spacing: 10)], spacing: 10) {
                ForEach(AmenMomentDeepenAction.allCases) { action in
                    Button {
                        Task { await run(action) }
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .background(deepenEnabled ? AnyShapeStyle(AmenMomentGlass.activePill) : AnyShapeStyle(AmenMomentGlass.disabledPill))
                    .clipShape(Capsule(style: .continuous))
                    .foregroundStyle(deepenEnabled ? .primary : .secondary)
                    .disabled(!deepenEnabled || isRunning)
                    .accessibilityLabel(action.title)
                }
            }

            Label("Gather gated", systemImage: "lock.shield")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(AmenMomentGlass.disabledPill)
                .clipShape(Capsule(style: .continuous))
                .foregroundStyle(.secondary)
                .accessibilityHint("complianceGateRequired")
        }
    }

    private var deepenEnabled: Bool {
        flags.momentSystemEnabled && flags.deepenActionsEnabled
    }

    private func run(_ action: AmenMomentDeepenAction) async {
        guard deepenEnabled else { return }
        selectedAction = action
        isRunning = true
        errorMessage = nil
        defer { isRunning = false }

        do {
            let mode: AmenMomentBereanMode = action == .crossReference ? .discern : .build
            result = try await client.runDeepen(
                action: action,
                moment: moment,
                mode: action == .summarize ? .ask : mode,
                saveTarget: action == .saveTo ? .prayerJournal : nil
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AmenMomentResultPanel: View {
    let result: AmenMomentDeepenResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(result.action.title)
                .font(.headline)
            Text(result.output.isEmpty ? "No output returned." : result.output)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !result.citations.isEmpty {
                Text(result.citations.joined(separator: "  "))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AmenMomentGlass.amenPurple)
            }
        }
        .padding(12)
        .background(AmenMomentGlass.resultPanel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private enum AmenMomentGlass {
    static let amenGold = Color(red: 0.85, green: 0.64, blue: 0.25)
    static let amenPurple = Color(red: 0.36, green: 0.25, blue: 0.55)
    static let amenBlue = Color(red: 0.18, green: 0.44, blue: 0.62)
    static let amenBlack = Color(red: 0.07, green: 0.07, blue: 0.07)

    static var surface: some ShapeStyle {
        .regularMaterial
    }

    static var activePill: some ShapeStyle {
        LinearGradient(colors: [amenGold.opacity(0.28), amenBlue.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var disabledPill: some ShapeStyle {
        amenBlack.opacity(0.08)
    }

    static var resultPanel: some ShapeStyle {
        amenGold.opacity(0.12)
    }
}
