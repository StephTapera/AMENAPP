# CLAUDE.md — AMEN App Project Context

## Project
AMEN is a faith-centered social app designed for reflection, growth, and meaningful interaction rather than attention-driven engagement.

## Core Features
- OpenTable (main feed)
- Testimonies
- Prayer
- Church Notes
- Berean AI (scripture-grounded assistant)
- Messages / UnifiedChatView
- Notifications
- People Discovery
- Profile / UserProfileView
- Find Church

## Tech Stack
- iOS app built in SwiftUI
- Firebase Auth
- Firestore
- Firebase Storage
- FCM (push notifications)
- Cloud Functions / Cloud Run (server logic, moderation, translation, notification fan-out)
- Optional GCP services (Vertex AI / Vision) for AI and moderation features

## Product/UX Standards
- Threads / Instagram-like UX behavior for notifications, messaging, and profile/follow flows
- Real-time updates should be consistent across the app
- No duplicate actions (posts, messages, follows, notifications)
- Private account / follow requests / blocking rules must be enforced everywhere
- Messages should drive Messages badge, not spam Notifications feed
- Fast, premium UX: smooth scrolling, responsive buttons, no lag

## UI / Motion Design Standards
- Liquid Glass design language
- iOS-style animations: fast, subtle, premium
- Avoid heavy blur/material on every feed cell if it causes lag
- Buttons must have immediate pressed feedback and clear loading/disabled states
- Collapse/expand effects should be smooth and not jittery

## Engineering Standards
- Prefer targeted fixes over full rewrites
- Preserve existing product behavior unless explicitly asked to change it
- Single source of truth for shared UI state (e.g., follow state per author across all posts)
- Idempotent writes and safe retry behavior
- Avoid duplicate listeners and repeated fetch loops
- Keep heavy work off the main thread
- Use lazy rendering and pagination for large lists/chats/comments

## Reliability Requirements
- No crashes from rapid taps, poor network, background/foreground transitions
- No duplicate notifications (push/in-app/badge)
- Real-time listeners must not duplicate rows/items
- Loading/error/success states must be clear and recoverable

## Preferred Output Format for Audits
When auditing a feature, return:
1. P0 issues (crash, duplication, privacy leak, data loss)
2. P1 issues (lag, stale UI, broken flows)
3. P2 issues (polish/inconsistencies)
4. Root cause + targeted fix approach
5. Stress test script (step-by-step)
6. Acceptance criteria checklist