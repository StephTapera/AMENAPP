//
//  PrayerTimerView.swift
//  AMENAPP
//
//  Created by Steph on 1/17/26.
//

import SwiftUI

struct PrayerTimerView: View {
    @Environment(\.dismiss) var dismiss
    @State private var currentPhase: PrayerPhase = .adoration
    @State private var timeRemaining = 300 // 5 minutes default
    @State private var isRunning = false
    @State private var timer: Timer?
    
    enum PrayerPhase: String, CaseIterable {
        case adoration = "Adoration"
        case confession = "Confession"
        case thanksgiving = "Thanksgiving"
        case supplication = "Supplication"
        
        var icon: String {
            switch self {
            case .adoration: return "sparkles"
            case .confession: return "heart.fill"
            case .thanksgiving: return "hands.clap.fill"
            case .supplication: return "hands.sparkles.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .adoration: return .yellow
            case .confession: return .red
            case .thanksgiving: return .green
            case .supplication: return .blue
            }
        }
        
        var prompt: String {
            switch self {
            case .adoration:
                return "Praise God for who He is - His character, His attributes, His majesty"
            case .confession:
                return "Confess your sins and shortcomings to God, knowing He is faithful to forgive"
            case .thanksgiving:
                return "Thank God for what He has done - His blessings, His provision, His faithfulness"
            case .supplication:
                return "Bring your requests to God for yourself, others, and His kingdom"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Phase indicator
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(PrayerPhase.allCases, id: \.self) { phase in
                            PhaseIndicator(
                                phase: phase,
                                isActive: currentPhase == phase,
                                isCompleted: PrayerPhase.allCases.firstIndex(of: phase)! < PrayerPhase.allCases.firstIndex(of: currentPhase)!
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 20)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Timer display
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .stroke(currentPhase.color.opacity(0.2), lineWidth: 12)
                                    .frame(width: 220, height: 220)
                                
                                Circle()
                                    .trim(from: 0, to: CGFloat(timeRemaining) / 300.0)
                                    .stroke(
                                        currentPhase.color,
                                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                                    )
                                    .frame(width: 220, height: 220)
                                    .rotationEffect(.degrees(-90))
                                    .animation(.linear, value: timeRemaining)
                                
                                VStack(spacing: 8) {
                                    Image(systemName: currentPhase.icon)
                                        .font(.system(size: 40))
                                        .foregroundStyle(currentPhase.color)
                                        .symbolEffect(.pulse, options: isRunning ? .repeating : .default, value: isRunning)
                                    
                                    Text(String(format: "%d:%02d", timeRemaining / 60, timeRemaining % 60))
                                        .font(.system(size: 48, weight: .bold, design: .rounded))
                                        .foregroundStyle(.primary)
                                }
                            }
                            
                            Text(currentPhase.rawValue)
                                .font(.custom("OpenSans-Bold", size: 28))
                                .foregroundStyle(currentPhase.color)
                        }
                        
                        // Prompt card
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Prayer Prompt")
                                .font(.custom("OpenSans-Bold", size: 16))
                                .foregroundStyle(.secondary)
                            
                            Text(currentPhase.prompt)
                                .font(.custom("OpenSans-Regular", size: 16))
                                .foregroundStyle(.primary)
                                .lineSpacing(6)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(currentPhase.color.opacity(0.1))
                        )
                        .padding(.horizontal)
                        
                        // Control buttons
                        VStack(spacing: 12) {
                            // Play/Pause button
                            Button {
                                toggleTimer()
                            } label: {
                                HStack {
                                    Image(systemName: isRunning ? "pause.fill" : "play.fill")
                                        .font(.system(size: 20, weight: .bold))
                                    
                                    Text(isRunning ? "Pause" : "Start")
                                        .font(.custom("OpenSans-Bold", size: 18))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(currentPhase.color)
                                )
                            }
                            
                            HStack(spacing: 12) {
                                // Skip button
                                Button {
                                    nextPhase()
                                } label: {
                                    HStack {
                                        Image(systemName: "forward.fill")
                                        Text("Next Phase")
                                            .font(.custom("OpenSans-Bold", size: 15))
                                    }
                                    .foregroundStyle(currentPhase.color)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14)
                                            .fill(currentPhase.color.opacity(0.1))
                                    )
                                }
                                
                                // Reset button
                                Button {
                                    resetTimer()
                                } label: {
                                    HStack {
                                        Image(systemName: "arrow.clockwise")
                                        Text("Reset")
                                            .font(.custom("OpenSans-Bold", size: 15))
                                    }
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14)
                                            .fill(Color.gray.opacity(0.1))
                                    )
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        // Time selector
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Duration per Phase")
                                .font(.custom("OpenSans-Bold", size: 16))
                                .foregroundStyle(.secondary)
                            
                            HStack(spacing: 12) {
                                ForEach([3, 5, 10, 15], id: \.self) { minutes in
                                    Button {
                                        setDuration(minutes: minutes)
                                    } label: {
                                        Text("\(minutes)m")
                                            .font(.custom("OpenSans-Bold", size: 14))
                                            .foregroundStyle(timeRemaining == minutes * 60 ? .white : .primary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .fill(timeRemaining == minutes * 60 ? currentPhase.color : Color.gray.opacity(0.1))
                                            )
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Prayer Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        stopTimer()
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .onDisappear {
            stopTimer()
        }
    }
    
    private func toggleTimer() {
        isRunning.toggle()
        
        if isRunning {
            startTimer()
        } else {
            stopTimer()
        }
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                // Move to next phase
                nextPhase()
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func resetTimer() {
        stopTimer()
        isRunning = false
        timeRemaining = 300
        currentPhase = .adoration
    }
    
    private func nextPhase() {
        if let currentIndex = PrayerPhase.allCases.firstIndex(of: currentPhase) {
            if currentIndex < PrayerPhase.allCases.count - 1 {
                currentPhase = PrayerPhase.allCases[currentIndex + 1]
                timeRemaining = 300
            } else {
                // Completed all phases
                stopTimer()
                isRunning = false
                // Could show completion message here
            }
        }
    }
    
    private func setDuration(minutes: Int) {
        if !isRunning {
            timeRemaining = minutes * 60
        }
    }
}

struct PhaseIndicator: View {
    let phase: PrayerTimerView.PrayerPhase
    let isActive: Bool
    let isCompleted: Bool
    
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(isActive ? phase.color : (isCompleted ? phase.color.opacity(0.3) : Color.gray.opacity(0.1)))
                    .frame(width: 44, height: 44)
                
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: phase.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(isActive ? .white : .secondary)
                }
            }
            
            Text(phase.rawValue)
                .font(.custom("OpenSans-SemiBold", size: 11))
                .foregroundStyle(isActive ? phase.color : .secondary)
                .lineLimit(1)
        }
        .frame(width: 80)
    }
}

#Preview {
    PrayerTimerView()
}
