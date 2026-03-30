//
//  MessageDeliveryStatusView.swift
//  AMENAPP
//
//  Displays message delivery status indicators
//  Created: January 28, 2026
//

import SwiftUI

/// Visual indicator for message delivery status
struct MessageDeliveryStatusView: View {
    let status: MessageDeliveryStatus
    let isFromCurrentUser: Bool
    
    var body: some View {
        if isFromCurrentUser {
            statusIcon
        }
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .sending:
            HStack(spacing: 2) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            
        case .sent:
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            
        case .delivered:
            HStack(spacing: -3) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            
        case .read:
            HStack(spacing: -3) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.blue)
            
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)
        }
    }
}

/// Animated delivery status indicator
struct AnimatedDeliveryStatusView: View {
    let status: MessageDeliveryStatus
    @State private var animationPhase = 0
    
    var body: some View {
        Group {
            switch status {
            case .sending:
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Color.secondary)
                            .frame(width: 4, height: 4)
                            .opacity(animationPhase == index ? 1.0 : 0.3)
                    }
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: false)) {
                        animationPhase = (animationPhase + 1) % 3
                    }
                }
                
            case .sent:
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .transition(.scale.combined(with: .opacity))
                
            case .delivered:
                HStack(spacing: -3) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .transition(.scale.combined(with: .opacity))
                
            case .read:
                HStack(spacing: -3) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.blue)
                .transition(.scale.combined(with: .opacity))
                
            case .failed:
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12))
                    Text("Failed")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.red)
                .transition(.scale.combined(with: .opacity))
        }
        }
        .animation(.easeInOut(duration: 0.3), value: status)
    }
}

/// Detailed delivery status with text
struct DetailedDeliveryStatusView: View {
    let status: MessageDeliveryStatus
    let timestamp: Date?
    
    var body: some View {
        HStack(spacing: 4) {
            MessageDeliveryStatusView(status: status, isFromCurrentUser: true)
            
            if let timestamp = timestamp {
                Text(timestamp, style: .time)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            
            if status != .sending && status != .failed {
                Text(statusText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var statusText: String {
        switch status {
        case .sent:
            return "Sent"
        case .delivered:
            return "Delivered"
        case .read:
            return "Read"
        case .sending:
            return "Sending..."
        case .failed:
            return "Failed"
        }
    }
}

// MARK: - Preview

#Preview("All Status Types") {
    VStack(alignment: .leading, spacing: 20) {
        Text("Delivery Status Indicators")
            .font(.headline)
        
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sending:")
                Spacer()
                MessageDeliveryStatusView(status: .sending, isFromCurrentUser: true)
            }
            
            HStack {
                Text("Sent:")
                Spacer()
                MessageDeliveryStatusView(status: .sent, isFromCurrentUser: true)
            }
            
            HStack {
                Text("Delivered:")
                Spacer()
                MessageDeliveryStatusView(status: .delivered, isFromCurrentUser: true)
            }
            
            HStack {
                Text("Read:")
                Spacer()
                MessageDeliveryStatusView(status: .read, isFromCurrentUser: true)
            }
            
            HStack {
                Text("Failed:")
                Spacer()
                MessageDeliveryStatusView(status: .failed, isFromCurrentUser: true)
            }
        }
        
        Divider()
        
        Text("Animated Versions")
            .font(.headline)
        
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sending:")
                Spacer()
                AnimatedDeliveryStatusView(status: .sending)
            }
            
            HStack {
                Text("Read:")
                Spacer()
                AnimatedDeliveryStatusView(status: .read)
            }
            
            HStack {
                Text("Failed:")
                Spacer()
                AnimatedDeliveryStatusView(status: .failed)
            }
        }
        
        Divider()
        
        Text("Detailed Status")
            .font(.headline)
        
        VStack(alignment: .leading, spacing: 12) {
            DetailedDeliveryStatusView(status: .sent, timestamp: Date())
            DetailedDeliveryStatusView(status: .delivered, timestamp: Date())
            DetailedDeliveryStatusView(status: .read, timestamp: Date())
        }
    }
    .padding()
}
