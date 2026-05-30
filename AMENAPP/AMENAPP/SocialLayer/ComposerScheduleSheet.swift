// INTEGRATION NOTE: Phase 4 — ComposerScheduleSheet wiring
//
// 1. SCHEDULE SHEET
//    In your composer view, hold `@State private var scheduledAt: Date? = nil`
//    and `@State private var showScheduleSheet = false`. Present via:
//
//      .sheet(isPresented: $showScheduleSheet) {
//          ComposerScheduleSheet(
//              scheduledAt: $scheduledAt,
//              onDone: { showScheduleSheet = false },
//              onClear: { scheduledAt = nil; showScheduleSheet = false }
//          )
//      }
//
//    When the user taps the publish/post button, call:
//      AmenCreationSchedulerService.shared.schedulePost(
//          text: draft.text,
//          mediaURLs: [],        // upload media first, pass remote URLs
//          intent: .post,        // or .prayer / .testimony per ComposerPostType
//          hashtags: [],         // extract hashtags from draft.text if needed
//          at: scheduledAt
//      )
//
// 2. POLL ATTACHMENT — PollComposerCard adapter
//    `PollComposerCard` (CreatePostPollComposer.swift) binds to:
//      @Binding var options: [String]           → maps to ComposerPollAttachment.options
//      @Binding var duration: CreatePostView.PollDuration  → translate to durationHours
//
//    Adapter mapping (CreatePostView.PollDuration → durationHours):
//      case .oneHour    → 1
//      case .sixHours   → 6
//      case .oneDay     → 24  (default)
//      case .threeDays  → 72
//      case .oneWeek    → 168
//
//    Wire the existing PollComposerCard by lifting its bindings into a local
//    `@State var pollOptions: [String]` and `@State var pollDuration: CreatePostView.PollDuration`,
//    then mirror writes into a `ComposerPollAttachment` via `.onChange`:
//
//      .onChange(of: pollOptions) { _, new in
//          poll.options = new
//      }
//      .onChange(of: pollDuration) { _, new in
//          poll.durationHours = durationHoursFor(new)
//      }
//
//    Do NOT redefine ComposerPollAttachment — it lives in ComposerContract.swift.
//
// 3. scheduledAt field on ComposerDraft
//    ComposerDraft (ComposerContract.swift) does NOT yet have a `scheduledAt: Date?` field.
//    Add it as:
//      var scheduledAt: Date? = nil
//    This is a backward-compatible additive change (Codable default = nil on decode).

import SwiftUI

// MARK: - ComposerScheduleSheet

/// Lightweight schedule-date picker sheet.
/// Presented from the composer toolbar schedule button.
/// Writes the selected date back via `$scheduledAt` binding.
///
/// Usage:
/// ```swift
/// .sheet(isPresented: $showScheduleSheet) {
///     ComposerScheduleSheet(
///         scheduledAt: $scheduledAt,
///         onDone: { showScheduleSheet = false },
///         onClear: { scheduledAt = nil; showScheduleSheet = false }
///     )
/// }
/// ```
struct ComposerScheduleSheet: View {

    // MARK: - Public interface

    @Binding var scheduledAt: Date?

    /// Called when the user taps "Schedule" (date already written to binding).
    var onDone: () -> Void

    /// Called when the user taps "Clear schedule".
    var onClear: () -> Void

    // MARK: - Private state

    @State private var selectedDate: Date = Date().addingTimeInterval(3_600)
    @State private var isScheduling: Bool = false
    @State private var appeared: Bool = false

    @Environment(\.colorScheme) private var scheme

    // MARK: - Date window

    private var minimumDate: Date { Date().addingTimeInterval(300) }   // now + 5 min
    private var maximumDate: Date { Date().addingTimeInterval(30 * 24 * 3_600) } // now + 30 days

