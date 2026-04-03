//
//  CoCreationCanvasView.swift
//  AMENAPP
//
//  Collaborative text canvas — shared live editing surface.
//

import SwiftUI

// MARK: - CoCreationCanvasView

struct CoCreationCanvasView: View {

    @ObservedObject var vm: CoCreationViewModel
    @FocusState private var isFocused: Bool

    private let amenPurple = Color(red: 0.42, green: 0.28, blue: 1.00)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Glass background
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                isFocused
                                    ? amenPurple.opacity(0.45)
                                    : Color.white.opacity(0.08),
                                lineWidth: isFocused ? 1.5 : 1
                            )
                    )
                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: isFocused)

                // Placeholder
                if vm.canvasText.isEmpty && !isFocused {
                    Text("Start writing together…")
                        .font(.systemScaled(17))
                        .foregroundStyle(Color.white.opacity(0.25))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 20)
                        .allowsHitTesting(false)
                }

                // TextEditor
                TextEditor(text: $vm.canvasText)
                    .font(.systemScaled(17))
                    .foregroundStyle(Color.white)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .lineSpacing(6)
                    .focused($isFocused)
                    .frame(
                        minHeight: geo.size.height * 0.6,
                        maxHeight: .infinity
                    )
                    .onChange(of: vm.canvasText) { oldValue, newValue in
                        vm.onCanvasChange(newValue)
                    }
                    .onTapGesture {
                        isFocused = true
                    }
            }
            .frame(minHeight: geo.size.height * 0.6)
        }
    }
}
