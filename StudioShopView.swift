// StudioShopView.swift
// AMEN Studio — Digital Products Shop

import SwiftUI

struct StudioShopView: View {
    let products: [StudioProduct]
    let creatorId: String
    let isOwnProfile: Bool

    @State private var selectedProduct: StudioProduct?
    @State private var showAddProduct = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if products.isEmpty {
                emptyShopState
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(products) { product in
                        StudioProductCard(product: product)
                            .onTapGesture { selectedProduct = product }
                    }
                }
                .padding(.horizontal, 16)
            }

            if isOwnProfile {
                Button {
                    showAddProduct = true
                } label: {
                    Label("Add a Product", systemImage: "plus.circle.fill")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundStyle(Color(red: 0.55, green: 0.25, blue: 0.88))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Color(red: 0.55, green: 0.25, blue: 0.88).opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color(red: 0.55, green: 0.25, blue: 0.88).opacity(0.2), lineWidth: 1)
                        )
                }
                .buttonStyle(.liquidGlass)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
        .padding(.top, 16)
        .sheet(item: $selectedProduct) { product in
            StudioProductDetailView(product: product, creatorId: creatorId, isOwnProfile: isOwnProfile)
        }
        .sheet(isPresented: $showAddProduct) {
            StudioAddProductView()
        }
    }

    @ViewBuilder
    private var emptyShopState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bag.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(isOwnProfile ? "Add digital products" : "No products yet")
                .font(.custom("OpenSans-SemiBold", size: 16))
            if isOwnProfile {
                Text("Sell templates, devotionals, resources, and more.")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(48)
    }
}

// MARK: - Product Card

struct StudioProductCard: View {
    let product: StudioProduct

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Cover image
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(product.category.color.opacity(0.15))
                    .frame(width: 64, height: 64)
                if let coverURL = product.coverImageURL, let url = URL(string: coverURL) {
                    CachedAsyncImage(url: url) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Image(systemName: product.category.icon)
                            .font(.system(size: 24))
                            .foregroundStyle(product.category.color)
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Image(systemName: product.category.icon)
                        .font(.system(size: 24))
                        .foregroundStyle(product.category.color)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(product.title)
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    productPriceTag
                }

                StudioCategoryChip(category: product.category)

