import Foundation
import AppKit
import UserNotifications

// MARK: - SchedulerService
//
// Phase 7e — Daily Briefing Scheduler.
//
// Responsibilities:
//   - Read `AppSettings.briefingScheduleEnabled` + `briefingScheduleMinutes`.
//   - Compute the next fire `Date` and drive a `Task`-based wait loop.
//   - On wake (NSWorkspace didWakeNotification) check for missed schedules:
//     if last-run + one-day is in the past, fire once immediately.
//   - Deliver results via UNUserNotificationCenter + persist to the `briefing`
//     table through `DatabaseManager`.
//   - Default OFF — does nothing until `AppSettings.briefingScheduleEnabled`.

@MainActor
final class SchedulerService: ObservableObject {

    // MARK: - Singleton

    static let shared = SchedulerService()

    // MARK: - Published state

    /// When the next briefing is scheduled to run. `nil` when disabled.
    @Published private(set) var nextRunAt: Date?

    /// The most recent briefing result (set after each run). Nil before the
    /// first run in this session.
    @Published private(set) var lastRunResult: BriefingResult?

    // MARK: - Injected dependencies

    /// Injected clock — overridable in tests.
    var now: () -> Date = { Date() }

    /// Injected calendar — overridable in tests.
    var calendar: Calendar = .current

    /// The runner that composes and executes the briefing.
    var runner: BriefingRunner = BriefingRunner()

    // MARK: - Private state

    private var schedulerTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var lastRunDate: Date?

    // MARK: - Init

    private init() {}

    // MARK: - Lifecycle

    /// Start the scheduler. Reads current settings; no-op if already running.
    func start() {
        guard AppSettings.shared.briefingScheduleEnabled else {
            stop()
            return
        }
        guard schedulerTask == nil else { return }
        setupWakeObserver()
        scheduleNext()
    }

    /// Stop the scheduler and cancel any pending task.
    func stop() {
        schedulerTask?.cancel()
        schedulerTask = nil
        nextRunAt = nil
        if let obs = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            wakeObserver = nil
        }
    }

    /// Force an immediate briefing run (used by the "Run now" button in Preferences).
    func runBriefingNow() async {
        let result = await runner.run(runAt: now())
        await persist(result)
        lastRunResult = result
        lastRunDate = result.runAt
        deliver(result)
    }

    // MARK: - Internal helpers (also used from tests via testability seam)

    /// Compute nextRunAt and launch the wait task.
    func scheduleNext() {
        let settings = AppSettings.shared
        guard settings.briefingScheduleEnabled else {
            nextRunAt = nil
            return
        }
        let schedule = BriefingSchedule(
            timeOfDayMinutes: settings.briefingScheduleMinutes,
            enabled: true
        )
        guard let fireDate = schedule.nextFireDate(after: now(), calendar: calendar) else {
            nextRunAt = nil
            return
        }
        nextRunAt = fireDate
        schedulerTask?.cancel()
        schedulerTask = Task { [weak self] in
            await self?.waitAndFire(until: fireDate)
        }
    }

    // MARK: - Private

    private func waitAndFire(until fireDate: Date) async {
        let delay = fireDate.timeIntervalSince(now())
        guard delay > 0 else {
            await fire()
            return
        }
        do {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        } catch {
            // Cancelled — stop here.
            return
        }
        await fire()
    }

    private func fire() async {
        guard AppSettings.shared.briefingScheduleEnabled else { return }
        let result = await runner.run(runAt: now())
        await persist(result)
        lastRunResult = result
        lastRunDate = result.runAt
        deliver(result)
        // Schedule the next one.
        scheduleNext()
    }

    /// Persist result to DB; swallow errors so a DB failure never stops the
    /// scheduler loop.
    private func persist(_ result: BriefingResult) async {
        do {
            _ = try DatabaseManager.shared.appendBriefing(result)
        } catch {
            print("[SchedulerService] Failed to persist briefing: \(error)")
        }
    }

    /// Post a UNUserNotification with a short summary.
    ///
    /// Skipped in test processes — `UNUserNotificationCenter.current()` requires
    /// a running application bundle and crashes inside `xctest`.
    private func deliver(_ result: BriefingResult) {
        // Guard: UNUserNotificationCenter is only available in a real app process.
        // When running under xctest, NSBundle.main points at the test runner binary
        // (not an .app bundle), so the notification centre crashes. Skip silently.
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }

        let content = UNMutableNotificationContent()
        content.title = "Morning Briefing"
        content.body  = String(result.summary.prefix(200))
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "briefing-\(result.runAt.timeIntervalSince1970)",
            content: content,
            trigger: nil // deliver immediately
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[SchedulerService] Notification error: \(error)")
            }
        }
    }

    /// On Mac wake, check whether a scheduled briefing was missed while the
    /// machine was asleep. If `lastRunDate + 1 day` is in the past, fire once
    /// immediately; otherwise the regular scheduled task will fire at its time.
    private func setupWakeObserver() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleWake()
            }
        }
    }

    private func handleWake() {
        guard AppSettings.shared.briefingScheduleEnabled else { return }

        let currentDate = now()
        let settings = AppSettings.shared
        let schedule = BriefingSchedule(
            timeOfDayMinutes: settings.briefingScheduleMinutes,
            enabled: true
        )

        // If we have never run, check if today's briefing time already passed.
        let referenceDate = lastRunDate ?? .distantPast

        // The briefing is "missed" if the last run was more than a day ago AND
        // today's target time has already passed.
        let oneDayAgo = currentDate.addingTimeInterval(-86400)
        if referenceDate < oneDayAgo {
            // Calculate today's scheduled time.
            if let todayFire = schedule.nextFireDate(after: currentDate.addingTimeInterval(-86400), calendar: calendar),
               todayFire < currentDate {
                // The scheduled time has passed — fire immediately.
                schedulerTask?.cancel()
                schedulerTask = Task { [weak self] in
                    await self?.fire()
                }
                return
            }
        }
        // Otherwise reschedule normally.
        scheduleNext()
    }
}
