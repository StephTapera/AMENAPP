# Firebase Cloud Functions for AMENAPP

This directory contains Cloud Functions that handle:
- Push notifications for user interactions
- Real-time messaging notifications
- Automated tasks and background jobs

## Setup Instructions

### 1. Install Firebase CLI
```bash
npm install -g firebase-tools
```

### 2. Login to Firebase
```bash
firebase login
```

### 3. Initialize Functions
```bash
firebase init functions
```

Select:
- TypeScript (recommended)
- Use ESLint
- Install dependencies now

### 4. Deploy Functions
```bash
firebase deploy --only functions
```

## Functions Overview

### Notification Functions

1. **onFollowCreated** - Sends push notification when someone follows you
2. **onAmenCreated** - Sends push notification when someone says Amen to your post
3. **onCommentCreated** - Sends push notification when someone comments on your post
4. **onMessageCreated** - Sends push notification for new messages

### Message Functions

1. **createConversation** - Creates a new conversation with proper indexing
2. **sendMessage** - Sends a message and updates conversation metadata
3. **markMessagesAsRead** - Marks messages as read and updates unread counts

## File Structure

```
functions/
├── src/
│   ├── index.ts                  # Main entry point
│   ├── notifications.ts          # Notification functions
│   ├── messaging.ts              # Messaging functions
│   └── utils/
│       ├── fcm.ts               # FCM helper functions
│       └── types.ts             # TypeScript types
├── package.json
└── tsconfig.json
```

## Environment Variables

Set these in Firebase Console > Functions > Configuration:

```bash
# None required - functions use Firebase Admin SDK
```

## Testing Functions

### Test Locally with Emulator
```bash
firebase emulators:start
```

### Test Specific Function
```bash
firebase functions:shell
```

## Monitoring

View function logs:
```bash
firebase functions:log
```

View specific function:
```bash
firebase functions:log --only onMessageCreated
```

## Cost Optimization

- Functions use minimum instances (0) to reduce costs
- Timeout set to 60 seconds for notifications
- Memory allocation: 256MB (sufficient for most operations)

## Security

- All functions validate authentication
- User data access controlled by Firestore rules
- FCM tokens stored securely in user documents
