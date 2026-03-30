// ReasoningThreadView.swift — AMEN App
// Full-screen modal for structured, AI-framed discussions on a post.

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct ReasoningThreadView: View {
    let postId: String
    let postText: String
    let postAuthorName: String

    @StateObject private var vm: ReasoningViewModel
    @State private var showAddArgument = false
    @State private var replyingToNodeId: String? = nil
    @State private var steelForExpanded = false
    @State private var steelAgainstExpanded = false
    @Environment(\.dismiss) private var dismiss

    init(postId: String, postText: String, postAuthorName: String) {
        self.postId = postId
        self.postText = postText
        self.postAuthorName = postAuthorName
        _vm = StateObject(wrappedValue: ReasoningViewModel(postId: postId, postText: postText))
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Color(.systemGroupedBackground).ignoresSafeArea()

                if vm.isLoadingFrame {
                    loadingView
                } else {
                    scrollContent
                }

                // FAB
                if !vm.isLoadingFrame {
                    addViewButton
                }
            }
            .navigationTitle("Discussion Thread")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(.black.opacity(0.7))
                            .font(.system(size: 15, weight: .medium))
                    }
                }
            }
        }
        .presentationDetents([.large])
        .sheet(isPresented: $showAddArgument) {
            AddArgumentSheet(vm: vm, parentNodeId: nil)
        }
        .task { await vm.loadOrCreate() }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(Color.purple)
                .scaleEffect(1.3)
            Text("Generating discussion frame...")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.black.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Scroll Content

    private var scrollContent: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 12) {

                // Original post preview
                originalPostCard

                // AI frame badge
                frameTypeBadge

                // Steel-man FOR
                SteelManCardView(
                    label: "Strongest case FOR",
                    text: vm.discussion.aiSteelManFor,
                    tintColor: Color(red: 0.55, green: 0.25, blue: 1.0),
                    isExpanded: $steelForExpanded
                )

                // Steel-man AGAINST
                SteelManCardView(
                    label: "Strongest case AGAINST",
                    text: vm.discussion.aiSteelManAgainst,
                    tintColor: Color(red: 0.96, green: 0.65, blue: 0.14),
                    isExpanded: $steelAgainstExpanded
                )

                // Section header
                sectionHeader

                // View update count pill
                if vm.discussion.viewUpdateCount > 0 {
                    viewUpdatePill
                }

                // Argument tree
                ForEach(vm.rootNodes) { node in
                    ArgumentNodeView(
                        node: node,
                        depth: 0,
                        vm: vm,
                        onReply: { nodeId in
                            replyingToNodeId = nodeId
                            showAddArgument = true
                        }
                    )
                }

                // Bottom padding for FAB
                Color.clear.frame(height: 80)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    // MARK: - Original Post Card

    private var originalPostCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.black.opacity(0.06))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(String(postAuthorName.prefix(1)).uppercased())
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.black.opacity(0.75))
                    )
                Text(postAuthorName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black.opacity(0.9))
                Spacer()
                Image(systemName: "quote.opening")
                    .font(.system(size: 12))
                    .foregroundColor(Color.purple.opacity(0.55))
            }
            Text(postText)
                .font(.system(size: 14))
                .foregroundColor(.black.opacity(0.7))
                .lineLimit(3)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(0.86), location: 0.0),
                                    .init(color: Color.white.opacity(0.70), location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.8)
                )
        )
    }

    // MARK: - Frame Type Badge

    private var frameTypeBadge: some View {
        let label: String
        let color: Color
        switch vm.discussion.aiFactualVsValues {
        case "factual":
            label = "Factual Disagreement"
            color = Color(red: 0.24, green: 0.71, blue: 0.96)
        case "values":
            label = "Values Disagreement"
            color = Color(red: 0.96, green: 0.42, blue: 0.42)
        default:
            label = "Factual + Values"
            color = Color(red: 0.55, green: 0.25, blue: 1.0)
        }

        return HStack(spacing: 6) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(color.opacity(0.13))
                .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 1))
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Section Header

    private var sectionHeader: some View {
        HStack {
            Text("Discussion")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.black)
            Text("(\(vm.nodes.count) arguments)")
                .font(.system(size: 14))
                .foregroundColor(.black.opacity(0.45))
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: - View Update Pill

    private var viewUpdatePill: some View {
        HStack(spacing: 5) {
            Text("↺")
                .font(.system(size: 13))
            Text("\(vm.discussion.viewUpdateCount) \(vm.discussion.viewUpdateCount == 1 ? "person" : "people") changed their view")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(Color(red: 0.20, green: 0.65, blue: 0.40))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(red: 0.20, green: 0.65, blue: 0.40).opacity(0.12))
                .overlay(Capsule().strokeBorder(Color(red: 0.20, green: 0.65, blue: 0.40).opacity(0.25), lineWidth: 1))
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - FAB

    private var addViewButton: some View {
        Button {
            replyingToNodeId = nil
            showAddArgument = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                Text("Add Your View")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(.black)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color.white.opacity(0.92), location: 0.0),
                                        .init(color: Color.white.opacity(0.68), location: 1.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.black.opacity(0.10), lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(0.10), radius: 18, x: 0, y: 8)
            )
        }
        .padding(.trailing, 20)
        .padding(.bottom, 24)
        .transition(.scale.combined(with: .opacity))
    }
}
