# AI Functions - Vertex AI Permission Fix

## Issue

Cloud Functions are deployed but returning errors:
- Scripture references: Returns 0 verses (should return 5)
- Note summary: Returns "Error generating summary"

## Root Cause

The Cloud Functions service account doesn't have permission to call Vertex AI.

## Fix

### Option 1: Enable Vertex AI API (Quick)

1. Go to [Google Cloud Console](https://console.cloud.google.com/apis/library/aiplatform.googleapis.com?project=amen-5e359)

2. Click **"Enable"** button

3. Wait 1-2 minutes for the API to activate

4. Test again in the app - it should work immediately

### Option 2: Grant Service Account Permissions (If Option 1 doesn't work)

1. **Find your Cloud Functions service account**:
   ```
   amen-5e359@appspot.gserviceaccount.com
   ```

2. **Go to IAM & Admin**:
   - https://console.cloud.google.com/iam-admin/iam?project=amen-5e359

3. **Find the service account** in the list:
   - Look for: `amen-5e359@appspot.gserviceaccount.com`
   - Or: `App Engine default service account`

4. **Click Edit (pencil icon)**

5. **Add Role**:
   - Click "+ ADD ANOTHER ROLE"
   - Search for: `Vertex AI User`
   - Select: **Vertex AI User**
   - Click **Save**

6. **Wait 1-2 minutes** for permissions to propagate

7. **Test again** in the app

## Verification

After fixing, you should see in console logs:

```
📖 [AI SCRIPTURE] Finding related verses for: Romans 12:1
📤 [AI SCRIPTURE] Sending request to Cloud Function...
✅ [AI SCRIPTURE] Found 5 related verses
```

And:

```
📝 [AI SUMMARY] Generating summary for note (1016 chars)
📤 [AI SUMMARY] Sending request to Cloud Function...
✅ [AI SUMMARY] Summary generated: "Living Sacrifices and Transformation"
```

## Alternative: Check Logs in Firebase Console

1. Go to [Firebase Console - Functions](https://console.firebase.google.com/project/amen-5e359/functions)

2. Click on `findScriptureReferences` or `summarizeNote`

3. Click **LOGS** tab

4. Look for error messages like:
   - "Permission denied"
   - "API not enabled"
   - "403 Forbidden"

This will show the exact Vertex AI error.

## Quick Links

- **Enable Vertex AI API**: https://console.cloud.google.com/apis/library/aiplatform.googleapis.com?project=amen-5e359
- **IAM Console**: https://console.cloud.google.com/iam-admin/iam?project=amen-5e359
- **Firebase Functions**: https://console.firebase.google.com/project/amen-5e359/functions
- **Cloud Functions Logs**: https://console.cloud.google.com/logs/query?project=amen-5e359

## Expected Behavior After Fix

1. Create a church note with "Romans 12:1"
2. AI finds 5 related verses like:
   - Romans 8:1 - "No condemnation in Christ"
   - Ephesians 4:1 - "Walk worthy of your calling"
   - 1 Peter 2:5 - "Living stones, spiritual house"
   - etc.
3. Summary includes:
   - Main theme
   - Scripture references
   - Key points
   - Action steps

## Cost After Fix

Once working:
- ~$0.000025 per scripture lookup
- ~$0.0000625 per summary
- **Total**: ~$0.10/month for 1000 notes

## Next Steps

1. Enable Vertex AI API (Option 1 above)
2. Test in app
3. If still not working, grant service account permissions (Option 2)
4. Check Firebase Console logs for detailed errors

The functions are deployed correctly - just need API permissions enabled!
