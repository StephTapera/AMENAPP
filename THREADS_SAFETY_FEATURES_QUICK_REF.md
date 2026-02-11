# 🛡️ Threads-Like Safety Features - Quick Reference

**Priority implementation guide for AMEN App**

---

## ✅ ALREADY IMPLEMENTED

| Feature | Status | Location |
|---------|--------|----------|
| **Block Users** | ✅ Live | BlockedUsersView.swift |
| **Report Content** | ✅ Live | Various views |
| **Privacy Settings** | ✅ Live | PrivacySettingsView.swift |
| **Content Moderation** | ✅ Live | ContentModerationService.swift |
| **Crisis Detection** | ✅ Live | CrisisDetectionService.swift |
| **Bug Reports** | ✅ Live | HelpSupportView.swift |
| **Feedback System** | ✅ Live | HelpSupportView.swift |

---

## 🎯 TOP 3 RECOMMENDATIONS (Quick Wins)

### 1. **Mute Accounts** ⏸️
**Effort**: Low (2-3 hours)  
**Impact**: High  
**Why**: Gentle alternative to blocking, reduces feed overwhelm

**Code Snippet**:
```swift
// Add to SocialService.swift
func muteUser(_ userId: String, duration: TimeInterval) async throws {
    try await db.collection("users").document(currentUserId)
        .updateData([
            "mutedUsers.\(userId)": Date().addingTimeInterval(duration)
        ])
}
```

---

### 2. **Comment Controls (Per Post)** 💬
**Effort**: Medium (4-5 hours)  
**Impact**: Very High  
**Why**: Protects vulnerable prayer requests, prevents pile-ons

**Options**:
- Everyone can comment
- Only followers
- Only mentioned people
- Comments off

**Code Snippet**:
```swift
// Add to Post model
enum CommentPermissions: String, Codable {
    case everyone, following, mentioned, off
}

// Add to CreatePostView
@State private var commentPermissions: CommentPermissions = .everyone
```

---

### 3. **Hidden Words Filter** 🚫
**Effort**: Medium (5-6 hours)  
**Impact**: High  
**Why**: User-controlled experience, reduces triggering content

**Features**:
- Personal word list
- Filter posts/comments containing those words
- Option: only filter from non-followers

**Code Snippet**:
```swift
// Add to PrivacySettingsView
@State private var hiddenWords: [String] = []
@State private var filterUnfollowedOnly = false

// Save to Firestore
users/{userId}/privacy/hiddenWords
```

---

## 🛡️ SAFETY TIER LIST

### **S-Tier** (Must Have)
- ✅ Block users (done)
- ✅ Report content (done)
- ⏸️ Mute accounts (add next)
- 💬 Comment controls (add next)

### **A-Tier** (High Value)
- 🚫 Hidden words filter
- 🤫 Restrict accounts (soft block)
- ⚠️ Sensitive content warnings
- ✅ Verified accounts (church leaders)

### **B-Tier** (Nice to Have)
- 👁️ Limited profile view
- ⚖️ Appeals system
- 🔕 Notification controls (per user)
- 📊 Activity status control

---

## 📋 Implementation Priority Order

### **Week 1** (Quick Wins)
1. Mute accounts (2-3 hours)
2. Comment controls (4-5 hours)
3. Hidden words filter (5-6 hours)

**Total**: ~12-14 hours of dev work

---

### **Week 2** (High Value)
4. Restrict accounts (6-8 hours)
5. Sensitive content warnings (4-5 hours)

**Total**: ~10-13 hours of dev work

---

### **Month 2** (Trust Features)
6. Verified accounts system (10-12 hours)
7. Appeals system (8-10 hours)

**Total**: ~18-22 hours of dev work

---

## 🔧 Technical Implementation Guide

### **Mute Accounts**
```swift
// 1. Add to User model
var mutedUsers: [String: Date] = [:] // userId: muteUntil

// 2. Filter feed
func fetchPosts() async throws -> [Post] {
    let posts = try await getAllPosts()
    return posts.filter { post in
        guard let muteUntil = currentUser.mutedUsers[post.authorId] else {
            return true // Not muted
        }
        return Date() > muteUntil // Mute expired
    }
}

// 3. UI in UserProfileView
Menu {
    Button("Mute for 24 hours") {
        Task { try await muteUser(user.id, duration: 86400) }
    }
    Button("Mute for 7 days") {
        Task { try await muteUser(user.id, duration: 604800) }
    }
    Button("Mute indefinitely") {
        Task { try await muteUser(user.id, duration: .infinity) }
    }
} label: {
    Image(systemName: "speaker.slash")
}
```

---

### **Comment Controls**
```swift
// 1. Add to Post model
var commentPermissions: CommentPermissions = .everyone

// 2. Check before allowing comment
func canComment(on post: Post) async -> Bool {
    switch post.commentPermissions {
    case .everyone: return true
    case .following: return await isFollowing(post.authorId)
    case .mentioned: return post.mentionedUsers.contains(currentUserId)
    case .off: return post.authorId == currentUserId // Only author
    }
}

// 3. UI in CreatePostView
Picker("Who can comment", selection: $commentPermissions) {
    Text("Everyone").tag(CommentPermissions.everyone)
    Text("People I follow").tag(CommentPermissions.following)
    Text("Mentioned only").tag(CommentPermissions.mentioned)
    Text("Comments off").tag(CommentPermissions.off)
}
```

