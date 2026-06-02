// AMENAPP/AMENAPP/ConnectSpaces/Spaces/AmenMinistryRoomCareTab.swift
// AMEN Connect + Spaces — Ministry Room Care Tab
// Built 2026-06-02
//
// Aegis contract respected: C-34 — care content never behind glass.
// Matte background throughout the content area. Glass only on section header chrome.

import SwiftUI

// MARK: - Main View

struct AmenMinistryRoomCareTab: View {
    let spaceId: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Glass chrome section header — header only, not content
            careHeader

            // Matte content area — wraps existing AmenCareQueueView
            AmenCareQueueView(spaceId: spaceId)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.amenBlack)
    }

    // MARK: - Glass Section Header (chrome only)

    private var careHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "heart.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.amenGold)
                .accessibilityHidden(true)

            Text("Care & Shepherding")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .bottom) {
                    Divider().opacity(0.25)
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Care and Shepherding section")
    }
}
