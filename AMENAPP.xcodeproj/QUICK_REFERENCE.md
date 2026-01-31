# 📋 QUICK REFERENCE CARD

## 🚀 Deploy Firebase Rules (5 minutes)

### Firestore Rules
1. Go to: https://console.firebase.google.com
2. Select your project
3. Firestore Database → Rules tab
4. Copy ALL content from `/repo/firestore.rules`
5. Paste into editor
6. Click **Publish**

### Storage Rules
1. Storage → Rules tab
2. Copy ALL content from `/repo/storage.rules`
3. Paste into editor
4. Click **Publish**

---

## 📱 Add Info.plist Entries (2 minutes)

### In Xcode:
1. Select your target → Info tab
2. Click **+** button
3. Add these two entries:

**Entry 1: Apple Music**
```
Key: Privacy - Media Library Usage Description
Value: AMENAPP uses Apple Music to provide worship songs and hymns for your spiritual journey.
```

**Entry 2: Location**
```
Key: Privacy - Location When In Use Usage Description
Value: AMENAPP uses your location to help you find churches near you.
```

### Or Edit XML Directly:
```xml
<key>NSAppleMusicUsageDescription</key>
<string>AMENAPP uses Apple Music to provide worship songs and hymns for your spiritual journey.</string>

<key>NSLocationWhenInUseUsageDescription</key>
<string>AMENAPP uses your location to help you find churches near you.</string>
```

---

## ✅ Test (3 minutes)

1. Clean Build: **Cmd+Shift+K**
2. Build: **Cmd+B**
3. Run: **Cmd+R**
4. Test:
   - ✅ Sign in
   - ✅ Create post
   - ✅ Send message
   - ✅ Follow user
   - ✅ Upload photo

---

## 🐛 Quick Troubleshooting

### "Permission denied" error
- Wait 2 minutes for rules to propagate
- Check Firebase Console that rules are published
- Verify user is signed in

### "Query requires an index" error
- Click the error link in console
- Wait 5-10 minutes for index to build

### Permission dialog doesn't show
- Delete app
- Clean build (Cmd+Shift+K)
- Reinstall

---

## 📁 Files Created

- ✅ `/repo/firestore.rules` - Database security (500+ lines)
- ✅ `/repo/storage.rules` - File storage security (200+ lines)
- ✅ `/repo/INFO_PLIST_SETUP_GUIDE.md` - Detailed guide
- ✅ `/repo/PRODUCTION_DEPLOYMENT_COMPLETE.md` - Full deployment guide

---

## 🎯 What's Protected

### ✅ Users CAN:
- Read any profile
- Update own profile
- Create posts
- Send messages
- Follow/unfollow
- Upload media (10MB max)

### ❌ Users CANNOT:
- Edit others' profiles
- Delete others' posts
- Modify follower counts
- View others' messages
- Upload files >10MB
- Access admin data

---

## 💡 Pro Tips

1. **Always test after deploying** - Spend 5 minutes clicking through features
2. **Monitor Firebase Console** - Check for rule violations
3. **Use pagination** - Don't load all data at once
4. **Compress images** - Keep under 10MB (already doing 70% compression)
5. **Set up indexes** - Click error links to auto-create them

---

## 📞 Support

- **Firebase**: https://firebase.google.com/support
- **Apple**: https://developer.apple.com/forums
- **Emergency Rollback**: Firebase Console → Rules → History → Restore

---

**Total Time: ~10 minutes**
**Status: Production Ready ✅**

*Last Updated: January 31, 2026*