---

### **Hidden Words**
```swift
// 1. Add to user privacy settings
var hiddenWords: [String] = []
var hideFromUnfollowedOnly: Bool = false

// 2. Filter content
func shouldHideContent(_ text: String, authorId: String) async -> Bool {
    // Check if from unfollowed user (if setting enabled)
    if hideFromUnfollowedOnly {
        let isFollowing = await FollowService.shared.isFollowing(authorId)
        if isFollowing { return false } // Don't filter followers
    }
    
    // Check for hidden words
    let lowercased = text.lowercased()
    return hiddenWords.contains { word in
        lowercased.contains(word.lowercased())
    }
}

// 3. UI in PrivacySettingsView
Section("Hidden Words") {
    ForEach(hiddenWords, id: \.self) { word in
        HStack {
            Text(word)
            Spacer()
            Button(action: { removeWord(word) }) {
                Image(systemName: "xmark.circle.fill")
            }
        }
    }
    
    Button("Add Word") {
        showAddWordSheet = true
    }
    
    Toggle("Only hide from people I don't follow", isOn: $hideFromUnfollowedOnly)
}
```

---

## 🎨 UI/UX Best Practices

### **Mute vs Block**
- **Mute**: Temporary, reversible, they don't know
- **Block**: Permanent, they can't interact, they might notice

### **Comment Controls Icons**
- 🌐 Everyone: `globe`
- 👥 Following: `person.2.fill`
- @ Mentioned: `at`
- 🚫 Off: `bubble.left.and.bubble.right.fill`

### **Confirmation Messages**
```swift
// Mute
"You won't see posts from @username for [duration]. They won't be notified."

// Restrict
"@username's comments will only be visible to them. They won't be notified."

// Hidden words added
"Posts and comments containing '[word]' will be filtered from your feed."
```

---

## 📊 Firebase Rules

```javascript
// Allow users to manage their own muted list
match /users/{userId}/mutedUsers/{mutedUserId} {
  allow read, write: if request.auth.uid == userId;
}

// Hidden words are private
match /users/{userId}/privacy {
  allow read, write: if request.auth.uid == userId;
}

// Comment permissions checked in post document
match /posts/{postId} {
  allow read: if true;
  allow write: if request.auth.uid == resource.data.authorId;
}
```

---

## ✅ Testing Checklist

### **Mute Accounts**
- [ ] Can mute user from profile
- [ ] Muted posts don't appear in feed
- [ ] Muted user doesn't get notified
- [ ] Can unmute before duration expires
- [ ] Mute auto-expires after duration

### **Comment Controls**
- [ ] Author can set permissions on create
- [ ] Non-followers can't comment (when set to following)
- [ ] Only mentioned users can comment (when set to mentioned)
- [ ] No comment box shows (when set to off)
- [ ] Author can always comment on own post

### **Hidden Words**
- [ ] Can add/remove words
- [ ] Posts with hidden words are filtered
- [ ] Comments with hidden words are hidden
- [ ] "Only non-followers" option works
- [ ] Case-insensitive matching

---

## 🚀 Rollout Strategy

### **Phase 1** (Week 1)
1. Release mute feature to beta testers
2. Collect feedback on duration options
3. Refine UX based on usage

### **Phase 2** (Week 2)
1. Release comment controls
2. Monitor for abuse/confusion
3. Add analytics on permission usage

### **Phase 3** (Week 3)
1. Release hidden words filter
2. Provide default word suggestions
3. Iterate on matching algorithm

---

## 📈 Success Metrics

### **Mute Feature**
- % of users who use mute vs block
- Average mute duration selected
- Unmute rate before expiration

### **Comment Controls**
- % of posts with restricted comments
- Comment drop on restricted posts
- Harassment reports on posts with restrictions

### **Hidden Words**
- Average number of hidden words per user
- % reduction in reported content
- User satisfaction (survey)

---

## 🏁 Quick Start

**Want to add mute feature right now?**

1. Add to `SocialService.swift`:
```swift
func muteUser(_ userId: String, hours: Int) async throws {
    let muteUntil = Date().addingTimeInterval(TimeInterval(hours * 3600))
    try await Firestore.firestore()
        .collection("users")
        .document(currentUserId)
        .updateData([
            "mutedUsers.\(userId)": Timestamp(date: muteUntil)
        ])
}
```

2. Add to `UserProfileView.swift`:
```swift
Menu {
    Button("Mute for 24 hours") {
        Task { try await socialService.muteUser(user.id, hours: 24) }
    }
} label: {
    Image(systemName: "speaker.slash")
}
```

3. Filter in `PostsManager.swift`:
```swift
posts.filter { post in
    let muteUntil = currentUser.mutedUsers[post.authorId]
    return muteUntil == nil || Date() > muteUntil
}
```

**Done!** 🎉

---

## 💡 Pro Tips

1. **Mute durations**: Offer 24h, 7d, 30d, forever (like Threads)
2. **Hidden words**: Suggest common filter words on first use
3. **Comment controls**: Default to "Everyone" for discoverability
4. **Restrict**: Add "People you've restricted" list in Settings
5. **Appeals**: Respond within 24 hours for trust

---

**Questions?** Check `FEEDBACK_AND_SAFETY_FEATURES_COMPLETE.md` for detailed implementation guide.
