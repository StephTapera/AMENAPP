// VictimShieldControlsView.swift
// AMENAPP
// Safety OS: full shield controls — feed mode, panic mode prep,
// and trusted contact escalation. Accessible from Settings > Safety.

import SwiftUI

struct VictimShieldControlsView: View {
    @ObservedObject private var feedControls = AmenFeedControlService.shared // PERF: singleton → @ObservedObject
    @State private var showPanicFlow = false
    @State private var showTrustedContacts = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            // MARK: Status header
            Section {
                shieldStatusHeader
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            // MARK: Feed protection mode
            Section {
                ForEach(FeedMode.allCases, id: \.self) { mode in
                    Button {
                        Task { try? await feedControls.applyMode(mode) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.displayName)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text(mode.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if feedControls.state.activeMode == mode {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Feed Protection Mode")
            } footer: {
                Text("Controls what content reaches your feed and how aggressive the algorithm is.")
            }

            // MARK: Panic Mode
            Section {
                Button {
                    showPanicFlow = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Activate Emergency Shield")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.red)
                            Text("Alert trusted contacts and access crisis resources")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "shield.lefthalf.filled.slash")
                            .foregroundStyle(.red)
                    }
                }
                .buttonStyle(.plain)
            } header: {
                Text("Emergency")
            } footer: {
                Text("Use this if you're experiencing exploitation, sextortion, or image-based abuse.")
            }

            // MARK: Trusted Contacts
            Section {
                Button {
                    showTrustedContacts = true
                } label: {
                    HStack {
                        Text("Manage Trusted Contacts")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            } header: {
                Text("Trusted Contacts")
            } footer: {
                Text("These people are alerted if you activate Emergency Shield.")
            }

            // MARK: Crisis Resources
            Section("Crisis Resources") {
                crisisLink(title: "988 Suicide & Crisis Lifeline", subtitle: "Call or text 988 — 24/7", url: "tel:988")
                crisisLink(title: "NCMEC CyberTipline", subtitle: "Report exploitation or missing child", url: "https://www.missingkids.org/gethelpnow/cybertipline")
                crisisLink(title: "StopItNow Helpline", subtitle: "1-888-PREVENT — abuse prevention", url: "tel:18887738368")
            }

            if let error = errorMessage {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Shield Controls")
        .navigationBarTitleDisplayMode(.large)
        .task { await feedControls.load() }
        .sheet(isPresented: $showPanicFlow) {
            SextortionPanicFlowView()
        }
        .sheet(isPresented: $showTrustedContacts) {
            NavigationStack {
                TrustedContactSetupView()
            }
        }
    }

    // MARK: - Components

    private var shieldStatusHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(shieldColor.opacity(0.12))
                    .frame(width: 56, height: 56)
                Image(systemName: shieldIcon)
                    .font(.system(size: 26))
                    .foregroundStyle(shieldColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(feedControls.state.activeMode.displayName)
                    .font(.title3.bold())
                Text(feedControls.state.activeMode.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }

    private var shieldIcon: String {
        switch feedControls.state.activeMode {
        case .quiet:          return "checkmark.shield.fill"
        case .friendsFirst:   return "shield.fill"
        case .localCommunity: return "shield.fill"
        case .balanced:       return "shield"
        case .ideasLearning:  return "shield"
        }
    }

    private var shieldColor: Color {
        switch feedControls.state.activeMode {
        case .quiet:          return .green
        case .friendsFirst:   return .blue
        case .localCommunity: return .blue
        case .balanced:       return .orange
        case .ideasLearning:  return .gray
        }
    }

    private func crisisLink(title: String, subtitle: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

