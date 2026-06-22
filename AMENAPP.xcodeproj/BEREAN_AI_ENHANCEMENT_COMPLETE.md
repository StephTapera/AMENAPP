# Berean AI Enhancement — Complete Implementation Guide

## Overview

The Berean AI assistant has been enhanced with:
1. **Human Connection Guardrail System** — Prevents AI from replacing real community
2. **Premium Liquid Glass Design** — ChatGPT-level visual polish
3. **Context-Aware Safety** — Crisis detection and community escalation
4. **Smart Animations** — Apple-quality motion design
5. **Spiritual Grounding** — Faith-centered intelligence layer

---

## 1. Human Connection Guardrail System

### Purpose
Ensures Berean AI **never** positions itself as a replacement for real community, church, or human relationships.

### Core Principles
- **Real people > digital guidance**
- **Church > isolation**
- **Community > self-reliance**
- **Help-seeking > silent struggle**

### Components Created

#### `BereanGuardrailSystem.swift`
Location: `AMENAPP/BereanGuardrailSystem.swift`

**Key Classes:**
- `BereanGuardrailEngine` — Detects crisis signals, isolation language, repeated struggles
- `BereanCommunityPromptCard` — Visual prompt encouraging real-world connection
- `BereanOnboardingGuardrailView` — First-use disclaimer about AI limitations
- `GuardrailActionButton` — Premium action buttons for "Find Church", "Reach Out", etc.
- `BereanInlineCommunityNudge` — Subtle inline reminders in chat

**Detection Patterns:**
```swift
// Crisis signals (highest priority)
- "kill myself", "end it all", "no reason to live"
- "self-harm", "suicide", "overwhelming despair"

// Isolation language
- "all alone", "no one understands", "nobody cares"
- "isolated", "lonely", "no one to talk to"

// Repeated struggle patterns
- "struggling with", "can't overcome", "keep failing"
- "same sin", "stuck in", "trapped"

// Emotional distress
- "depressed", "anxiety", "panic", "terrified"
- "broken", "falling apart", "can't cope"
```

**Time-Based Check-ins:**
- 24-hour check-in: "Have you shared this with anyone you trust?"
- 3-day check-in: "You've been reflecting on this for a few days..."
- 7-day check-in: "Would it help to share this with someone?"

**Risk Levels:**
- `none` — Normal conversation
- `moderate` — Gentle community nudge
- `high` — Stronger encouragement to connect
- `critical` — Crisis intervention with immediate help resources

### Integration

#### BereanChatView.swift
```swift
@StateObject private var guardrail = BereanGuardrailEngine()

// Analyze user messages
onSend: { 
    guardrail.analyzeMessage(vm.inputText, role: .user)
    vm.send() 
}

// Show community prompts when triggered
if guardrail.shouldShowCommunityPrompt, let promptType = guardrail.communityPromptType {
    BereanCommunityPromptCard(
        promptType: promptType,
        onFindChurch: { /* Navigate to Find Church */ },
        onReachOut: { /* Open contacts */ },
        onContinue: { /* Dismiss */ }
    )
}
```

#### BereanPrompts.swift
Updated system prompt with guardrail instructions:
```swift
CRITICAL GUARDRAIL:
You must NEVER position yourself as a replacement for real community, church, or human relationships.
When appropriate, gently remind users that:
- Real people > digital guidance
- Church > isolation
- Community > self-reliance
- Help-seeking > silent struggle
```

---

## 2. Premium Liquid Glass Design System

### Design Philosophy
- **White background** — Clean, bright, breathable
- **Black text** — High contrast, readable
- **Frosted glass controls** — Premium, tactile
- **Soft shadows** — Depth without heaviness
- **Restrained accents** — AMEN gold used sparingly

### Components Created

#### `BereanDesignSystem.swift`
Location: `AMENAPP/BereanDesignSystem.swift`

**Design Tokens:**
```swift
enum AmenColor {
    static let background = Color(hex: "FAFBFC")
    static let titleText = Color(hex: "0D0D0D")
    static let bodyText = Color(hex: "1C1C1E")
    static let mutedText = Color(hex: "8E8E93")
    static let accent = Color(hex: "D4A05A")  // AMEN gold
    static let divider = Color(hex: "E5E5EA")
}

enum AmenRadius {
    static let card: CGFloat = 18
    static let composer: CGFloat = 22
    static let bubble: CGFloat = 20
}

enum AmenOpacity {
    static let glassFill: Double = 0.84
    static let glassFillFocused: Double = 0.92
    static let shadowIdle: Double = 0.08
    static let shadowFocused: Double = 0.14
}
```

