import SwiftUI

// MARK: - Progressive Disclosure Panel (Primitive 42 / 29)
// Attaches to any Selah media card. Press-and-hold reveals depth layers.
// Level 1: visual only  →  Level 2: caption + context  →  Level 3: action row
// →  Level 4: Berean insight  →  Level 5: memory/continuation path
// Additive only — wrap any card in SelahDisclosureContainer.

enum SelahDisclosureLevel: Int, CaseIterable, Comparable {
    case visual    = 1
    case caption   = 2
    case actions   = 3
    case berean    = 4
    case memory    = 5

    static func < (lhs: SelahDisclosureLevel, rhs: SelahDisclosureLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .visual:   return "Visual"
        case .caption:  return "Caption"
        case .actions:  return "Actions"
        case .berean:   return "Insight"
        case .memory:   return "Memory"
        }
    }
}

// MARK: - Disclosure Container

struct SelahDisclosureContainer<Content: View>: View {
    let item: SelahMediaItem
    let memories: [SelahMediaMemory]
    @ViewBuilder let content: () -> Content

    @State private var level: SelahDisclosureLevel = .visual
    @State private var isHolding = false
    @State private var bereanInsight: String?
    @State private var bereanLoading = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            content()
                .scaleEffect(isHolding ? 0.97 : 1.0)
                .animation(reduceMotion ? .none : .spring(response: 0.2, dampingFraction: 0.7), value: isHolding)

            if level > .visual {
                disclosurePanel
                    .transition(
                        reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        )
                    )
            }

            // Level indicator dots (top-right corner)
            levelIndicator
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .contentShape(Rectangle())
        .onLongPressGesture(
            minimumDuration: 0.35,
            pressing: { pressing in
                withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.15)) {
                    isHolding = pressing
                }
                if pressing { HapticManager.impact(style: .medium) }
            },
            perform: {
                withAnimation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.8)) {
                    let next = SelahDisclosureLevel(rawValue: min(level.rawValue + 1, 5)) ?? .memory
                    level = next
                    if next == .berean && bereanInsight == nil { fetchBereanInsight() }
                }
                HapticManager.impact(style: .light)
            }
        )
        .onTapGesture {
            // Tap collapses back to visual
            if level > .caption {
                withAnimation(reduceMotion ? .none : .easeOut(duration: 0.2)) {
                    level = .visual
                }
            }
        }
    }

    // MARK: - Disclosure Panel

    private var disclosurePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if level >= .caption {
                captionLayer
            }
            if level >= .actions {
                Divider().padding(.horizontal, 14)
                actionLayer
            }
            if level >= .berean {
                Divider().padding(.horizontal, 14)
                bereanLayer
            }
            if level >= .memory {
                Divider().padding(.horizontal, 14)
                memoryLayer
            }
        }
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 0, topTrailingRadius: 0,
                bottomTrailingRadius: 16, bottomLeadingRadius: 16
            )
            .fill(.regularMaterial)
        )
    }

    private var captionLayer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !item.caption.isEmpty {
                Text(item.caption)
                    .font(.subheadline)
                    .lineLimit(3)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
            }
            if let ref = item.scriptureRef, !ref.isEmpty {
                Label(ref, systemImage: "book.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 14)
            }
            // Context windows row
            if !item.meaningTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(item.meaningTags.prefix(3)) { tag in
                            SelahContextWindowOverlay(reason: "Theme: \(tag.label)", confidence: tag.confidence)
                        }
                    }
                    .padding(.horizontal, 14)
                }
                .padding(.bottom, 10)
            }
        }
    }

    private var actionLayer: some View {
        HStack(spacing: 18) {
            disclosureAction(icon: "brain", label: "Save") {
                Task { try? await SelahMediaService.shared.saveMemory(
                    SelahMediaMemory(
                        title: item.caption.isEmpty ? "Moment" : String(item.caption.prefix(50)),
                        linkedMediaIds: [item.id ?? ""],
                        meaningTags: item.meaningTags
                    )
                )}
            }
            disclosureAction(icon: "arrow.right.circle", label: "Continue") {
                let cont = SelahMediaContinuation(
                    promptText: "Continue reflecting on this moment.",
                    contextSummary: item.caption,
                    action: .reflect,
                    linkedMediaId: item.id
                )
                Task { try? await SelahMediaService.shared.saveContinuation(cont) }
            }
            disclosureAction(icon: "square.and.arrow.up", label: "Share") {}
            Spacer()
            // Lifecycle badge
            PostLifecycleBadge(
                stage: PostLifecycleEngine.inferStage(from: item, memories: memories),
                compact: true
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var bereanLayer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Berean Insight", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.purple)
                .padding(.horizontal, 14)
                .padding(.top, 10)

            if bereanLoading {
                HStack {
                    ProgressView().scaleEffect(0.7)
                    Text("Thinking…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            } else if let insight = bereanInsight {
                Text(insight)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
        }
    }

    private var memoryLayer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Memory Path", systemImage: "brain")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.teal)
                .padding(.horizontal, 14)
                .padding(.top, 10)

            let linked = memories.filter { $0.linkedMediaIds.contains(item.id ?? "") }
            if linked.isEmpty {
                Text("Not yet saved to memory. Long-press again to save.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(linked.prefix(3)) { m in
                            Text(m.title.isEmpty ? "Memory" : m.title)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.teal)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.teal.opacity(0.10)))
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }
            Spacer(minLength: 12)
        }
    }

    // MARK: - Level Indicator

    private var levelIndicator: some View {
        HStack(spacing: 3) {
            ForEach(SelahDisclosureLevel.allCases, id: \.rawValue) { l in
                Circle()
                    .fill(l <= level ? Color.white : Color.white.opacity(0.3))
                    .frame(width: 4, height: 4)
            }
        }
        .padding(6)
        .background(Capsule().fill(.ultraThinMaterial))
    }

    // MARK: - Helpers

    private func disclosureAction(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func fetchBereanInsight() {
        guard !item.caption.isEmpty || item.scriptureRef != nil else {
            bereanInsight = "Open this moment fully to explore its meaning."
            return
        }
        bereanLoading = true
        Task {
            var accumulated = ""
            let question = "In one sentence, what theme or truth might this moment carry?"
            do {
                let stream = SelahMediaService.shared.askBereanAboutMedia(item: item, question: question)
                for try await chunk in stream { accumulated += chunk }
            } catch {}
            await MainActor.run {
                bereanInsight = accumulated.isEmpty ? "Reflect on what stands out to you." : accumulated
                bereanLoading = false
            }
        }
    }
}

// MARK: - UnevenRoundedRectangle helper for iOS 16 compat

private struct UnevenRoundedRectangle: Shape {
    var topLeadingRadius: CGFloat
    var topTrailingRadius: CGFloat
    var bottomTrailingRadius: CGFloat
    var bottomLeadingRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + topLeadingRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topTrailingRadius, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - topTrailingRadius, y: rect.minY + topTrailingRadius),
                    radius: topTrailingRadius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomTrailingRadius))
        path.addArc(center: CGPoint(x: rect.maxX - bottomTrailingRadius, y: rect.maxY - bottomTrailingRadius),
                    radius: bottomTrailingRadius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + bottomLeadingRadius, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + bottomLeadingRadius, y: rect.maxY - bottomLeadingRadius),
                    radius: bottomLeadingRadius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeadingRadius))
        path.addArc(center: CGPoint(x: rect.minX + topLeadingRadius, y: rect.minY + topLeadingRadius),
                    radius: topLeadingRadius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}
