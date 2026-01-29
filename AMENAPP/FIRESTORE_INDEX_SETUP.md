# Firestore Index Creation Guide

## 🎯 **Quick Setup - 3 Steps**

### **Step 1: Run Search Migration**
1. Open your app
2. Profile → Settings (three lines) → Developer Tools
3. Tap **"Migrate Users for Search"**
4. Wait for ✅ success message

### **Step 2: Create Indexes (Choose Method)**

#### **Method A: Automatic (Easiest) ⭐**
1. Try searching for a user in your app
2. Check Xcode console
3. You'll see an error like:
   ```
   ❌ Firestore: FAILED_PRECONDITION: The query requires an index.
   You can create it here: https://console.firebase.google.com/...
   ```
4. **Click the link** - it creates the index automatically!
5. Repeat search - you'll get another error for the second index
6. **Click that link too**
7. Done! ✅

#### **Method B: Manual**
1. Open: https://console.firebase.google.com
2. Select your project
3. Go to: **Firestore Database** → **Indexes**
4. Click **"Create Index"** button
5. Create **Index 1**:
   - Collection ID: `users`
   - Add field: `usernameLowercase` → `Ascending`
   - Add field: `__name__` → `Ascending`
   - Click **"Create"**
6. Click **"Create Index"** again
7. Create **Index 2**:
   - Collection ID: `users`
   - Add field: `displayNameLowercase` → `Ascending`
   - Add field: `__name__` → `Ascending`
   - Click **"Create"**

### **Step 3: Wait & Test**
1. Wait **2-3 minutes** for indexes to build
2. Status changes from "Building" → "Enabled"
3. Test search in your app
4. ✅ Done!

---

## 📋 **Index Requirements**

### **Index 1: Username Search**
```
Collection ID: users
Fields indexed:
  - usernameLowercase: Ascending
  - __name__: Ascending

Query scope: Collection
Status: Must be "Enabled"
```

### **Index 2: Display Name Search**
```
Collection ID: users
Fields indexed:
  - displayNameLowercase: Ascending
  - __name__: Ascending

Query scope: Collection
Status: Must be "Enabled"
```

---

## 🖼️ **Visual Guide**

### Firebase Console Navigation:
```
Firebase Console Home
    ↓
Select Project: "AMENAPP" (or your project name)
    ↓
Left Sidebar: "Firestore Database"
    ↓
Top Tabs: Click "Indexes"
    ↓
Click "Create Index" button
    ↓
Fill in fields (see above)
    ↓
Click "Create"
    ↓
Wait 2-3 minutes
    ↓
Status shows "Enabled" ✅
```

---

## ⏱️ **Timeline**

| Step | Time Required |
|------|---------------|
| Run migration | 10-30 seconds |
| Create index (manual) | 1-2 minutes |
| Index building | 2-3 minutes |
| **Total** | **~5 minutes** |

---

## ✅ **Verification**

### **How to verify indexes are working:**

1. **In Firebase Console:**
   - Go to Indexes tab
   - Both indexes show status: **"Enabled"** (green)
   - No yellow "Building" status

2. **In Your App:**
   - Open Developer Tools
   - Go to "Test Search" section
   - Type a username (e.g., "john")
   - Should show results immediately
   - No errors in Xcode console

3. **In Main Search:**
   - Go to app's Search view
   - Search for a known user
   - Results appear within 1-2 seconds
   - Can search by username or display name

---

## 🐛 **Common Issues**

### **Issue 1: "Index still building after 5+ minutes"**

**Solutions:**
- Refresh Firebase Console page
- Check Firebase status: https://status.firebase.google.com
- Try deleting and recreating the index
- Check internet connection

### **Issue 2: "Search returns no results"**

**Checklist:**
- [ ] Migration completed successfully?
- [ ] Both indexes show "Enabled"?
- [ ] Waited 2-3 minutes after creating indexes?
- [ ] Searching for a user that exists?
- [ ] User has both `usernameLowercase` and `displayNameLowercase` fields?

**Debug:**
```swift
// In Developer Tools → Test Search
// Try searching for: "test" or first letters of a known username
// Check Xcode console for error messages
```

### **Issue 3: "Firestore error: FAILED_PRECONDITION"**

**This is actually GOOD!** 
- Error message contains index creation link
- Click the link to auto-create index
- This is the fastest way to create indexes

---

## 📊 **What Indexes Do**

### **Without Indexes:**
```
Search Query: "john"
❌ Error: Index required
⏱️ Time: Instant failure
```

### **With Indexes:**
```
Search Query: "john"
✅ Finds: [@johnsmith, @johnny, @john_doe]
⏱️ Time: <1 second
📈 Performance: Optimized for millions of users
```

---

## 🎓 **Understanding Firestore Indexes**

### **Why are indexes needed?**

Firestore requires indexes for:
- **Range queries** (>=, <=)
- **Sorting** + filtering
- **Multiple field queries**

Our search uses range queries:
```swift
.whereField("usernameLowercase", isGreaterThanOrEqualTo: "john")
.whereField("usernameLowercase", isLessThanOrEqualTo: "john\u{f8ff}")
```

This allows **prefix matching** (searches starting with "john").

### **Why two indexes?**

1. **Username Index**: Searches by @username
2. **Display Name Index**: Searches by full name

Users can find each other either way!

---

## 💡 **Pro Tips**

### **Tip 1: Use Automatic Index Creation**
Always prefer clicking the error link - it's faster and less error-prone than manual creation.

### **Tip 2: Keep Developer Tools Accessible**
During development, keep Developer Tools easily accessible for testing.

### **Tip 3: Monitor Index Usage**
In Firebase Console → Indexes, you can see:
- Number of operations
- Last used timestamp
- Storage usage

### **Tip 4: Test with Real Data**
Create 3-4 test accounts with different usernames to thoroughly test search.

---

## 🚀 **After Setup**

Once indexes are created, they work permanently:
- ✅ No maintenance required
- ✅ Automatically used by Firestore
- ✅ Scales to millions of users
- ✅ No performance degradation

---

## 📞 **Need Help?**

If you encounter issues:

1. **Check Xcode Console** for specific errors
2. **Use Developer Tools → Test Search** for debugging
3. **Verify indexes in Firebase Console** (Status: "Enabled")
4. **Check migration completed** successfully
5. **Ensure internet connectivity** for Firebase

---

## 🎉 **Success Indicators**

You know it's working when:
- ✅ Both indexes show "Enabled" in Firebase Console
- ✅ Test search returns results in Developer Tools
- ✅ Main app search finds users by username
- ✅ Main app search finds users by display name
- ✅ No Firestore errors in Xcode console
- ✅ Search results appear in < 1 second

---

**Ready? Let's go!** 🚀

Run the app → Developer Tools → Migrate → Create Indexes → Test!
