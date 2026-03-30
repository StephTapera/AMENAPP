//
//  ChurchNotesEditorFeaturesExtension.swift
//  AMENAPP
//
//  Integration guide + standalone demo for the Church Notes smart features.
//
//  ══════════════════════════════════════════════════════════════════════════════
//  HOW TO WIRE FEATURES INTO EnhancedChurchNoteEditor
//  ══════════════════════════════════════════════════════════════════════════════
//
//  STEP 1 — Paste these stored properties into the EnhancedChurchNoteEditor
//  struct body (alongside the existing @State vars around line 88):
//
//    // MARK: — Smart Feature ViewModels
//    @StateObject private var aiInsightsVM    = AIInsightsViewModel()
//    @StateObject private var scriptureDNAVM  = ScriptureDNAViewModel()
//    @StateObject private var churchRadarVM   = ChurchRadarViewModel()
//    @StateObject private var voiceWisdomVM   = VoiceToWisdomViewModel()
//    @StateObject private var communityDuetVM = CommunityDuetViewModel()
//    @StateObject private var quoteForgeVM    = QuoteForgeViewModel()
//    @StateObject private var growthArcVM     = GrowthArcViewModel()
//
//    // MARK: — Smart Feature Sheet Toggles
//    @State private var showCommunityDuet = false
//    @State private var showQuoteForge    = false
//    @State private var showGrowthArc     = false
//
//  ──────────────────────────────────────────────────────────────────────────────
//  STEP 2 — In body's ScrollView VStack, after `tagsSection` and before
//  `.padding(.bottom, 40)`, add:
//
//    // Smart feature panels
//    VStack(spacing: 16) {
//        VoiceToWisdomView(viewModel: voiceWisdomVM, noteBody: $content)
//        AIInsightsPanelView(viewModel: aiInsightsVM, bodyText: $content)
//        ScriptureDNAView(viewModel: scriptureDNAVM, reference: $scripture)
//        ChurchRadarView(viewModel: churchRadarVM) { church in
//            churchName   = church.name
//            pastor       = church.pastorName
//            if sermonTitle.isEmpty { sermonTitle = church.sermonTitle }
//        }
//    }
//    .padding(.horizontal, 16)
//
//  ──────────────────────────────────────────────────────────────────────────────
//  STEP 3 — Add sheet presentations to the .sheet chain in body
//  (after .sheet(isPresented: $showPhotoScan)):
//
//    .sheet(isPresented: $showCommunityDuet) {
//        CommunityDuetSheet(viewModel: communityDuetVM, noteBody: $content)
//    }
//    .sheet(isPresented: $showQuoteForge) {
//        QuoteForgeSheet(viewModel: quoteForgeVM, noteBody: $content)
//    }
//    .sheet(isPresented: $showGrowthArc) {
//        GrowthArcSheet(viewModel: growthArcVM)
//    }
//
//  ──────────────────────────────────────────────────────────────────────────────
//  STEP 4 — In headerView, add toolbar buttons alongside the existing
//  DoctrineCheckButton / StudyGuideButton (inside the `if !content.isEmpty` guard):
//
//    Button { showQuoteForge    = true } label: { Image(systemName: "quote.bubble.fill") }
//    Button { showGrowthArc     = true } label: { Image(systemName: "chart.line.uptrend.xyaxis") }
//    Button { showCommunityDuet = true } label: { Image(systemName: "person.2.fill") }
//
//  ══════════════════════════════════════════════════════════════════════════════

import SwiftUI

// MARK: - ChurchNotesFeatureWiring
//
// Standalone demo / integration test. Verifies all feature views compile and
// receive the correct bindings. Not used in production navigation flow.

struct ChurchNotesFeatureWiring: View {

    @StateObject private var aiInsightsVM    = AIInsightsViewModel()
    @StateObject private var scriptureDNAVM  = ScriptureDNAViewModel()
    @StateObject private var churchRadarVM   = ChurchRadarViewModel()
    @StateObject private var voiceWisdomVM   = VoiceToWisdomViewModel()
    @StateObject private var communityDuetVM = CommunityDuetViewModel()
    @StateObject private var quoteForgeVM    = QuoteForgeViewModel()
    @StateObject private var growthArcVM     = GrowthArcViewModel()

    @State private var content     = ""
    @State private var scripture   = ""
    @State private var churchName  = ""
    @State private var pastor      = ""
    @State private var sermonTitle = ""

    @State private var showCommunityDuet = false
    @State private var showQuoteForge    = false
    @State private var showGrowthArc     = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "050508").ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {

                        // Text entry (mirrors what EnhancedChurchNoteEditor provides)
                        TextEditor(text: $content)
                            .frame(minHeight: 120)
                            .foregroundColor(.white)
                            .scrollContentBackground(.hidden)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 16)

                        // ── Feature panels ───────────────────────────────────

                        VoiceToWisdomView(
                            viewModel: voiceWisdomVM,
                            noteBody: $content
                        )
                        .padding(.horizontal, 16)

                        AIInsightsPanelView(
                            viewModel: aiInsightsVM,
                            bodyText: $content
                        )
                        .padding(.horizontal, 16)

                        ScriptureDNAView(
                            viewModel: scriptureDNAVM,
                            reference: $scripture
                        )
                        .padding(.horizontal, 16)

                        ChurchRadarView(viewModel: churchRadarVM) { church in
                            churchName   = church.name
                            pastor       = church.pastorName
                            if sermonTitle.isEmpty {
                                sermonTitle = church.sermonTitle
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Feature Demo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        Button { showQuoteForge    = true } label: {
                            Image(systemName: "quote.bubble.fill")
                                .foregroundColor(.cnGold)
                        }
                        Button { showGrowthArc     = true } label: {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .foregroundColor(.cnGold)
                        }
                        Button { showCommunityDuet = true } label: {
                            Image(systemName: "person.2.fill")
                                .foregroundColor(.cnGold)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showCommunityDuet) {
            CommunityDuetSheet(viewModel: communityDuetVM, noteBody: $content)
        }
        .sheet(isPresented: $showQuoteForge) {
            QuoteForgeSheet(viewModel: quoteForgeVM, noteBody: $content)
        }
        .sheet(isPresented: $showGrowthArc) {
            GrowthArcSheet(viewModel: growthArcVM)
        }
    }
}
