# Firebase Security Rules - Production Ready

This directory contains production-ready security rules for your AMEN app.

## 📁 Files

- **`firestore.rules`** - Cloud Firestore security rules
- **`firebase-realtime-database.rules.json`** - Realtime Database security rules

## 🚀 Deployment

### Using Firebase Console (Manual)

#### Firestore Rules:
1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select project: `amen-5e359`
3. Navigate to **Firestore Database** → **Rules** tab
4. Copy contents from `firestore.rules`
5. Click **Publish**

#### Realtime Database Rules:
1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select project: `amen-5e359`
3. Navigate to **Realtime Database** → **Rules** tab
4. Copy contents from `firebase-realtime-database.rules.json`
5. Click **Publish**

### Using Firebase CLI (Automated)

```bash
# Install Firebase CLI if not already installed
npm install -g firebase-tools

# Login to Firebase
firebase login

# Deploy Firestore rules
firebase deploy --only firestore:rules

# Deploy Realtime Database rules
firebase deploy --only database
```

## 🔐 Security Features

### Firestore Rules Include:

✅ **Authentication Required** - All operations require signed-in users
✅ **Owner-Based Access** - Users can only modify their own data
✅ **Field Validation** - Ensures required fields are present
✅ **Immutable Fields** - Prevents changing critical fields (uid, createdAt)
✅ **Participant Checks** - For conversations, only participants can access
✅ **Cascade Permissions** - Subcollections inherit parent permissions appropriately
✅ **Block Protection** - Users can block others
✅ **Report Audit Trail** - Reports cannot be edited/deleted
✅ **Admin Protection** - App settings can only be changed via Cloud Functions

### Realtime Database Rules Include:

✅ **User-Specific Data** - Each user can only access their own data
✅ **Public Profiles** - Authenticated users can read all profiles
✅ **Typing Indicators** - Real-time typing status per conversation
✅ **Online Status** - Real-time presence tracking
✅ **FCM Tokens** - Secure notification token storage
✅ **Validation Rules** - Ensures data structure integrity

## 📋 Collections Overview

### Firestore Collections:

| Collection | Read | Write | Notes |
|------------|------|-------|-------|
| `users` | All authenticated | Owner only | User profiles |
| `posts` | All authenticated | Owner only | Posts/content |
| `testimonies` | All authenticated | Owner only | User testimonies |
| `prayers` | All authenticated | Owner only | Prayer requests |
| `notifications` | Owner only | System + Owner | User notifications |
| `conversations` | Participants only | Participants only | Direct messages |
| `follows` | All authenticated | Owner only | Follow relationships |
| `blocks` | Owner only | Owner only | Blocked users |
| `savedPosts` | Owner only | Owner only | Saved content |
| `reposts` | All authenticated | Owner only | Reposted content |
| `communities` | All authenticated | Creator/Mods | Community groups |
| `reports` | Reporter only | Reporter only | Content reports |

### Realtime Database Nodes:

| Node | Read | Write | Notes |
|------|------|-------|-------|
| `user_posts` | All authenticated | Owner only | User post references |
| `user_profiles` | All authenticated | Owner only | Quick profile lookup |
| `online_status` | All authenticated | Owner only | Presence system |
| `typing` | Participants | Owner only | Typing indicators |
| `notification_tokens` | Owner only | Owner only | FCM tokens |

## ⚠️ Important Notes

### Before Production:

1. **Remove Test Nodes**: Delete the `test` node from Realtime Database rules
2. **Review Permissions**: Audit all rules for your specific use case
3. **Test Thoroughly**: Use Firebase Emulator Suite to test rules
4. **Monitor Usage**: Set up Firebase monitoring and alerts
5. **Rate Limiting**: Consider implementing rate limiting via Cloud Functions

### Testing Rules Locally:

```bash
# Install Firebase Emulator Suite
firebase init emulators

# Start emulators
firebase emulators:start

# Run tests against emulators
# Your app should use emulator endpoints in development
```

### Best Practices:

1. **Never use `allow read, write: if true;`** in production
2. **Always validate user input** at the rules level
3. **Use helper functions** to keep rules DRY
4. **Document complex rules** with comments
5. **Version control rules** in your repository
6. **Deploy rules with CI/CD** for consistency
7. **Monitor rule evaluations** in Firebase Console

## 🧪 Testing

You can test these rules using the Firebase Console:

1. Go to **Firestore** or **Realtime Database**
2. Click **Rules** tab
3. Click **Rules Playground**
4. Test different scenarios with different auth states

## 📚 Resources

- [Firestore Security Rules Documentation](https://firebase.google.com/docs/firestore/security/get-started)
- [Realtime Database Security Rules](https://firebase.google.com/docs/database/security)
- [Firebase Security Best Practices](https://firebase.google.com/docs/rules/best-practices)
- [Firebase Emulator Suite](https://firebase.google.com/docs/emulator-suite)

## 🆘 Common Issues

### "Permission Denied" Errors:
- Check that user is authenticated
- Verify user is the owner of the resource
- Check that all required fields are present
- Review participant lists for conversations

### "Index Required" Errors:
- Click the link in the error message
- Or manually create the index in Firebase Console
- Wait 5-10 minutes for index to build

### Rules Not Working:
- Clear browser cache
- Restart Firebase emulators
- Check for syntax errors in rules
- Verify Firebase SDK initialization

---

**Last Updated**: January 31, 2026
**Version**: 1.0.0
**Status**: ✅ Production Ready
