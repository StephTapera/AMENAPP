# ⚠️ IMPORTANT: Model Definitions

## Single Source of Truth for Models

**PostInteractionModels.swift** is the ONLY file where these models should be defined:

- ✅ `Comment` - for post comments and replies
- ✅ `SavedPost` - for user's saved/bookmarked posts
- ✅ `Repost` - for tracking when users repost content (**PUBLIC** struct)
- ✅ `PostMention` - for @mention tracking
- ✅ `CommentWithReplies` - helper for nested comment display

## If You See "Ambiguous type lookup" Errors

If you get errors like:
```
error: 'Repost' is ambiguous for type lookup in this context
error: Invalid redeclaration of 'Repost'
```

**This means there's a duplicate definition somewhere!**

### How to Fix:

1. **Search the entire project** (⌘ + Shift + F)
2. Search for: `struct Repost`
3. **Delete ANY occurrences** that are NOT in `PostInteractionModels.swift`

### Common places duplicates hide:
- Old backup files
- `Models.swift` or `SocialModels.swift`
- Demo/Example files
- Commented-out code blocks

## Models Are Used By:

- `CommentService.swift` - uses `Comment` and `CommentWithReplies`
- `SavedPostsService.swift` - uses `SavedPost`
- `RepostService.swift` - uses `Repost`
- `PostInteractionsViewModel.swift` - uses all models

---

**Last Verified:** January 20, 2026
