import Foundation
import UIKit
import UserNotifications
import Observation

/// The one optional daily reminder (SPEC §3 E12/E13): permission, the chosen time, a schedule only
/// on days a vow is still open, the badge of open vows from the reminder time on, and the silent
/// badge reset at each midnight. Local only.
@MainActor
@Observable
final class ReminderCenter {
    static let shared: ReminderCenter = ReminderCenter()

    private(set) var isOn: Bool
    private(set) var minuteOfDay: Int
    private(set) var hasAsked: Bool
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    /// Set when a reminder is tapped; MainView selects that vow and sets it back to nil.
    var openRequest: GroupID? = nil

    private let prefs: Preferences = Preferences()
    private let delegate: ReminderDelegate = ReminderDelegate()
    @ObservationIgnored private var installed: Bool = false
    /// True once `authorization` holds the system's answer (it reads `.notDetermined` until then).
    @ObservationIgnored private var statusKnown: Bool = false
    /// The latest sync that arrived while the reminder was on but the authorization was still loading.
    @ObservationIgnored private var deferredGroups: [ReminderGroup]? = nil

    private init() {
        let stored: Preferences = Preferences()
        isOn = stored.loadReminderOn()
        minuteOfDay = stored.loadReminderMinute()
        hasAsked = stored.loadReminderAsked()
    }

    /// The one-time offer after the first kept day (only once the system's answer is known).
    var shouldOffer: Bool {
        statusKnown && !hasAsked && !isOn && authorization == .notDetermined
    }

