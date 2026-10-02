import CloudKit
import Foundation
import Observation

enum CloudPhase: Equatable {
    case checking
    case ready
    case noAccount(String)
    case failed(String)
}

/// The app's single source of truth: profile, iCloud state, and the snapshots of every group
/// the user belongs to. All CloudKit work goes through CloudService.
@MainActor
@Observable
final class AppStore {
    private(set) var phase: CloudPhase = .checking
    private(set) var profile: Profile? = nil
    private(set) var userID: String? = nil
    private(set) var groupIDs: [GroupID] = []
    private(set) var snapshots: [GroupID: GroupSnapshot] = [:]
    private(set) var isRefreshing: Bool = false
    var toast: String? = nil
    var pendingVowPrompt: GroupID? = nil
    /// The most recent create/join failure, shown inside the sheet (a toast would sit behind it).
    private(set) var lastError: String? = nil

    private var testingModeStorage: Bool = false

    /// Persisted to UserDefaults "vow.testingMode".
    var testingMode: Bool {
        get { return testingModeStorage }
        set {
            testingModeStorage = newValue
            prefs.saveTestingMode(newValue)
        }
    }

    private var cloud: CloudService { return CloudService.shared }
    private let prefs: Preferences = Preferences()
    private let cache: SnapshotCache = SnapshotCache()

    @ObservationIgnored private var refreshingIDs: Set<GroupID> = []
    @ObservationIgnored private var refreshAllInFlight: Bool = false
    @ObservationIgnored private var bootstrapInFlight: Bool = false
    @ObservationIgnored private var themeCache: [GroupID: DailyTheme] = [:]
    @ObservationIgnored private var inFlightCheckIns: Set<CheckInInfo> = []

    init() {
        profile = prefs.loadProfile()
        testingModeStorage = prefs.loadTestingMode()
        let cachedUserID: String? = prefs.loadUserID()
        userID = cachedUserID
        if let payload = cache.load(), payload.userID == nil || payload.userID == cachedUserID {
            var map: [GroupID: GroupSnapshot] = [:]
            for s in payload.snapshots {
                map[s.group.id] = s
            }
            snapshots = map
            var order: [GroupID] = []
            for id in payload.order where map[id] != nil && !order.contains(id) {
                order.append(id)
            }
            for s in payload.snapshots where !order.contains(s.group.id) {
                order.append(s.group.id)
            }
            groupIDs = order
        }
        // With a known account and cached data, show it immediately; bootstrap re-validates.
        if cachedUserID != nil && !snapshots.isEmpty {
            phase = .ready
        }
    }

    // MARK: - Lifecycle

