# Creator Firestore Rules Draft

Rules intent:
- Creator data is private to the owner by default.
- Only server-side logic can mutate moderation and processing fields.
- Church-scoped assets require role checks.

```rules
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    function isSignedIn() {
      return request.auth != null;
    }

    function isOwner(userId) {
      return isSignedIn() && request.auth.uid == userId;
    }

    match /users/{userId}/creatorProjects/{projectId} {
      allow read, create, update, delete: if isOwner(userId);
      allow update: if isOwner(userId)
        && !('status' in request.resource.data.diff(resource.data).changedKeys())
        && !('moderationStatus' in request.resource.data.diff(resource.data).changedKeys());
    }

    match /users/{userId}/creatorAssets/{assetId} {
      allow read, create, update, delete: if isOwner(userId);
      allow update: if isOwner(userId)
        && !('moderationStatus' in request.resource.data.diff(resource.data).changedKeys());
    }

    match /users/{userId}/creatorBrandKits/{brandKitId} {
      allow read, write: if isOwner(userId);
    }

    match /users/{userId}/creatorDrafts/{draftId} {
      allow read, write: if isOwner(userId);
    }

    match /users/{userId}/creatorExports/{exportId} {
      allow read, write: if isOwner(userId);
    }

    match /users/{userId}/creatorJobs/{jobId} {
      allow read: if isOwner(userId);
      allow create: if isOwner(userId);
      allow update: if isOwner(userId) && request.resource.data.status == resource.data.status;
    }

    match /creatorTemplates/{templateId} {
      allow read: if true;
      allow write: if false;
    }

    match /creatorFeatureFlags/{flagId} {
      allow read: if isSignedIn();
      allow write: if false;
    }

    match /creatorEntitlements/{userId} {
      allow read: if isOwner(userId);
      allow write: if false;
    }

    match /creatorUsageAnalytics/{dayKey} {
      allow write: if isSignedIn();
      allow read: if false;
    }

    match /churches/{churchId}/creatorBrandKits/{brandKitId} {
      allow read: if isSignedIn();
      allow write: if false;
    }
  }
}
```
