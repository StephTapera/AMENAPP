# 📋 Copy-Paste Terminal Commands

Quick reference for deploying Cloud Functions. Copy and paste these commands in order.

---

## 1️⃣ Setup (One-Time)

```bash
# Install Firebase CLI (if not already installed)
npm install -g firebase-tools

# Login to Firebase
firebase login

# Navigate to your project
cd /path/to/AMENAPP

# List available Firebase projects
firebase projects:list

# Select your project (replace with your project ID)
firebase use your-project-id
```

---

## 2️⃣ Install Dependencies

```bash
# Navigate to functions directory
cd functions

# Install all dependencies
npm install

# Go back to project root
cd ..
```

---

## 3️⃣ Deploy Functions

```bash
# Deploy all functions
firebase deploy --only functions

# OR deploy specific functions
firebase deploy --only functions:onFollowCreated,onAmenCreated,onCommentCreated,onMessageCreated
```

---

## 4️⃣ Enable Required APIs

```bash
# Enable Cloud Functions API
gcloud services enable cloudfunctions.googleapis.com

# Enable Cloud Messaging API
gcloud services enable fcm.googleapis.com

# Enable Cloud Scheduler API
gcloud services enable cloudscheduler.googleapis.com
```

---

## 5️⃣ Verify Deployment

```bash
# List deployed functions
firebase functions:list

# View function logs
firebase functions:log

# Follow logs in real-time
firebase functions:log --follow

# View specific function logs
firebase functions:log --only onFollowCreated
```

---

## 🔄 Update Functions (When You Make Changes)

```bash
# Navigate to project root
cd /path/to/AMENAPP

# Deploy all functions
firebase deploy --only functions

# OR deploy single function
firebase deploy --only functions:onFollowCreated
```

---

## 🗑️ Delete a Function

```bash
# Delete a specific function
firebase functions:delete functionName

# Example
firebase functions:delete onFollowCreated
```

---

## 🐛 Troubleshooting Commands

```bash
# Check Firebase CLI version
firebase --version

# Check Node.js version (need v18+)
node --version

# Check npm version
npm --version

# Login again if needed
firebase login --reauth

# Check current Firebase project
firebase projects:list
firebase use

# View detailed function logs with errors
firebase functions:log --only onFollowCreated

# Check function status in real-time
firebase functions:log --follow

# Test Firebase connection
firebase projects:list
```

---

## 📦 Package Management

```bash
# Check for outdated packages
cd functions
npm outdated

# Update all packages
npm update

# Install specific package
npm install package-name --save

# Reinstall all dependencies
rm -rf node_modules package-lock.json
npm install
```

---

## 🧪 Local Testing (Optional)

```bash
# Install Firebase emulators
npm install -g firebase-tools

# Start emulators
firebase emulators:start

# OR start only functions emulator
firebase emulators:start --only functions

# Deploy to emulator for testing
firebase deploy --only functions --project=demo-test
```

---

## 📊 Monitoring Commands

```bash
# View function invocation count
firebase functions:list

# Stream logs continuously
firebase functions:log --follow

# View logs for specific function
firebase functions:log --only onFollowCreated

# View logs from last hour
firebase functions:log --since 1h

# View logs with errors only
firebase functions:log --level error
```

---

## 🔐 Authentication Commands

```bash
# Login
firebase login

# Login with different account
firebase login --reauth

# Logout
firebase logout

# List logged in accounts
firebase login:list

# Use CI token (for automated deployments)
firebase login:ci
```

---

## 🌍 Multi-Project Commands

```bash
# Add project alias
firebase use --add

# List project aliases
firebase use

# Switch to specific project
firebase use production
firebase use staging

# Deploy to specific project
firebase deploy --only functions --project=production
```

---

## 🚀 Quick Deploy Sequence

Copy this entire block for fast deployment:

```bash
cd /path/to/AMENAPP && \
cd functions && \
npm install && \
cd .. && \
firebase deploy --only functions && \
firebase functions:list && \
echo "✅ Deployment complete!"
```

---

## 🔄 Quick Update Sequence

When you modify functions:

```bash
cd /path/to/AMENAPP && \
firebase deploy --only functions && \
echo "✅ Functions updated!"
```

---

## 📝 Common Function Names

For your AMEN app, these are your function names:

```
onFollowCreated          - Triggers when someone follows you
onAmenCreated           - Triggers when someone says Amen
onCommentCreated        - Triggers when someone comments
onMessageCreated        - Triggers when someone messages you
createConversation      - Creates new conversations
sendMessage             - Sends messages
markMessagesAsRead      - Marks messages as read
deleteMessage           - Deletes messages
cleanupTypingIndicators - Cleans up old typing indicators
```

---

## 🎯 Target Specific Functions

