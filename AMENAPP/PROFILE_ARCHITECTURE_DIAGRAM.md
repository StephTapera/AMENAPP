# Profile System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            PROFILE VIEW SYSTEM                               │
│                         Complete Backend Architecture                        │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                              PRESENTATION LAYER                              │
└─────────────────────────────────────────────────────────────────────────────┘

                            ┌──────────────────┐
                            │  ProfileView.swift │
                            │                   │
                            │  @State vars:     │
                            │  - profileData    │
                            │  - userPosts      │
                            │  - savedPosts     │
                            │  - reposts        │
                            │  - userReplies    │
                            └──────────────────┘
                                     │
                ┌────────────────────┼────────────────────┐
                │                    │                    │
       ┌────────▼────────┐  ┌───────▼────────┐  ┌───────▼────────┐
       │ EditProfileView │  │  SettingsView  │  │  QR Code View  │
       │                 │  │                │  │                │
       │ - Name/Bio Edit │  │ - Preferences  │  │ - Share Profile│
       │ - Avatar Upload │  │ - Security     │  │                │
       │ - Interests     │  │ - Notifications│  │                │
       │ - Social Links  │  │                │  │                │
       └─────────────────┘  └────────────────┘  └────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                             BUSINESS LOGIC LAYER                             │
└─────────────────────────────────────────────────────────────────────────────┘

              ┌──────────────────────────────────────────┐
              │          SERVICE LAYER (7 Services)       │
              └──────────────────────────────────────────┘
                              │
         ┌────────────────────┼────────────────────┐
         │                    │                    │
┌────────▼─────────┐  ┌───────▼────────┐  ┌──────▼──────────┐
│  UserService     │  │ SocialLinks    │  │ FirebaseManager │
│  ✅ IMPLEMENTED   │  │ Service        │  │ ✅ IMPLEMENTED  │
│                  │  │ ✅ IMPLEMENTED  │  │                 │
│ • fetchUser()    │  │                │  │ • auth          │
│ • updateProfile()│  │ • addLink()    │  │ • firestore     │
│ • uploadImage()  │  │ • removeLink() │  │ • storage       │
│ • saveInterests()│  │ • validate()   │  │ • uploadImage() │
│ • updateSettings│  │ • fetchLinks() │  │ • CRUD ops      │
└──────────────────┘  └────────────────┘  └─────────────────┘

         │                    │                    │
         └────────────────────┼────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              │    REALTIME DATABASE SERVICES  │
              └───────────────────────────────┘
                              │
         ┌────────────────────┼────────────────────┐
         │                    │                    │
┌────────▼─────────┐  ┌───────▼────────┐  ┌──────▼──────────┐
│ RealtimePost     │  │ RealtimeSaved  │  │ RealtimeReposts │
│ Service          │  │ PostsService   │  │ Service         │
│ ✅ IMPLEMENTED    │  │ ✅ IMPLEMENTED  │  │ ✅ IMPLEMENTED   │
│                  │  │                │  │                 │
│ • fetchPosts()   │  │ • toggleSave() │  │ • repostPost()  │
│ • createPost()   │  │ • fetchSaved() │  │ • undoRepost()  │
│ • observePosts() │  │ • observeSaved()│  │ • fetchReposts()│
│ • deletePost()   │  │ • isPostSaved()│  │ • observeReposts│
└──────────────────┘  └────────────────┘  └─────────────────┘

                              │
                    ┌─────────▼─────────┐
                    │ RealtimeComments  │
                    │ Service           │
                    │ ✅ IMPLEMENTED     │
                    │                   │
                    │ • createComment() │
                    │ • fetchComments() │
                    │ • fetchUserComments│
                    │ • deleteComment() │
                    │ • observeComments()│
                    └───────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                               DATA LAYER                                     │
└─────────────────────────────────────────────────────────────────────────────┘

              ┌──────────────────────────────────────────┐
              │           FIREBASE BACKEND               │
              └──────────────────────────────────────────┘
                              │
         ┌────────────────────┼────────────────────┐
         │                    │                    │
┌────────▼─────────┐  ┌───────▼────────┐  ┌──────▼──────────┐
│   FIRESTORE      │  │ REALTIME DB    │  │ FIREBASE STORAGE│
│                  │  │                │  │                 │
│ /users/{userId}  │  │ /posts         │  │ /profile_images/│
│                  │  │ /user_posts    │  │   {userId}/     │
│ - displayName    │  │ /post_stats    │  │   profile.jpg   │
│ - username       │  │ /comments      │  │                 │
│ - bio            │  │ /user_comments │  │ • Upload avatar │
│ - initials       │  │ /user_saved    │  │ • Get download  │
│ - profileImageURL│  │   _posts       │  │   URL           │
│ - interests[]    │  │ /user-reposts  │  │ • Delete image  │
│ - socialLinks[]  │  │ /post-reposts  │  │                 │
│ - settings{}     │  │                │  │                 │
│ - createdAt      │  │ Real-time sync!│  │ CDN delivery!   │
│ - updatedAt      │  │                │  │                 │
└──────────────────┘  └────────────────┘  └─────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                           DATA FLOW PATTERNS                                 │
└─────────────────────────────────────────────────────────────────────────────┘

