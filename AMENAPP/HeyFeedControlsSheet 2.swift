//
//  HeyFeedControlsSheet.swift
//  AMENAPP
//
//  Hey Feed controls UI - "Like 'Dear Algo' but for OpenTable"
//  Compact sheet with mode, topics, debate, sensitivity, and pacing controls
//

import SwiftUI

struct HeyFeedControlsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var prefsService = HeyFeedPreferencesService.shared
    
    @State private var selectedMode: FeedMode
    @State private var pinnedTopics: Set<FeedTopic>
    @State private var debateLevel: DebateLevel
    @State private var sensitivityFilter: SensitivityFilter
    @State private var refreshPacing: RefreshPacing
    
    init() {
        let prefs = HeyFeedPreferencesService.shared.preferences
        _selectedMode = State(initialValue: prefs.mode)
        _pinnedTopics = State(initialValue: prefs.pinnedTopics)
        _debateLevel = State(initialValue: prefs.debateLevel)
        _sensitivityFilter = State(initialValue: prefs.sensitivityFilter)
        _refreshPacing = State(initialValue: prefs.refreshPacing)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.largeTitle)
                            .foregroundColor(.blue)
                        
                        Text("Hey Feed")
                            .font(.title2.weight(.bold))
                        
                        Text("Control what you see in OpenTable")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top)
                    
                    Divider()
                    
                    // Feed Mode
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Feed Mode", systemImage: "wand.and.stars")
                            .font(.headline)
                        
                        ForEach(FeedMode.allCases, id: \.self) { mode in
                            ModeButton(
                                mode: mode,
                                isSelected: selectedMode == mode,
                                action: {
                                    selectedMode = mode
                                    Task {
                                        await prefsService.setMode(mode)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                    
                    Divider()
                    
                    // Topics
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Pinned Topics", systemImage: "tag")
                            .font(.headline)
                        
                        Text("Boost content about these topics")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HeyFeedFlowLayout(spacing: 8) {
                            ForEach(FeedTopic.allCases, id: \.self) { topic in
                                TopicChip(
                                    topic: topic,
                                    isPinned: pinnedTopics.contains(topic),
                                    action: {
                                        if pinnedTopics.contains(topic) {
                                            pinnedTopics.remove(topic)
                                        } else {
                                            pinnedTopics.insert(topic)
                                        }
                                        Task {
                                            await prefsService.toggleTopicPin(topic)
                                        }
                                    }
                                )
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    Divider()
                    
                    // Debate Level
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Debate Tolerance", systemImage: "bubble.left.and.bubble.right")
                            .font(.headline)
                        
                        ForEach(DebateLevel.allCases, id: \.self) { level in
                            DebateLevelButton(
                                level: level,
                                isSelected: debateLevel == level,
                                action: {
                                    debateLevel = level
                                    Task {
                                        await prefsService.setDebateLevel(level)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                    
                    Divider()
                    
                    // Sensitivity Filter
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Content Sensitivity", systemImage: "shield")
                            .font(.headline)
                        
                        ForEach(SensitivityFilter.allCases, id: \.self) { filter in
                            SensitivityFilterButton(
                                filter: filter,
                                isSelected: sensitivityFilter == filter,
                                action: {
                                    sensitivityFilter = filter
                                    Task {
                                        await prefsService.setSensitivityFilter(filter)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                    
                    Divider()
                    
                    // Refresh Pacing
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Refresh Pacing", systemImage: "arrow.clockwise")
                            .font(.headline)
                        
                        ForEach(RefreshPacing.allCases, id: \.self) { pacing in
                            RefreshPacingButton(
                                pacing: pacing,
                                isSelected: refreshPacing == pacing,
                                action: {
                                    refreshPacing = pacing
                                    Task {
                                        await prefsService.setRefreshPacing(pacing)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer(minLength: 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Mode Button

struct ModeButton: View {
    let mode: FeedMode
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(isSelected ? .white : .primary)
                    
                    Text(mode.description)
                        .font(.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                }
            }
            .padding(12)
            .background(isSelected ? Color.blue : Color(.systemGray6))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Topic Chip

struct TopicChip: View {
    let topic: FeedTopic
    let isPinned: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: topic.icon)
                    .font(.caption)
                Text(topic.displayName)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isPinned ? Color.blue : Color(.systemGray5))
            .foregroundColor(isPinned ? .white : .primary)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Debate Level Button

struct DebateLevelButton: View {
    let level: DebateLevel
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(level.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(isSelected ? .white : .primary)
                    
                    Text(level.description)
                        .font(.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                }
            }
            .padding(10)
            .background(isSelected ? Color.blue : Color(.systemGray6))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sensitivity Filter Button

struct SensitivityFilterButton: View {
    let filter: SensitivityFilter
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(filter.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(isSelected ? .white : .primary)
                    
                    Text(filter.description)
                        .font(.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                }
            }
            .padding(10)
            .background(isSelected ? Color.blue : Color(.systemGray6))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Refresh Pacing Button

struct RefreshPacingButton: View {
    let pacing: RefreshPacing
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pacing.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(isSelected ? .white : .primary)
                    
                    Text(pacing.description)
                        .font(.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                }
            }
            .padding(10)
            .background(isSelected ? Color.blue : Color(.systemGray6))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow Layout (for topic chips)

struct HeyFeedFlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX,
                                     y: bounds.minY + result.frames[index].minY),
                         proposal: ProposedViewSize(result.frames[index].size))
        }
    }
    
    struct FlowResult {
        var frames: [CGRect] = []
        var size: CGSize = .zero
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                
                frames.append(CGRect(x: currentX, y: currentY, width: size.width, height: size.height))
                
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}
