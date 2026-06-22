"use strict";
// serviceTime.ts — compute the next upcoming service occurrence.
//
// Each ServiceTime has dayOfWeek (0=Sun), startLocal ("HH:mm") and an IANA
// timezone. We compute "minutes from now until the next occurrence" using the
// church's own timezone so "starts soon" is correct regardless of the caller's
// location. No external date library — Intl.DateTimeFormat provides the
// timezone-local wall clock.
Object.defineProperty(exports, "__esModule", { value: true });
exports.computeNextService = computeNextService;
exports.isOpenNow = isOpenNow;
/** Wall-clock components of `nowMs` in the given IANA timezone. */
function zonedNow(nowMs, timezone) {
    const fmt = new Intl.DateTimeFormat("en-US", {
        timeZone: timezone,
        weekday: "short",
        hour: "2-digit",
        minute: "2-digit",
        hour12: false,
    });
    const parts = fmt.formatToParts(new Date(nowMs));
    const get = (t) => parts.find((p) => p.type === t)?.value ?? "";
    const wdMap = {
        Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6,
    };
    const dow = wdMap[get("weekday")] ?? 0;
    let hour = parseInt(get("hour"), 10);
    if (hour === 24)
        hour = 0; // some locales emit "24" for midnight
    const minute = parseInt(get("minute"), 10);
    return { dow, minutesOfDay: hour * 60 + minute };
}
function parseStartLocal(startLocal) {
    const m = /^(\d{1,2}):(\d{2})$/.exec(startLocal || "");
    if (!m)
        return null;
    const h = parseInt(m[1], 10);
    const min = parseInt(m[2], 10);
    if (h < 0 || h > 23 || min < 0 || min > 59)
        return null;
    return h * 60 + min;
}
/** Minutes until the next weekly occurrence of one service. */
function minutesUntil(service, nowMs) {
    const startMinutes = parseStartLocal(service.startLocal);
    if (startMinutes == null)
        return null;
    let tz;
    try {
        tz = zonedNow(nowMs, service.timezone);
    }
    catch {
        return null; // bad timezone → skip this service
    }
    const WEEK = 7 * 24 * 60;
    let delta = (service.dayOfWeek - tz.dow) * 24 * 60 + (startMinutes - tz.minutesOfDay);
    while (delta < 0)
        delta += WEEK;
    return delta;
}
/** The soonest upcoming service across all of a church's service times. */
function computeNextService(serviceTimes, nowMs) {
    let best = null;
    for (const s of serviceTimes) {
        const mins = minutesUntil(s, nowMs);
        if (mins == null)
            continue;
        if (!best || mins < best.startsInMinutes) {
            best = { serviceTimeId: s.id, startsInMinutes: mins, isOnline: s.isOnline };
        }
    }
    return best;
}
/** openNow ≈ a service is currently in session (started, not yet ended). */
function isOpenNow(serviceTimes, nowMs) {
    for (const s of serviceTimes) {
        const start = parseStartLocal(s.startLocal);
        if (start == null)
            continue;
        let tz;
        try {
            tz = zonedNow(nowMs, s.timezone);
        }
        catch {
            continue;
        }
        if (tz.dow === s.dayOfWeek) {
            const end = start + Math.max(0, s.durationMinutes);
            if (tz.minutesOfDay >= start && tz.minutesOfDay < end)
                return true;
        }
    }
    return false;
}
