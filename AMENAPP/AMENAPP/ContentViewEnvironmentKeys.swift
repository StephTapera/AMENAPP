import SwiftUI

// MARK: - Environment Key for Tab Bar Visibility

struct TabBarVisibleKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(true)
}

extension EnvironmentValues {
    var tabBarVisible: Binding<Bool> {
        get { self[TabBarVisibleKey.self] }
        set { self[TabBarVisibleKey.self] = newValue }
    }
}

// MARK: - Environment Key for Main Tab Selection
struct MainTabSelectionKey: EnvironmentKey {
    static let defaultValue: Binding<Int> = .constant(0)
}

extension EnvironmentValues {
    var mainTabSelection: Binding<Int> {
        get { self[MainTabSelectionKey.self] }
        set { self[MainTabSelectionKey.self] = newValue }
    }
}

// P0 FIX: Using existing ScrollOffsetPreferenceKey from PeopleDiscoveryView
// (No need to redefine - already exists globally)

// P0 FIX: Removed UIView.findScrollView extension - no longer needed with PreferenceKey approach
