import SwiftUI
// MARK: - Collapsible Community Section

// MARK: - Daily Verse Banner (replaces Top Ideas / Spotlight cards)

// MARK: - Pencil Scribble Compose Icon

/// Ballpoint pen silhouette matching the reference icon.
/// Solid filled shape — angled ~40° (tip points lower-left, cap upper-right).
/// Includes: rounded cap, pen barrel, tapered tip, and clip detail on the right side.
/// No underline / scribble. Drawn entirely with SwiftUI Canvas — crisp at any size.
struct BallpointPenIcon: View {
    var size: CGFloat = 24
    var color: Color = .primary

    var body: some View {
        Canvas { ctx, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height

            // ─── MAIN PEN BODY (solid filled silhouette) ──────────────────
            // The pen is angled ~40° from vertical, tip at lower-left,
            // rounded cap at upper-right — matching the reference closely.
            //
            // Layout (normalised, y=0 top):
            //   Cap top-right  ≈ (0.78, 0.08)
            //   Cap top-left   ≈ (0.54, 0.08)
            //   Barrel widens slightly then narrows to tip
            //   Tip point      ≈ (0.18, 0.90)

            let bodyPath = Path { p in
                // === Cap (rounded rectangle top) ===
                // Top-right of cap (rounded corner)
                p.move(to: CGPoint(x: w * 0.72, y: h * 0.06))
                // Top edge of cap — with rounded right corner
                p.addQuadCurve(
                    to:      CGPoint(x: w * 0.82, y: h * 0.14),
                    control: CGPoint(x: w * 0.84, y: h * 0.06)
                )
                // Right side of cap, curving down into barrel
                p.addLine(to: CGPoint(x: w * 0.76, y: h * 0.28))
                // Barrel right side — narrows toward tip
                p.addLine(to: CGPoint(x: w * 0.70, y: h * 0.36))
                // Taper zone — barrel narrows for the lower half
                p.addLine(to: CGPoint(x: w * 0.60, y: h * 0.54))
                // Tip section — right edge converges to point
                p.addLine(to: CGPoint(x: w * 0.44, y: h * 0.76))
                // Sharp tip at the bottom-left
                p.addLine(to: CGPoint(x: w * 0.18, y: h * 0.93))
                // Tip — left edge (tip is a narrow sharp point)
                p.addLine(to: CGPoint(x: w * 0.26, y: h * 0.72))
                // Left barrel side — runs back up, parallel to right side
                p.addLine(to: CGPoint(x: w * 0.40, y: h * 0.50))
                p.addLine(to: CGPoint(x: w * 0.50, y: h * 0.32))
                p.addLine(to: CGPoint(x: w * 0.56, y: h * 0.24))
                // Left cap side
                p.addLine(to: CGPoint(x: w * 0.62, y: h * 0.14))
                // Top-left of cap (rounded left corner)
                p.addQuadCurve(
                    to:      CGPoint(x: w * 0.72, y: h * 0.06),
                    control: CGPoint(x: w * 0.60, y: h * 0.06)
                )
                p.closeSubpath()
            }

            // Solid fill — entire silhouette
            ctx.fill(bodyPath, with: .color(color))

            // ─── CAP GROOVE (band between cap and barrel) ─────────────────
            // A thin light line separates the cap from the barrel, giving the
            // "click-top ballpoint" profile visible in the reference.
            let groovePath = Path { p in
                p.move(to: CGPoint(x: w * 0.56, y: h * 0.24))
                p.addLine(to: CGPoint(x: w * 0.76, y: h * 0.28))
            }
            ctx.stroke(
                groovePath,
                with: .color(Color(white: 1.0, opacity: 0.55)),
                style: StrokeStyle(lineWidth: w * 0.055, lineCap: .round)
            )

            // ─── CLIP (spring clip on right side of barrel) ───────────────
            // Thin curved strip that runs alongside the right edge of the barrel.
            // In the reference this is visible as a raised strip with a small loop at the bottom.
            let clipPath = Path { p in
                // Clip top — joins at barrel below cap groove
                p.move(to: CGPoint(x: w * 0.72, y: h * 0.30))
                // Runs parallel to the right barrel edge, slightly outside
                p.addCurve(
                    to:      CGPoint(x: w * 0.58, y: h * 0.58),
                    control1: CGPoint(x: w * 0.80, y: h * 0.36),
                    control2: CGPoint(x: w * 0.72, y: h * 0.50)
                )
                // Small loop/curl at the bottom of the clip
                p.addQuadCurve(
                    to:      CGPoint(x: w * 0.64, y: h * 0.54),
                    control: CGPoint(x: w * 0.54, y: h * 0.62)
                )
            }
            ctx.stroke(
                clipPath,
                with: .color(Color(white: 1.0, opacity: 0.50)),
                style: StrokeStyle(lineWidth: w * 0.07, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Banner Color Palette

struct BannerColorOption: Identifiable {
    let id: String       // stored in Firestore
    let label: String
    let top: Color
    let bottom: Color
    let shadow: Color
    var isLight: Bool = false  // true for light backgrounds — uses dark checkmark/border

    static let all: [BannerColorOption] = [
        BannerColorOption(
            id: "red",
            label: "Red",
            top:    Color(red: 0.97, green: 0.25, blue: 0.20),
            bottom: Color(red: 0.92, green: 0.18, blue: 0.14),
            shadow: Color(red: 0.92, green: 0.18, blue: 0.14)
        ),
        BannerColorOption(
            id: "midnight",
            label: "Midnight",
            top:    Color(red: 0.10, green: 0.12, blue: 0.28),
            bottom: Color(red: 0.06, green: 0.07, blue: 0.18),
            shadow: Color(red: 0.06, green: 0.07, blue: 0.20)
        ),
        BannerColorOption(
            id: "forest",
            label: "Forest",
            top:    Color(red: 0.10, green: 0.38, blue: 0.22),
            bottom: Color(red: 0.06, green: 0.28, blue: 0.15),
            shadow: Color(red: 0.06, green: 0.28, blue: 0.15)
        ),
        BannerColorOption(
            id: "ocean",
            label: "Ocean",
            top:    Color(red: 0.05, green: 0.35, blue: 0.62),
            bottom: Color(red: 0.03, green: 0.25, blue: 0.48),
            shadow: Color(red: 0.03, green: 0.25, blue: 0.50)
        ),
        BannerColorOption(
            id: "plum",
            label: "Plum",
            top:    Color(red: 0.38, green: 0.12, blue: 0.42),
            bottom: Color(red: 0.28, green: 0.07, blue: 0.32),
            shadow: Color(red: 0.28, green: 0.07, blue: 0.34)
        ),
        // New colors from brand palette
        BannerColorOption(
            id: "deepplum",
            label: "Deep Plum",
            top:    Color(red: 0.220, green: 0.098, blue: 0.196),  // #381932
            bottom: Color(red: 0.165, green: 0.063, blue: 0.149),
            shadow: Color(red: 0.220, green: 0.098, blue: 0.196)
        ),
        BannerColorOption(
            id: "milk",
            label: "Milk",
            top:    Color(red: 1.000, green: 0.953, blue: 0.902),  // #FFF3E6
            bottom: Color(red: 0.980, green: 0.933, blue: 0.882),
            shadow: Color(red: 0.800, green: 0.750, blue: 0.700),
            isLight: true
        ),
        BannerColorOption(
            id: "cyprus",
            label: "Cyprus",
            top:    Color(red: 0.000, green: 0.275, blue: 0.263),  // #004643
            bottom: Color(red: 0.000, green: 0.200, blue: 0.192),
            shadow: Color(red: 0.000, green: 0.275, blue: 0.263)
        ),
        BannerColorOption(
            id: "sanddune",
            label: "Sand Dune",
            top:    Color(red: 0.941, green: 0.929, blue: 0.898),  // #F0EDE5
            bottom: Color(red: 0.910, green: 0.898, blue: 0.863),
            shadow: Color(red: 0.700, green: 0.680, blue: 0.640),
            isLight: true
        ),
        BannerColorOption(
            id: "tomato",
            label: "Tomato",
            top:    Color(red: 0.961, green: 0.196, blue: 0.000),  // #F53200
            bottom: Color(red: 0.902, green: 0.157, blue: 0.000),
            shadow: Color(red: 0.961, green: 0.196, blue: 0.000)
        ),
        BannerColorOption(
            id: "amber",
            label: "Amber",
            top:    Color(red: 0.961, green: 0.529, blue: 0.039),  // #F5870A
            bottom: Color(red: 0.910, green: 0.478, blue: 0.020),
            shadow: Color(red: 0.961, green: 0.529, blue: 0.039)
        ),
        BannerColorOption(
            id: "obsidian",
            label: "Obsidian",
            top:    Color(red: 0.039, green: 0.039, blue: 0.039),  // #0A0A0A
            bottom: Color(red: 0.020, green: 0.020, blue: 0.020),
            shadow: Color(red: 0.000, green: 0.000, blue: 0.000)
        ),
    ]

    static func find(_ id: String?) -> BannerColorOption {
        all.first { $0.id == id } ?? all[0]
    }
}

// MARK: - Banner Color Picker Sheet

struct BannerColorPickerSheet: View {
    @Binding var selectedColorId: String
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            // Handle
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            Text("Banner Color")
                .font(AMENFont.bold(17))
                .foregroundStyle(.primary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(BannerColorOption.all) { option in
                        Button {
                            selectedColorId = option.id
                            onSelect(option.id)
                            HapticManager.impact(style: .light)
                            dismiss()
                        } label: {
                            VStack(spacing: 8) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [option.top, option.bottom],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 52, height: 52)
                                        .shadow(color: option.shadow.opacity(0.35), radius: 6, y: 3)

                                    if selectedColorId == option.id {
                                        let accentColor: Color = option.isLight ? .black.opacity(0.7) : .white
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(accentColor, lineWidth: 2.5)
                                            .frame(width: 52, height: 52)
                                        Image(systemName: "checkmark")
                                            .font(.systemScaled(14, weight: .bold))
                                            .foregroundStyle(accentColor)
                                    }
                                }
                                Text(option.label)
                                    .font(AMENFont.regular(11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.instantFeedback)
                    }
                }
                .padding(.horizontal, 20)
            }

            Spacer()
        }
        .presentationDetents([.height(220)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(24)
    }
}

// MARK: - Daily Verse Banner

struct DailyVerseBanner: View {
    @ObservedObject private var verseService = DailyVerseGenkitService.shared
    // OFFLINE FIX: retry AI verse generation when the app returns to foreground
    // and the displayed verse is still just the curated offline fallback.
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var networkMonitor = AMENNetworkMonitor.shared

    var body: some View {
        DailyVerseBannerView(
            verse: verseService.todayVerse,
            isLoading: verseService.isGenerating,
            onLoad: { Task { await verseService.generatePersonalizedDailyVerse() } }
        )
        .task {
            await loadCachedVerseIfNeeded()
        }
        // OFFLINE FIX: When the app moves to active and the verse is a curated fallback
        // (isPersonalized == false), attempt a fresh Cloud Function call now that the
        // network may be available.  Guard on isGenerating to avoid duplicate calls.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active,
               !verseService.isPersonalized,
               networkMonitor.isConnected,
               !verseService.isGenerating {
                Task { _ = await verseService.generatePersonalizedDailyVerse(forceRefresh: true) }
            }
        }
    }

    private func loadCachedVerseIfNeeded() async {
        guard verseService.todayVerse == nil else { return }
        if let data = UserDefaults.standard.data(forKey: UserDefaultsKeys.cachedDailyVerse),
           let date = UserDefaults.standard.object(forKey: UserDefaultsKeys.cachedVerseDate) as? Date,
           Calendar.current.isDate(date, inSameDayAs: Date()),
           let verse = try? JSONDecoder().decode(PersonalizedDailyVerse.self, from: data) {
            await MainActor.run {
                verseService.todayVerse = verse
            }
        } else {
            _ = await verseService.generatePersonalizedDailyVerse()
        }
    }
}

// MARK: - Daily Verse Detail Sheet

struct DailyVerseDetailSheet: View {
    let verse: PersonalizedDailyVerse?
    let color: BannerColorOption
    @Environment(\.dismiss) private var dismiss
    @State private var showBerean = false

    private var reference: String {
        verse?.reference ?? "Jeremiah 29:11"
    }

    private var text: String {
        verse?.text ?? "\"For I know the plans I have for you,\" declares the LORD, \"plans to prosper you and not to harm you, plans to give you hope and a future.\""
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Verse card
                    VStack(spacing: 16) {
                        Text(text)
                            .font(AMENFont.regular(20))
                            .foregroundStyle(.white)
                            .lineSpacing(6)
                            .multilineTextAlignment(.leading)

                        Text("— \(reference)")
                            .font(AMENFont.semiBold(15))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [color.top, color.bottom],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .padding(.horizontal)

                    // Action buttons
                    VStack(spacing: 12) {
                        Button {
                            showBerean = true
                        } label: {
                            Label("Reflect with Berean", systemImage: "sparkles")
                                .font(AMENFont.semiBold(16))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        ShareLink(item: "\(text)\n\n— \(reference)\n\nShared from AMEN") {
                            Label("Share Verse", systemImage: "square.and.arrow.up")
                                .font(AMENFont.semiBold(16))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .padding(.horizontal)

                    // Reflection prompt
                    if let reflection = verse?.reflection, !reflection.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Today's Reflection")
                                .font(AMENFont.bold(15))
                                .foregroundStyle(.primary)
                            Text(reflection)
                                .font(AMENFont.regular(15))
                                .foregroundStyle(.secondary)
                                .lineSpacing(4)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.top, 20)
            }
            .navigationTitle("Daily Verse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(AMENFont.semiBold(16))
                }
            }
            .sheet(isPresented: $showBerean) {
                BereanChatView(initialQuery: "Help me reflect on \(reference): \"\(text)\"")
            }
        }
    }
}

