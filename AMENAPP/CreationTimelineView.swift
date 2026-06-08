// CreationTimelineView.swift
// AMEN Creator — Timeline Editor
// Horizontal scrollable segment-based timeline

import SwiftUI

// MARK: - Timeline View

struct CreationTimelineView: View {
    @ObservedObject var vm: SceneBuilderViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Timeline header
            HStack {
                Text("Timeline")
                    .font(.custom("OpenSans-Bold", size: 15))
                Spacer()
                DurationBadge(seconds: vm.totalDuration)
                if let tone = vm.scenePlan?.tone {
                    ToneBadge(tone: tone)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            if vm.timelineSegments.isEmpty {
                emptyTimeline
            } else {
                segmentList
            }
        }
    }

    // MARK: - Empty

    private var emptyTimeline: some View {
        CreationEmptyState(
            icon: "slider.horizontal.3",
            title: "No Segments Yet",
            message: "Select a template or add media to build your timeline.",
            actionLabel: nil,
            action: nil
        )
        .frame(maxWidth: .infinity)
    }

    // MARK: - Segment List

    private var segmentList: some View {
        List {
            ForEach(vm.timelineSegments) { segment in
                TimelineSegmentRow(
                    segment: segment,
                    isSelected: vm.selectedSegmentId == segment.id,
                    assets: vm.selectedAssets,
                    onTap: { vm.selectSegment(segment.id) },
                    onDelete: { vm.deleteSegment(segment) },
                    onCaptionEdit: { vm.updateSegmentCaption(segment.id, caption: $0) }
                )
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .onMove { source, dest in vm.moveSegment(from: source, to: dest) }
            .onDelete { idx in
                idx.forEach { i in vm.deleteSegment(vm.timelineSegments[i]) }
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(.active))
        .frame(minHeight: 320)
    }
}

// MARK: - Segment Row

struct TimelineSegmentRow: View {
    let segment: CreationTimelineSegment
    let isSelected: Bool
    let assets: [CreationAsset]
    let onTap: () -> Void
    let onDelete: () -> Void
    let onCaptionEdit: (String) -> Void

    @State private var editingCaption = false
    @State private var captionDraft = ""

    var linkedAsset: CreationAsset? {
        guard let id = segment.assetId else { return nil }
        return assets.first { $0.id == id }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Kind indicator strip
                RoundedRectangle(cornerRadius: 3)
                    .fill(segment.kind.color)
                    .frame(width: 4)
                    .frame(height: 56)

                // Thumbnail placeholder or asset preview
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(segment.kind.color.opacity(0.1))
                        .frame(width: 52, height: 52)

                    Image(systemName: segment.kind.icon)
                        .font(.systemScaled(20))
                        .foregroundStyle(segment.kind.color)
                }

                // Segment info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        SegmentKindPill(kind: segment.kind, isSelected: false)
                        Spacer()
                        DurationBadge(seconds: segment.duration)
                    }

                    if let caption = segment.captionText, !caption.isEmpty {
                        Text(caption)
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if let text = segment.text, !text.isEmpty {
                        Text(text)
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Tap to edit")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(Color.secondary.opacity(0.5))
                    }
                }

                // AI lock indicator
                if segment.lockedByAI {
                    Image(systemName: "sparkle")
                        .font(.systemScaled(12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.black.opacity(0.05) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                isSelected ? Color.black.opacity(0.2) : Color.black.opacity(0.07),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    )
            )
            .scaleEffect(isSelected ? 1.01 : 1.0)
            .animation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7)), value: isSelected)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                editingCaption = true
                captionDraft = segment.captionText ?? segment.text ?? ""
            } label: {
                Label("Edit Caption", systemImage: "text.cursor")
            }

            Button(role: .destructive, action: onDelete) {
                Label("Delete Segment", systemImage: "trash.fill")
            }
        }
        .sheet(isPresented: $editingCaption) {
            CaptionEditSheet(
                initialText: captionDraft,
                segmentKind: segment.kind
            ) { updated in
                onCaptionEdit(updated)
            }
            .presentationDetents([.medium])
        }
    }
}

// MARK: - Caption Edit Sheet

struct CaptionEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var text: String
    let segmentKind: CreationSegmentKind
    let onSave: (String) -> Void

    init(initialText: String, segmentKind: CreationSegmentKind, onSave: @escaping (String) -> Void) {
        self._text = State(initialValue: initialText)
        self.segmentKind = segmentKind
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    SegmentKindPill(kind: segmentKind)
                    Text("Edit Caption")
                        .font(.custom("OpenSans-Bold", size: 16))
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top)

                TextEditor(text: $text)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .frame(minHeight: 120)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.gray.opacity(0.07))
                    )
                    .padding(.horizontal)

                HStack {
                    Text("\(text.count) characters")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)

                GlassCreationButton(label: "Save Caption", icon: "checkmark") {
                    onSave(text)
                    dismiss()
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Horizontal Timeline Scroll

struct HorizontalTimelineScroll: View {
    @ObservedObject var vm: SceneBuilderViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Timeline")
                .font(.custom("OpenSans-Bold", size: 13))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.timelineSegments) { segment in
                        HorizontalSegmentCard(
                            segment: segment,
                            isSelected: vm.selectedSegmentId == segment.id
                        ) {
                            vm.selectSegment(segment.id)
                        }
                    }

                    // Add segment button
                    Button {
                        // Let user add a blank segment
                        let blank = CreationTimelineSegment(
                            id: UUID().uuidString,
                            kind: .mainClip,
                            assetId: nil, startTime: nil, endTime: nil,
                            duration: 5, text: nil, captionText: nil,
                            overlayStyle: nil, transitionIn: .softFade, transitionOut: .softFade,
                            emphasis: .medium, lockedByAI: false
                        )
                        vm.timelineSegments.append(blank)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.systemScaled(18, weight: .medium))
                            Text("Add")
                                .font(.custom("OpenSans-SemiBold", size: 11))
                        }
                        .foregroundStyle(.secondary)
                        .frame(width: 72, height: 72)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color.black.opacity(0.15), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - Horizontal Segment Card

struct HorizontalSegmentCard: View {
    let segment: CreationTimelineSegment
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(segment.kind.color.opacity(0.1))
                        .frame(width: 72, height: 52)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    isSelected ? segment.kind.color : Color.black.opacity(0.08),
                                    lineWidth: isSelected ? 2 : 1
                                )
                        )

                    Image(systemName: segment.kind.icon)
                        .font(.systemScaled(18))
                        .foregroundStyle(segment.kind.color)
                }

                Text(DurationBadge(seconds: segment.duration).label)
                    .font(.custom("OpenSans-Bold", size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8)), value: isSelected)
    }
}