                HStack(spacing: 10) {
                    productMeta(icon: "doc.fill", label: product.fileTypes.joined(separator: ", "))
                    if product.downloadCount > 0 {
                        productMeta(icon: "arrow.down.circle.fill", label: "\(product.downloadCount) downloads")
                    }
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.systemGray4).opacity(0.35), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var productPriceTag: some View {
        if product.isFree {
            Text("Free")
                .font(.custom("OpenSans-Bold", size: 13))
                .foregroundStyle(Color(red: 0.18, green: 0.62, blue: 0.36))
        } else {
            Text(product.price.formatted(.currency(code: product.currency)))
                .font(.custom("OpenSans-Bold", size: 14))
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private func productMeta(icon: String, label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Product Detail View

struct StudioProductDetailView: View {
    let product: StudioProduct
    let creatorId: String
    let isOwnProfile: Bool

    @StateObject private var service = StudioDataService.shared
    @State private var showPurchaseConfirmation = false
    @State private var isPurchasing = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Cover
                    if let coverURL = product.coverImageURL, let url = URL(string: coverURL) {
                        CachedAsyncImage(url: url) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            productHeroPlaceholder
                        }
                        .frame(maxWidth: .infinity, maxHeight: 240)
                        .clipped()
                    } else {
                        productHeroPlaceholder
                            .frame(height: 160)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        // Title and price
                        VStack(alignment: .leading, spacing: 6) {
                            StudioCategoryChip(category: product.category)
                            Text(product.title)
                                .font(.custom("OpenSans-Bold", size: 24))
                            priceSection
                        }

                        Divider()

                        // Description
                        Text(product.description)
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.primary)

                        // File info
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Includes")
                                .font(.custom("OpenSans-Bold", size: 15))
                            HStack(spacing: 10) {
                                ForEach(product.fileTypes, id: \.self) { type in
                                    fileTypeBadge(type)
                                }
                            }
                        }

                        // License
                        VStack(alignment: .leading, spacing: 6) {
                            Text("License")
                                .font(.custom("OpenSans-Bold", size: 15))
                            Text(product.licenseType.label)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(red: 0.15, green: 0.45, blue: 0.90))
                            Text(product.licenseType.description)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }

                        // Version
                        HStack {
                            Text("Version \(product.version)")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if product.downloadCount > 0 {
                                Text("\(product.downloadCount) downloads")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Fee transparency
                        feeTransparencyNote

                        // CTA
                        if !isOwnProfile {
                            purchaseCTA
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private var productHeroPlaceholder: some View {
        ZStack {
            product.category.color.opacity(0.15)
            Image(systemName: product.category.icon)
                .font(.system(size: 48))
                .foregroundStyle(product.category.color)
        }
    }

    @ViewBuilder
    private var priceSection: some View {
        if product.isFree {
            HStack(spacing: 6) {
                Text("Free")
                    .font(.custom("OpenSans-Bold", size: 28))
                    .foregroundStyle(Color(red: 0.18, green: 0.62, blue: 0.36))
                Text("— no cost to download")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.price.formatted(.currency(code: product.currency)))
                    .font(.custom("OpenSans-Bold", size: 28))
                Text("One-time purchase • Instant download")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func fileTypeBadge(_ type: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.fill")
                .font(.system(size: 11))
            Text(type)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(Color(red: 0.15, green: 0.45, blue: 0.90))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(red: 0.15, green: 0.45, blue: 0.90).opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var feeTransparencyNote: some View {
        if !product.isFree {
            let fee = AMENFeeConfig.calculateFee(amount: product.price, type: .productSale)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AMEN Platform Fee")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("A \(Int(AMENFeeConfig.productSaleFeePercent * 100))% platform fee applies (\(fee.fee.formatted(.currency(code: product.currency)))). The creator receives \(fee.net.formatted(.currency(code: product.currency))).")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private var purchaseCTA: some View {
        VStack(spacing: 8) {
            Button {
                showPurchaseConfirmation = true
            } label: {
                HStack {
                    if isPurchasing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(product.isFree ? "Download Free" : "Purchase — \(product.price.formatted(.currency(code: product.currency)))")
                            .font(.custom("OpenSans-Bold", size: 16))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    product.isFree
                        ? Color(red: 0.18, green: 0.62, blue: 0.36)
                        : Color(red: 0.55, green: 0.25, blue: 0.88),
                    in: RoundedRectangle(cornerRadius: 14)
                )
            }
            .buttonStyle(.liquidGlass)
            .disabled(isPurchasing)

            Text(product.refundPolicy.isEmpty ? "All sales final" : product.refundPolicy)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Add Product View

struct StudioAddProductView: View {
    @StateObject private var service = StudioDataService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var category: StudioCategory = .templates
    @State private var description = ""
    @State private var isFree = false
    @State private var price = ""
    @State private var licenseType: ProductLicense = .personal
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Product Info") {
                    TextField("Product Title", text: $title)
                    Picker("Category", selection: $category) {
                        ForEach(StudioCategory.allCases) { cat in
                            Label(cat.label, systemImage: cat.icon).tag(cat)
                        }
                    }
                }
                Section("Description") {
                    TextEditor(text: $description).frame(minHeight: 80)
                }
                Section("Pricing") {
                    Toggle("Free Download", isOn: $isFree)
                    if !isFree {
                        TextField("Price (USD)", text: $price).keyboardType(.decimalPad)
                    }
                }
                Section("License") {
                    Picker("License Type", selection: $licenseType) {
                        ForEach(ProductLicense.allCases, id: \.self) { license in
                            Text(license.label).tag(license)
                        }
                    }
                    Text(licenseType.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(title.isEmpty || isSaving)
                        .font(.custom("OpenSans-SemiBold", size: 15))
                }
            }
        }
    }

    private func save() {
        guard let userId = service.myProfile?.userId else { return }
        isSaving = true
        let product = StudioProduct(
            creatorId: userId,
            title: title,
            category: category,
            description: description,
            previewImageURLs: [],
            fileURLs: [],
            fileTypes: [],
            fileSizeKB: 0,
            price: Double(price) ?? 0.0,
            isFree: isFree,
            currency: "USD",
            version: "1.0",
            downloadCount: 0,
            purchaseCount: 0,
            saveCount: 0,
            refundPolicy: "",
            licenseType: licenseType,
            moderationState: .active,
            isPublished: true,
            searchKeywords: [title.lowercased()],
            tags: [],
            createdAt: Date(),
            updatedAt: Date()
        )
        Task {
            try? await service.saveProduct(product)
            isSaving = false
            dismiss()
        }
    }
}