    // MARK: - Formatted label

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d 'at' h:mm a"
        return f.string(from: selectedDate)
    }

    // MARK: - Validation

    private var isValidSelection: Bool {
        selectedDate >= minimumDate && selectedDate <= maximumDate
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // Sheet background
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(AmenTheme.Colors.glassFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .strokeBorder(
                            AmenTheme.Colors.glassStroke,
                            lineWidth: 0.75
                        )
                )
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Drag handle
                Capsule()
                    .fill(AmenTheme.Colors.textTertiary.opacity(0.35))
                    .frame(width: 36, height: 4)
                    .padding(.top, 10)
                    .padding(.bottom, 18)

                // Header
                sheetHeader

                Divider()
                    .background(AmenTheme.Colors.separatorSubtle)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)

                // Date picker
                datePickerSection

                // Explanation
                explanationRow

                Divider()
                    .background(AmenTheme.Colors.separatorSubtle)
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 20)

                // Actions
                actionButtons

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)   // using custom handle above
        .onAppear {
            // Seed picker from existing binding
            if let existing = scheduledAt {
                selectedDate = existing
            } else {
                // Default: next hour boundary, at minimum 5 minutes out
                let candidate = Calendar.current.nextDate(
                    after: minimumDate,
                    matching: DateComponents(minute: 0),
                    matchingPolicy: .nextTime
                ) ?? minimumDate.addingTimeInterval(3_600)
                selectedDate = min(candidate, maximumDate)
            }
            withAnimation(Motion.adaptive(.spring(response: 0.40, dampingFraction: 0.82))) {
                appeared = true
            }
        }
    }

    // MARK: - Sheet header

    private var sheetHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Schedule Post")
                    .font(AMENFont.bold(18))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)

                if isValidSelection {
                    Text(formattedDate)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(AmenTheme.Colors.amenBlue)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 4)),
                                removal: .opacity
                            )
                        )
                        .animation(
                            Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.78)),
                            value: formattedDate
                        )
                } else {
                    Text("Choose a date at least 5 minutes from now")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                }
            }

            Spacer()
        }
        .padding(.bottom, 14)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
    }

    // MARK: - Date picker

    private var datePickerSection: some View {
        DatePicker(
            "",
            selection: $selectedDate,
            in: minimumDate...maximumDate,
            displayedComponents: [.date, .hourAndMinute]
        )
        .datePickerStyle(.graphical)
        .tint(AmenTheme.Colors.amenBlue)
        .labelsHidden()
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AmenTheme.Colors.surfaceCard)
                .shadow(color: AmenTheme.Colors.shadowCard, radius: 12, x: 0, y: 3)
        )
        .opacity(appeared ? 1 : 0)
        .animation(
            Motion.adaptive(Motion.appearEase).delay(0.06),
            value: appeared
        )
    }

    // MARK: - Explanation row

    private var explanationRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.amenBlue)

            Text("Your post will be queued and published automatically.")
                .font(AMENFont.regular(13))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.top, 16)
        .padding(.bottom, 2)
        .opacity(appeared ? 1 : 0)
        .animation(
            Motion.adaptive(Motion.appearEase).delay(0.08),
            value: appeared
        )
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {

            // Primary — "Schedule"
            Button {
                commitSchedule()
            } label: {
                ZStack {
                    if isScheduling {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(AmenTheme.Colors.textInverse)
                    } else {
                        Text("Schedule")
                            .font(AMENFont.bold(16))
                            .foregroundStyle(
                                isValidSelection
                                    ? AmenTheme.Colors.textInverse
                                    : AmenTheme.Colors.textTertiary
                            )
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    Capsule()
                        .fill(
                            isValidSelection
                                ? AmenTheme.Colors.amenBlue
                                : AmenTheme.Colors.surfaceInput
                        )
                        .shadow(
                            color: isValidSelection
                                ? AmenTheme.Colors.amenBlue.opacity(0.35)
                                : .clear,
                            radius: 10, x: 0, y: 4
                        )
                )
            }
            .disabled(!isValidSelection || isScheduling)
            .amenPress()
            .animation(
                Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.80)),
                value: isValidSelection
            )

            // Secondary — "Clear schedule" (only when already scheduled)
            if scheduledAt != nil {
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.34, dampingFraction: 0.82))) {
                        onClear()
                    }
                } label: {
                    Text("Clear schedule")
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 6)),
                        removal: .opacity
                    )
                )
            }
        }
        .opacity(appeared ? 1 : 0)
        .animation(
            Motion.adaptive(Motion.appearEase).delay(0.10),
            value: appeared
        )
    }

    // MARK: - Actions

    private func commitSchedule() {
        guard isValidSelection else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Write the selected date back into the binding immediately so the
        // caller can show ScheduledStatusChip before the async write resolves.
        scheduledAt = selectedDate

        isScheduling = true

        // Fire-and-forget scheduling write. The composer's post submission path
        // is responsible for the final schedulePost() call with full draft data
        // (see INTEGRATION NOTE at the top of this file).
        // Here we just confirm the date selection and dismiss.
        withAnimation(Motion.adaptive(.spring(response: 0.32, dampingFraction: 0.80))) {
            isScheduling = false
        }
        onDone()
    }
}

// MARK: - Preview

#if DEBUG
struct ComposerScheduleSheet_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // No existing schedule
            ComposerScheduleSheet(
                scheduledAt: .constant(nil),
                onDone: {},
                onClear: {}
            )
            .previewDisplayName("Schedule — no existing date")

            // Already-scheduled state (shows "Clear schedule")
            ComposerScheduleSheet(
                scheduledAt: .constant(Calendar.current.date(
                    byAdding: .hour, value: 3, to: Date()
                )),
                onDone: {},
                onClear: {}
            )
            .previewDisplayName("Schedule — already set")

            // Dark mode
            ComposerScheduleSheet(
                scheduledAt: .constant(nil),
                onDone: {},
                onClear: {}
            )
            .preferredColorScheme(.dark)
            .previewDisplayName("Schedule — dark mode")
        }
    }
}
#endif

// MARK: - TODO: BACKEND
//
// voteOnPoll Firebase Callable
// ─────────────────────────────────────────────────────────────────────────────
// NOTE: `voteOnPoll` currently exists only as a local Firestore transaction
// inside FirebaseMessagingService (for in-conversation polls). It is NOT yet
// exposed as a Firebase Callable Cloud Function for feed/post polls.
//
// When post-level polls (ComposerPollAttachment) are published to Firestore,
// a separate callable is required so feed poll votes are:
//   - Rate-limited server-side (1 vote per postId per userId)
//   - Idempotent (safe to retry on poor network)
//   - Authenticated-only (not callable by unauthenticated clients)
//
// Required callable contract:
//
// callable: voteOnPoll
// input:  { postId: string, optionIndex: number, userId: string }
// output: { options: [{ text: string, voteCount: number }], totalVotes: number }
// security: authenticated, rate-limit 1 vote per postId per userId
//
// Firestore write pattern (inside the callable):
//   posts/{postId}/poll/options[optionIndex].votes  += 1
//   posts/{postId}/poll/voters/{userId}             = { optionIndex, votedAt }
//   Enforce: if voters/{userId} already exists → return current state, no write.
//
// iOS call site (add to PostActionsService or FeedViewModel):
//
//   let fn = Functions.functions().httpsCallable("voteOnPoll")
//   let result = try await fn.call(["postId": postId,
//                                   "optionIndex": optionIndex,
//                                   "userId": uid])
//   // Decode result.data as [String: Any] → refresh local poll state
//
// Deploy command (from /functions):
//   firebase deploy --only functions:voteOnPoll
