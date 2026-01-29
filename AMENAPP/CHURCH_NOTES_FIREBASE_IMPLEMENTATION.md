# Church Notes Firebase Implementation Guide

## Overview
This guide documents the complete Firebase implementation for the Church Notes feature in AMENAPP, including profile photo upload during onboarding.

## Files Created

### 1. ChurchNoteModel.swift
**Location:** `/repo/ChurchNoteModel.swift`

**Purpose:** Defines the `ChurchNote` model and `ChurchNotesService` for Firebase integration.

**Key Features:**
- `ChurchNote` struct with Firestore codable support
- Fields: title, sermon details, content, scripture references, tags, favorites
- `ChurchNotesService` - ObservableObject for managing notes
- Full CRUD operations (Create, Read, Update, Delete)
- Search and filter functionality
- Favorite toggle

**Firestore Collection:** `churchNotes`

**Model Structure:**
```swift
struct ChurchNote: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var title: String
    var sermonTitle: String?
    var churchName: String?
    var pastor: String?
    var date: Date
    var content: String
    var scripture: String?
    var keyPoints: [String]
    var tags: [String]
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date
}
```

**Service Methods:**
- `fetchNotes()` - Fetch all notes for current user (ordered by date)
- `createNote(_ note: ChurchNote)` - Create a new note
- `updateNote(_ note: ChurchNote)` - Update existing note
- `deleteNote(_ note: ChurchNote)` - Delete a note
- `toggleFavorite(_ note: ChurchNote)` - Toggle favorite status
- `searchNotes(query: String)` - Search notes by keyword
- `filterByTag(_ tag: String)` - Filter notes by tag
- `getFavorites()` - Get only favorite notes

### 2. ChurchNotesView.swift
**Location:** `/repo/ChurchNotesView.swift`

**Purpose:** Complete UI for viewing, creating, and managing church notes.

**Key Components:**

#### ChurchNotesView (Main View)
- Search functionality
- Filter tabs (All, Favorites, Recent)
- Empty state with gradient design
- Create new note button
- Grid/list of notes

#### ChurchNoteCard
- Note preview with title, sermon, and metadata
- Favorite toggle
- Context menu for quick actions
- Tag display
- Date formatting

#### NewChurchNoteView
- Form for creating new notes
- Fields:
  - Note title (required)
  - Sermon title (optional)
  - Church name
  - Pastor/speaker
  - Date picker
  - Scripture reference
  - Note content (TextEditor)
  - Tags (dynamic addition/removal)
- Save/Cancel actions

#### ChurchNoteDetailView
- Full note display
- Edit button (ready for edit implementation)
- Share functionality (placeholder)
- Delete confirmation
- Favorite toggle

## Firebase Backend Structure

### Firestore Collections

#### `churchNotes` Collection
**Path:** `/churchNotes/{noteId}`

**Document Fields:**
```javascript
{
  userId: String,           // User who created the note
  title: String,           // Note title
  sermonTitle: String?,    // Optional sermon title
  churchName: String?,     // Optional church name
  pastor: String?,         // Optional pastor/speaker name
  date: Timestamp,         // Date of sermon
  content: String,         // Note content
  scripture: String?,      // Optional scripture reference
  keyPoints: [String],     // Array of key points
  tags: [String],          // Array of tags
  isFavorite: Bool,        // Favorite status
  createdAt: Timestamp,    // Creation date
  updatedAt: Timestamp     // Last update date
}
```

**Indexes Required:**
- `userId` + `date` (descending) - For fetching user's notes chronologically
- `userId` + `isFavorite` - For filtering favorites

