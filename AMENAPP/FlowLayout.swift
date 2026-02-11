//
//  FlowLayout.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//
//  Custom flow layout for wrapping views (tags, pills, etc.)
//

import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var horizontalSpacing: CGFloat?
    var verticalSpacing: CGFloat?
    
    private var hSpacing: CGFloat {
        horizontalSpacing ?? spacing
    }
    
    private var vSpacing: CGFloat {
        verticalSpacing ?? spacing
    }
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = calculateLayout(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = calculateLayout(proposal: proposal, subviews: subviews)
        
        for (index, subview) in subviews.enumerated() {
            let position = result.positions[index]
            subview.place(
                at: CGPoint(
                    x: bounds.minX + position.x,
                    y: bounds.minY + position.y
                ),
                proposal: ProposedViewSize(
                    width: result.sizes[index].width,
                    height: result.sizes[index].height
                )
            )
        }
    }
    
    private func calculateLayout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        var sizes: [CGSize] = []
        var positions: [CGPoint] = []
        
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxLineWidth: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            // Check if we need to wrap to next line
            if currentX + size.width > maxWidth && currentX > 0 {
                // Move to next line
                currentX = 0
                currentY += lineHeight + vSpacing
                totalHeight = currentY
                lineHeight = 0
            }
            
            // Store position
            positions.append(CGPoint(x: currentX, y: currentY))
            sizes.append(size)
            
            // Update tracking variables
            currentX += size.width + hSpacing
            lineHeight = max(lineHeight, size.height)
            maxLineWidth = max(maxLineWidth, currentX - hSpacing)
        }
        
        // Add final line height
        totalHeight += lineHeight
        
        return LayoutResult(
            size: CGSize(width: maxLineWidth, height: totalHeight),
            positions: positions,
            sizes: sizes
        )
    }
    
    private struct LayoutResult {
        let size: CGSize
        let positions: [CGPoint]
        let sizes: [CGSize]
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            // Example 1: Simple tags
            VStack(alignment: .leading, spacing: 12) {
                Text("Simple Flow Layout")
                    .font(.headline)
                
                FlowLayout(spacing: 8) {
                    ForEach(["Prayer", "Faith", "Hope", "Love", "Grace", "Mercy", "Worship", "Praise"], id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.blue)
                            )
                    }
                }
            }
            
            // Example 2: Different sized elements
            VStack(alignment: .leading, spacing: 12) {
                Text("Mixed Sizes")
                    .font(.headline)
                
                FlowLayout(spacing: 10) {
                    ForEach(["Short", "Medium Length Tag", "X", "Another Long Tag Here", "Hi", "Test"], id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.purple)
                            )
                    }
                }
            }
            
            // Example 3: Custom spacing
            VStack(alignment: .leading, spacing: 12) {
                Text("Custom Spacing")
                    .font(.headline)
                
                FlowLayout(horizontalSpacing: 16, verticalSpacing: 12) {
                    ForEach(1...10, id: \.self) { number in
                        Text("\(number)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(Color.green)
                            )
                    }
                }
            }
        }
        .padding()
    }
}
