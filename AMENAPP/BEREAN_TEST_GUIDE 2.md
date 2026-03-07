# Berean AI — Quick Test Guide

## 🚀 Quick Smoke Tests (5 minutes)

### Test 1: Speed Test ⚡
**Goal**: Verify 2-3x faster responses

```
1. Open Berean AI
2. Send: "What is John 3:16?"
3. Time the response
   ✅ PASS: Response in <2 seconds
   ❌ FAIL: Response takes >3 seconds
```

**Check Console**:
```
Should see: "📊 Context: simple query → 2 messages (saved ~X messages)"
Should see: "✅ Response generation completed in 1.XX s"
```

---

### Test 2: Duplicate Prevention 🛡️
**Goal**: No duplicate messages

```
1. Open Berean AI
2. Send a message
3. While it's generating, tap send button 10 times rapidly
   ✅ PASS: Only 1 message appears
   ❌ FAIL: Multiple identical messages appear
```

**Check Console**:
```
Should see: "⏭️ Skipping duplicate request" (if tapped multiple times)
OR "⚠️ Request already in flight, ignoring duplicate"
```

---

### Test 3: Citation Validation ✅
**Goal**: No fake verse references displayed

```
1. Open Berean AI
2. Send: "Tell me about Genesis 100:1 and Matthew 50:20"
   (These are fake - Genesis only has 50 chapters, Matthew only has 28)
   
   ✅ PASS: Response appears but fake references are NOT shown as verse chips
   ❌ FAIL: Fake references appear as clickable verse chips
```

**Check Console**:
```
Should see: "⚠️ Invalid chapter: Genesis only has 50 chapters, got 100"
Should see: "⚠️ Invalid chapter: Matthew only has 28 chapters, got 50"
```

---

### Test 4: Memory Stability 💾
**Goal**: App doesn't crash or slow down in long chats

```
1. Open Berean AI
2. Send 120 messages (use copy-paste to speed up)
3. App should remain responsive
   ✅ PASS: App still responsive, no crash
   ❌ FAIL: App lags severely or crashes
```

**Check Console**:
```
After ~100 messages, should see: 
"📉 Trimmed conversation history to 100 messages"
```

---

### Test 5: State Recovery 🔄
**Goal**: UI never gets stuck

```
Test A: Cancel during generation
1. Send a message
2. Immediately tap the stop button
   ✅ PASS: UI returns to normal, can send another message
   ❌ FAIL: UI stuck in loading state

Test B: Error recovery
1. Turn off WiFi
2. Try to send a message
3. Turn WiFi back on
   ✅ PASS: Error banner shows, can retry
   ❌ FAIL: App stuck or crashes

Test C: Background/foreground
1. Send a message
2. While it's generating, background the app (swipe up)
3. Return to app after 2 seconds
   ✅ PASS: Generation completes or recovers properly
   ❌ FAIL: App stuck or duplicates message
```

---

## 📊 Performance Verification

### Monitor Console Output

**Good Signs** ✅:
```
📊 Context: simple query → 2 messages (saved ~8 messages)
✅ Response generation completed in 1.23s
📊 Context used: 2 messages | References found: 3
⚡ Performance: Response time: 1.50s | Avg: 1.45s
```

**Warning Signs** ⚠️:
```
⚠️ Slow response detected: 6.50s
⚠️ Invalid scripture reference detected: Genesis 100:1
⚠️ Request already in flight, ignoring duplicate
```

**Error Signs** ❌:
```
❌ OpenAI error: ...
❌ Network error: ...
❌ Received empty response from AI
```

---

## 🎯 Expected Performance

### Response Times (After Fixes)
| Query Type | Target | Acceptable | Unacceptable |
|------------|--------|------------|--------------|
| Simple ("What is John 3:16?") | <2s | 2-3s | >3s |
| Follow-up ("Tell me more") | <3s | 3-4s | >5s |
| Complex study | <5s | 5-6s | >8s |

### Context Usage
| Query Type | Target Messages | Max Acceptable |
|------------|-----------------|----------------|
| Simple | 2 | 4 |
| Follow-up | 4 | 6 |
| Study | 6 | 10 |

---

## 🔧 Troubleshooting

### Problem: Responses still slow (>3s for simple queries)

**Check**:
1. Console shows context size
   - Should see: "2 messages" for simple queries
   - If seeing "10 messages", fix didn't apply

2. Network speed
   - Run on WiFi for accurate testing
   - Mobile networks may add latency

3. API endpoint
   - Verify Genkit/OpenAI service is responding quickly
   - Check API logs for backend latency

---

### Problem: Seeing duplicate messages

**Check**:
1. Console for duplicate prevention logs
   - Should see: "⏭️ Skipping duplicate request"
   - If not seeing this, idempotency check may not be working

2. Request ID tracking
   - Add debug log in `generateResponseStreaming`:
     ```swift
     print("🆔 Request ID: \(requestId)")
     print("🆔 Pending: \(String(describing: pendingRequestId))")
     print("🆔 Completed: \(completedRequestIds.count)")
     ```

---

### Problem: Fake citations still appearing

**Check**:
1. Console for validation logs
   - Should see: "⚠️ Invalid reference filtered: ..."
   - If not seeing this, validation may be bypassed

2. Verify `isValidReference` is being called
   - Add debug log in `extractVerseReferences`:
     ```swift
     print("🔍 Checking reference: \(reference)")
     print("🔍 Is valid: \(isValidReference(reference))")
     ```

---

### Problem: App crashing in long chats

**Check**:
1. Console for trimming logs
   - Should see: "📉 Trimmed conversation history to 100 messages"
   - If not seeing this, trimming may not be working

2. Memory usage in Xcode
   - Run Instruments → Allocations
   - Watch for unbounded growth

3. Verify `appendMessage` is being called
   - Search code for `.append(` on `messages` array
   - Should all go through `appendMessage()` now

---

## ✅ Ship Checklist

Before shipping to production:

- [ ] All 5 smoke tests pass
- [ ] Response times meet targets
- [ ] No duplicate messages in stress test
- [ ] No fake citations in validation test
- [ ] Memory stable after 120+ messages
- [ ] UI recovers from all error conditions
- [ ] Console shows expected performance logs
- [ ] No red errors in 20-minute test session

---

## 📈 Success Metrics

### What to Track in Production

1. **Average Response Time**
   - Target: <2.5s
   - Already logged in console

2. **Citation Accuracy**
   - Target: 100% valid references
   - Monitor console warnings

3. **Duplicate Rate**
   - Target: 0%
   - Monitor for duplicate request logs

4. **Crash Rate**
   - Target: <0.1%
   - Monitor with Firebase Crashlytics

5. **API Cost**
   - Target: 50-70% reduction vs. old implementation
   - Monitor token usage in API logs

---

## 🎉 Expected Improvements

### User Experience
- ⚡ 2-3x faster for simple questions
- 🎯 100% accurate scripture citations
- 💪 Stable performance in long conversations
- 🛡️ No duplicate messages
- 🔄 Reliable error recovery

### Cost Savings
- 💰 50-70% reduction in API tokens
- 📉 Lower infrastructure costs
- 🚀 Can handle more users with same budget

### Developer Experience
- 📊 Better logging and observability
- 🐛 Easier to debug issues
- 🧪 Testable and verifiable fixes
- 📝 Clear performance metrics
