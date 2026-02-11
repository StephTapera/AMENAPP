# 🛒 In-App Purchase Integration Guide
**Complete Step-by-Step Setup for AMEN Premium**

---

## ✅ COMPLETED STEPS (Steps 1-2)

### Step 1: Premium Files Added ✅
- ✅ `PremiumManager.swift` - Manages subscriptions and usage tracking
- ✅ `PremiumUpgradeView.swift` - Beautiful premium upgrade UI
- ✅ Files moved to correct Xcode location: `AMENAPP/AMENAPP/`

### Step 2: Code Integration ✅
- ✅ `StoreKit` framework imported in `AMENAPPApp.swift`
- ✅ `PremiumManager` initialized in app lifecycle
- ✅ Entitlements file updated with In-App Payments capability
- ✅ Premium upgrade state already exists in `BereanAIAssistantView`

---

## 📋 NEXT STEPS (Steps 3-4)

## STEP 3: App Store Connect Setup (15-20 minutes)

### 3.1 Create App Store Connect Account (if not already done)
1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Sign in with your Apple Developer account
3. If you don't have an Apple Developer account:
   - Go to [developer.apple.com](https://developer.apple.com)
   - Enroll in Apple Developer Program ($99/year)
   - Wait for approval (usually 24-48 hours)

### 3.2 Create Your App in App Store Connect
1. **Go to Apps Section**
   - Click "My Apps"
   - Click the "+" button → "New App"

2. **Fill in App Information**
   - **Platform**: iOS
   - **Name**: AMEN
   - **Primary Language**: English (or your preferred language)
   - **Bundle ID**: Select your bundle ID (e.g., `com.amen.app`)
   - **SKU**: Create unique identifier (e.g., `AMEN-APP-2026`)
   - **User Access**: Full Access (default)

3. **Click "Create"**

### 3.3 Create In-App Purchase Products
1. **Navigate to In-App Purchases**
   - In your app page, scroll down
   - Click "In-App Purchases" section
   - Click the "+" button

2. **Create Monthly Subscription**
   - Select: "Auto-Renewable Subscription"
   - Click "Create"
   
   **Product Information:**
   - **Reference Name**: `AMEN Pro Monthly`
   - **Product ID**: `com.amen.pro.monthly` ⚠️ MUST MATCH PremiumManager.swift
   - **Subscription Group**: Create new group → `AMEN Pro Subscriptions`
   
   **Subscription Duration:**
   - Select: `1 Month`
   
   **Subscription Prices:**
   - Click "Add Subscription Price"
   - **Base Price**: $4.99 USD per month
   - Apple will auto-convert to other currencies
   
   **App Store Localization (English):**
   - **Display Name**: `AMEN Pro Monthly`
   - **Description**: `Unlock unlimited AI Bible study, daily verses, and premium features with monthly access.`
   
   **Review Information:**
   - **Screenshot**: (You'll upload this later during app review)
   - **Review Notes**: `Monthly subscription for AMEN Pro features`
   
   - Click "Save"

3. **Create Yearly Subscription (RECOMMENDED - Most Popular)**
   - Click "+" again
   - Select: "Auto-Renewable Subscription"
   
   **Product Information:**
   - **Reference Name**: `AMEN Pro Yearly`
   - **Product ID**: `com.amen.pro.yearly` ⚠️ MUST MATCH PremiumManager.swift
   - **Subscription Group**: Select existing `AMEN Pro Subscriptions`
   
   **Subscription Duration:**
   - Select: `1 Year`
   
   **Subscription Prices:**
   - **Base Price**: $29.99 USD per year (Save 50% vs monthly!)
   
   **App Store Localization (English):**
   - **Display Name**: `AMEN Pro Yearly`
   - **Description**: `Get unlimited AI Bible study, daily verses, and premium features for an entire year. Best value!`
   
   - Click "Save"

4. **Create Lifetime Purchase (OPTIONAL - Highest Revenue)**
   - Click "+" again
   - Select: "Non-Consumable" (one-time purchase)
   
   **Product Information:**
   - **Reference Name**: `AMEN Pro Lifetime`
   - **Product ID**: `com.amen.pro.lifetime` ⚠️ MUST MATCH PremiumManager.swift
   
   **Price:**
   - Select: **Tier 10** (~$99.99 USD)
   
   **App Store Localization (English):**
   - **Display Name**: `AMEN Pro Lifetime`
   - **Description**: `One-time payment for lifetime access to all AMEN Pro features. Never pay again!`
   
   - Click "Save"

### 3.4 Submit In-App Purchases for Review
1. **Add Review Information to Subscription Group**
   - Go to "Subscription Groups" → `AMEN Pro Subscriptions`
   - Click "Edit"
   - **Display Name**: `AMEN Pro`
   - Click "Save"

2. **Each Product Must Be "Ready to Submit"**
   - Go to each product you created
   - Ensure all sections have green checkmarks
   - Status should say "Ready to Submit"

3. **Products will be reviewed with your app submission**

---

## STEP 4: Xcode Project Configuration (10 minutes)

### 4.1 Enable In-App Purchase Capability
1. **Open Xcode**
   - Open your `AMENAPP.xcodeproj`

2. **Select Your Target**
   - Click on your project in the navigator (top blue icon)
   - Select "AMENAPP" under TARGETS

3. **Go to Signing & Capabilities**
   - Click the "Signing & Capabilities" tab
   - Click "+ Capability" button (top left)
   - Search for: `In-App Purchase`
   - Double-click to add it

4. **Verify Entitlements**
   - Your `AMENAPP.entitlements` file should now include:
   ```xml
   <key>com.apple.developer.in-app-payments</key>
   <array>
       <string>merchant.com.amen.app</string>
   </array>
   ```
   - ✅ This has already been added by Claude!

### 4.2 Configure StoreKit Testing (Test Without Real Money!)
1. **Create StoreKit Configuration File**
   - In Xcode: `File` → `New` → `File...`
   - Scroll down to "Resource"
   - Select: "StoreKit Configuration File"
   - Name it: `Configuration.storekit`
   - Click "Create"

2. **Add Products to StoreKit Configuration**
   - Click the "+" button at the bottom
   - Select: "Add Auto-Renewable Subscription"
   
   **For Monthly Subscription:**
   - **Reference Name**: `AMEN Pro Monthly`
   - **Product ID**: `com.amen.pro.monthly`
   - **Price**: `$4.99`
   - **Subscription Duration**: `1 Month`
   - **Free Trial Duration**: `7 Days` (optional)
   
   **Repeat for Yearly:**
   - **Product ID**: `com.amen.pro.yearly`
   - **Price**: `$29.99`
   - **Subscription Duration**: `1 Year`
   
   **Repeat for Lifetime:**
   - Product Type: "Add Non-Consumable"
   - **Product ID**: `com.amen.pro.lifetime`
   - **Price**: `$99.99`

3. **Enable StoreKit Testing in Scheme**
   - Click your scheme dropdown (top left, next to Play button)
   - Select "Edit Scheme..."
   - Select "Run" in left sidebar
   - Go to "Options" tab
   - Under "StoreKit Configuration", select: `Configuration.storekit`
   - Click "Close"

### 4.3 Test Your Integration (Before App Store Submission!)
1. **Build and Run Your App**
   - Click the Play button or press `⌘ + R`

2. **Test Premium Features**
   - Navigate to an AI feature (Berean AI, Daily Verse)
   - Try to exceed the free message limit (10 messages)
   - You should see the premium upgrade sheet appear
   
3. **Test Purchase Flow**
   - Select a subscription plan
   - Click "Start Free Trial"
   - StoreKit will simulate the purchase (no real money!)
   - Verify the premium features unlock

4. **Test Restore Purchases**
   - Delete the app
   - Reinstall and run
   - Go to premium upgrade screen
   - Click "Restore Purchases"
   - Verify your purchase is restored

### 4.4 Add Premium Usage Tracking to AI Features

**Already Integrated in BereanAIAssistantView.swift:**
```swift
@State private var showPremiumUpgrade = false
```

**To trigger the premium upgrade prompt, add this check before sending AI messages:**
```swift
// Check if user can send message
if !PremiumManager.shared.canSendMessage() {
    // Show premium upgrade
    showPremiumUpgrade = true
    return
}

// Increment message count for free users
PremiumManager.shared.incrementMessageCount()

// Send AI message
await viewModel.sendMessage(messageText)
```

**Add the premium upgrade sheet:**
```swift
.sheet(isPresented: $showPremiumUpgrade) {
    PremiumUpgradeView()
}
```

---

## 🏗️ BUILD YOUR APP (Step 5)

### Build for Testing (Simulator)
```bash
# Build for iPhone simulator
⌘ + B (Command + B)
```

### Build for TestFlight (Real Device Testing)
1. **Select Real Device or "Any iOS Device"**
   - Change scheme from "iPhone Simulator" to your device

2. **Archive Your App**
   - `Product` → `Archive`
   - Wait for build to complete (~5-10 minutes)

3. **Upload to App Store Connect**
   - When archive completes, "Organizer" window opens
   - Click "Distribute App"
   - Select "App Store Connect"
   - Click "Upload"
   - Click "Next" → "Upload"

4. **Wait for Processing**
   - Go to App Store Connect
   - Navigate to your app → TestFlight
   - Wait for build to process (~10-30 minutes)

5. **Test on Real Device**
   - Add yourself as a tester
   - Download TestFlight app on iPhone
   - Install your app
   - Test premium features with StoreKit sandbox

---

## 🧪 TESTING CHECKLIST

### ✅ Before Submission
- [ ] In-App Purchases created in App Store Connect
- [ ] Product IDs match exactly in code
- [ ] StoreKit configuration file created
- [ ] App builds without errors
- [ ] Premium upgrade UI appears when limit reached
- [ ] Purchase flow completes successfully
- [ ] Restore purchases works
- [ ] Premium features unlock after purchase
- [ ] Free tier limits work correctly (10 messages/day)
- [ ] Daily usage resets properly

### ✅ Sandbox Testing (TestFlight)
- [ ] Test on real device with sandbox account
- [ ] Purchase monthly subscription
- [ ] Verify features unlock
- [ ] Cancel subscription and verify expiration
- [ ] Test yearly subscription
- [ ] Test lifetime purchase
- [ ] Test restore purchases
- [ ] Test purchase on multiple devices

---

## 📊 PRODUCT IDS REFERENCE

**⚠️ These MUST match exactly in App Store Connect and PremiumManager.swift**

| Product Name | Product ID | Type | Price |
|--------------|------------|------|-------|
| AMEN Pro Monthly | `com.amen.pro.monthly` | Auto-Renewable | $4.99/month |
| AMEN Pro Yearly | `com.amen.pro.yearly` | Auto-Renewable | $29.99/year |
| AMEN Pro Lifetime | `com.amen.pro.lifetime` | Non-Consumable | $99.99 one-time |

---

## 🎯 INTEGRATION POINTS

### Where Premium is Already Set Up:
1. ✅ **PremiumManager.swift** - Core subscription logic
2. ✅ **PremiumUpgradeView.swift** - Premium UI
3. ✅ **AMENAPPApp.swift** - App initialization
4. ✅ **BereanAIAssistantView.swift** - Has `showPremiumUpgrade` state

### Where to Add Premium Checks:
1. **AI Bible Study (Berean AI)** - Limit 10 messages/day for free
2. **Daily Verse AI** - Limit 10 requests/day for free
3. **AI Search** - Limit 10 searches/day for free
4. **Any other AI features** - Apply same limits

---

## 🚨 COMMON ISSUES & FIXES

### Issue: Products not loading in app
**Fix:** 
- Verify Product IDs match exactly (case-sensitive!)
- Wait 2-4 hours after creating products in App Store Connect
- Ensure app bundle ID matches in App Store Connect
- Check Xcode logs for StoreKit errors

### Issue: Purchase fails with "Cannot connect to iTunes Store"
**Fix:**
- Sign out of App Store on device: Settings → App Store → Sign Out
- Sign in with sandbox test account
- Sandbox accounts are created in App Store Connect → Users and Access → Sandbox Testers

### Issue: "This product is not available"
**Fix:**
- Ensure product status is "Ready to Submit" in App Store Connect
- Wait 2-4 hours for products to propagate
- Verify you're using the correct bundle ID

### Issue: Purchase succeeds but features don't unlock
**Fix:**
- Check `PremiumManager.shared.hasProAccess` in debugger
- Verify `grantPremiumAccess()` is being called
- Check UserDefaults is persisting: `UserDefaults.standard.bool(forKey: "hasProAccess")`

---

## 📱 QUICK TESTING COMMANDS

### Test Premium Status in Xcode Console
```swift
// Print current premium status
print("Has Pro Access: \(PremiumManager.shared.hasProAccess)")
print("Messages Used: \(PremiumManager.shared.freeMessagesUsed)")
print("Messages Remaining: \(PremiumManager.shared.freeMessagesRemaining)")
```

### Manually Grant Premium (For Testing)
```swift
// In Xcode console (lldb):
po UserDefaults.standard.set(true, forKey: "hasProAccess")
po PremiumManager.shared.loadPremiumStatus()
```

### Reset Free Tier Usage (For Testing)
```swift
// In Xcode console (lldb):
po UserDefaults.standard.set(0, forKey: "freeMessagesUsed")
po UserDefaults.standard.set(Date(), forKey: "lastMessageResetDate")
po PremiumManager.shared.loadUsageData()
```

---

## 🎉 YOU'RE READY!

### Next Steps:
1. **Complete Step 3**: Create products in App Store Connect
2. **Complete Step 4**: Configure Xcode project
3. **Build and Test**: Verify everything works
4. **Submit for Review**: Upload to App Store

### Questions?
- Check StoreKit documentation: [developer.apple.com/storekit](https://developer.apple.com/storekit)
- Test with sandbox accounts before going live
- Monitor App Store Connect for review status

---

**🔥 Pro Tips:**
- **7-day free trial** is automatically configured for all subscriptions
- **Yearly plan** typically gets 60-70% of subscriptions (best value!)
- **Lifetime plan** appeals to power users (highest revenue per user)
- **Test thoroughly** before submitting - in-app purchases are heavily reviewed
- **Provide clear value** - users need to understand what they're paying for

**Good luck with your launch! 🚀**
