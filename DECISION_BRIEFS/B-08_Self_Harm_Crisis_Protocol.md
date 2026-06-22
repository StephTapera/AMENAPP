# B-08: Self-Harm and Crisis Content Protocol
**Group:** BEFORE-LAUNCH
**Decision:** When self-harm or suicidal ideation content is detected, what is the response protocol?

---

## Recommended Answer
Accept the recommended protocol: block content from public posting; show 988 Suicide and Crisis Lifeline resources inline; notify the church's designated pastoral contact via a private CF-written Firestore document (not push notification); log to safety audit log; do not delete — preserve for potential legal hold.

## Rationale
Crisis content requires a response that is both protective (prevent harmful content from spreading) and pastoral (connect the person with real help). The 988 Lifeline resource display is a non-negotiable safety baseline. Pastoral notification is sensitive — push notifications about a member's mental health could be seen by anyone near the device, hence the recommendation to write a private Firestore document for the pastoral contact to read in the app. Not deleting the content is important because legal proceedings related to self-harm may require it.

## What the code already does (file:line)
- Berean AI audit found crisis routing exists in Berean AI responses
- `functions/safety/submitSafetyReport.js` — safety report CF exists; handles crisis categories
- `AMENAPP/AMENAPP/CommunityOS/ChildSafety/AmenChildSafetyService.swift` — safety audit log writes exist for CSAM
- Gap: No confirmed "988 resource inline display" component found in iOS post creation flow
- Gap: No confirmed pastoral notification path (Firestore document write to pastoral contact's inbox) found for self-harm crisis content outside Berean AI

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Recommended protocol | Add 988 resource display to moderation result handler; add pastoral notification Firestore write in moderation CF | Correct; industry best practice |
| 988 resources only, no pastoral notification | Remove pastoral notification path | Simpler; less integrated with faith community use case |
| Block and delete content | Delete instead of preserve | Evidence destroyed; legal liability if harm follows |

## Legal consultation required?
NO — mental health crisis response best practices are well documented. Apple App Store Guidelines Section 1.4.1 requires apps that provide mental health services to include a crisis line.

---
**Status:** ☐ OPEN
**Owner:** Safety Officer + Product + Engineering Lead
