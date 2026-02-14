# App Store Connect Subscription Setup Guide
## Berean Pro - In-App Subscriptions

This guide will walk you through setting up auto-renewable subscriptions in App Store Connect for Berean Pro.

---

## 📋 Prerequisites

Before you begin, ensure you have:
- ✅ An active Apple Developer account ($99/year)
- ✅ App created in App Store Connect
- ✅ Signed Paid Applications Agreement in App Store Connect
- ✅ Tax and banking information completed

---

## 🎯 Step 1: Create Subscription Group

1. **Log in to App Store Connect**
   - Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
   - Select your app (AMENAPP)

2. **Navigate to Subscriptions**
   - Click on your app
   - Go to **"Monetization" → "Subscriptions"**
   - Click **"+" (Create Subscription Group)**

3. **Configure Subscription Group**
   - **Subscription Group Name**: `Berean Pro`
   - **Reference Name**: `berean_pro_subscriptions`
   - Click **"Create"**

---

## 💳 Step 2: Add Subscription Products

You need to create **three subscription products** as defined in `PremiumManager.swift`:

### 2.1 Monthly Subscription

1. Click **"+" next to your subscription group**
2. Fill in the details:

**Product Information:**
- **Product ID**: `com.amen.pro.monthly`
- **Reference Name**: `Berean Pro Monthly`
- **Subscription Duration**: `1 Month`

**Subscription Prices:**
- Click **"Add Subscription Price"**
- Select **"Start from Scratch"**
- **Price**: `$4.99 USD` (or your preferred price)
- **Availability**: All territories

**Subscription Localizations:**
- **Language**: English (U.S.)
- **Subscription Display Name**: `Monthly Subscription`
- **Description**: `Unlimited AI Bible study, advanced features, and priority support`

**Review Information (for App Review):**
- **Screenshot**: Upload a screenshot showing the subscription benefits
- **Review Notes**: "This subscription unlocks unlimited AI-powered Bible study features, conversation history, and premium support."

3. Click **"Save"**

---

### 2.2 Yearly Subscription (Recommended)

1. Click **"+" again** to add another subscription
2. Fill in the details:

**Product Information:**
- **Product ID**: `com.amen.pro.yearly`
- **Reference Name**: `Berean Pro Yearly`
- **Subscription Duration**: `1 Year`

**Subscription Prices:**
- Click **"Add Subscription Price"**
- **Price**: `$29.99 USD` (40% savings vs monthly)
- **Availability**: All territories

**Subscription Localizations:**
- **Language**: English (U.S.)
- **Subscription Display Name**: `Yearly Subscription`
- **Description**: `Save 40% with annual billing. Unlimited AI Bible study, advanced features, and priority support.`

**Review Information:**
- **Screenshot**: Same screenshot as monthly
- **Review Notes**: "Annual subscription with 40% savings. Unlocks all premium features."

3. Click **"Save"**

---

### 2.3 Lifetime Purchase (Non-Consumable)

⚠️ **Important**: Lifetime purchases are **Non-Consumable** products, NOT subscriptions.

1. Go back to your app overview
2. Navigate to **"Monetization" → "In-App Purchases"**
3. Click **"+" (Manage)**

**Product Information:**
- **Type**: Select **"Non-Consumable"**
- **Product ID**: `com.amen.pro.lifetime`
- **Reference Name**: `Berean Pro Lifetime`

**Pricing:**
- Click **"Add In-App Purchase Price"**
- **Price**: `$99.99 USD` (one-time purchase)
- **Availability**: All territories

**Localizations:**
- **Language**: English (U.S.)
- **Display Name**: `Lifetime Access`
- **Description**: `One-time purchase for unlimited lifetime access to all premium features`

**Review Information:**
- **Screenshot**: Upload screenshot
- **Review Notes**: "One-time lifetime purchase for all premium features. No recurring charges."

4. Click **"Save"**

---

## 🎁 Step 3: Configure Free Trial

1. Go back to **Subscriptions** → **Berean Pro group**
2. Click on **Monthly Subscription**
3. Scroll to **"Subscription Pricing"**
4. Click **"Edit"** on your pricing

**Introductory Offer:**
- Click **"Add Introductory Offer"**
- **Type**: `Free`
- **Duration**: `7 Days`
- **Eligibility**: `New Subscribers`

5. **Save** changes

6. Repeat for **Yearly Subscription**

---

## 🔄 Step 4: Configure Subscription Settings

### 4.1 Subscription Group Settings

1. Click on the **Berean Pro** subscription group
2. Configure these settings:

**Family Sharing:**
- ✅ **Enable Family Sharing** (allows subscribers to share with family members)

**Subscription Management URL:**
- Leave blank (uses default App Store management)

---

### 4.2 App-Level Subscription Settings

1. Go to **App Store** tab → **Subscriptions**
2. Configure:

**Subscription Status URL:**
- Leave blank for now (optional: set up for server-side verification)

**App Store Server Notifications:**
- Leave blank for now (optional: for real-time updates)

---

## 🧪 Step 5: Test Subscriptions (Sandbox)

Before releasing, you must test your subscriptions in the sandbox environment.

### 5.1 Create Sandbox Tester Account

1. In App Store Connect, go to **"Users and Access"**
2. Click **"Sandbox Testers"**
3. Click **"+" to add a tester**
4. Fill in details:
   - **First Name**: Test
   - **Last Name**: User
   - **Email**: `testuser@example.com` (must be unique, not a real Apple ID)
   - **Password**: Create a strong password
   - **Country**: United States