╔═══════════════════════════════════════════════════════════════════════════╗
║                        1. PROFILE LOADING FLOW                            ║
╚═══════════════════════════════════════════════════════════════════════════╝

ProfileView.onAppear()
        │
        ├──► UserService.fetchCurrentUser()
        │         │
        │         └──► Firestore /users/{userId}
        │                   │
        │                   └──► Returns User model
        │                         │
        │                         └──► Updates @Published currentUser
        │                               │
        │                               └──► UI updates automatically
        │
        ├──► RealtimePostService.fetchUserPosts()
        │         │
        │         └──► Realtime DB /user_posts/{userId}
        │                   │
        │                   └──► Fetch each post from /posts/{postId}
        │                         │
        │                         └──► Returns [Post]
        │                               │
        │                               └──► Updates @State userPosts
        │
        ├──► RealtimeSavedPostsService.fetchSavedPosts()
        │         │
        │         └──► Realtime DB /user_saved_posts/{userId}
        │                   │
        │                   └──► Returns [Post]
        │                         │
        │                         └──► Updates @State savedPosts
        │
        ├──► RealtimeRepostsService.fetchUserReposts()
        │         │
        │         └──► Realtime DB /user-reposts/{userId}
        │                   │
        │                   └──► Returns [Post]
        │                         │
        │                         └──► Updates @State reposts
        │
        └──► RealtimeCommentsService.fetchUserComments()
                  │
                  └──► Realtime DB /user_comments/{userId}
                        │
                        └──► Returns [Comment]
                              │
                              └──► Updates @State userReplies

╔═══════════════════════════════════════════════════════════════════════════╗
║                      2. PROFILE UPDATE FLOW                               ║
╚═══════════════════════════════════════════════════════════════════════════╝

EditProfileView.saveProfile()
        │
        ├──► Validate input (name length, bio length, etc.)
        │         │
        │         └──► If invalid → Show error
        │
        ├──► UserService.updateProfile(displayName, bio)
        │         │
        │         ├──► Generate new initials from name
        │         ├──► Create search keywords
        │         │
        │         └──► Firestore.updateData()
        │                   │
        │                   ├──► /users/{userId} updated
        │                   │
        │                   ├──► Cache to UserDefaults
        │                   │         (for fast post creation)
        │                   │
        │                   └──► @Published currentUser updates
        │                             │
        │                             └──► UI refreshes
        │
        ├──► UserService.saveOnboardingPreferences()
        │         │
        │         └──► Firestore.updateData()
        │                   │
        │                   └──► interests[] saved
        │
        ├──► SocialLinksService.updateSocialLinks()
        │         │
        │         └──► Firestore.updateData()
        │                   │
        │                   └──► socialLinks[] saved
        │
        └──► Success haptic feedback → Dismiss sheet

╔═══════════════════════════════════════════════════════════════════════════╗
║                      3. AVATAR UPLOAD FLOW                                ║
╚═══════════════════════════════════════════════════════════════════════════╝

PhotosPicker selects image
        │
        └──► UIImage loaded
              │
              └──► UserService.uploadProfileImage(image)
                    │
                    ├──► Compress to JPEG (70% quality)
                    │
                    ├──► Storage.putDataAsync()
                    │         │
                    │         └──► Upload to /profile_images/{userId}/profile.jpg
                    │               │
                    │               └──► Returns download URL
                    │
                    ├──► Firestore.updateData()
                    │         │
                    │         └──► profileImageURL = downloadURL
                    │
                    ├──► Cache URL to UserDefaults
                    │
                    ├──► Update @Published currentUser
                    │
                    └──► UI shows new avatar instantly

╔═══════════════════════════════════════════════════════════════════════════╗
║                   4. REAL-TIME SYNC PATTERN                               ║
╚═══════════════════════════════════════════════════════════════════════════╝

ProfileView sets up listeners:

RealtimePostService.observeUserPosts(userId) { posts in
    @MainActor
    self.userPosts = posts  ◄── Auto-updates when posts change
}

RealtimeSavedPostsService.observeSavedPosts { postIds in
    @MainActor
    // Fetch full posts and update
}

RealtimeRepostsService.observeUserReposts(userId) { posts in
    @MainActor
    self.reposts = posts  ◄── Auto-updates when reposts change
}

Firebase Realtime Database:
    .observe(.value) { snapshot in
        // Parse data
        // Call completion handler
        // UI updates automatically
    }

Benefits:
    ✅ Instant updates across devices
    ✅ Battery efficient
    ✅ Auto-reconnects on network change
    ✅ No polling needed

┌─────────────────────────────────────────────────────────────────────────────┐
│                        PERFORMANCE OPTIMIZATIONS                             │
└─────────────────────────────────────────────────────────────────────────────┘

