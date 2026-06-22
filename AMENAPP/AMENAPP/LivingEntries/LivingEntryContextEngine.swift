import Foundation

struct LivingEntryContextEvaluation: Equatable, Sendable {
    let surfaceScore: Double
    let contextMatchScore: Double
    let interruptionPenalty: Double
    let matchedReasons: [String]

    var shouldSurfaceNow: Bool {
        surfaceScore >= 0.65
    }
}

struct LivingEntryRuntimeContext: Equatable, Sendable {
    var now: Date
    var isAtChurch: Bool
    var nearbyChurchId: String?
    var recentChurchVisitId: String?
    var serviceStartAt: Date?
    var appOpenedAfterInactivity: Bool
    var eveningHours: Bool
    var activeTyping: Bool
    var lowMotion: Bool
    var quietModeActive: Bool
    var focusModeActive: Bool
    var isSunday: Bool

    static func current(
        now: Date = Date(),
        isAtChurch: Bool = false,
        nearbyChurchId: String? = nil,
        recentChurchVisitId: String? = nil,
        serviceStartAt: Date? = nil,
        appOpenedAfterInactivity: Bool = false,
        eveningHours: Bool? = nil,
        activeTyping: Bool = false,
        lowMotion: Bool = true,
        quietModeActive: Bool = false,
        focusModeActive: Bool = false,
        calendar: Calendar = .current
    ) -> LivingEntryRuntimeContext {
        let hour = calendar.component(.hour, from: now)
        let resolvedEvening = eveningHours ?? (hour >= 18 && hour <= 22)
        return LivingEntryRuntimeContext(
            now: now,
            isAtChurch: isAtChurch,
            nearbyChurchId: nearbyChurchId,
            recentChurchVisitId: recentChurchVisitId,
            serviceStartAt: serviceStartAt,
            appOpenedAfterInactivity: appOpenedAfterInactivity,
            eveningHours: resolvedEvening,
            activeTyping: activeTyping,
            lowMotion: lowMotion,
            quietModeActive: quietModeActive,
            focusModeActive: focusModeActive,
            isSunday: calendar.component(.weekday, from: now) == 1
        )
    }
}

enum LivingEntryContextEngine {
    static func evaluate(
        entry: LivingEntry,
        context: LivingEntryRuntimeContext,
        calendar: Calendar = .current
    ) -> LivingEntryContextEvaluation {
        var contextMatchScore = 0.0
        var interruptionPenalty = 0.0
        var reasons: [String] = []

        if let dueAt = entry.dueAt, dueAt <= context.now {
            contextMatchScore += 0.7
            reasons.append(triggerReason(for: .time, fallback: "Due now"))
        }

        for rule in entry.triggerRules where rule.enabled {
            switch rule.type {
            case .churchProximity:
                if context.nearbyChurchId != nil, context.nearbyChurchId == entry.churchId ?? rule.churchId {
                    contextMatchScore += 0.7
                    reasons.append("Near church")
                }
            case .beforeService:
                if let serviceStartAt = context.serviceStartAt,
                   let beforeMinutes = rule.beforeEventMinutes,
                   minutes(from: context.now, to: serviceStartAt) <= beforeMinutes,
                   serviceStartAt > context.now {
                    contextMatchScore += 0.6
                    reasons.append("Before service")
                }
            case .afterChurch:
                if context.recentChurchVisitId == entry.churchId ?? rule.churchId || context.isAtChurch == false && entry.isChurchRelated {
                    contextMatchScore += 0.55
                    reasons.append("After church")
                }
            case .quietMoment:
                if context.lowMotion && context.appOpenedAfterInactivity && context.eveningHours && !context.activeTyping {
                    contextMatchScore += 0.65
                    reasons.append("Quiet moment")
                }
            case .userIdle:
                if context.appOpenedAfterInactivity && !context.activeTyping {
                    contextMatchScore += 0.45
                    reasons.append("You came back")
                }
            case .time:
                if let scheduledAt = rule.scheduledAt, scheduledAt <= context.now {
                    contextMatchScore += 0.55
                    reasons.append("Scheduled")
                }
            case .manual, .location, .calendar:
                break
            }
        }

        if context.isSunday {
            if entry.isChurchRelated || entry.intent == .churchVisit || entry.intent == .sermonReflection {
                contextMatchScore += 0.3
                reasons.append("Sunday mode")
            }
            if entry.intent == .work && !entry.isDueNow {
                interruptionPenalty += 0.25
            }
        }

        if context.focusModeActive && entry.intent != .work && !entry.isDueNow {
            interruptionPenalty += 0.12
        }
        if context.quietModeActive && entry.intent == .work {
            interruptionPenalty += 0.1
        }

        let score = clamp(
            (entry.priorityScore * 0.35)
            + (entry.gravityScore * 0.25)
            + (entry.spiritualWeight * 0.20)
            + (min(contextMatchScore, 1.0) * 0.15)
            - (min(interruptionPenalty, 1.0) * 0.05)
        )

        return LivingEntryContextEvaluation(
            surfaceScore: score,
            contextMatchScore: clamp(contextMatchScore),
            interruptionPenalty: clamp(interruptionPenalty),
            matchedReasons: Array(NSOrderedSet(array: reasons)) as? [String] ?? reasons
        )
    }

    private static func triggerReason(for type: LivingEntryTriggerType, fallback: String) -> String {
        switch type {
        case .time: return "Due tonight"
        case .location: return "Nearby"
        case .churchProximity: return "Near church"
        case .calendar: return "Calendar window"
        case .quietMoment: return "Quiet moment"
        case .afterChurch: return "After church"
        case .beforeService: return "Before service"
        case .userIdle: return "Idle window"
        case .manual: return fallback
        }
    }

    private static func minutes(from start: Date, to end: Date) -> Int {
        Int(end.timeIntervalSince(start) / 60)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
