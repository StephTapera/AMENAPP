# Package Dependencies for AMENAPP

## Required Dependencies

Add these to your Xcode project via **File → Add Package Dependencies**:

### 1. Algolia Search Client
```
https://github.com/algolia/algoliasearch-client-swift
```
**Version:** 8.0.0 or later
**Required for:** User search, post search, autocomplete

---

### 2. Firebase iOS SDK
```
https://github.com/firebase/firebase-ios-sdk
```
**Version:** 10.0.0 or later
**Products to add:**
- FirebaseAuth
- FirebaseFirestore
- FirebaseStorage
- FirebaseAnalytics (optional)

---

## Package.swift (if using SPM)

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AMENAPP",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "AMENAPP",
            targets: ["AMENAPP"]
        ),
    ],
    dependencies: [
        // Firebase
        .package(
            url: "https://github.com/firebase/firebase-ios-sdk",
            from: "10.0.0"
        ),
        // Algolia
        .package(
            url: "https://github.com/algolia/algoliasearch-client-swift",
            from: "8.0.0"
        ),
    ],
    targets: [
        .target(
            name: "AMENAPP",
            dependencies: [
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseStorage", package: "firebase-ios-sdk"),
                .product(name: "AlgoliaSearchClient", package: "algoliasearch-client-swift"),
            ]
        ),
    ]
)
```

---

## Import Statements

Add these to files that use search:

```swift
// For Algolia search
import AlgoliaSearchClient

// For Firebase
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
```

---

## Troubleshooting Dependencies

### "No such module 'AlgoliaSearchClient'"
1. Clean build folder: **Cmd + Shift + K**
2. Delete derived data
3. Restart Xcode
4. Rebuild project

### Version conflicts
If you get dependency resolution errors:
1. Update all packages to latest versions
2. Reset package caches: **File → Packages → Reset Package Caches**
3. Update Swift tools version in Package.swift

---

## Minimum Deployment Target

- **iOS 17.0+** (for SwiftUI features)
- **Swift 5.9+**
- **Xcode 15.0+**
