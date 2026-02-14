# Google Cloud Integration Guide

Complete setup guide for Cloud Storage, Cloud Functions 2nd Gen, and Vertex AI Crisis Detection.

---

## 📦 What Was Implemented

### 1. **Cloud Storage for Media Files**
- Upload images, videos, and audio for posts
- Automatic compression and optimization
- CDN-backed delivery for fast loading
- File: `CloudStorageService.swift`

### 2. **Cloud Functions 2nd Gen for Moderation**
- Auto-moderate posts and comments
- Real-time content checking
- Flagging system for inappropriate content
- Files: `cloud-functions/moderation.js`

### 3. **Vertex AI Crisis Detection**
- Detect suicidal ideation and self-harm
- Classify crisis levels (low/medium/high/critical)
- Automatic resource recommendations
- Admin alerts for critical cases
- Files: `VertexAICrisisDetectionService.swift`, `cloud-functions/crisis-detection.js`

---

## 🚀 Deployment Steps

### Prerequisites

```bash
# Install Firebase CLI
npm install -g firebase-tools

# Login to Firebase
firebase login

# Initialize project (if not already done)
firebase init
```

### Step 1: Enable Google Cloud Services

```bash
# Enable Cloud Storage
gcloud services enable storage-googleapis.com

# Enable Vertex AI
gcloud services enable aiplatform.googleapis.com

# Enable Cloud Functions
gcloud services enable cloudfunctions.googleapis.com
```

### Step 2: Deploy Cloud Functions

```bash
cd cloud-functions

# Install dependencies
npm install

# Deploy all functions
firebase deploy --only functions

# Or deploy individually
firebase deploy --only functions:moderatePost
firebase deploy --only functions:moderateComment
firebase deploy --only functions:checkContent
firebase deploy --only functions:detectCrisis
```

### Step 3: Configure Firebase Storage Rules

Update `storage.rules`:

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    // Posts media - user can upload their own
    match /posts/{userId}/{mediaType}/{fileName} {
      allow read: if true; // Public read
      allow write: if request.auth != null
                   && request.auth.uid == userId
                   && request.resource.size < 10 * 1024 * 1024; // 10MB limit
    }

    // Profile images
    match /profiles/{userId}/{fileName} {
      allow read: if true;
      allow write: if request.auth != null
                   && request.auth.uid == userId
                   && request.resource.size < 5 * 1024 * 1024; // 5MB limit
    }
  }
}
```

Deploy storage rules:
```bash
firebase deploy --only storage
```

### Step 4: Update Firestore Security Rules

Add to `firestore.rules`:

```javascript
// Moderation queue - admin only
match /moderationQueue/{docId} {
  allow read: if isAdmin();
  allow write: if false; // Cloud Functions only
}

// Crisis detections - admin only
match /crisisDetections/{docId} {
  allow read: if isAdmin();
  allow write: if false; // Cloud Functions only
}

// Crisis alerts - admin only
match /crisisAlerts/{docId} {
  allow read: if isAdmin();
  allow write: if false; // Cloud Functions only
}

function isAdmin() {
  return request.auth != null &&
         get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin';
}
```

Deploy Firestore rules:
```bash
firebase deploy --only firestore:rules
```

### Step 5: Set Up Environment Variables

```bash
# Set project ID
firebase functions:config:set project.id="your-project-id"

# Get current config
firebase functions:config:get
```

---

## 💻 iOS Integration

### 1. Cloud Storage - Upload Post Media

```swift
import SwiftUI

struct CreatePostView: View {
    @State private var selectedImage: UIImage?
    @State private var uploadProgress: Double = 0
    @State private var isUploading = false

    var body: some View {
        VStack {
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()

                if isUploading {
                    ProgressView(value: uploadProgress)
                        .padding()
                    Text("\(Int(uploadProgress * 100))% uploaded")
                }

                Button("Upload") {
                    uploadImage()
                }
                .disabled(isUploading)
            }
        }
    }

    func uploadImage() {
        guard let image = selectedImage,
              let userId = AuthService.shared.currentUser?.id else { return }

        isUploading = true

        Task {
            do {
                let imageURL = try await CloudStorageService.shared.uploadImage(
                    image: image,
                    userId: userId,
                    compressionQuality: 0.7
                ) { progress in
                    await MainActor.run {
                        uploadProgress = progress
                    }
                }

                print("✅ Image uploaded: \(imageURL)")

                // Save post to Firestore with image URL
                await savePost(imageURL: imageURL)

            } catch {
                print("❌ Upload failed: \(error)")
            }

            await MainActor.run {
                isUploading = false
            }
        }
    }

    func savePost(imageURL: String) async {
        // Your post creation logic
    }
}
```

### 2. Crisis Detection - Check Messages

```swift
struct MessageInputView: View {
    @State private var messageText = ""
    @State private var showCrisisAlert = false
    @State private var crisisResources: [CrisisResource] = []

