import Foundation

struct LiturgicalCalendar {
    static func composerPlaceholder(for date: Date = Date()) -> String? {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let weekday = cal.component(.weekday, from: date) // 1=Sun
        let year = cal.component(.year, from: date)
        let easter = easterDate(year: year)
        let easterDOY = cal.ordinality(of: .day, in: .year, for: easter) ?? 0
        let currentDOY = cal.ordinality(of: .day, in: .year, for: date) ?? 0
        let month = cal.component(.month, from: date)
        let day = cal.component(.day, from: date)

        // Good Friday
        if currentDOY == easterDOY - 2 {
            return "Ask about the cross and what happened on Good Friday…"
        }
        // Easter Sunday
        if currentDOY == easterDOY {
            return hour < 12 ? "He is risen! Ask anything about the Resurrection…" : "Reflect on Easter — what does it mean to you?"
        }
        // Ash Wednesday (Easter - 46 days)
        if currentDOY == easterDOY - 46 {
            return "It's Ash Wednesday — bring a prayer or ask about fasting…"
        }
        // Holy Week
        if currentDOY >= easterDOY - 7 && currentDOY < easterDOY {
            return "We're in Holy Week — ask about the Passion story…"
        }
        // Lent
        if currentDOY > easterDOY - 46 && currentDOY < easterDOY - 7 {
            return hour < 10 ? "A Lenten morning — bring a fast prayer…" : "Ask a Lenten question…"
        }
        // Pentecost (50 days after Easter)
        if currentDOY == easterDOY + 49 {
            return "It's Pentecost — ask about the Holy Spirit…"
        }
        // Advent (approx Dec 1 – 24)
        if (month == 12 && day <= 24) || (month == 11 && day >= 27) {
            return "It's Advent — ask about waiting, hope, and the coming of Christ…"
        }
        // Christmas
        if month == 12 && day == 25 {
            return "Merry Christmas! Ask about the birth of Jesus…"
        }
        // Sunday
        if weekday == 1 {
            if hour < 9 { return "Sunday morning — prepare your heart for worship…" }
            if hour < 13 { return "Ask about today's sermon passage or Sunday reading…" }
            return "Bring a prayer for the week ahead…"
        }
        // Wednesday evening
        if weekday == 4 && hour >= 17 {
            return "Midweek — bring a prayer or ask a deeper question…"
        }
        // Late evening
        if hour >= 21 {
            return "Evening reflection — what's on your heart?"
        }
        // Early morning
        if hour < 8 {
            return "Morning — ask Berean to start your day…"
        }
        return nil
    }

    static func easterDate(year: Int) -> Date {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        var comp = DateComponents()
        comp.year = year; comp.month = month; comp.day = day
        return Calendar.current.date(from: comp) ?? Date()
    }
}
