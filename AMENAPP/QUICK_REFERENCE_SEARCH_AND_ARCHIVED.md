# QUICK REFERENCE: Global Search & Archived Messages

## Global Search Button (🔍)

### What It Does:
**Searches all your message conversations for matching text**

### Location:
Top right of Messages tab, next to the compose button

### How to Use:
1. Tap the 🔍 search icon
2. Type any text to search for
3. See results appear in real-time
4. Use filter tabs to narrow results:
   - **All** - All matching messages
   - **Photos** - Messages with images
   - **Links** - Messages with URLs  
   - **People** - One result per sender
5. Tap any result to open that conversation

### Features:
- ✅ Searches across ALL conversations
- ✅ Case-insensitive matching
- ✅ 300ms debounce (waits after typing)
- ✅ Smart timestamps ("Today", "Yesterday", etc.)
- ✅ Shows sender name for each result
- ✅ Tappable results to jump to conversation

### Performance:
- Searches last 100 messages per conversation
- ~1-2 seconds for 10 conversations
- Cancels previous search if you type again

---

## Archived Messages Real-Time

### What Changed:
**Archived conversations now update instantly when:**
- Someone sends you a message in an archived chat
- You archive/unarchive a conversation
- New activity happens in archived chats

### How to Archive:
1. Long-press any conversation
2. Tap "Archive"
3. Conversation moves to "Archived" tab instantly

### How to Unarchive:
1. Go to "Archived" tab
2. Long-press conversation
3. Tap "Unarchive"
4. Conversation moves back to "Messages" tab

### Real-Time Features:
- ✅ Instant archiving (< 0.5 seconds)
- ✅ New message previews update live
- ✅ Timestamps update in real-time
- ✅ No duplicates
- ✅ Works offline (syncs when back online)

### Console Logs:
When archived conversations load, you'll see:
```
📥 Received 10 total documents for archived check
   📦 Found archived: abc123, name: "Family Group"
✅ Loaded 2 unique archived conversations
🌐 Archived conversations loaded from server
```

---

## Quick Testing Checklist

### Test Search:
- [ ] Tap 🔍 button at top right
- [ ] Type "hello" or common word
- [ ] Results appear within 1 second
- [ ] Try "Photos" filter
- [ ] Tap a result - opens correct chat
- [ ] Clear search - returns to empty state

### Test Archived:
- [ ] Archive a conversation (long-press → Archive)
- [ ] Go to Archived tab - see it instantly
- [ ] Send message to archived chat - preview updates
- [ ] Unarchive (long-press → Unarchive) - moves back instantly
- [ ] Check for duplicates - should be none

---

## Troubleshooting

### Search not working?
1. Check you're authenticated
2. Check conversations exist with messages
3. Check network connection
4. Look for errors in console

### Archived not updating?
1. Check listener is started (look for "👂 Starting real-time listener" in console)
2. Verify `archivedByArray` field exists in Firestore
3. Check user ID matches in array
4. Ensure Firestore rules allow reading conversations

---

## Code References

### Search Implementation:
- **UI:** `MessagesView.swift` → `GlobalMessageSearchView`
- **Logic:** `FirebaseMessagingService.swift` → `searchMessagesInConversation()`
- **Filtering:** `GlobalMessageSearchView.filterResults()`

### Archived Implementation:
- **UI:** `MessagesView.swift` → `archivedContent`
- **Logic:** `FirebaseMessagingService.swift` → `startListeningToArchivedConversations()`
- **Actions:** `archiveConversation()` / `unarchiveConversation()`

---

## Performance Tips

### For Search:
- Searches only last 100 messages per conversation
- Increase limit for more thorough search (slower)
- Consider Algolia for production full-text search

### For Archived:
- Real-time listener is always active
- No extra network calls needed
- Filtering happens in memory (very fast)

---

## Next Steps

After testing, consider:
1. **Add search to individual conversations** (not just global)
2. **Highlight matching text** in search results
3. **Add date range filters** to search
4. **Auto-archive old conversations** (30+ days)
5. **Add archive folders** for organization

---

Need help? Check `MESSAGING_SEARCH_AND_ARCHIVED_FIXES.md` for full details!
