# Creator Spaces Rules Contract

Deployable rules should enforce these boundaries before Creator Spaces is enabled in production Remote Config.

## Firestore

```rules
match /mediaAssets/{assetId} {
  allow read: if request.auth != null && (
    resource.data.authorId == request.auth.uid ||
    resource.data.moderation.status == 'approved'
  );
  allow create, update, delete: if false; // Cloud Functions only.
}

match /provenanceLabels/{labelId} {
  allow read: if request.auth != null;
  allow create, update, delete: if false; // Prevent spoofed authenticity.
}

match /memoryNodes/{nodeId} {
  allow read: if request.auth != null && resource.data.authorId == request.auth.uid;
  allow create, update, delete: if false; // Server-owned graph spine.
}

match /creatorSafetyChecks/{checkId} {
  allow read: if request.auth != null && resource.data.authorId == request.auth.uid;
  allow write: if false;
}

match /guardianMediaQueue/{assetId} {
  allow read, write: if false;
}
```

## Storage

```rules
match /creator_spaces/{uid}/{assetId}/{fileName=**} {
  allow read: if request.auth != null && request.auth.uid == uid;
  allow write: if request.auth != null
    && request.auth.uid == uid
    && request.resource.size < 250 * 1024 * 1024
    && request.resource.contentType in [
      'image/jpeg', 'image/jpg', 'image/png', 'image/heic', 'image/heif',
      'video/mp4', 'video/quicktime', 'video/x-m4v',
      'audio/mpeg', 'audio/mp4', 'audio/m4a', 'audio/aac', 'audio/wav', 'audio/x-wav'
    ];
  allow delete: if request.auth != null && request.auth.uid == uid;
}
```

Do not expose EXIF/device fingerprints or private context publicly. Any public media detail UI should read the server-rendered provenance label only.
