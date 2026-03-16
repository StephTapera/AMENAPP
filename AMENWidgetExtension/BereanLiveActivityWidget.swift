//
//  BereanLiveActivityWidget.swift
//  AMENWidgetExtension
//
//  Dynamic Island UI for the Berean AI Live Activity.
//  Compact, minimal, and expanded views.
//

import SwiftUI
import WidgetKit
import ActivityKit

// ActivityAttributes conformance for the widget extension target
extension BereanActivityAttributes: ActivityAttributes {}

struct BereanLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BereanActivityAttributes.self) { context in
            // Lock Screen / Banner view
            BereanLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded view regions
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "cross.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.purple)
                        .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.phase == .loading {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.purple)
                    } else if context.state.phase == .complete {
                        Text("\(context.state.sourceCount)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.purple))
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    Text("Berean AI")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        // Response text
                        if context.state.phase == .loading {
                            Text(context.state.phase.statusText)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(.gray)
                                .italic()
                        } else {
                            Text(context.state.responseText)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(.white)
                                .lineLimit(4)
                                .lineSpacing(2)
                        }

                        // Scripture pills
                        if !context.state.scriptures.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(context.state.scriptures, id: \.self) { ref in
                                        Text(ref)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Capsule().fill(Color.purple.opacity(0.6)))
                                    }
                                }
                            }
                        }

                        // Go Deeper button
                        if context.state.phase == .complete {
                            Link(destination: URL(string: "amen://berean?postID=\(context.attributes.postID)")!) {
                                Text("Go Deeper")
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
                // Compact left — cross icon
                Image(systemName: "cross.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.purple)
            } compactTrailing: {
                // Compact right — status
                if context.state.phase == .loading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(.purple)
                } else if context.state.phase == .complete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                } else {
                    Text("AI")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.purple)
                }
            } minimal: {
                // Minimal — just the cross icon
                Image(systemName: "cross.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.purple)
            }
        }
    }
}

// MARK: - Lock Screen / Banner View

private struct BereanLockScreenView: View {
    let context: ActivityViewContext<BereanActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "cross.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.purple)
                Text("Berean AI")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                if context.state.phase == .loading {
                    ProgressView().scaleEffect(0.7).tint(.purple)
                }
            }

            Text(context.state.phase == .loading
                 ? context.state.phase.statusText
                 : context.state.responseText)
                .font(.system(size: 13))
                .foregroundStyle(context.state.phase == .loading ? .gray : .white)
                .lineLimit(3)

            if context.state.phase == .complete {
                Link(destination: URL(string: "amen://berean?postID=\(context.attributes.postID)")!) {
                    Text("Go Deeper")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.purple)
                }
            }
        }
        .padding(16)
        .activityBackgroundTint(.black)
    }
}
