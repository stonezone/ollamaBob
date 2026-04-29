import Foundation

/// User-configured schedule for the daily briefing.
///
/// v1 supports `daily at HH:MM` only. Weekly/monthly/cron expressions are out
/// of scope for Phase 7e and will be handled in a follow-up.
///
/// `timeOfDayMinutes` encodes the target wall-clock time as minutes-since-midnight
/// (range 0–1439).  Default 420 = 07:00 local time.
struct BriefingSchedule: Equatable, Codable, Sendable {

    // MARK: - Constants

    /// Default briefing time: 07:00 local time (420 minutes since midnight).
    static let defaultTimeOfDayMinutes: Int = 420

    // MARK: - Properties

    /// Minutes since midnight (0 = 00:00, 420 = 07:00, 1439 = 23:59).
    /// Values outside 0–1439 are clamped on read.
    let timeOfDayMinutes: Int

    /// Master enable flag. When `false`, `SchedulerService` does not schedule
    /// or fire briefings. Default `false` — user must opt in.
    let enabled: Bool

    // MARK: - Derived helpers

    /// Clamped time, guaranteed 0–1439.
    var clampedMinutes: Int { min(max(timeOfDayMinutes, 0), 1439) }

    /// Hour component (0–23).
    var hour: Int { clampedMinutes / 60 }

    /// Minute component (0–59).
    var minute: Int { clampedMinutes % 60 }

    /// Human-readable time string, e.g. "07:00".
    var displayTime: String { String(format: "%02d:%02d", hour, minute) }

    // MARK: - Next fire date

    /// Returns the next wall-clock `Date` at which a briefing should fire,
    /// given `referenceDate` as the current time.
    ///
    /// If the target time has already passed today, the next fire is tomorrow.
    func nextFireDate(after referenceDate: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard enabled else { return nil }
        var components = calendar.dateComponents([.year, .month, .day], from: referenceDate)
        components.hour   = hour
        components.minute = minute
        components.second = 0

        guard let todayFire = calendar.date(from: components) else { return nil }

        if todayFire > referenceDate {
            return todayFire
        }
        // Add one day.
        return calendar.date(byAdding: .day, value: 1, to: todayFire)
    }
}