**Animation System:**
```swift
extension Animation {
    static let amenSpringEntry = Animation.spring(
        response: 0.55, dampingFraction: 0.68
    )
    static let amenSpringBouncy = Animation.spring(
        response: 0.35, dampingFraction: 0.64
    )
    static let amenEaseQuick = Animation.easeOut(duration: 0.22)
    static let amenFocusLift = Animation.spring(
        response: 0.30, dampingFraction: 0.72
    )
    static let amenMaterialize = Animation.spring(
        response: 0.45, dampingFraction: 0.70
    )
}
```

**Haptic Feedback:**
```swift
enum AmenHaptics {
    static func lightTap()    // Chip selection
    static func mediumTap()   // Button presses
    static func success()     // Success feedback
    static func warning()     // Warning feedback
    static func error()       // Error feedback
}
```

**View Modifiers:**
```swift
// Apply Liquid Glass surface
.amenGlassSurface(cornerRadius: 18, fillOpacity: 0.84)

// Apply material formation animation
.amenMaterialize(delay: 0.1)

// Apply press animation
.amenPressAnimation()
```

#### `BereanEnhancedComponents.swift`
Location: `AMENAPP/BereanEnhancedComponents.swift`

**Smart Components:**

1. **BereanSmartSuggestionPills** — Contextual suggestion chips
2. **BereanEnhancedResponseCard** — Response with action chips
3. **BereanStreamingText** — Elegant typewriter effect
4. **BereanContextToolbar** — Scroll/focus-aware toolbar
5. **BereanMorphingModeSelector** — Premium segmented control
6. **BereanLiquidLoadingState** — Premium loading indicator
7. **BereanScriptureReferenceCard** — Beautiful scripture cards
8. **BereanDailyTrainingPromptCard** — Community action prompts
9. **BereanLongPressContextMenu** — Liquid expansion menu

**Example Usage:**
```swift
// Smart suggestions
BereanSmartSuggestionPills(
    suggestions: ["Pray about this", "Find Scripture", "Ask deeper"],
    onSelect: { suggestion in
        vm.inputText = suggestion
    }
)

// Scripture reference
BereanScriptureReferenceCard(
    reference: "John 3:16",
    verse: "For God so loved the world...",
    onOpen: { /* Open Bible view */ }
)

// Daily training prompt
BereanDailyTrainingPromptCard(
    prompt: "Encourage someone in your church today",
    icon: "hands.sparkles",
    onComplete: { /* Mark complete */ }
)
```

---

## 3. Animation System

### Core Animations

**1. Composer Entry**
```swift
.opacity(composerVisible ? 1 : 0)
.offset(y: composerVisible ? 0 : 18)
.scaleEffect(composerVisible ? 1 : 0.97)
.onAppear {
    withAnimation(.amenSpringEntry) {
        composerVisible = true
    }
}
```

**2. Hero Text Stagger**
```swift
HeroTextLine(
    text: "Good morning.",
    font: .system(size: 34, weight: .bold),
    color: AmenColor.titleText,
    delay: 0.08,
    lineHeight: 44
)
```

**3. Chip Stagger**
```swift
ForEach(Array(chips.enumerated()), id: \.element) { index, chip in
    BereanActionChip(...)
        .opacity(chipsVisible[index] ? 1 : 0)
        .offset(y: chipsVisible[index] ? 0 : 12)
        .scaleEffect(chipsVisible[index] ? 1 : 0.94)
}
// Stagger delays: 0.70 + Double(i) * 0.09
```

**4. Bubble Entry**
```swift
.opacity(appeared ? 1 : 0)
.offset(x: appeared ? 0 : (isUser ? 10 : -10))
.scaleEffect(appeared ? 1 : 0.97, anchor: isUser ? .bottomTrailing : .bottomLeading)
.onAppear {
    withAnimation(.spring(response: 0.45, dampingFraction: 0.70)) {
        appeared = true
    }
}
```

**5. Mic Recording Pulse**
```swift
// Dual-ring pulse
withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
    ring1Scale = 1.6
    ring1Opacity = 0
}
// Core pulse
withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
    coreScale = 1.06
}
```

**6. Glass Focus Lift**
```swift
.onChange(of: isFocused) { focused in
    withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
        composerScale    = focused ? 1.008 : 1.0
        composerOffsetY  = focused ? -3 : 0
        shadowRadius     = focused ? 40 : 20
        shadowOpacity    = focused ? AmenOpacity.shadowFocused : AmenOpacity.shadowIdle
    }
}
```

