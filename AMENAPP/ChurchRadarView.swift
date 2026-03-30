//
//  ChurchRadarView.swift
//  AMENAPP
//
//  Live Church Radar — animated radar canvas + nearby church pills.
//

import SwiftUI

struct ChurchRadarView: View {
    @StateObject var viewModel: ChurchRadarViewModel
    var onChurchSelected: (LiveChurch) -> Void

    @State private var isCollapsed: Bool = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var selectedId: UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text("📡")
                Text("LIVE RADAR")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.4))

                // Live pulse dot
                Circle()
                    .fill(Color.amenEmerald)
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulseScale)
                    .shadow(color: .amenEmerald.opacity(0.6), radius: 4)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                            pulseScale = 1.5
                        }
                    }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                        isCollapsed.toggle()
                    }
                } label: {
                    Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(GlassPillButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, isCollapsed ? 14 : 8)

            if !isCollapsed {
                VStack(spacing: 12) {
                    // Radar canvas
                    RadarCanvas(
                        sweepAngle: viewModel.sweepAngle,
                        churches: viewModel.nearbyChurches,
                        selectedId: selectedId
                    )
                    .frame(width: 200, height: 200)
                    .frame(maxWidth: .infinity)

                    // Church pills scroll
                    if !viewModel.nearbyChurches.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(viewModel.nearbyChurches) { church in
                                    ChurchRadarPill(
                                        church: church,
                                        isSelected: selectedId == church.id
                                    ) {
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                            selectedId = church.id
                                        }
                                        onChurchSelected(church)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.bottom, 14)
                    } else {
                        Text("Scanning for nearby churches…")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.35))
                            .padding(.bottom, 14)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 20).fill(Color.amenCyan.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
        .onAppear {
            viewModel.loadNearbyChurches()
            viewModel.startRadar()
        }
        .onDisappear {
            viewModel.stopRadar()
        }
    }
}

// MARK: - Radar Canvas

private struct RadarCanvas: View {
    let sweepAngle: Double
    let churches: [LiveChurch]
    let selectedId: UUID?

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxRadius = min(size.width, size.height) / 2

            // 4 concentric rings
            for i in 1...4 {
                let r = maxRadius * CGFloat(i) / 4
                let opacity = 0.15 - Double(i) * 0.02
                context.stroke(
                    Path { p in p.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)) },
                    with: .color(.white.opacity(max(0.05, opacity))),
                    lineWidth: 0.8
                )
            }

            // Radial grid lines every 45°
            for deg in stride(from: 0, to: 360, by: 45) {
                let radians = CGFloat(deg) * .pi / 180
                let end = CGPoint(
                    x: center.x + maxRadius * cos(radians),
                    y: center.y + maxRadius * sin(radians)
                )
                context.stroke(
                    Path { p in p.move(to: center); p.addLine(to: end) },
                    with: .color(.white.opacity(0.06)),
                    lineWidth: 0.5
                )
            }

            // Sweep wedge
            let sweepRad = CGFloat(sweepAngle - 90) * .pi / 180
            var wedge = Path()
            wedge.move(to: center)
            wedge.addArc(
                center: center,
                radius: maxRadius,
                startAngle: .radians(sweepRad - 0.5),
                endAngle: .radians(sweepRad),
                clockwise: false
            )
            wedge.closeSubpath()
            context.fill(wedge, with: .color(Color.amenCyan.opacity(0.3)))

            // Church dots
            for (idx, church) in churches.enumerated() {
                let angle = CGFloat(idx) * (360.0 / CGFloat(churches.count)) * .pi / 180
                let distance = maxRadius * CGFloat(min(church.distanceMiles, 10.0) / 10.0) * 0.85
                let dot = CGPoint(
                    x: center.x + distance * cos(angle),
                    y: center.y + distance * sin(angle)
                )
                let isSelected = church.id == selectedId
                let dotColor: Color = church.isLive ? .amenEmerald : .white.opacity(0.4)
                let r: CGFloat = isSelected ? 6 : 4

                context.fill(
                    Path(ellipseIn: CGRect(x: dot.x - r, y: dot.y - r, width: r * 2, height: r * 2)),
                    with: .color(dotColor)
                )
                if isSelected {
                    context.stroke(
                        Path(ellipseIn: CGRect(x: dot.x - 8, y: dot.y - 8, width: 16, height: 16)),
                        with: .color(Color.cnGold),
                        lineWidth: 1.5
                    )
                }
            }

            // Center dot
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)),
                with: .color(.amenCyan)
            )
        }
    }
}

// MARK: - Church Pill

private struct ChurchRadarPill: View {
    let church: LiveChurch
    let isSelected: Bool
    let onTap: () -> Void

    @State private var scale: CGFloat = 1.0

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                scale = 0.97
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    scale = 1.0
                }
            }
            onTap()
        } label: {
            HStack(spacing: 6) {
                if church.isLive {
                    Circle()
                        .fill(Color.amenEmerald)
                        .frame(width: 6, height: 6)
                }
                Text(church.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.85))
                Text(String(format: "%.1f mi", church.distanceMiles))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(Color.white.opacity(0.04)))
                    .overlay(
                        Capsule()
                            .strokeBorder(isSelected ? Color.cnGold : Color.white.opacity(0.08), lineWidth: isSelected ? 1.5 : 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(scale)
    }
}
