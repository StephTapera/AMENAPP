//
//  PrayerChainLiveActivityWidget.swift
//  AMENWidgetExtension
//
//  Dynamic Island + Lock Screen UI for Prayer Chain Live Activity.
//  Shows real-time prayer count progress.
//

import SwiftUI
import WidgetKit
import ActivityKit

struct PrayerChainLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PrayerChainActivityAttributes.self) { context in
            // Lock Screen / Banner view
            PrayerChainLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded view regions
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "hands.sparkles.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.purple)
                        .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(spacing: 2) {
                        Text("\(context.state.currentCount)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                        Text("of \(context.attributes.targetCount)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    Text("Prayer Chain")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        // Prayer request text
                        Text(context.attributes.prayerText)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.white)
                            .lineLimit(3)
                            .lineSpacing(2)
                        
                        // Progress bar
                        VStack(alignment: .leading, spacing: 4) {
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    // Background
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.white.opacity(0.15))
                                        .frame(height: 8)
                                    
                                    // Progress fill
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.purple, Color(red: 0.6, green: 0.3, blue: 0.9)],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: geometry.size.width * context.state.percentComplete, height: 8)
                                }
                            }
                            .frame(height: 8)
                            
                            Text("\(Int(context.state.percentComplete * 100))% complete")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        
                        // Recent prayers
                        if !context.state.recentPrayers.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.5))
                                Text(recentPrayersText(context.state.recentPrayers))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .lineLimit(1)
                            }
                        }
                        
                        // Complete button or view details
                        if context.state.isComplete {
                            Link(destination: URL(string: "amen://prayer?id=\(context.attributes.prayerRequestID)")!) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 14))
                                    Text("Prayer Complete!")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule().fill(Color.green.opacity(0.8))
                                )
                            }
                        } else {
                            Link(destination: URL(string: "amen://prayer?id=\(context.attributes.prayerRequestID)")!) {
                                Text("Pray Now")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        Capsule().fill(
                                            LinearGradient(
                                                colors: [Color.purple, Color(red: 0.4, green: 0.2, blue: 0.8)],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                    )
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                // Compact left — prayer hands icon
                Image(systemName: "hands.sparkles.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.purple)
            } compactTrailing: {
                // Compact right — prayer count
                HStack(spacing: 2) {
                    Text("\(context.state.currentCount)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text("/\(context.attributes.targetCount)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            } minimal: {
                // Minimal — just the prayer hands icon with progress indicator
                ZStack {
                    Circle()
                        .trim(from: 0, to: context.state.percentComplete)
                        .stroke(Color.purple, lineWidth: 2)
                        .rotationEffect(.degrees(-90))
                        .frame(width: 16, height: 16)
                    
                    Image(systemName: "hands.sparkles.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.purple)
                }
            }
        }
    }
    
    private func recentPrayersText(_ names: [String]) -> String {
        if names.isEmpty { return "" }
        if names.count == 1 { return "\(names[0]) prayed" }
        if names.count == 2 { return "\(names[0]) and \(names[1]) prayed" }
        return "\(names[0]), \(names[1]) and \(names.count - 2) others prayed"
    }
}

// MARK: - Lock Screen / Banner View

private struct PrayerChainLockScreenView: View {
    let context: ActivityViewContext<PrayerChainActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "hands.sparkles.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.purple)
                Text("Prayer Chain")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(context.state.currentCount) / \(context.attributes.targetCount)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text("\(Int(context.state.percentComplete * 100))%")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Text(context.attributes.prayerText)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .lineLimit(2)
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 6)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [Color.purple, Color(red: 0.6, green: 0.3, blue: 0.9)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * context.state.percentComplete, height: 6)
                }
            }
            .frame(height: 6)

            if context.state.isComplete {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Prayer Complete!")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.green)
                }
            } else {
                Link(destination: URL(string: "amen://prayer?id=\(context.attributes.prayerRequestID)")!) {
                    Text("Pray Now")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.purple)
                }
            }
        }
        .padding(16)
        .activityBackgroundTint(.black)
    }
}