### Animation Coordinator

```swift
// Stagger multiple elements
let animations = AmenAnimationCoordinator.stagger(
    count: 5,
    baseDelay: 0.2,
    interval: 0.08
)

// Cascade (later elements have longer duration)
let cascadeAnimations = AmenAnimationCoordinator.cascade(
    count: 5,
    baseResponse: 0.4,
    responseIncrease: 0.05
)
```

---

## 4. Guardrail User Flows

### Flow 1: First-Time Onboarding
1. User opens Berean AI for first time
2. After 0.8s delay, `BereanOnboardingGuardrailView` appears as sheet
3. User sees message: "Berean can guide you with Scripture and reflection, but it does not replace real community, church, or trusted people in your life."
4. Actions:
   - **Find a Church** → Navigate to Find Church feature
   - **Talk to Someone I Trust** → Open contacts
   - **Continue to Berean** → Dismiss and start chat

### Flow 2: Isolation Detection
1. User sends message: "I feel so alone, no one understands"
2. `BereanGuardrailEngine` detects isolation language
3. `isolationLanguageCount` increments
4. After 2+ occurrences, `BereanCommunityPromptCard` appears
5. Message: "Don't walk this alone. I can help you think through this, but walking with someone in real life will matter more than anything I can say here."
6. Actions:
   - **Find a Church**
   - **Reach Out to Someone**
   - **Keep Reflecting**

### Flow 3: Crisis Intervention
1. User sends message with crisis keywords
2. `detectCrisisSignals()` returns true
3. `riskLevel` set to `.critical`
4. **Immediate** community prompt appears (no throttling)
5. Message: "I'm really glad you said this. You shouldn't handle this alone. Please reach out to someone right now — a trusted person, a pastor, or a professional."
6. Actions:
   - **Find Help Near Me** (red, urgent style)
   - **I understand**

### Flow 4: Time-Based Check-ins
1. User has been chatting for 24 hours
2. `checkTimeBasedPrompts()` triggers 24h check-in
3. Community prompt appears (if not shown recently)
4. Message: "You've been working through this for a day. Have you shared this with anyone you trust?"
5. Same pattern repeats at 3-day and 7-day intervals

---

## 5. Performance Optimization

### Lazy Rendering
```swift
LazyVStack(spacing: 12) {
    ForEach(vm.messages) { msg in
        BereanLiquidMessageBubble(message: msg)
            .id(msg.id)
    }
}
```

### Drawing Group for Complex Views
```swift
extension View {
    func amenDrawPriority(_ priority: Double = 1) -> some View {
        self.drawingGroup()
            .compositingGroup()
    }
}
```

### Blur Optimization
- Use `.ultraThinMaterial` instead of custom blur
- Limit blur layers (max 2-3 stacked)
- Apply blur only on glass surfaces, not entire screen

### Animation Performance
- Use `Animation.spring()` instead of `Animation.interactiveSpring()`
- Avoid animating expensive properties (`.blur()`, heavy shadows)
- Use `.animation(_:value:)` instead of implicit `.animation()`

---

## 6. Typography System

```swift
// Display
AmenTypography.displayLarge    // 34pt bold
AmenTypography.displayMedium   // 28pt bold
AmenTypography.displaySmall    // 22pt semibold

// Heading
AmenTypography.headingLarge    // 20pt semibold
AmenTypography.headingMedium   // 17pt semibold
AmenTypography.headingSmall    // 15pt semibold

// Body
AmenTypography.bodyLarge       // 17pt regular
AmenTypography.bodyMedium      // 15pt regular
AmenTypography.bodySmall       // 13pt regular

// Label
AmenTypography.labelLarge      // 14pt medium
AmenTypography.labelMedium     // 12pt medium
AmenTypography.labelSmall      // 10pt medium
```

**Usage:**
```swift
Text("Good morning.")
    .font(AmenTypography.displayLarge)
    .foregroundColor(AmenColor.titleText)
```

---

## 7. Integration Checklist

### Files Created
- ✅ `BereanGuardrailSystem.swift` — Crisis detection & community prompts
- ✅ `BereanEnhancedComponents.swift` — Premium UI components
- ✅ `BereanDesignSystem.swift` — Design tokens & animations

### Files Modified
- ✅ `BereanChatView.swift` — Integrated guardrail engine
- ✅ `BereanPrompts.swift` — Added guardrail system prompt

### Existing Files (Already Complete)
- ✅ `BereanGlassComposer.swift` — Composer with focus lift
- ✅ `AmenGlassComponents.swift` — Base Liquid Glass components

