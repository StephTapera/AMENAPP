# Amen Hero-First Liquid Glass Design Guide

Amen's interface direction is content-first, hero-led, and Liquid Glass native. The content is the UI. Interface chrome should fade away until needed, and navigation should behave like a living layer above content instead of a permanent structure.

This guide belongs beside the CommunityOS design system because it defines how feeds, profiles, churches, search, notifications, and AI action layers should feel across the app.

## Core Principle

Prioritize people, videos, creators, churches, sermons, spaces, events, and moments over headers, menus, buttons, and static navigation.

Content should begin almost immediately below the status bar. Glass controls float above it, materialize as context demands, and never fully replace the content beneath them.

## Hero-First Content Architecture

Feed screens should let images and video stretch toward the top edge, with transparent navigation floating above. Creator and church profiles should start with a full-width hero image, live service, worship image, event hero, or atmosphere media. Profile identity, avatar, follow actions, catalog access, and contextual controls should layer on top of that content.

The content becomes the identity.

## Blended Top Navigation

The top area is not a fixed header. It is a glass layer.

Expanded state:

- Status bar, search, and profile controls float above content.
- Background blur and opacity are near zero.
- Content remains visually dominant.

Scroll state:

- Content slides underneath the navigation layer.
- Blur, opacity, and shadow increase gradually.
- The navigation should never become a fully solid bar.

Suggested progression:

- At top: 0% blur, 0% background.
- Early scroll: 10% blur, 10% opacity.
- Continued scroll: 20% blur, 20% opacity.
- Settled scroll: readable glass with visible content underneath.

## Floating Liquid Glass Tab Bar

The tab bar should float as a physical object above content. It should use a large radius, soft glass, subtle border, and restrained elevation.

Expanded state:

- Show Home, Spaces, Create, Search, and Profile with labels.
- Use a wider pill and comfortable spacing.

Scroll down:

- Shrink the bar.
- Hide labels.
- Keep icons visible.
- Compress width and reduce glass thickness.
- Animate over roughly 150-250 ms.

Deep reading mode:

- Keep only a small floating pill with icons.
- Maximize content visibility.

Reverse scroll:

- Expand smoothly and predictively.
- Avoid jumps and abrupt snaps.

## Morphing Interface Philosophy

Every interactive component should have progressive states:

- Rest: minimal.
- Hover or touch proximity: elevated.
- Active: expanded.
- Focus: detailed.

Components should morph rather than abruptly appear. A notification bell can become a stack, then a notification center. A card can become a destination. A search pill can become a full search layer.

## Magazine Grid Layout

Feeds should feel like a gallery, magazine, Pinterest board, Apple TV surface, and App Store Today collection combined.

Use:

- Edge-to-edge media.
- Large visual blocks.
- Minimal chrome.
- Consistent spacing.
- Clear visual rhythm.

## Content Fade System

As cards approach the top navigation layer, content should subtly blur, fade, or scale underneath glass. Content should flow beneath headers instead of colliding with them.

## Smart Content Cards

Each card should act as a destination.

Recommended structure:

- Hero media: top 60%.
- Metadata and actions: bottom 40%.

Cards can represent sermons, church events, creator classes, books, music releases, prayers, and resources.

Card expansion should preserve context. The tapped card grows from its position, the image remains continuous, text expands, and controls appear later.

## Layered Depth System

Use four depth layers:

1. Background.
2. Content.
3. Glass controls.
4. Temporary interactions such as menus, notifications, search, and AI suggestions.

## Color Philosophy

The interface base should stay neutral so content color dominates.

Base:

- White.
- Graphite.
- Soft gray.

Accent:

- System accent by default.
- Dynamic church or creator color only where context supports it.
- Gold should be treated as a contextual content or ceremonial accent, not the default UI chrome.

## Intelligent Profiles

Profiles should feel like personal operating systems, not static bio pages.

Expected sections:

- Identity hero.
- Recent activity.
- Catalog: books, music, podcasts, classes, sermons, resources.
- Knowledge graph: topics they discuss.
- Influence map: people and communities they interact with.
- Timeline: journey and milestones.

Access these sections through expandable glass pills and contextual layers.

## Search As A Layer

Search should be available from the top glass layer and behave like an overlay, not a separate page by default.

On activation:

- The search pill expands.
- Existing content remains visible underneath.
- Results animate into place through glass.

## Notification Architecture

Avoid flooding people with individual notifications. Prefer notification clusters.

Example:

"12 people interacted with your prayer."

Tapping a cluster should unfold individual notifications through an accordion or stacked-card animation.

## Feed As Workspace

Feed items should support contextual actions without forcing navigation away from the feed:

- Swipe preview.
- Save.
- Listen.
- Summarize.
- Translate.
- AI context.
- Related content.

The feed should be a workspace, not only a scrolling list.

## Motion Principles

Motion should communicate hierarchy, focus, transition, and ownership. Avoid decorative animation.

Use:

- Spring-based transitions.
- Subtle scale.
- Blur interpolation.
- Opacity interpolation.
- Liquid expansion.

Avoid:

- Excessive bounce.
- Flashy effects.
- Heavy glow.
- Motion that does not explain a state change.

## Implementation Notes

SwiftUI's current Liquid Glass APIs include `glassEffect`, `GlassEffectContainer`, `glassEffectID`, and `glassEffectTransition`. Prefer system glass where available, use existing Amen glass tokens for fallbacks, and keep Reduce Transparency and Reduce Motion paths intact.

Limit simultaneous glass effects for performance. Group related glass controls in a shared container when possible so shapes can blend and morph consistently.

## Target Feeling

Amen should feel like Apple Photos, Apple TV, App Store Today, VisionOS, Instagram Discover, Pinterest, and Liquid Glass combined into a content-first operating system where navigation feels alive, content owns the screen, interfaces morph instead of switching, and every layer behaves like physical glass floating above living content.
