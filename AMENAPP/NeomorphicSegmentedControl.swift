//
//  NeomorphicSegmentedControl.swift
//  AMENAPP
//
//  Beautiful neomorphic segmented control for filter buttons
//

import SwiftUI

// MARK: - Neomorphic Segmented Control

struct NeomorphicSegmentedControl: View {
    @Binding var selectedIndex: Int
    let options: [String]
    @Namespace private var animation
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        selectedIndex = index
                    }
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                } label: {
                    Text(options[index])
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundStyle(selectedIndex == index ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            ZStack {
                                if selectedIndex == index {
                                    // Selected state - recessed/inset look
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color(white: 0.88),
                                                    Color(white: 0.91)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .overlay(
                                            // Inner shadow for depth
                                            Capsule()
                                                .strokeBorder(
                                                    LinearGradient(
                                                        colors: [
                                                            Color.black.opacity(0.15),
                                                            Color.black.opacity(0.03)
                                                        ],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ),
                                                    lineWidth: 1
                                                )
                                                .blur(radius: 0.5)
                                        )
                                        .overlay(
                                            // Bottom light edge
                                            Capsule()
                                                .strokeBorder(
                                                    LinearGradient(
                                                        colors: [
                                                            Color.clear,
                                                            Color.white.opacity(0.3)
                                                        ],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ),
                                                    lineWidth: 0.5
                                                )
                                        )
                                        .matchedGeometryEffect(id: "SEGMENT_PILL", in: animation)
                                }
                            }
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(white: 0.94),
                            Color(white: 0.91)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.gray.opacity(0.2),
                            Color.gray.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
        .shadow(color: .white.opacity(0.7), radius: 6, x: 0, y: -2)
    }
}

// MARK: - Messages Filter View (Example Usage)

struct MessagesFilterControl: View {
    @Binding var selectedFilter: MessageFilter
    
    enum MessageFilter: Int, CaseIterable {
        case messages = 0
        case requests = 1
        case archived = 2
        
        var title: String {
            switch self {
            case .messages: return "Messages"
            case .requests: return "Requests"
            case .archived: return "Archived"
            }
        }
    }
    
    var body: some View {
        NeomorphicSegmentedControl(
            selectedIndex: Binding(
                get: { selectedFilter.rawValue },
                set: { selectedFilter = MessageFilter(rawValue: $0) ?? .messages }
            ),
            options: MessageFilter.allCases.map { $0.title }
        )
        .padding(.horizontal, 16)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        // Example 1: Messages Filter
        VStack(spacing: 12) {
            Text("Messages Filter")
                .font(.custom("OpenSans-Bold", size: 16))
            
            NeomorphicSegmentedControl(
                selectedIndex: .constant(0),
                options: ["Messages", "Requests", "Archived"]
            )
            .padding(.horizontal, 20)
        }
        
        // Example 2: Three Options
        VStack(spacing: 12) {
            Text("Auction Example")
                .font(.custom("OpenSans-Bold", size: 16))
            
            NeomorphicSegmentedControl(
                selectedIndex: .constant(1),
                options: ["Auction", "Listed", "Pre-Order"]
            )
            .padding(.horizontal, 20)
        }
        
        // Example 3: Four Options
        VStack(spacing: 12) {
            Text("Home Tab Example")
                .font(.custom("OpenSans-Bold", size: 16))
            
            NeomorphicSegmentedControl(
                selectedIndex: .constant(0),
                options: ["Store", "Saved", "Activity", "Home"]
            )
            .padding(.horizontal, 20)
        }
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
