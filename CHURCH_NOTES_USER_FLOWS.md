# Church Notes User Flows & Implementation Guide

## Overview
This document explains the complete user flows for Church Notes sharing, discovery, and OpenTable posting.

---

## 🔄 User Flow 1: Creating & Posting to OpenTable

### Step-by-Step Flow:

1. **Create Note**
   - User taps + button in Church Notes
   - Fills in: Title, Sermon Details, Date, Content (rich text), Scripture, Tags
   - Taps checkmark ✓ to save
   - Smart confirmation shows "Note Saved!" → auto-dismisses → back to feed

2. **Post to OpenTable**
   - User opens saved note (tap on note card)
   - Taps ellipsis menu (···) in top right
   - Selects "Share to #OPENTABLE"
   - `ShareNoteToOpenTableSheet` opens with:
     - Text editor for personal commentary
     - Preview of sermon metadata
     - Post/Cancel buttons
   - User adds thoughts and taps "Post"
   - System creates OpenTable post with:
     - User's commentary
     - Full note content and metadata
     - `churchNoteId` linking to original note
   - Success message shows
   - Post appears in OpenTable feed

### Current Implementation:
- **File**: `ChurchNotesView.swift` (lines 2008-2010)
- **Service**: `ChurchNotesShareHelper.shareToCommunit()` (line 207)
- **Post Creation**: Uses `PostsManager.shared.createPost()` with `churchNoteId` field

---

## 👀 User Flow 2: Discovering Church Notes (Current)

### In Church Notes Tab:

#### Filter Options:
1. **For You** (Personalized)
   - Uses `ChurchNotesDiscoveryService` with 7 ranking signals
   - ⚠️ **Current Gap**: User data not integrated (following, church, tags)
   - Shows: Notes ranked by relevance + recency

2. **Recent**
   - Chronological order (newest first)
   - All notes from everyone

3. **Following**
   - Notes from people user follows
   - ⚠️ **Current Gap**: Not connected to FollowService yet

4. **All**
   - All notes sorted by date
   - User's own notes excluded from discovery

5. **Community** (OpenTable Notes)
   - Shows notes that were posted to OpenTable
   - Uses `ElegantChurchNotesFeedForChurchNotesView`
   - Displays with elegant header: "SHARED NOTES / Community Church Notes"
   - Cards show as compact Liquid Glass pills

6. **Favorites**
   - Notes user has favorited (star icon)

### In OpenTable Feed:

#### Church Note Posts:
- Posts with `churchNoteId != nil` display special card
- **Preview Card** shows:
  - "Church Note" badge
  - Title (bold, 2 lines max)
  - Content preview
  - Church name + date metadata
  - "Tap to view full note" hint
