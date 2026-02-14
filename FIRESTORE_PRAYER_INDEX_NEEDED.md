# Missing Firestore Index for Prayer Requests

## Error
```
Listen for query at prayerRequests failed: The query requires an index.
```

## Create Index

Click this link to create the required index:

https://console.firebase.google.com/v1/r/project/amen-5e359/firestore/indexes?create_composite=ClFwcm9qZWN0cy9hbWVuLTVlMzU5L2RhdGFiYXNlcy8oZGVmYXVsdCkvY29sbGVjdGlvbkdyb3Vwcy9wcmF5ZXJSZXF1ZXN0cy9pbmRleGVzL18QARoKCgZ1c2VySWQQARoNCgljcmVhdGVkQXQQAhoMCghfX25hbWVfXxAC

## What This Index Does

This creates a composite index on the `prayerRequests` collection for:
- Field: `userId` (Ascending)
- Field: `createdAt` (Descending)  
- Field: `__name__` (Descending)

This allows efficient querying of prayer requests by user, sorted by creation date.

## Steps

1. Click the link above
2. Click "Create Index"
3. Wait 2-5 minutes for index to build
4. Prayer requests will load faster

## Status

Index will show as "Building..." then "Enabled" when ready.