    var body: some View {
        VStack {
            TextField("Type a message...", text: $messageText)

            Button("Send") {
                checkForCrisis()
            }
        }
        .alert("Crisis Support Resources", isPresented: $showCrisisAlert) {
            Button("Get Help Now") {
                // Open crisis resources
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("We noticed you might be going through a difficult time. Please consider reaching out to these resources.")
        }
    }

    func checkForCrisis() {
        guard let userId = AuthService.shared.currentUser?.id else { return }

        Task {
            do {
                let result = try await VertexAICrisisDetectionService.shared.detectCrisis(
                    in: messageText,
                    userId: userId
                )

                if result.shouldAlert {
                    await MainActor.run {
                        crisisResources = VertexAICrisisDetectionService.shared.getCrisisResources(for: result)
                        showCrisisAlert = true
                    }
                } else {
                    // Send message normally
                    await sendMessage()
                }

            } catch {
                print("❌ Crisis detection failed: \(error)")
                // Send message anyway (fail open for user experience)
                await sendMessage()
            }
        }
    }

    func sendMessage() async {
        // Your message sending logic
    }
}
```

### 3. Real-time Moderation Check

```swift
func checkContentBeforePosting(text: String) async -> Bool {
    do {
        let functions = Functions.functions()
        let result = try await functions.httpsCallable("checkContent").call(["text": text])

        guard let data = result.data as? [String: Any],
              let isAppropriate = data["isAppropriate"] as? Bool else {
            return true // Fail open if check fails
        }

        if !isAppropriate {
            if let reason = data["reason"] as? String {
                print("⚠️ Content flagged: \(reason)")
            }
            return false
        }

        return true

    } catch {
        print("❌ Moderation check failed: \(error)")
        return true // Fail open
    }
}
```

---

## 📊 Monitoring & Analytics

### View Logs

```bash
# View all function logs
firebase functions:log

# View specific function
firebase functions:log --only moderatePost

# Real-time logs
firebase functions:log --follow
```

### Cloud Console Dashboards

1. **Cloud Functions**: https://console.cloud.google.com/functions
2. **Cloud Storage**: https://console.cloud.google.com/storage
3. **Vertex AI**: https://console.cloud.google.com/vertex-ai
4. **Firestore**: https://console.firebase.google.com/project/[PROJECT_ID]/firestore

---

## 💰 Cost Estimates

### Cloud Storage
- **Storage**: $0.026/GB/month
- **Downloads**: $0.12/GB
- **Operations**: $0.05/10k operations
- **Estimate**: ~$5-20/month for 1000 active users

### Cloud Functions 2nd Gen
- **Invocations**: $0.40/million
- **Compute**: $0.00001667/GB-second
- **Networking**: $0.12/GB
- **Estimate**: ~$10-30/month for 1000 active users

### Vertex AI (Gemini 1.5 Flash)
- **Input**: $0.075 per 1M characters
- **Output**: $0.30 per 1M characters
- **Estimate**: ~$5-15/month for 1000 active users

**Total estimated cost**: $20-65/month for 1000 active users

---

## 🔒 Security Best Practices

1. **Storage Rules**: Always validate file size and type
2. **Function Auth**: Verify user authentication in callable functions
3. **Rate Limiting**: Implement rate limits to prevent abuse
4. **Data Privacy**: Never store full message content in crisis logs
5. **Admin Access**: Restrict moderation queue to admin users only

---

## 🧪 Testing

### Test Cloud Functions Locally

```bash
cd cloud-functions

# Install Firebase emulators
firebase init emulators

# Start emulators
firebase emulators:start

# Test moderation function
curl -X POST http://localhost:5001/[PROJECT_ID]/us-central1/checkContent \
  -H "Content-Type: application/json" \
  -d '{"data":{"text":"test message"}}'
```

### Test Crisis Detection

```swift
// In your test file
func testCrisisDetection() async throws {
    let service = VertexAICrisisDetectionService.shared

    let result = try await service.detectCrisis(
        in: "I feel really stressed about work",
        userId: "test-user-id"
    )

    XCTAssertEqual(result.level, .low)
}
```

---

## 📝 Next Steps

1. ✅ Deploy Cloud Functions
2. ✅ Update storage and Firestore rules
3. ✅ Integrate CloudStorageService into CreatePostView
4. ✅ Add crisis detection to messaging
5. ✅ Create admin dashboard for moderation queue
6. ✅ Set up monitoring alerts
7. ✅ Test with real users in staging environment

---

## 🆘 Troubleshooting

### Function Deployment Fails

```bash
# Check function logs
firebase functions:log --only moderatePost

# Verify dependencies
cd cloud-functions && npm install

# Check IAM permissions
gcloud projects get-iam-policy [PROJECT_ID]
```

### Storage Upload Fails

- Check storage rules
- Verify file size limits
- Check user authentication
- Verify Firebase Storage is enabled in console

### Vertex AI Errors

- Ensure Vertex AI API is enabled
- Check region (must be us-central1)
- Verify service account has Vertex AI permissions
- Check quota limits in Cloud Console

---

## 📚 Resources

- [Cloud Storage Documentation](https://firebase.google.com/docs/storage)
- [Cloud Functions 2nd Gen](https://firebase.google.com/docs/functions/2nd-gen)
- [Vertex AI Gemini API](https://cloud.google.com/vertex-ai/docs/generative-ai/model-reference/gemini)
- [Firebase Security Rules](https://firebase.google.com/docs/rules)

---

**Integration Complete!** 🎉

Your app now has:
- ✅ Professional media storage with CDN
- ✅ AI-powered content moderation
- ✅ Crisis detection and intervention
- ✅ Scalable serverless architecture