╔═══════════════════════════════════════════════════════════════════════════╗
║                       1. UserDefaults Cache                               ║
╚═══════════════════════════════════════════════════════════════════════════╝

When profile updates:
    └──► Cache to UserDefaults:
          • currentUserDisplayName
          • currentUserUsername
          • currentUserInitials
          • currentUserProfileImageURL

When creating post:
    └──► Read from UserDefaults (INSTANT)
          No Firestore read needed!
          Saves read costs + latency

╔═══════════════════════════════════════════════════════════════════════════╗
║                      2. Listener Persistence                              ║
╚═══════════════════════════════════════════════════════════════════════════╝

ProfileView.onAppear():
    if !listenersActive {
        setupListeners()
        listenersActive = true
    }

ProfileView.onDisappear():
    // DON'T remove listeners
    // Keep data persistent for tab switching
    // Real-time updates continue in background

Result:
    ✅ No reload on tab switch
    ✅ Data stays fresh
    ✅ Smooth UX

╔═══════════════════════════════════════════════════════════════════════════╗
║                      3. Optimistic Updates                                ║
╚═══════════════════════════════════════════════════════════════════════════╝

User creates post:
    1. Add to userPosts[] IMMEDIATELY
       └──► UI updates instantly (optimistic)
    
    2. Send to Firebase
       └──► If success: Already in UI ✓
       └──► If fail: Remove from UI + show error

User saves post:
    1. Add to savedPosts[] IMMEDIATELY
    2. Toggle Firebase in background
    3. Listener confirms later

Result:
    ✅ Instant UI feedback
    ✅ Perceived performance boost
    ✅ Better UX

╔═══════════════════════════════════════════════════════════════════════════╗
║                      4. Batch Operations                                  ║
╚═══════════════════════════════════════════════════════════════════════════╝

Creating a post:

❌ BAD (3 separate writes):
    database.child("posts").child(postId).setValue(...)
    database.child("user_posts").child(userId).setValue(...)
    database.child("post_stats").child(postId).setValue(...)

✅ GOOD (1 atomic write):
    let updates = [
        "/posts/\(postId)": postData,
        "/user_posts/\(userId)/\(postId)": timestamp,
        "/post_stats/\(postId)": statsData
    ]
    database.updateChildValues(updates)

Benefits:
    ✅ Atomic (all or nothing)
    ✅ Fewer network requests
    ✅ Consistent data
    ✅ Better performance

┌─────────────────────────────────────────────────────────────────────────────┐
│                         NOTIFICATION SYSTEM                                  │
└─────────────────────────────────────────────────────────────────────────────┘

NotificationCenter events for cross-view updates:

.newPostCreated
    └──► ProfileView adds to userPosts[]

.postDeleted
    └──► ProfileView removes from all arrays

.postSaved
    └──► ProfileView adds to savedPosts[]

.postUnsaved
    └──► ProfileView removes from savedPosts[]

.postReposted
    └──► ProfileView adds to reposts[]

Pattern:
    Service performs action
         │
         └──► NotificationCenter.post()
                   │
                   └──► ProfileView.onReceive()
                             │
                             └──► Update UI

┌─────────────────────────────────────────────────────────────────────────────┐
│                          ERROR HANDLING                                      │
└─────────────────────────────────────────────────────────────────────────────┘

Service Layer:
    do {
        try await operation()
    } catch FirebaseError.unauthorized {
        throw "Not signed in"
    } catch FirebaseError.documentNotFound {
        throw "Data not found"
    } catch {
        throw error
    }

View Layer:
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""

    Task {
        isSaving = true
        do {
            try await service.save()
            // Success haptic
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            // Error haptic
        }
        isSaving = false
    }

┌─────────────────────────────────────────────────────────────────────────────┐
│                         SUMMARY: WHAT'S IMPLEMENTED                          │
└─────────────────────────────────────────────────────────────────────────────┘

✅ SERVICES (7 total)
   1. UserService - Profile management
   2. SocialLinksService - Social media links
   3. FirebaseManager - Centralized Firebase access
   4. RealtimePostService - Post CRUD + real-time
   5. RealtimeSavedPostsService - Saved posts
   6. RealtimeRepostsService - Reposts
   7. RealtimeCommentsService - Comments/replies

✅ DATA LAYER
   • Firestore - User profiles, settings
   • Realtime Database - Posts, comments, interactions
   • Firebase Storage - Profile images

✅ FEATURES
   • Load profile from Firestore
   • Update name, bio, interests
   • Upload/remove avatar
   • Manage social links
   • Display posts, saved, reposts, replies
   • Real-time synchronization
   • Optimistic updates
   • Error handling
   • Performance optimization

✅ READY FOR PRODUCTION
   All backend services implemented and tested!

┌─────────────────────────────────────────────────────────────────────────────┐
│                         END OF ARCHITECTURE DIAGRAM                          │
└─────────────────────────────────────────────────────────────────────────────┘
```
