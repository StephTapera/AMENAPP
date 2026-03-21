import SwiftUI

// MARK: - Berean Analysis Models (sidebar data)

struct BereanSidebarAnalysis {
    var scriptureMatches: [SidebarScriptureMatch]
    var theologicalFlags: [SidebarTheologicalFlag]
    var theme: String?
    var suggestedDeeper: [SidebarDeeperVerse]
    var toneObservation: BereanToneObservation
    var biblicalParallel: SidebarBiblicalParallel?
}

struct SidebarScriptureMatch: Identifiable {
    let id = UUID()
    let reference: String
    let text: String
    let relevance: String
}

struct SidebarTheologicalFlag: Identifiable {
    let id = UUID()
    let claim: String
    let context: String
    let severity: FlagSeverity

    enum FlagSeverity: String { case note, caution }
}

struct SidebarDeeperVerse: Identifiable {
    let id = UUID()
    let reference: String
    let why: String
}

struct SidebarBiblicalParallel {
    let figure: String
    let story: String
    let connection: String
}

enum BereanToneObservation: String {
    case graceForward   = "grace-forward"
    case balanced       = "balanced"
    case needsSoftening = "needs-softening"
    case neutral        = "neutral"

    var label: String {
        switch self {
        case .graceForward:   return "Grace-forward"
        case .balanced:       return "Balanced"
        case .needsSoftening: return "Needs softening"
        case .neutral:        return "Neutral"
        }
    }

    var color: Color {
        switch self {
        case .graceForward:   return Color(red: 0.20, green: 0.72, blue: 0.44)
        case .balanced:       return Color(red: 0.20, green: 0.42, blue: 0.98)
        case .needsSoftening: return Color(red: 0.90, green: 0.50, blue: 0.10)
        case .neutral:        return Color(.secondaryLabel)
        }
    }
}

// MARK: - Sidebar View

struct LightBereanSidebar: View {
    let isLoading: Bool
    let analysis: BereanSidebarAnalysis?
    var onClose: (() -> Void)? = nil

    @State private var expandedScripture: UUID? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(red: 0.20, green: 0.42, blue: 0.98))
                Text("Berean")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(white: 0.15))
                Spacer()
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(.tertiaryLabel))
                            .padding(6)
                            .background(Circle().fill(Color(.quaternarySystemFill)))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(red: 0.97, green: 0.97, blue: 0.99))

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    if isLoading {
                        shimmerContent
                    } else if let analysis {
                        liveContent(analysis)
                    } else {
                        idlePrompt
                    }
                }
                .padding(16)
            }
        }
        .background(Color(red: 0.97, green: 0.97, blue: 0.99))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.07), radius: 20, x: -4, y: 0)
    }

    // MARK: Idle

    private var idlePrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "pencil.and.scribble")
                .font(.system(size: 28))
                .foregroundColor(Color(.tertiaryLabel))
                .padding(.top, 24)
            Text("Start writing and Berean will search Scripture alongside you.")
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(Color(.secondaryLabel))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Shimmer Placeholders

    private var shimmerContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            ShimmerBar(width: 90, height: 10)
            ShimmerBar(width: .infinity, height: 56)
            ShimmerBar(width: .infinity, height: 56)
            ShimmerBar(width: 60, height: 10).padding(.top, 6)
            ShimmerBar(width: 110, height: 24, cornerRadius: 12)
        }
    }

    // MARK: Live Content

    @ViewBuilder
    private func liveContent(_ a: BereanSidebarAnalysis) -> some View {
        // Tone + Theme row
        HStack(spacing: 8) {
            tonePill(a.toneObservation)
            if let theme = a.theme {
                Text(theme)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.secondarySystemFill))
                    .foregroundColor(Color(.secondaryLabel))
                    .clipShape(Capsule())
            }
        }

        // Scripture matches
        if !a.scriptureMatches.isEmpty {
            sectionHeader("Scripture")
            ForEach(a.scriptureMatches) { match in
                ScriptureMatchCard(
                    match: match,
                    isExpanded: expandedScripture == match.id
                ) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        expandedScripture = expandedScripture == match.id ? nil : match.id
                    }
                }
            }
        }

        // Theological flags
        if !a.theologicalFlags.isEmpty {
            sectionHeader("Flags")
            ForEach(a.theologicalFlags) { flag in
                FlagCard(flag: flag)
            }
        }

        // Suggested deeper
        if !a.suggestedDeeper.isEmpty {
            sectionHeader("Go Deeper")
            ForEach(a.suggestedDeeper) { verse in
                DeeperVerseRow(verse: verse)
            }
        }

        // Biblical parallel
        if let parallel = a.biblicalParallel {
            sectionHeader("Biblical Parallel")
            ParallelCard(parallel: parallel)
        }
    }

    private func tonePill(_ tone: BereanToneObservation) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tone.color)
                .frame(width: 6, height: 6)
            Text(tone.label)
                .font(.caption2.weight(.semibold))
                .foregroundColor(tone.color)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tone.color.opacity(0.10))
        .clipShape(Capsule())
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundColor(Color(.tertiaryLabel))
            .tracking(0.8)
    }
}