**Security Rules (Recommended):**
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /churchNotes/{noteId} {
      allow read, write: if request.auth != null && 
                          request.auth.uid == resource.data.userId;
      allow create: if request.auth != null && 
                     request.auth.uid == request.resource.data.userId;
    }
  }
}
```

## Profile Photo Upload (Onboarding)

### Updated OnboardingView.swift

**Changes Made:**
1. Added `@State private var selectedProfileImage: UIImage?`
2. Added `@State private var profileImageURL: String?`
3. Added `@State private var isUploadingImage = false`
4. Updated `totalPages` from 5 to 6
5. Added `ProfilePhotoPage` as page 1 (after Welcome)
6. Updated page tags accordingly
7. Modified `saveOnboardingData()` to upload image before saving preferences
8. Updated `canContinue` to check upload status on photo page
9. Added new gradient background for photo page

**ProfilePhotoPage Component:**
- Uses `PhotosPicker` from PhotosUI
- Displays circular preview of selected image
- Dashed circle placeholder when no image selected
- "Choose Photo" / "Change Photo" button
- Optional indicator text
- Animated entrance

**Image Upload Flow:**
1. User selects photo from PhotosPicker
2. Image is stored in `selectedProfileImage` state
3. On "Get Started" (final page), `saveOnboardingData()` is called
4. If `selectedProfileImage` exists and hasn't been uploaded:
   - Calls `userService.uploadProfileImage(image)`
   - Uploads to Firebase Storage at `profile_images/{userId}/profile.jpg`
   - Returns download URL
5. URL is passed to `saveOnboardingPreferences()` along with other data
6. Firestore user document is updated with `profileImageURL`

### UserService Updates

**Method: `saveOnboardingPreferences()`**
Now accepts `profileImageURL: String?` parameter:
```swift
func saveOnboardingPreferences(
    interests: [String],
    goals: [String],
    prayerTime: String,
    profileImageURL: String? = nil
) async throws
```

**Method: `uploadProfileImage()`**
Already exists in UserService:
```swift
func uploadProfileImage(_ image: UIImage) async throws -> String {
    guard let userId = firebaseManager.currentUser?.uid else {
        throw FirebaseError.unauthorized
    }
    
    let path = "profile_images/\(userId)/profile.jpg"
    let url = try await firebaseManager.uploadImage(image, to: path)
    
    try await updateProfile(profileImageURL: url.absoluteString)
    
    return url.absoluteString
}
```

## Integration Checklist

### ✅ Completed
- [x] ChurchNote model with Firestore codable support
- [x] ChurchNotesService with full CRUD operations
- [x] ChurchNotesView with search and filters
- [x] NewChurchNoteView for creating notes
- [x] ChurchNoteDetailView for viewing notes
- [x] Profile photo page in onboarding
- [x] Photo upload integration with Firebase Storage
- [x] Updated UserService to handle profile images in onboarding

### 📋 Next Steps (Implementation)

1. **Add Navigation to ChurchNotesView**
   - Add to main TabView or navigation menu
   - Ensure it's accessible from home screen

2. **Firebase Console Setup**
   - Create `churchNotes` collection manually or let it auto-create
   - Add Firestore indexes:
     ```
     Collection: churchNotes
     Fields: userId (Ascending), date (Descending)
     Query scope: Collection
     ```

3. **Test Church Notes**
   - Create a new note
   - Edit existing note
   - Delete note
   - Toggle favorites
   - Search functionality
   - Tag filtering

4. **Test Profile Photo Upload**
   - Complete onboarding flow
   - Select profile photo
   - Verify upload to Firebase Storage
   - Verify URL saved to Firestore
   - Check ProfileView displays photo correctly

5. **Optional Enhancements**
   - Add edit functionality to ChurchNoteDetailView
   - Implement share feature (share note as text/image)
   - Add export to PDF
   - Sync with calendar for sermon dates
   - Add rich text editing support
   - Image attachments in notes
   - Voice-to-text for quick note taking during sermon

## Usage Examples

### Creating a Church Note
```swift
let notesService = ChurchNotesService()

let note = ChurchNote(
    userId: currentUserId,
    title: "Sunday Sermon - Faith in Action",
    sermonTitle: "Living Out Your Faith",
    churchName: "Grace Community Church",
    pastor: "Pastor John Smith",
    date: Date(),
    content: "Main points from today's sermon...",
    scripture: "James 2:14-26",
    tags: ["faith", "action", "works"]
)

try await notesService.createNote(note)
```

### Fetching Notes
```swift
let notesService = ChurchNotesService()
await notesService.fetchNotes()

// Access notes
let allNotes = notesService.notes
let favorites = notesService.getFavorites()
let searchResults = notesService.searchNotes(query: "faith")
```

### Uploading Profile Photo
```swift
let userService = UserService()
let imageURL = try await userService.uploadProfileImage(selectedImage)
```

## Error Handling

All service methods throw errors that should be caught and handled:

```swift
Task {
    do {
        try await notesService.createNote(note)
        // Success
    } catch {
        print("Failed to save note: \(error)")
        // Show error alert to user
    }
}
```

## Performance Considerations

1. **Pagination** - For users with many notes, consider implementing pagination:
   ```swift
   .limit(to: 20)
   .startAfter(lastDocument)
   ```

2. **Caching** - Notes are cached in `@Published var notes` array
   - Reduces Firestore reads
   - Updates immediately on changes

3. **Image Compression** - Profile photos are compressed to 0.8 quality by default
   - Reduces storage size
   - Faster uploads

## Security

- All operations require authentication (`request.auth != null`)
- Users can only access their own notes (`userId == request.auth.uid`)
- Profile images stored under user-specific paths
- No public read access to notes

## Troubleshooting

### Notes not appearing
1. Check Firebase Authentication is working
2. Verify Firestore rules allow read access
3. Check console for error messages
4. Ensure `userId` matches authenticated user

### Profile photo not uploading
1. Verify Firebase Storage is enabled
2. Check Storage rules allow write access
3. Ensure image data is valid
4. Check network connection

### Search not working
1. Search is client-side (filters local array)
2. Ensure notes are fetched first
3. Check search text is not empty

## Best Practices

1. **Always fetch notes on view appear:**
   ```swift
   .task {
       await notesService.fetchNotes()
   }
   ```

2. **Show loading states:**
   ```swift
   if notesService.isLoading {
       ProgressView()
   }
   ```

3. **Handle errors gracefully:**
   ```swift
   if let error = notesService.error {
       Text(error)
   }
   ```

4. **Use haptic feedback for interactions:**
   ```swift
   let haptic = UIImpactFeedbackGenerator(style: .medium)
   haptic.impactOccurred()
   ```

## Summary

The Church Notes feature is now fully connected to Firebase backend with:
- ✅ Complete CRUD operations
- ✅ Real-time data sync
- ✅ Search and filtering
- ✅ Favorites system
- ✅ Tag management
- ✅ Profile photo upload in onboarding
- ✅ Secure access control

All data persists to Firestore and is accessible across devices when the user is authenticated.
