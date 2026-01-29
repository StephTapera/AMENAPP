//
//  ScrollViewHelpers.swift
//  AMENAPP
//
//  Helpers for ScrollView offset tracking and scroll-to-bottom functionality
//

import SwiftUI

// MARK: - ScrollView with Offset Tracking

struct ScrollViewWithOffset<Content: View>: View {
    @Binding var offset: CGFloat
    @ViewBuilder let content: Content
    
    var body: some View {
        ScrollView {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ScrollOffsetPreferenceKey.self,
                    value: geometry.frame(in: .named("scroll")).origin.y
                )
            }
            .frame(height: 0)
            
            content
        }
        .coordinateSpace(name: "scroll")
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
            offset = value
        }
    }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Scroll View Reader Helper

struct ScrollableMessageList<Content: View>: View {
    @Binding var messages: [AppMessage]
    @Binding var showScrollButton: Bool
    @State private var scrollOffset: CGFloat = 0
    let scrollProxy: ScrollViewProxy?
    @ViewBuilder let content: (AppMessage, AppMessage?, AppMessage?) -> Content
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        let previousMessage = index > 0 ? messages[index - 1] : nil
                        let nextMessage = index < messages.count - 1 ? messages[index + 1] : nil
                        
                        content(message, previousMessage, nextMessage)
                            .id(message.id)
                    }
                }
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geometry.frame(in: .named("scroll")).minY
                        )
                    }
                )
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                // Negative value means scrolled up
                showScrollButton = value < -500
            }
            .onAppear {
                // Scroll to bottom on appear
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: messages.count) { _, _ in
                // Auto-scroll to bottom when new message arrives
                if !showScrollButton {
                    withAnimation {
                        scrollToBottom(proxy: proxy)
                    }
                }
            }
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastMessage = messages.last {
            proxy.scrollTo(lastMessage.id, anchor: .bottom)
        }
    }
}

// MARK: - Extension for Easy Scrolling

extension View {
    func scrollToBottom(_ action: @escaping () -> Void) -> some View {
        self.modifier(ScrollToBottomModifier(action: action))
    }
}

struct ScrollToBottomModifier: ViewModifier {
    let action: () -> Void
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                Button(action: action) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue)
                        .background(
                            Circle()
                                .fill(Color.white)
                                .frame(width: 42, height: 42)
                        )
                        .shadow(radius: 4)
                }
                .padding()
            }
    }
}