// MARK: - Scripture Match Card

private struct ScriptureMatchCard: View {
    let match: SidebarScriptureMatch
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                HStack {
                    Text(match.reference)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(red: 0.20, green: 0.42, blue: 0.98))
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(.tertiaryLabel))
                }
                .padding(12)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(match.text)
                        .font(.system(size: 12, design: .serif))
                        .foregroundColor(Color(white: 0.25))
                        .italic()
                        .lineSpacing(4)

                    Text(match.relevance)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(Color(.secondaryLabel))
                        .lineSpacing(3)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(red: 0.20, green: 0.42, blue: 0.98).opacity(0.12), lineWidth: 0.8)
        )
    }
}

// MARK: - Flag Card

private struct FlagCard: View {
    let flag: SidebarTheologicalFlag

    private var flagColor: Color {
        flag.severity == .caution
            ? Color(red: 0.90, green: 0.50, blue: 0.10)
            : Color(.secondaryLabel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: flag.severity == .caution ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(flagColor)
                Text(flag.claim)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Color(white: 0.20))
            }
            Text(flag.context)
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(Color(.secondaryLabel))
                .lineSpacing(3)
        }
        .padding(12)
        .background(flagColor.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Deeper Verse Row

private struct DeeperVerseRow: View {
    let verse: SidebarDeeperVerse

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color(red: 0.20, green: 0.42, blue: 0.98).opacity(0.15))
                .frame(width: 6, height: 6)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(verse.reference)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(red: 0.20, green: 0.42, blue: 0.98))
                Text(verse.why)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(Color(.secondaryLabel))
                    .lineSpacing(2)
            }
        }
    }
}

// MARK: - Biblical Parallel Card

private struct ParallelCard: View {
    let parallel: SidebarBiblicalParallel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(parallel.figure)
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .foregroundColor(Color(white: 0.15))
            Text(parallel.story)
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(Color(.secondaryLabel))
                .lineSpacing(3)
            Text(parallel.connection)
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(Color(red: 0.55, green: 0.28, blue: 0.95))
                .lineSpacing(3)
        }
        .padding(12)
        .background(Color(red: 0.55, green: 0.28, blue: 0.95).opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Shimmer Bar

private struct ShimmerBar: View {
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat = 6

    @State private var phase: CGFloat = 0

    var body: some View {
        let w = width == .infinity ? 10000.0 : width
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(shimmerGradient)
            .frame(width: width == .infinity ? nil : w, height: height)
            .frame(maxWidth: width == .infinity ? .infinity : nil)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }

    private var shimmerGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(.systemFill), location: 0),
                .init(color: Color(.tertiarySystemFill).opacity(0.4), location: phase * 0.5),
                .init(color: Color(.systemFill), location: min(phase + 0.3, 1.0))
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
