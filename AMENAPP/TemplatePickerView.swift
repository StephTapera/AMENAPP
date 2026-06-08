// TemplatePickerView.swift
// AMEN Creator — Template Picker
// Living template selection with category filtering

import SwiftUI

struct TemplatePickerView: View {
    @ObservedObject var vm: SceneBuilderViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: CreationTemplateCategory?

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var filteredTemplates: [CreationTemplate] {
        guard let cat = selectedCategory else { return CreationTemplate.systemTemplates }
        return CreationTemplate.systemTemplates.filter { $0.category == cat }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        // All
                        CategoryFilterChip(
                            label: "All",
                            icon: "sparkles",
                            color: .black,
                            isSelected: selectedCategory == nil
                        ) {
                            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
                                selectedCategory = nil
                            }
                        }

                        ForEach(CreationTemplateCategory.allCases) { cat in
                            CategoryFilterChip(
                                label: cat.displayName,
                                icon: cat.icon,
                                color: cat.color,
                                isSelected: selectedCategory == cat
                            ) {
                                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
                                    selectedCategory = selectedCategory == cat ? nil : cat
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
                .background(.regularMaterial)

                Divider()

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(filteredTemplates) { template in
                            TemplateCard(
                                template: template,
                                isSelected: vm.selectedTemplate?.id == template.id
                            ) {
                                vm.applyTemplate(template)
                                dismiss()
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Choose Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Template Card

struct TemplateCard: View {
    let template: CreationTemplate
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                // Icon header
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(template.category.color.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: template.iconName)
                            .font(.systemScaled(20))
                            .foregroundStyle(template.category.color)
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.systemScaled(18))
                            .foregroundStyle(template.category.color)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(.custom("OpenSans-Bold", size: 15))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(template.description)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .lineSpacing(2)
                }

                HStack(spacing: 6) {
                    DurationBadge(seconds: template.defaultDuration)

                    if template.supportsScripture {
                        HStack(spacing: 3) {
                            Image(systemName: "book.fill")
                                .font(.systemScaled(9))
                            Text("Scripture")
                                .font(.custom("OpenSans-SemiBold", size: 10))
                        }
                        .foregroundStyle(template.category.color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(template.category.color.opacity(0.1)))
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(
                                isSelected ? template.category.color.opacity(0.6) : Color.black.opacity(0.08),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75)), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Category Filter Chip

struct CategoryFilterChip: View {
    let label: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.systemScaled(12, weight: .medium))
                Text(label)
                    .font(.custom("OpenSans-SemiBold", size: 13))
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? color : Color.clear)
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                isSelected ? Color.clear : Color.black.opacity(0.15),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
