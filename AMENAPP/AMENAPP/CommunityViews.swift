import SwiftUI
struct CollapsibleCommunitySection: View {
    @AppStorage("communitySectionExpanded") private var isExpanded = true
    @Binding var showTopIdeas: Bool
    @Binding var showSpotlight: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with expand/collapse button
            Button {
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
                    isExpanded.toggle()
                }
                
                HapticManager.impact(style: .light)
            } label: {
                HStack {
                    Text("Community")
                        .font(AMENFont.bold(16))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : 180))
                }
                .padding(.horizontal)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Community Cards - Liquid Glass Design
            if isExpanded {
                HStack(spacing: 12) {
                    LiquidGlassCommunityCard(
                        icon: "arrow.up",
                        iconColor: Color.white, // White upward arrow
                        backgroundGradientTop: Color(red: 0.40, green: 0.75, blue: 0.95), // Light sky blue
                        backgroundGradientBottom: Color(red: 0.60, green: 0.85, blue: 0.98), // Lighter blue (bottom)
                        useBurgundyStyle: false,
                        title: "Top Ideas",
                        subtitle: "This Week"
                    ) {
                        showTopIdeas = true
                    }
                    
                    LiquidGlassCommunityCard(
                        icon: "lightbulb.fill",
                        iconColor: Color.white, // White lightbulb
                        backgroundGradientTop: Color(red: 0.25, green: 0.35, blue: 0.45), // Deep slate blue
                        backgroundGradientBottom: Color(red: 0.35, green: 0.45, blue: 0.55), // Lighter slate blue
                        useBurgundyStyle: false,
                        title: "Spotlight",
                        subtitle: "Featured"
                    ) {
                        showSpotlight = true
                    }
                }
                .padding(.horizontal)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95)).animation(.spring(response: 0.3, dampingFraction: 0.8)),
                    removal: .opacity.combined(with: .scale(scale: 0.95)).animation(.spring(response: 0.3, dampingFraction: 0.8))
                ))
            }
        }
        .sheet(isPresented: $showTopIdeas) {
            TopIdeasView()
        }
        .sheet(isPresented: $showSpotlight) {
            SpotlightView()
        }
    }
}

// MARK: - Liquid Glass Community Card (Black & White with Color Accents)

struct LiquidGlassCommunityCard: View {
    let icon: String
    let iconColor: Color
    var backgroundGradientTop: Color? = nil
    var backgroundGradientBottom: Color? = nil
    var useBurgundyStyle: Bool = false
    let title: String
    let subtitle: String
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            HapticManager.impact(style: .light)
            action()
        }) {
            HStack(spacing: 12) {
                // White icon
                Image(systemName: icon)
                    .font(.systemScaled(16, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: isPressed)
                
                VStack(alignment: .leading, spacing: 3) {
                    // White text for both banners
                    Text(title)
                        .font(.systemScaled(15, weight: .semibold))
                        .italic()
                        .foregroundStyle(.white)
                    
                    Text(subtitle)
                        .font(.systemScaled(12, weight: .semibold))
                        .italic()
                        .foregroundStyle(.white.opacity(0.9))
                }
                
                Spacer()
                
                Image(systemName: "arrow.right")
                    .font(.systemScaled(12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    // Use gradient colors if provided, otherwise use black glassmorphic background
                    if let gradientTop = backgroundGradientTop, let gradientBottom = backgroundGradientBottom {
                        // Custom gradient background
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                LinearGradient(
                                    colors: [gradientTop, gradientBottom],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: gradientTop.opacity(0.3), radius: 8, x: 0, y: 4)
                    } else {
                        // Black glassmorphic background (default)
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.black.opacity(0.6))
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(.ultraThinMaterial)
                            )
                    }
                    
                    // Transparent liquid glass border
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.3),
                                    .white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                }
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.smooth(duration: 0.2)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}