5. Click **"Create"**

### 5.2 Test on Device

1. **Sign out** of production App Store on test device:
   - Settings → App Store → Sign Out

2. **Install your app** from Xcode or TestFlight

3. **Trigger purchase** in the app

4. When prompted, **sign in with sandbox tester account**

5. **Complete purchase** (you won't be charged)

6. **Verify**:
   - Check `PremiumManager.hasProAccess` is `true`
   - Verify unlimited messages work
   - Test restore purchases

### 5.3 Test Scenarios

Test these scenarios:
- ✅ Monthly subscription purchase
- ✅ Yearly subscription purchase
- ✅ Lifetime purchase
- ✅ Free trial activation
- ✅ Restore purchases after reinstall
- ✅ Subscription cancellation (Settings → Subscriptions)
- ✅ Subscription renewal (auto-renews every 5 minutes in sandbox)

---

## 📱 Step 6: App Metadata for Subscriptions

### 6.1 Update App Privacy

1. Go to **App Privacy**
2. Add **"Purchases"** data type if not already listed
3. Specify how subscription data is used

### 6.2 Age Rating

1. Review **Age Rating**
2. Ensure it's appropriate (likely 4+)

### 6.3 App Store Description

Update your app description to mention premium features:

```
🌟 BEREAN PRO FEATURES:

Upgrade to Berean Pro for:
• Unlimited AI Bible study conversations
• Advanced devotionals and study plans
• Save and sync conversation history
• Share insights with community
• Priority support
• Ad-free experience

Try free for 7 days, then $4.99/month or $29.99/year (save 40%)
```

---

## 🚀 Step 7: Submit for Review

### 7.1 Prepare for App Review

Create a demo video or detailed review notes showing:
1. How to access the premium upgrade screen
2. The subscription purchase flow
3. What premium features unlock

### 7.2 Review Notes Template

Add this to your App Review notes:

```
SUBSCRIPTION TESTING:

Test Account: [Your sandbox tester email]
Password: [Sandbox tester password]

TO TEST SUBSCRIPTIONS:
1. Open the app and navigate to Resources → Berean AI
2. Tap the "Pro" badge in the top right
3. Select a subscription plan
4. Complete purchase with sandbox account

PREMIUM FEATURES UNLOCKED:
- Unlimited AI conversations (free tier: 10/day)
- Advanced AI features
- Conversation history
- Save messages
- Share to feed

All subscriptions include a 7-day free trial.
```

---

## ✅ Step 8: Post-Launch Monitoring

### 8.1 Monitor Subscription Analytics

In App Store Connect:
- Go to **"Trends" → "Subscriptions"**
- Monitor:
  - Active subscribers
  - Trial conversion rate
  - Churn rate
  - Retention

### 8.2 Customer Support

Be prepared to help users with:
- Purchase issues
- Restore purchases
- Cancellation requests
- Refund requests

---

## 🔧 Troubleshooting

### Common Issues:

**"Cannot connect to iTunes Store"**
- Solution: Check network connection, try again later

**"This In-App Purchase has already been bought"**
- Solution: Use `restorePurchases()` instead

**Subscriptions not loading**
- Check Product IDs match exactly: `com.amen.pro.monthly`, etc.
- Ensure Paid Applications Agreement is signed
- Wait 2-3 hours after creating products

**"Invalid Product ID"**
- Ensure products are in "Ready to Submit" state
- Check Bundle ID matches
- Clear Xcode derived data and rebuild

---

## 📊 Pricing Recommendations

Based on current market research:

| Plan | Price | Value Proposition |
|------|-------|-------------------|
| Monthly | $4.99 | Flexible, try before committing |
| Yearly | $29.99 | Save 40% ($59.88 → $29.99) |
| Lifetime | $99.99 | One-time, best long-term value |

**Most Popular**: Yearly (40% savings attracts conversions)

---

## 🎯 Next Steps

After setting up subscriptions:

1. ✅ Test all three subscription tiers
2. ✅ Test free trial flow
3. ✅ Test restore purchases
4. ✅ Update app screenshots to show "Pro" badge
5. ✅ Create marketing materials highlighting premium features
6. ✅ Submit app for review
7. ✅ Monitor conversion rates and optimize pricing

---

## 📚 Additional Resources

- [Apple: Implementing In-App Purchases](https://developer.apple.com/in-app-purchase/)
- [Apple: Testing In-App Purchases](https://developer.apple.com/documentation/storekit/in-app_purchase/testing_in-app_purchases_with_sandbox)
- [StoreKit 2 Documentation](https://developer.apple.com/documentation/storekit/in-app_purchase/original_api_for_in-app_purchase)

---

## ✨ Your Implementation is Complete!

The app already has:
- ✅ `PremiumManager.swift` - StoreKit 2 implementation
- ✅ `PremiumUpgradeView.swift` - Beautiful black & white Liquid Glass UI
- ✅ Usage tracking (10 free messages/day)
- ✅ Purchase & restore functionality
- ✅ Product IDs configured

**You just need to create the products in App Store Connect!**

---

## 💡 Pro Tips

1. **Offer trials**: 7-day trials significantly boost conversions
2. **Annual push**: Highlight the 40% savings on yearly
3. **Visual design**: The new Liquid Glass design will stand out
4. **Clear value**: Show exactly what users get with Pro
5. **Easy restore**: Make restore purchases prominent for users switching devices

Good luck with your launch! 🚀
