# AMEN App Architecture

## Overview
This app follows the **MVVM (Model-View-ViewModel)** architecture pattern, which separates concerns into three main layers:

- **Models**: Data structures and business logic
- **Views**: UI components (SwiftUI views)
- **ViewModels**: State management and coordination between Models and Views

## Project Structure

```
AMENAPP/
├── Models/
│   ├── User.swift              # User data model
│   ├── Post.swift              # Post data model with actions
│   └── TrendingTopic.swift     # Trending topic data model
│
├── ViewModels/
│   ├── ContentViewModel.swift  # Main app state (tab selection, auth)
│   └── HomeViewModel.swift     # Home feed state and logic
│
├── Views/
│   ├── ContentView.swift       # Main tab view container
│   └── Components/             # Reusable UI components
│       ├── PostCard.swift
│       ├── CategoryPill.swift
│       ├── CommunityCard.swift
│       └── TrendingCard.swift
│
└── Services/
    └── PostService.swift       # API calls for posts
```

## Architecture Patterns

### ViewModels
ViewModels are `@MainActor` classes that conform to `ObservableObject`. They:
- Hold `@Published` properties for state
- Expose methods for user actions
- Coordinate with Services for data fetching
- Handle business logic

**Example:**
```swift
@MainActor
class HomeViewModel: ObservableObject {
    @Published var posts: [Post] = []
    @Published var isLoading = false
    
    func loadPosts() async {
        isLoading = true
        posts = await PostService.shared.fetchPosts()
        isLoading = false
    }
}
```

### Views
Views are pure SwiftUI and focus only on:
- Displaying data from ViewModels
- Handling user interactions by calling ViewModel methods
- UI layout and styling

**Example:**
```swift
struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    
    var body: some View {
        List(viewModel.posts) { post in
            PostCard(post: post)
        }
        .task {
            await viewModel.loadPosts()
        }
    }
}
```

### Models
Models are simple Swift structs/classes that:
- Conform to `Codable` for API serialization
- Conform to `Identifiable` for SwiftUI lists
- Are immutable (use methods to return new instances for changes)

### Services
Services are `actor` types (for thread-safety) that:
- Handle all network communication
- Abstract away API details
- Are accessed via singleton pattern (`shared`)
- Use async/await for all operations

## Data Flow

1. **User Interaction** → View captures event
2. **View** → Calls ViewModel method
3. **ViewModel** → Calls Service to fetch/update data
4. **Service** → Makes API call
5. **Service** → Returns data to ViewModel
6. **ViewModel** → Updates `@Published` properties
7. **View** → Automatically re-renders with new data

## Key Features

### State Management
- `@StateObject`: For ViewModel lifecycle tied to View
- `@Published`: For properties that trigger View updates
- `@State`: For local View-only state (animations, toggles)

### Async Operations
- All network calls use `async/await`
- ViewModels use `Task {}` to call async functions
- Views use `.task {}` modifier for lifecycle-based async work

### Error Handling
- Services throw typed errors (`PostServiceError`)
- ViewModels catch errors and expose as `@Published` properties
- Views display error states to users

## Next Steps for Backend Integration

### 1. Update PostService.swift
Replace mock implementations with real API calls:
```swift
func fetchPosts(category: String) async throws -> [Post] {
    let url = URL(string: "\(baseURL)/posts?category=\(category)")!
    let (data, _) = try await URLSession.shared.data(from: url)
    return try JSONDecoder().decode([Post].self, from: data)
}
```

### 2. Add Authentication Service
```swift
actor AuthService {
    static let shared = AuthService()
    
    func signIn(email: String, password: String) async throws -> User
    func signOut() async throws
    func getCurrentUser() async -> User?
}
```

### 3. Update ViewModels to Use Services
```swift
func loadPosts() async {
    isLoadingPosts = true
    do {
        posts = try await PostService.shared.fetchPosts(category: selectedCategory)
    } catch {
        errorMessage = error.localizedDescription
    }
    isLoadingPosts = false
}
```

## Testing Strategy

### Unit Tests
Test ViewModels and Services:
```swift
@Test("Load posts updates published property")
func testLoadPosts() async throws {
    let viewModel = HomeViewModel()
    await viewModel.loadPosts()
    #expect(viewModel.posts.isEmpty == false)
}
```

### UI Tests
Test Views and user flows using Swift Testing or XCTest UI.

## Best Practices

1. **Keep Views Dumb**: No business logic in Views
2. **ViewModels Don't Know About Views**: No `import SwiftUI` in ViewModels
3. **Services Are Thread-Safe**: Use `actor` for Services
4. **Immutable Models**: Use functional updates instead of mutations
5. **Async All The Way**: No callbacks, use async/await
6. **Error Handling**: Always handle errors gracefully
7. **Mock Data During Development**: Helps with UI iteration without backend

## Dependencies

- **SwiftUI**: UI framework
- **Combine**: For `@Published` and `ObservableObject`
- **Foundation**: For networking and data models

No third-party dependencies currently used.