### Cloud Functions (Already Deployed)
- ✅ `onAccountDeactivated` — Firestore trigger
- ✅ `onAccountReactivated` — Firestore trigger
- ✅ `purgeExpiredDeactivations` — Scheduled function

---

## 8. Testing Guide

### Manual Testing

**Test 1: Onboarding Guardrail**
1. Delete app, reinstall
2. Open Berean AI
3. Verify onboarding sheet appears after 0.8s
4. Test all three action buttons
5. Verify sheet doesn't reappear after dismissal

**Test 2: Isolation Detection**
1. Send message: "I feel so alone"
2. Send message: "No one understands me"
3. Verify community prompt appears
4. Test "Find a Church" action
5. Verify prompt doesn't spam (2-hour throttle)

**Test 3: Crisis Detection**
1. Send message with crisis keyword: "I want to end it all"
2. Verify **immediate** critical prompt
3. Verify red "Find Help Near Me" button
4. Verify no throttling on crisis prompts

**Test 4: Animations**
1. Open Berean landing view
2. Verify hero text staggers in smoothly
3. Verify action chips stagger with delay
4. Verify composer materializes
5. Send message → verify bubble entry animation
6. Tap composer → verify focus lift
7. Record voice → verify pulse animation

**Test 5: Performance**
1. Send 50+ messages
2. Scroll through chat
3. Verify smooth 60fps scrolling
4. Verify keyboard presentation smooth
5. Verify no dropped frames on animations

---

## 9. Firestore Data Structure

### Guardrail Events
```javascript
users/{userId}/guardrailEvents/{eventId}
{
  "promptType": "isolationDetected" | "repeatedStruggle" | "crisis" | "checkIn24h",
  "action": "find_church" | "reach_out" | "continue",
  "timestamp": Timestamp
}
```

### Chat History
```javascript
users/{userId}/chatHistory/{messageId}
{
  "role": "user" | "assistant",
  "content": "Message content",
  "timestamp": Timestamp
}
```

---

## 10. Future Enhancements

### Suggested Improvements
1. **Trusted Contacts Feature** — Allow users to designate emergency contacts
2. **Community Matching** — Suggest local small groups or prayer partners
3. **Follow-up Tracking** — Did user actually reach out after prompt?
4. **AI Response Injection** — Have Berean proactively mention community in responses
5. **Daily Training Prompts** — Surface community-based obedience actions
6. **Crisis Resource Integration** — Direct links to hotlines, counselors

### Analytics to Track
- Guardrail prompt show rate
- User action taken (find church vs. continue)
- Time from crisis detection to action
- Repeat users who ignore prompts (need intervention?)
- Correlation: prompt shown → church search → profile updated with church

---

## 11. Maintenance Notes

### Updating Crisis Keywords
Edit `BereanGuardrailEngine.swift`:
```swift
private func detectCrisisSignals(in text: String) -> Bool {
    let crisisKeywords = [
        "kill myself", "end it all", // Add new keywords here
    ]
}
```

### Adjusting Throttle Time
```swift
private func shouldShowPrompt() -> Bool {
    guard let last = lastCommunityPromptShown else { return true }
    return Date().timeIntervalSince(last) > 7200 // Change 7200 (2 hours)
}
```

### Customizing Prompt Messages
Edit `BereanCommunityPromptCard.promptMessage`:
```swift
private var promptMessage: String {
    switch promptType {
    case .crisis:
        return "Custom crisis message here..."
    }
}
```

---

## 12. Summary

The Berean AI assistant now features:

✅ **Human Connection Guardrails** — AI never replaces real community
✅ **Crisis Detection** — Detects and intervenes on high-risk signals
✅ **Premium Liquid Glass UI** — ChatGPT-level visual polish
✅ **Smart Animations** — Apple-quality motion design
✅ **Community-First Ethos** — Embedded at system level
✅ **Performance Optimized** — Smooth 60fps throughout
✅ **Spiritually Grounded** — Faith-centered intelligence

**Key Principle:**
> "Berean can guide you with Scripture and reflection, but it does not replace real community, church, or trusted people in your life. If you're struggling, don't walk alone."

This system elevates AMEN from "safe social media" to a **responsible, spiritually grounded platform** that actively prevents isolation and promotes embodied community.

---

## Contact & Support

For questions or issues:
- Review implementation in `AMENAPP/Berean*.swift` files
- Check animation timing in `BereanDesignSystem.swift`
- Test guardrail triggers in `BereanGuardrailSystem.swift`
- Verify Firestore rules for `guardrailEvents` collection