- **Tapping** opens `ChurchNoteDetailModal`:
  - Full note with all metadata
  - Rich formatted content
  - AMEN + Comment buttons at bottom
  - Read-only (unless you're the author)

---

## 🤝 User Flow 3: Sharing with Friends (Gaps Identified)

### Current Capability:
✅ **External Sharing** (Working)
- User opens note detail
- Taps share button (square.and.arrow.up)
- `ChurchNoteShareOptionsSheet` opens with:
  - **Share as Text**: iOS share sheet → Messages, Email, etc.
  - **Share as PDF**: Generate PDF → iOS share sheet
  - **Copy Note Link**: Deep link `amenapp://note/{id}` → Clipboard

### Missing Capability:
❌ **In-App Friend Sharing** (Not Implemented)
- Database field exists: `sharedWith: [String]` (array of user IDs)
- Permission system exists: `.privateNote`, `.shared`, `.publicNote`
- **No UI to**:
  - Select AMEN friends to share with
  - Set note permissions
  - View "Shared with Me" notes
  - See who you've shared notes with

---

## 📊 Discovery Algorithm Details

### Ranking Signals (ChurchNotesDiscoveryService):

| Signal | Weight | Description | Status |
|--------|--------|-------------|--------|
| **Author Connection** | 25% | Following author | ⚠️ Needs FollowService |
| **Church Affinity** | 20% | Same church/denomination | ⚠️ Needs user church data |
| **Recency** | 15% | Exponential decay (7-day half-life) | ✅ Working |
| **Engagement Quality** | 15% | Amens, comments, shares | ⚠️ Needs PostInteractions |
| **Relevance Tags** | 10% | Jaccard similarity | ⚠️ Needs user interests |
| **Mutual Connections** | 10% | Friends of friends | ⚠️ Needs social graph |
| **Scripture** | 5% | Matching references | ⚠️ Needs user preferences |

**Total Score**: Weighted sum of all signals → Sort descending

### Debug Logging:
- Enabled in DEBUG builds
- Shows top 3 contributing factors for each note
- Percentage contribution of each signal
- Location: `ChurchNotesDiscoveryService.swift` lines 202-213

---

## 🎯 Recommended Improvements

### Priority 1: In-App Friend Sharing

**Add New UI**:
```
ChurchNoteDetailView → Share Menu:
├─ Share to OpenTable (existing)
├─ Share as Text (existing)
├─ Share as PDF (existing)
└─ Share with Friends (NEW)
    └─ Opens: FriendSelectionSheet
        ├─ Search friends
        ├─ Multi-select checkboxes
        ├─ "Share" button
        └─ Updates: note.sharedWith array
```

**Implementation**:
1. Create `FriendSelectionSheet` view
2. Fetch friends from `FollowService.shared.following`
3. Update `ChurchNotesService.shareWithUsers(noteId, userIds)`
4. Add "Shared with Me" filter option
5. Add notifications when note is shared

### Priority 2: Connect Discovery Algorithm

**Integrate User Data**:
```swift
// In ChurchNotesView.swift (lines 59-68)
let userFollowing = FollowService.shared.following  // ✅ Get actual following
let userChurch = userProfileService.currentUserChurch  // ✅ Get user's church
let userTags = userPreferences.interests  // ✅ Get user interests
```

**Add User Profile Fields**:
- `currentUserChurch: String?` - User's church name
- `interests: [String]` - Topics user cares about
- `favoriteScriptures: [String]` - Preferred scripture passages

### Priority 3: Enhanced Community Feed

**Add Features**:
1. **Search in Community**
   - Search bar in Community filter
   - Search by: title, church, pastor, scripture, tags

2. **Sort Options**
   - Most Recent
   - Most Popular (by engagement)
   - Most Relevant (discovery score)

3. **View Metrics**
   - "X people viewed this note"
   - "Shared Y times"

### Priority 4: Notifications

**Add Notification Types**:
1. `noteSharedWithYou` - Someone shared a note with you
2. `notePostedByFollowing` - Person you follow posted church note
3. `noteCommented` - Someone commented on your shared note
4. `noteAmened` - Someone amenned your shared note

---

## 📱 Current UI Components

### Main Views:
1. **ChurchNotesView** - Main tab with filters and feeds
2. **NewChurchNoteView** - Create/edit with rich text editor
3. **ChurchNoteDetailView** - Full note display (editable if owner)
4. **ElegantChurchNoteReadView** - Read-only view from OpenTable

### Supporting Views:
1. **MinimalTypographyHeader** - Search + filter pills
2. **MinimalNotesList** - Grid of personal notes
3. **ElegantChurchNotesFeedForChurchNotesView** - Community feed
4. **ChurchNotePreviewCard** - Compact pill for OpenTable posts
5. **ShareNoteToOpenTableSheet** - Post creation modal
6. **ChurchNoteShareOptionsSheet** - Share menu options

### Reusable Components:
1. **RichTextEditorView** - Formatting toolbar + markdown editor
2. **GlassTextField** - Glassmorphic input fields
3. **TagPill** - Tag display with remove button
4. **FlowLayout** - Automatic tag wrapping

---

## 🗄️ Data Models

### ChurchNote
```swift
struct ChurchNote {
    let id: String
    let userId: String  // Author
    let title: String
    let sermonTitle: String?
    let churchName: String?
    let pastor: String?
    let date: Date
    let content: String  // Markdown formatted
    let scripture: String?
    let tags: [String]
    let scriptureReferences: [String]
    let createdAt: Date
    let updatedAt: Date
    let isFavorite: Bool
    let shareLinkId: String?  // For deep linking
    
    // Sharing fields
    let permission: NotePermission  // .privateNote, .shared, .publicNote
    let sharedWith: [String]  // Array of user IDs (⚠️ Not used in UI)
}
```

### Post (with Church Note)
```swift
struct Post {
    // Standard post fields...
    let churchNoteId: String?  // ✅ Links to ChurchNote
}
```

---

## 🔗 Deep Linking

### Format: `amenapp://note/{shareLinkId}`

**How it works**:
1. Each note has unique `shareLinkId` (UUID)
2. Link copied to clipboard or shared externally
3. App intercepts URL → Fetches note from Firestore
4. Opens `ChurchNoteDetailModal` with note

**Current Status**: ✅ Implemented, clipboard only

---

## 📈 Analytics Opportunities

### Track:
1. Notes created per user
2. Notes shared to OpenTable (conversion rate)
3. Note views from community
4. Engagement on shared notes (amens, comments)
5. Most popular churches/pastors/scriptures
6. Discovery algorithm effectiveness (click-through rates)

---

## 🎨 Design System

**Liquid Glass Theme**:
- Glassmorphic cards with gradient backgrounds
- White borders (opacity 0.1-0.2, 0.5-1pt stroke)
- Subtle shadows for depth
- Spring animations throughout
- Custom OpenSans fonts
- Minimal, clean typography

**Color Palette**:
- Background: Dark gradients (0.08-0.18 opacity variations)
- Text: White with varying opacity (0.4-1.0)
- Accents: Purple, Cyan, Orange (for interactions)
- Dividers: White 0.1-0.2 opacity

---

## 🚀 Next Steps

### Immediate Actions:
1. ✅ Create this documentation
2. ⚠️ Implement "Share with Friends" UI
3. ⚠️ Connect discovery algorithm to user data
4. ⚠️ Add "Shared with Me" filter
5. ⚠️ Set up notifications for note sharing

### Future Enhancements:
- [ ] Collaborative notes (multiple authors)
- [ ] Note templates (sermon outline, devotional, study guide)
- [ ] Export to Notion/Evernote
- [ ] Audio note attachments
- [ ] Church note collections/series
- [ ] Weekly/monthly note summaries
