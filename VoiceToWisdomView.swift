//
//  VoiceToWisdomView.swift
//  AMENAPP
//
//  Inline voice capture + Berean AI enhancement for church notes.
//

import SwiftUI
import AVFoundation

struct VoiceToWisdomView: View {
    @StateObject var viewModel: VoiceToWisdomViewModel
    @Binding var noteBody: String

    @State private var isExpanded: Bool = false

    var body: some View {
        Group {
            if viewModel.isProcessing {
                processingCard
            } else if viewModel.isRecording {
                recordingCard
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            } else if !viewModel.transcribedText.isEmpty {
                // Auto-inject once and reset
                Color.clear
                    .frame(height: 0)
                    .onAppear { injectTranscription() }
            } else {
                idlePill
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: viewModel.isRecording)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: viewModel.isProcessing)
        .onDisappear { viewModel.cleanup() }
    }

    // MARK: - Idle pill

    private var idlePill: some View {
        Button {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                isExpanded = true
            }
            viewModel.startRecording()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.subheadline)
                Text("Voice")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(colors: [.amenEmerald, Color(hex: "16A34A")], startPoint: .leading, endPoint: .trailing)
                    )
                    .shadow(color: Color.amenEmerald.opacity(0.4), radius: 8, y: 4)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recording card

    private var recordingCard: some View {
        HStack(spacing: 14) {
            // Waveform bars
            HStack(spacing: 3) {
                ForEach(Array(viewModel.waveformHeights.enumerated()), id: \.offset) { _, height in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.amenEmerald)
                        .frame(width: 3, height: height)
                        .animation(.spring(response: 0.25, dampingFraction: 0.5), value: height)
                }
            }
            .frame(height: 36)

            // Elapsed time
            Text(viewModel.formattedElapsed())
                .font(.system(.subheadline, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.85))
                .frame(minWidth: 36)

            Spacer()

            // Stop button
            Button {
                viewModel.stopRecording()
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    isExpanded = false
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "stop.fill")
                        .font(.caption)
                    Text("Stop & Enhance")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(colors: [Color(hex: "EF4444"), Color(hex: "B91C1C")], startPoint: .leading, endPoint: .trailing)
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16).fill(Color.amenEmerald.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.amenEmerald.opacity(0.25), lineWidth: 1))
        )
        .shadow(color: Color.amenEmerald.opacity(0.25), radius: 12, y: 4)
    }

    // MARK: - Processing card

    private var processingCard: some View {
        ProcessingShimmerCard()
    }

    // MARK: - Inject transcription

    private func injectTranscription() {
        let text = viewModel.transcribedText
        guard !text.isEmpty else { return }

        let block = "\n\n[Voice Note — \(Date().formatted(.dateTime.hour().minute()))]\n\(text)"
        noteBody += block
        // Clear so we don't re-inject
        viewModel.transcribedText = ""
    }
}

// MARK: - Processing Shimmer Card

private struct ProcessingShimmerCard: View {
    @State private var shimmerOffset: CGFloat = -180

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(.amenEmerald)
                .scaleEffect(0.85)

            Text("Enhancing with Berean AI…")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white.opacity(0.7))

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16).fill(Color.amenEmerald.opacity(0.06)))
                .overlay(
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.06), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 100)
                        .offset(x: shimmerOffset)
                        .clipped()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                )
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.amenEmerald.opacity(0.15), lineWidth: 1))
        )
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                shimmerOffset = 320
            }
        }
    }
}