```bash
# Deploy only notification functions
firebase deploy --only functions:onFollowCreated,onAmenCreated,onCommentCreated,onMessageCreated

# Deploy only messaging functions
firebase deploy --only functions:createConversation,sendMessage,markMessagesAsRead,deleteMessage

# View logs for notification functions
firebase functions:log --only onFollowCreated,onAmenCreated

# Delete all messaging functions
firebase functions:delete createConversation sendMessage markMessagesAsRead deleteMessage
```

---

## ⚡ Speed Tips

```bash
# Deploy faster by skipping predeploy hooks
firebase deploy --only functions --force

# Deploy without functions validation
firebase deploy --only functions --debug

# Use specific region
firebase deploy --only functions:us-central1

# Parallel deployment (if you have many functions)
firebase deploy --only functions --parallel
```

---

## 🔍 Debugging Commands

```bash
# Enable debug mode
firebase --debug deploy --only functions

# Check firebase.json configuration
cat firebase.json

# Verify functions directory structure
ls -la functions/

# Check package.json
cat functions/package.json

# Verify Node version in functions
cat functions/.node-version

# Test function syntax
cd functions && npm run lint
```

---

## 💾 Backup & Restore

```bash
# Backup functions code
cp -r functions functions_backup_$(date +%Y%m%d)

# Download current functions
firebase functions:config:get > functions/config.json

# Compare local and deployed functions
firebase functions:list
```

---

## 🎨 Pretty Logging

```bash
# Watch logs with syntax highlighting (requires jq)
firebase functions:log --follow | jq

# Export logs to file
firebase functions:log > functions_logs_$(date +%Y%m%d).txt

# Search logs for specific text
firebase functions:log | grep "ERROR"

# Count function invocations
firebase functions:log | grep "Function execution took" | wc -l
```

---

## 📱 Test Notifications

```bash
# After deployment, test from command line using curl

# Test follow notification
curl -X POST https://us-central1-your-project.cloudfunctions.net/testNotification \
  -H "Content-Type: application/json" \
  -d '{"type": "follow", "userId": "test-user-id"}'

# Test amen notification  
curl -X POST https://us-central1-your-project.cloudfunctions.net/testNotification \
  -H "Content-Type: application/json" \
  -d '{"type": "amen", "userId": "test-user-id", "postId": "test-post-id"}'
```

---

## ✅ Quick Health Check

Run this to verify everything is working:

```bash
echo "=== Firebase Functions Health Check ===" && \
firebase projects:list && \
echo "" && \
firebase use && \
echo "" && \
firebase functions:list && \
echo "" && \
echo "✅ All systems operational!"
```

---

## 🆘 Emergency Commands

If something goes wrong:

```bash
# Rollback to previous version (if available)
firebase functions:delete functionName
firebase deploy --only functions:functionName

# Clear local cache
rm -rf node_modules package-lock.json
npm cache clean --force
npm install

# Reinstall Firebase CLI
npm uninstall -g firebase-tools
npm install -g firebase-tools

# Check for Firebase outages
curl -I https://www.firebasestatus.com/

# View Firebase service status
open https://status.firebase.google.com/
```

---

## 📚 Helpful One-Liners

```bash
# Count deployed functions
firebase functions:list | grep -c "function"

# Show function regions
firebase functions:list | grep "region"

# Find errors in logs
firebase functions:log | grep -i "error" | tail -20

# Show last 10 function executions
firebase functions:log | head -10

# Calculate total invocations today
firebase functions:log --since 1d | grep "Function execution" | wc -l
```

---

## 🎯 Complete First-Time Setup

Copy this entire block for first-time setup:

```bash
# Complete first-time deployment
echo "🚀 Starting Firebase Functions deployment..." && \
npm install -g firebase-tools && \
firebase login && \
cd /path/to/AMENAPP && \
firebase use your-project-id && \
cd functions && \
npm install && \
cd .. && \
gcloud services enable cloudfunctions.googleapis.com && \
gcloud services enable fcm.googleapis.com && \
gcloud services enable cloudscheduler.googleapis.com && \
firebase deploy --only functions && \
firebase functions:list && \
echo "✅ Deployment complete! Functions are live!" && \
echo "📊 View logs: firebase functions:log --follow"
```

**Don't forget to replace:**
- `/path/to/AMENAPP` with your actual project path
- `your-project-id` with your Firebase project ID

---

## 📖 Reference

For more detailed information, see:
- `DEPLOY_NOW.md` - Complete deployment guide
- `FIREBASE_FUNCTIONS_SETUP.md` - Detailed setup instructions
- `IMPLEMENTATION_COMPLETE_SUMMARY.md` - Feature overview

---

**Pro Tip:** Bookmark this file for quick access to commands! 🔖