    /// "8:00 PM" in the user's locale (anchored on today, so DST and calendars behave).
    var timeText: String {
        let date: Date = Calendar.current.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// Call from VowApp.init (before launch finishes) so notification taps reach the delegate.
    func install() {
        guard !installed, !AppStore.isRunningUnitTests else { return }
        installed = true
        UNUserNotificationCenter.current().delegate = delegate
        Task { await refreshAuthorization() }
    }

    /// Reads the system setting. If notifications were turned off for Vow while the reminder was on,
    /// the reminder turns off too (saved), the schedule is cleared and the badge goes to 0.
    /// Then runs a sync that was waiting for the answer.
    func refreshAuthorization() async {
        guard ReminderCenter.available else { return }
        let status: UNAuthorizationStatus = await ReminderCenter.systemStatus()
        if authorization != status {
            authorization = status
        }
        statusKnown = true
        if isOn && !isAuthorized {
            isOn = false
            prefs.saveReminderOn(false)
            clearAll()
        }
        if let waiting: [ReminderGroup] = deferredGroups {
            deferredGroups = nil
            sync(groups: waiting, now: Date())
        }
    }

    /// Marks asked, requests [.alert, .sound, .badge] (the system prompt appears only the first time),
    /// refreshes authorization, sets and saves isOn = granted.
    func enable() async -> Bool {
        markAsked()
        guard ReminderCenter.available else { return false }
        let granted: Bool = await ReminderCenter.requestPermission()
        await refreshAuthorization()
        if isOn != granted {
            isOn = granted
        }
        prefs.saveReminderOn(granted)
        return granted
    }

    /// isOn = false (saved), removes pending and delivered reminders, badge 0.
    func disable() {
        if isOn {
            isOn = false
        }
        prefs.saveReminderOn(false)
        deferredGroups = nil
        clearAll()
    }

    /// Clamps to 0...1439 and saves. The caller syncs afterwards.
    func setMinuteOfDay(_ minute: Int) {
        let clamped: Int = min(max(minute, 0), 24 * 60 - 1)
        if minuteOfDay != clamped {
            minuteOfDay = clamped
        }
        prefs.saveReminderMinute(clamped)
    }

    /// hasAsked = true (saved).
    func markAsked() {
        guard !hasAsked else { return }
        hasAsked = true
        prefs.saveReminderAsked(true)
    }

    /// From ReminderDelegate on a tap.
    func handleTap(zoneName: String, ownerName: String) {
        openRequest = GroupID(zoneName: zoneName, ownerName: ownerName)
    }

    /// Rebuilds the plan around `now` (ReminderPlan, Calendar.current): today's reminder only while a
    /// vow is open, one a day for the next days, a silent badge reset at each midnight, and the badge
    /// set to the open vows from the reminder time on. Off or not allowed: nothing pending, badge 0.
    /// Delivered reminders that are no longer true (earlier days; today's once nothing is open) are removed.
    func sync(groups: [ReminderGroup], now: Date) {
        guard ReminderCenter.available else { return }
        if isOn && !statusKnown {
            // Cold launch: the authorization is still loading. Schedule once it is known.
            let first: Bool = deferredGroups == nil
            deferredGroups = groups
            if first {
                Task { await refreshAuthorization() }
            }
            return
        }
        let calendar: Calendar = Calendar.current
        let center: UNUserNotificationCenter = UNUserNotificationCenter.current()
        let active: Bool = isOn && isAuthorized
        var planned: [UNNotificationRequest] = []
        if active {
            planned = plannedRequests(groups: groups, now: now, calendar: calendar)
        }
        // Re-adding an identifier replaces its pending request, so only the others are removed.
        var keep: Set<String> = []
        for request in planned {
            keep.insert(request.identifier)
        }
        let known: [String] = ReminderPlan.identifiersToClear(now: now, calendar: calendar)
        let obsolete: [String] = known.filter { (id: String) -> Bool in !keep.contains(id) }
        center.removePendingNotificationRequests(withIdentifiers: obsolete)
        center.removeDeliveredNotifications(withIdentifiers: staleDelivered(known, groups: groups, now: now, calendar: calendar))
        for request in planned {
            center.add(request, withCompletionHandler: nil)
        }
        if active {
            setBadge(ReminderPlan.badgeCount(groups: groups, minuteOfDay: minuteOfDay, now: now, calendar: calendar))
        } else {
            setBadge(0)
        }
    }

    /// After "Reset local data": isOn false, minute default, hasAsked false, pending cleared, badge 0.
    func resetAfterLocalDataReset() {
        if isOn {
            isOn = false
        }
        if minuteOfDay != ReminderPlan.defaultMinute {
            minuteOfDay = ReminderPlan.defaultMinute
        }
        if hasAsked {
            hasAsked = false
        }
        if openRequest != nil {
            openRequest = nil
        }
        deferredGroups = nil
        prefs.saveReminderOn(false)
        prefs.saveReminderMinute(ReminderPlan.defaultMinute)
        prefs.saveReminderAsked(false)
        clearAll()
    }

    // MARK: - Private

    /// Unit tests run hosted in the app: never touch notifications there.
    private static var available: Bool {
        !AppStore.isRunningUnitTests
    }

    private var isAuthorized: Bool {
        switch authorization {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }

    private nonisolated static func systemStatus() async -> UNAuthorizationStatus {
        let settings: UNNotificationSettings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    private nonisolated static func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// The day reminders, then the midnight badge resets.
    private func plannedRequests(groups: [ReminderGroup], now: Date, calendar: Calendar) -> [UNNotificationRequest] {
        var out: [UNNotificationRequest] = []
        let reminders: [ReminderRequest] = ReminderPlan.requests(groups: groups, minuteOfDay: minuteOfDay, now: now, calendar: calendar)
        for item in reminders {
            out.append(reminderRequest(item, calendar: calendar))
        }
        for reset in ReminderPlan.badgeResets(now: now, calendar: calendar) {
            out.append(badgeResetRequest(reset, calendar: calendar))
        }
        return out
    }

    private func reminderRequest(_ item: ReminderRequest, calendar: Calendar) -> UNNotificationRequest {
        let content: UNMutableNotificationContent = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.sound = UNNotificationSound.default
        content.badge = NSNumber(value: item.badge)
        content.threadIdentifier = "vow.reminder"
        if let target: GroupID = item.groupID {
            var info: [AnyHashable: Any] = [:]
            info[AnyHashable(ReminderDelegate.zoneKey)] = target.zoneName
            info[AnyHashable(ReminderDelegate.ownerKey)] = target.ownerName
            content.userInfo = info
        }
        return UNNotificationRequest(identifier: item.id, content: content, trigger: trigger(at: item.fireDate, calendar: calendar))
    }

    /// Only a badge of 0: no title, body or sound, so nothing is shown.
    private func badgeResetRequest(_ reset: ReminderBadgeReset, calendar: Calendar) -> UNNotificationRequest {
        let content: UNMutableNotificationContent = UNMutableNotificationContent()
        content.badge = NSNumber(value: 0)
        return UNNotificationRequest(identifier: reset.id, content: content, trigger: trigger(at: reset.fireDate, calendar: calendar))
    }

    /// Wall-clock time in the device's calendar, so it follows the user across time zones.
    private func trigger(at date: Date, calendar: Calendar) -> UNCalendarNotificationTrigger {
        let parts: DateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
    }

    /// Every known identifier except today's reminder while a vow is still open today.
    private func staleDelivered(_ known: [String], groups: [ReminderGroup], now: Date, calendar: Calendar) -> [String] {
        let openToday: Bool = groups.contains(where: { (g: ReminderGroup) -> Bool in !g.keptToday })
        guard openToday else { return known }
        let today: String = ReminderPlan.identifier(for: now, calendar: calendar)
        return known.filter { (id: String) -> Bool in id != today }
    }

    /// Nothing pending or delivered, badge 0.
    private func clearAll() {
        guard ReminderCenter.available else { return }
        let ids: [String] = ReminderPlan.identifiersToClear(now: Date(), calendar: Calendar.current)
        let center: UNUserNotificationCenter = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
        setBadge(0)
    }

    private func setBadge(_ count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(max(count, 0), withCompletionHandler: nil)
    }
}

/// Not actor-isolated (UserNotifications calls it on its own queue).
final class ReminderDelegate: NSObject, UNUserNotificationCenterDelegate {
    /// userInfo keys of a one-vow reminder.
    static let zoneKey: String = "zone"
    static let ownerKey: String = "owner"

    /// In the foreground the stage already shows the state: no banner or sound. The badge still
    /// applies, so the reminder's count and the silent midnight reset to 0 land while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.badge])
    }

    /// A tap on a one-vow reminder opens that vow (MainView reads ReminderCenter.openRequest).
    /// The several-vows reminder carries no vow, so its tap only opens the app.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let target: GroupID = ReminderDelegate.groupID(from: response.notification.request) {
            let zone: String = target.zoneName
            let owner: String = target.ownerName
            Task { @MainActor in
                ReminderCenter.shared.handleTap(zoneName: zone, ownerName: owner)
            }
        }
        completionHandler()
    }

    /// The vow a reminder points at: only Vow's own reminder identifiers, with a non-empty zone and owner.
    private static func groupID(from request: UNNotificationRequest) -> GroupID? {
        guard request.identifier.hasPrefix(ReminderPlan.idPrefix) else { return nil }
        let info: [AnyHashable: Any] = request.content.userInfo
        guard let zone: String = info[AnyHashable(ReminderDelegate.zoneKey)] as? String,
              let owner: String = info[AnyHashable(ReminderDelegate.ownerKey)] as? String,
              !zone.isEmpty, !owner.isEmpty else { return nil }
        return GroupID(zoneName: zone, ownerName: owner)
    }
}