    static var isRunningUnitTests: Bool {
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func bootstrap() async {
        // Unit tests are hosted in the app without entitlements: never touch CloudKit there.
        if AppStore.isRunningUnitTests { return }
        if bootstrapInFlight { return }
        bootstrapInFlight = true
        defer { bootstrapInFlight = false }

        if case .failed = phase {
            phase = .checking
        }

        do {
            let status: CKAccountStatus = try await cloud.accountStatus()
            guard status == .available else {
                phase = .noAccount(CloudErrors.accountMessage(status))
                return
            }

            let uid: String = try await cloud.currentUserID()
            if let old = userID, old != uid {
                // Different iCloud account: the cached groups belong to someone else.
                snapshots = [:]
                groupIDs = []
                themeCache = [:]
                cache.clear()
            }
            userID = uid
            prefs.saveUserID(uid)
            phase = .ready
            installShareHandler()
            await refreshAll()
        } catch {
            let message: String = CloudErrors.message(error)
            if snapshots.isEmpty || userID == nil {
                phase = .failed(message)
            } else {
                phase = .ready
                installShareHandler()
                toast = message
            }
        }
    }

    private func installShareHandler() {
        ShareInbox.handler = { [weak self] (metadata: CKShare.Metadata) in
            guard let store = self else { return }
            Task { @MainActor in
                _ = await store.acceptShare(metadata)
            }
        }
    }

    func refreshAll() async {
        guard userID != nil, !refreshAllInFlight else { return }
        refreshAllInFlight = true
        isRefreshing = true
        defer {
            refreshAllInFlight = false
            isRefreshing = false
        }

        let keysAtStart: Set<GroupID> = Set(snapshots.keys)
        let ids: [GroupID]
        do {
            ids = try await cloud.fetchGroupIDs()
        } catch {
            if !CloudErrors.isNetwork(error) || snapshots.isEmpty {
                toast = CloudErrors.message(error)
            }
            return
        }

        var fresh: [GroupID: GroupSnapshot] = [:]
        var firstError: Error? = nil
        for id in ids {
            do {
                let s: GroupSnapshot = try await cloud.fetchSnapshot(id)
                fresh[id] = merged(s, previous: snapshots[id])
            } catch {
                if CloudErrors.isGone(error) { continue }
                if let old = snapshots[id] { fresh[id] = old }
                if firstError == nil { firstError = error }
            }
        }

        // Keep groups that were added locally (create/join) while this refresh was running.
        let listed: Set<GroupID> = Set(ids)
        for (id, s) in snapshots where !listed.contains(id) && !keysAtStart.contains(id) {
            fresh[id] = s
        }
        // Drop groups removed locally (leave/delete/reset) while this refresh was running.
        for id in keysAtStart where snapshots[id] == nil {
            fresh[id] = nil
        }
        // Re-merge with the current state: check-ins saved while the fetches were running must survive.
        for (id, s) in fresh {
            if let current = snapshots[id] {
                fresh[id] = merged(s, previous: current)
            }
        }

        snapshots = fresh
        if let p = pendingVowPrompt, fresh[p] == nil {
            pendingVowPrompt = nil
        }
        reorder()
        persist()

        if let e = firstError, !CloudErrors.isNetwork(e) {
            toast = CloudErrors.message(e)
        }
    }

    func refresh(_ id: GroupID) async {
        guard userID != nil, !refreshingIDs.contains(id) else { return }
        refreshingIDs.insert(id)
        defer { refreshingIDs.remove(id) }
        do {
            let s: GroupSnapshot = try await cloud.fetchSnapshot(id)
            upsert(merged(s, previous: snapshots[id]))
        } catch {
            if CloudErrors.isGone(error) {
                if snapshots[id] != nil {
                    removeLocal(id)
                    toast = "That group no longer exists."
                }
            } else if !CloudErrors.isNetwork(error) || snapshots[id] == nil {
                toast = CloudErrors.message(error)
            }
        }
    }

    // MARK: - Profile & settings

    func saveProfile(displayName: String) {
        let name: String = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let p = Profile(displayName: name)
        profile = p
        prefs.saveProfile(p)

        // Fire-and-forget: update my display name in every group I'm active in.
        var updates: [(GroupID, MemberInfo)] = []
        for id in groupIDs {
            if var m = myMember(id), m.leftDay == nil, m.displayName != name {
                m.displayName = name
                updates.append((id, m))
            }
        }
        if updates.isEmpty { return }
        for (id, m) in updates {
            upsertMember(m, in: id)
        }
        persist()
        let service: CloudService = cloud
        let toSave: [(GroupID, MemberInfo)] = updates
        Task { @MainActor in
            for (id, m) in toSave {
                do {
                    try await service.saveMember(m, in: id)
                } catch {
                    // Ignored; the next refresh restores the server value.
                }
            }
        }
    }

    func resetLocalData() {
        prefs.clearAll()
        cache.clear()
        profile = nil
        testingModeStorage = false
        snapshots = [:]
        groupIDs = []
        themeCache = [:]
        pendingVowPrompt = nil
        toast = nil
        // userID stays in memory (same iCloud account); groups reload on the next refreshAll.
    }

    // MARK: - Derived

    func summary(for id: GroupID) -> GroupSummary? {
        guard let s = snapshots[id] else { return nil }
        return Settlement.summarize(s, viewerID: userID ?? "", now: Date())
    }

    func theme(for id: GroupID) -> DailyTheme {
        let cycle: Int
        let day: Int
        if let s = summary(for: id) {
            cycle = s.cycle
            day = s.dayInCycle
        } else {
            cycle = 1
            day = 1
        }
        if let cached = themeCache[id], cached.cycle == cycle, cached.day == day {
            return cached
        }
        let fresh: DailyTheme = DailyTheme.make(cycle: cycle, day: day)
        themeCache[id] = fresh
        return fresh
    }

    func isOwner(_ id: GroupID) -> Bool {
        if id.ownerName == CKCurrentUserDefaultName { return true }
        if let uid = userID, let s = snapshots[id], !s.group.ownerUserID.isEmpty {
            return s.group.ownerUserID == uid
        }
        return false
    }

    func myMember(_ id: GroupID) -> MemberInfo? {
        guard let uid = userID, let s = snapshots[id] else { return nil }
        return s.members.first(where: { $0.userID == uid })
    }

    var totalBalance: Double {
        var total: Double = 0
        for id in groupIDs {
            if let viewer = summary(for: id)?.viewer {
                total += viewer.net
            }
        }
        return total
    }

    // MARK: - Groups

    func createGroup(name: String, vow: String, stake: Int, isTest: Bool) async -> GroupID? {
        lastError = nil
        guard let uid = await ensureUserID() else { return nil }
        let groupName: String = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let vowText: String = vow.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !groupName.isEmpty else { return nil }
        let me = MemberInfo(
            userID: uid,
            displayName: profile?.displayName ?? "Me",
            vow: vowText,
            joinedDay: 0,
            joinedEpoch: 0,
            leftDay: nil
        )
        do {
            let s: GroupSnapshot = try await cloud.createGroup(name: groupName, stake: stake, isTest: isTest, me: me)
            snapshots[s.group.id] = s
            groupIDs.removeAll(where: { $0 == s.group.id })
            groupIDs.insert(s.group.id, at: 0)
            persist()
            toast = "Group created. Invite your crew."
            return s.group.id
        } catch {
            fail(error)
            return nil
        }
    }

    /// The signed-in iCloud user, fetched on demand if launch couldn't get it (e.g. iCloud was
    /// still signing in). Sets `lastError` and returns nil when there isn't one.
    private func ensureUserID() async -> String? {
        if let uid = userID { return uid }
        do {
            let status: CKAccountStatus = try await cloud.accountStatus()
            guard status == .available else {
                fail(message: CloudErrors.accountMessage(status))
                return nil
            }
            let uid: String = try await cloud.currentUserID()
            userID = uid
            prefs.saveUserID(uid)
            if phase != .ready { phase = .ready }
            return uid
        } catch {
            fail(error)
            return nil
        }
    }

    private func fail(_ error: Error) {
        fail(message: CloudErrors.message(error))
    }

    private func fail(message: String) {
        lastError = message
        toast = message
    }

    func join(url: URL) async -> Bool {
        lastError = nil
        do {
            let metadata: CKShare.Metadata = try await cloud.shareMetadata(for: url)
            return await acceptShare(metadata)
        } catch {
            fail(error)
            return false
        }
    }

    /// Accepts an invitation (from a pasted link or from the system via ShareInbox).
    @discardableResult
    func acceptShare(_ metadata: CKShare.Metadata) async -> Bool {
        guard await ensureUserID() != nil else { return false }
        do {
            let id: GroupID = try await cloud.accept(metadata)
            let s: GroupSnapshot = try await cloud.fetchSnapshot(id)
            upsert(merged(s, previous: snapshots[id]))
            if let m = myMember(id), m.leftDay == nil, !m.vow.isEmpty {
                toast = "You're already in this group"
            } else {
                pendingVowPrompt = id
            }
            return true
        } catch {
            fail(error)
            return false
        }
    }

    func setVow(_ vow: String, in id: GroupID) async {
        guard let uid = userID, let s = snapshots[id] else { return }
        let text: String = vow.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let name: String = profile?.displayName ?? "Me"
        let previous: MemberInfo? = myMember(id)

        var m: MemberInfo
        if let existing = previous, existing.leftDay == nil {
            m = existing
            m.vow = text
            m.displayName = name
        } else {
            m = MemberInfo(
                userID: uid,
                displayName: name,
                vow: text,
                joinedDay: DayClock.currentDay(s.group, now: Date()),
                joinedEpoch: s.group.epoch,
                leftDay: nil
            )
        }

        upsertMember(m, in: id)
        do {
            try await cloud.saveMember(m, in: id)
            if pendingVowPrompt == id {
                pendingVowPrompt = nil
            }
            persist()
        } catch {
            if let p = previous {
                upsertMember(p, in: id)
            } else {
                removeMember(uid, in: id)
            }
            toast = CloudErrors.message(error)
        }
    }

    func checkIn(_ id: GroupID) async {
        guard let uid = userID, let s = snapshots[id], let me = myMember(id), me.leftDay == nil else { return }
        let day: Int = DayClock.currentDay(s.group, now: Date())
        let epoch: Int = s.group.epoch
        let already: Bool = s.checkIns.contains(where: { $0.userID == uid && $0.day == day && $0.epoch == epoch })
        if already { return }

        let pending = CheckInInfo(userID: uid, day: day, epoch: epoch, serverDate: nil)
        inFlightCheckIns.insert(pending)
        defer { inFlightCheckIns.remove(pending) }
        var optimistic: GroupSnapshot = s
        optimistic.checkIns.append(pending)
        snapshots[id] = optimistic

        do {
            let saved: CheckInInfo = try await cloud.saveCheckIn(pending, in: id)
            if var cur = snapshots[id] {
                cur.checkIns.removeAll(where: { $0.userID == uid && $0.day == day && $0.epoch == epoch })
                cur.checkIns.append(saved)
                snapshots[id] = cur
            }
            persist()
        } catch {
            if var cur = snapshots[id] {
                cur.checkIns.removeAll(where: { $0 == pending })
                snapshots[id] = cur
            }
            toast = "Couldn't check in. Check your connection and try again."
        }
    }

    func advanceTestDay(_ id: GroupID) async {
        guard isOwner(id), var g = snapshots[id]?.group, g.isTest else { return }
        g.testDay += 1
        do {
            try await cloud.saveGroup(g)
            setGroup(g)
            persist()
            toast = "Day \(g.testDay + 1)"
            await refresh(id)
        } catch {
            toast = CloudErrors.message(error)
        }
    }

    func resetTestGroup(_ id: GroupID) async {
        guard isOwner(id), var g = snapshots[id]?.group, g.isTest else { return }
        g.epoch += 1
        g.testDay = 0
        do {
            try await cloud.saveGroup(g)
            setGroup(g)
            persist()
            toast = "Group reset"
            await refresh(id)
        } catch {
            toast = CloudErrors.message(error)
        }
    }

    func leave(_ id: GroupID) async {
        guard snapshots[id] != nil else { return }
        if isOwner(id) {
            toast = "You own this group. Delete it instead."
            return
        }
        do {
            if var m = myMember(id), let s = snapshots[id] {
                m.leftDay = DayClock.currentDay(s.group, now: Date())
                do {
                    try await cloud.saveMember(m, in: id)
                } catch {
                    if !CloudErrors.isGone(error) { throw error }
                }
            }
            do {
                try await cloud.leave(id)
            } catch {
                if !CloudErrors.isGone(error) { throw error }
            }
            removeLocal(id)
            toast = "You left the group."
        } catch {
            toast = CloudErrors.message(error)
        }
    }

    func deleteGroup(_ id: GroupID) async {
        guard isOwner(id) else { return }
        do {
            try await cloud.deleteGroup(id)
            removeLocal(id)
            toast = "Group deleted."
        } catch {
            if CloudErrors.isGone(error) {
                removeLocal(id)
                toast = "Group deleted."
            } else {
                toast = CloudErrors.message(error)
            }
        }
    }

    // MARK: - Local state helpers

    /// Keeps optimistic (pending, still being saved) check-ins the server doesn't know about yet, and
    /// server-confirmed check-ins a fetch that started before their save didn't see. Check-in records are
    /// never deleted (resets bump the epoch), so a confirmed one can always be kept.
    private func merged(_ incoming: GroupSnapshot, previous: GroupSnapshot?) -> GroupSnapshot {
        guard let prev = previous else { return incoming }
        var out: GroupSnapshot = incoming
        for c in prev.checkIns where c.serverDate != nil || inFlightCheckIns.contains(c) {
            let known: Bool = out.checkIns.contains(where: {
                $0.userID == c.userID && $0.day == c.day && $0.epoch == c.epoch
            })
            if !known {
                out.checkIns.append(c)
            }
        }
        return out
    }

    private func upsert(_ s: GroupSnapshot) {
        let id: GroupID = s.group.id
        snapshots[id] = s
        if !groupIDs.contains(id) {
            groupIDs.append(id)
            reorder()
        }
        persist()
    }

    private func setGroup(_ g: GroupInfo) {
        guard var s = snapshots[g.id] else { return }
        var updated: GroupInfo = g
        if updated.shareURL == nil {
            updated.shareURL = s.group.shareURL
        }
        s.group = updated
        snapshots[g.id] = s
    }

    private func upsertMember(_ m: MemberInfo, in id: GroupID) {
        guard var s = snapshots[id] else { return }
        if let i = s.members.firstIndex(where: { $0.userID == m.userID }) {
            s.members[i] = m
        } else {
            s.members.append(m)
        }
        snapshots[id] = s
    }

    private func removeMember(_ userID: String, in id: GroupID) {
        guard var s = snapshots[id] else { return }
        s.members.removeAll(where: { $0.userID == userID })
        snapshots[id] = s
    }

    private func removeLocal(_ id: GroupID) {
        snapshots[id] = nil
        groupIDs.removeAll(where: { $0 == id })
        themeCache[id] = nil
        if pendingVowPrompt == id {
            pendingVowPrompt = nil
        }
        persist()
    }

    /// Most recently created first; only ids with a snapshot.
    private func reorder() {
        let all: [GroupSnapshot] = Array(snapshots.values)
        let sorted: [GroupSnapshot] = all.sorted { (a: GroupSnapshot, b: GroupSnapshot) -> Bool in
            if a.group.createdAt != b.group.createdAt {
                return a.group.createdAt > b.group.createdAt
            }
            return a.group.id.zoneName < b.group.id.zoneName
        }
        groupIDs = sorted.map { $0.group.id }
    }

    private func persist() {
        var list: [GroupSnapshot] = []
        for id in groupIDs {
            if var s = snapshots[id] {
                // Never cache optimistic check-ins: they'd outlive their save attempt.
                s.checkIns.removeAll(where: { $0.serverDate == nil })
                list.append(s)
            }
        }
        cache.save(SnapshotCache.Payload(userID: userID, order: groupIDs, snapshots: list))
    }
}
