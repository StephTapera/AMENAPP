// BereanPrayerSurfaceView.swift (formerly BereanPrayerJournalView.swift)
// AMEN — Berean Reading Surface: Prayer Journal (W6)
// Flag: bereanPrayerJournal (default false)
//
// SAFETY INVARIANTS:
// - isPrivate = true always by default. Content stays on device.
// - Any share requires: (1) confirmation alert, (2) Guard routing (TODO marked).
// - No public share path without both gates.
// - Child-safety / COPPA: inherits from GUARDIAN/Aegis.

import SwiftUI

struct BereanPrayerSurfaceView: View {

    @AppStorage("berean.prayer.today") private var todayEntry: String = ""
    @State private var answeredPrayers: [String] = ["God's provision this month", "Healing for a friend"]
    @State private var prayerList: [String] = ["Wisdom for a decision", "Peace for my family"]
    @State private var scriptureToPray: String = "Psalm 23:1 — \"The Lord is my shepherd, I lack nothing.\""
    @State private var isPrivate: Bool = true
    @State private var isLoading = false
    @State private var showShareConfirmation = false
    @State private var showAddPrayer = false
    @State private var newPrayerText = ""

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.bereanIvory.ignoresSafeArea()

            if isLoading {
                VStack { Spacer(); WordGlowLoader(); Spacer() }
            } else {
                journalContent
            }

            FloatingPrimaryCTA(label: .startPrayer) { startGuidedPrayer() }
                .padding(.trailing, 24)
                .padding(.bottom, 32)
        }
        .alert("Share Prayer Entry?", isPresented: $showShareConfirmation) {
            Button("Share") {
                // TODO: UGC SAFETY — route prayer content through GUARDIAN/Aegis Guard mode.
                //       Do not share any prayer content without Guard clearance.
                //       Sharing prayer content with minors present requires extra COPPA check.
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Prayer entries are private by default. Share only what you're comfortable making public.")
        }
        .sheet(isPresented: $showAddPrayer) {
            addPrayerSheet
        }
    }

    // MARK: - Journal Content

    private var journalContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Prayer Journal")
                            .font(BereanReaderType.displayTitle)
                            .foregroundStyle(Color.bereanInk)
                        if isPrivate {
                            Label("Private", systemImage: "lock.fill")
                                .font(BereanType.caption())
                                .foregroundStyle(Color.bereanInk.opacity(0.45))
                        }
                    }
                    Spacer()
                    Button {
                        showShareConfirmation = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.bereanInk.opacity(0.5))
                    }
                    .frame(width: BereanMetrics.minTapTarget, height: BereanMetrics.minTapTarget)
                    .accessibilityLabel("Share prayer entry")
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)

                // Today's Prayer
                BereanReaderCard(header: "Today's Prayer") {
                    TextEditor(text: $todayEntry)
                        .font(BereanReaderType.body)
                        .foregroundStyle(Color.bereanInk)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .frame(minHeight: 110)
                        .overlay(
                            Group {
                                if todayEntry.isEmpty {
                                    Text("Write your prayer here…")
                                        .font(BereanReaderType.body)
                                        .foregroundStyle(Color.bereanInk.opacity(0.3))
                                        .allowsHitTesting(false)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                        .padding(.top, 8)
                                }
                            }
                        )
                        .accessibilityLabel("Today's prayer text")
                }
                .padding(.horizontal, 16)

                // Answered Prayers
                BereanReaderCard(header: "Answered Prayers") {
                    VStack(alignment: .leading, spacing: 8) {
                        if answeredPrayers.isEmpty {
                            Text("Mark prayers as answered to see them here.")
                                .font(BereanType.body())
                                .foregroundStyle(Color.bereanInk.opacity(0.45))
                        } else {
                            ForEach(answeredPrayers, id: \.self) { prayer in
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.bereanInk.opacity(0.5))
                                        .font(.system(size: 14))
                                    Text(prayer)
                                        .font(BereanReaderType.body)
                                        .foregroundStyle(Color.bereanInk)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .accessibilityLabel("Answered prayers list")

                // Praying For
                BereanReaderCard(header: "Praying For") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(prayerList, id: \.self) { item in
                            HStack(spacing: 8) {
                                Image(systemName: "hands.and.sparkles")
                                    .foregroundStyle(Color.bereanInk.opacity(0.4))
                                    .font(.system(size: 13))
                                Text(item)
                                    .font(BereanReaderType.body)
                                    .foregroundStyle(Color.bereanInk)
                            }
                        }
                        Button {
                            showAddPrayer = true
                        } label: {
                            Label("Add intention", systemImage: "plus")
                                .font(BereanType.caption())
                                .foregroundStyle(Color.bereanInk.opacity(0.5))
                        }
                        .accessibilityLabel("Add a new prayer intention")
                    }
                }
                .padding(.horizontal, 16)

                // Scripture to Pray
                BereanReaderCard(header: "Scripture to Pray") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(scriptureToPray)
                            .font(BereanReaderType.body)
                            .foregroundStyle(Color.bereanInk)
                            .italic()
                        BereanActionPill(
                            label: "Pray This",
                            icon: "hands.and.sparkles.fill",
                            onTap: {
                                handleAction(.scriptureToMeditate)
                            }
                        )
                        .accessibilityHint("Open guided prayer from this scripture")
                    }
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 100)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Add Prayer Sheet

    private var addPrayerSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Prayer Intention")
                .font(BereanType.sectionTitle())
                .foregroundStyle(Color.bereanInk)
                .padding(.top, 24)
                .padding(.horizontal, 20)

            TextField("Who or what are you praying for?", text: $newPrayerText, axis: .vertical)
                .font(BereanReaderType.body)
                .foregroundStyle(Color.bereanInk)
                .padding(.horizontal, 20)
                .lineLimit(3)
                .accessibilityLabel("Prayer intention text")

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { showAddPrayer = false }
                    .foregroundStyle(Color.bereanInk.opacity(0.5))
                Button("Add") {
                    if !newPrayerText.trimmingCharacters(in: .whitespaces).isEmpty {
                        prayerList.append(newPrayerText)
                        newPrayerText = ""
                    }
                    showAddPrayer = false
                }
                .foregroundStyle(Color.bereanInk)
                .bold()
            }
            .padding(.horizontal, 20)
            Spacer()
        }
        .background(Color.bereanIvory.ignoresSafeArea())
        .presentationDetents([.medium])
    }

    // MARK: - Actions

    private func startGuidedPrayer() {
        // TODO: Route through BereanContextActionEngine or BereanStudyService
        //       with action: .guidedPrayer. Reflect mode generates prayer prompts.
        handleAction(.guidedPrayer)
    }

    private func handleAction(_ action: BereanAIAction) {
        // TODO: Route through BereanContextActionEngine.perform(action: action, payload: [...])
        //       UGC (prayer text) must pass through Guard before any AI submission.
        print("Prayer AI action: \(action.displayName) → \(action.routesTo.rawValue)")
    }
}

#Preview {
    BereanPrayerSurfaceView()
}
