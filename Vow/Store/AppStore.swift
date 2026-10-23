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
    /// When the last refreshAll finished (nil until the first one this session). UI timing only.
    private(set) var lastSyncedAt: Date? = nil
    /// The group of the most recent accepted invite, and a counter that changes on every acceptance,
    /// so the UI can show that group even when you were already in it.
    private(set) var lastAcceptedGroup: GroupID? = nil
    private(set) var acceptCount: Int = 0
    var toast: String? = nil
    var pendingVowPrompt: GroupID? = nil
    /// The most recent create/join failure, shown inside the sheet (a toast would sit behind it).
    private(set) var lastError: String? = nil
    /// Proof uploads still running: post id → progress, 0...1. Gone when the save ends, either way.
    private(set) var uploads: [String: Double] = [:]
    /// Ids of your posts whose save failed. They stay in the chat, unsent, until `retryPost` or
    /// `discardPost`. Never cached, so a relaunch or "Reset local data" drops them.
    private(set) var failedPosts: Set<String> = []
    /// zoneName → the newest record that group's Chat showed when you last looked. Mirrors Preferences
    /// so the chat dot updates as you read.
    private(set) var chatSeenAt: [String: Date] = [:]

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
    /// Something asked for a refresh of every group while one ran: it goes round once more.
    @ObservationIgnored private var refreshAllAgain: Bool = false
    /// The calls that wait for that round.
    @ObservationIgnored private var refreshAllWaiters: [CheckedContinuation<Void, Never>] = []
    /// Counts the rounds that brought something new, so a push can tell iOS whether it did.
    @ObservationIgnored private var refreshAllChanges: Int = 0
    /// CloudKit's push subscriptions were saved this launch, for this account (`subscribeIfNeeded`).
    @ObservationIgnored private var subscribed: Bool = false
    /// A save of them is under way.
    @ObservationIgnored private var subscribing: Bool = false
    @ObservationIgnored private var bootstrapInFlight: Bool = false
    @ObservationIgnored private var themeCache: [GroupID: DailyTheme] = [:]
    @ObservationIgnored private var inFlightCheckIns: Set<CheckInInfo> = []
    @ObservationIgnored private var inFlightExcuses: Set<ExcuseInfo> = []
    @ObservationIgnored private var inFlightVotes: Set<VoteInfo> = []
    @ObservationIgnored private var inFlightReactions: Set<ReactionInfo> = []
    /// Ids of posts still being saved.
    @ObservationIgnored private var inFlightPosts: Set<String> = []
    /// The drafts of failed proofs, by post id: their files wait in the outbox for a retry.
    @ObservationIgnored private var failedDrafts: [String: MediaDraft] = [:]
    /// Test groups with a Next day or a reset still running. Both save the whole group record, so either
    /// is ignored while one runs: a late Next day can't write the old epoch back over a reset.
    @ObservationIgnored private var testDayInFlight: Set<GroupID> = []
    /// Groups whose voting rule is being saved. A second change is ignored until the first ends, so
    /// each one is worked out from the log the last one left.
    @ObservationIgnored private var voteRuleInFlight: Set<GroupID> = []

    init() {
        profile = prefs.loadProfile()
        testingModeStorage = prefs.loadTestingMode()
        chatSeenAt = prefs.loadChatSeen()
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
        // Drafts live only in memory, so what an earlier launch left in the outbox can never be sent.
        if !AppStore.isRunningUnitTests {
            try? FileManager.default.removeItem(at: MediaPrep.outbox)
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
                // Different iCloud account: the cached groups and their photos belong to someone else.
                snapshots = [:]
                groupIDs = []
                themeCache = [:]
                failedPosts = []
                failedDrafts = [:]
                cache.clear()
                MediaCache.shared.clearAll()
                cloud.forgetAllZones()
                subscribed = false
            }
            userID = uid
            prefs.saveUserID(uid)
            phase = .ready
            installInboxes()
            await refreshAll()
        } catch {
            let message: String = CloudErrors.message(error)
            if snapshots.isEmpty || userID == nil {
                phase = .failed(message)
            } else {
                phase = .ready
                installInboxes()
                toast = message
            }
        }
    }

    /// What the system delivers before the store can act on it: share invitations, and CloudKit's pushes, which
    /// refresh every group (a push doesn't say which changed).
    private func installInboxes() {
        ShareInbox.handler = { [weak self] (metadata: CKShare.Metadata) in
            guard let store = self else { return }
            Task { @MainActor in
                _ = await store.acceptShare(metadata)
            }
        }
        ChangeInbox.handler = { [weak self] () async -> Bool in
            guard let store = self else { return false }
            let before: Int = store.refreshAllChanges
            await store.refreshAll()
            return store.refreshAllChanges != before
        }
    }

    /// Saves CloudKit's push subscriptions once per launch and account. A refresh that reaches iCloud asks, so the
    /// first one does it and, after a failed save, the next one tries again (the polls sync meanwhile). A save
    /// that ends after the account changed doesn't count for the new one.
    private func subscribeIfNeeded() {
        guard let uid = userID, !subscribed, !subscribing else { return }
        subscribing = true
        let service: CloudService = cloud
        Task { @MainActor in
            let saved: Bool = await service.ensureSubscriptions()
            self.subscribing = false
            if saved && self.userID == uid {
                self.subscribed = true
            }
        }
    }

    /// Refreshes every group. A call while one runs (a push, a pull to refresh) doesn't start another: the running
    /// one goes round once more when it ends, so a change that landed after it fetched that group isn't left for
    /// the next poll, and the call returns when that round has. Calls during one round share the next.
    func refreshAll() async {
        guard userID != nil else { return }
        if refreshAllInFlight {
            refreshAllAgain = true
            await withCheckedContinuation { (waiter: CheckedContinuation<Void, Never>) in
                self.refreshAllWaiters.append(waiter)
            }
            return
        }
        refreshAllInFlight = true
        isRefreshing = true
        repeat {
            refreshAllAgain = false
            await refreshEveryGroup()
        } while refreshAllAgain
        refreshAllInFlight = false
        isRefreshing = false
        let waiters: [CheckedContinuation<Void, Never>] = refreshAllWaiters
        refreshAllWaiters = []
        for waiter in waiters {
            waiter.resume()
        }
    }

    /// One round of `refreshAll`.
    private func refreshEveryGroup() async {
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
        subscribeIfNeeded()

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
        // Re-merge with the current state: check-ins saved while the fetches were running must survive. A
        // group the fetch brought nothing new for keeps its current value.
        for (id, s) in fresh {
            if let current = snapshots[id] {
                let next: GroupSnapshot = merged(s, previous: current)
                fresh[id] = AppStore.sameContent(next, current) ? current : next
            }
        }

        // Writing `snapshots` re-renders every view that reads it, and persisting encodes every group.
        if fresh != snapshots {
            // A group that has gone (its owner deleted it, or you left on another device) takes its media and
            // its mirror.
            for id in snapshots.keys where fresh[id] == nil {
                MediaCache.shared.removeGroup(id)
                cloud.forgetZone(id)
            }
            snapshots = fresh
            refreshAllChanges += 1
            if let p = pendingVowPrompt, fresh[p] == nil {
                pendingVowPrompt = nil
            }
            pruneFailedPosts()
            reorder()
            persist()
        }
        lastSyncedAt = Date()

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
        MediaCache.shared.clearAll()
        cloud.forgetAllZones()
        chatSeenAt = [:]
        profile = nil
        testingModeStorage = false
        snapshots = [:]
        groupIDs = []
        themeCache = [:]
        failedPosts = []
        failedDrafts = [:]
        pendingVowPrompt = nil
        toast = nil
        lastSyncedAt = nil
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

    /// `endDate`: any moment on the vow's final day (nil = no end). The earliest end is tomorrow.
    func createGroup(name: String, vow: String, stake: Int, isTest: Bool, endDate: Date? = nil) async -> GroupID? {
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
            let s: GroupSnapshot = try await cloud.createGroup(name: groupName, stake: stake, isTest: isTest,
                                                               endDate: endDate, me: me)
            snapshots[s.group.id] = s
            groupIDs.removeAll(where: { $0 == s.group.id })
            groupIDs.insert(s.group.id, at: 0)
            persist()
            toast = "Group created."
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

    /// Everyone's records count against the group owner's iCloud storage, so when it is full only the owner
    /// can free it: members are told whose it is. nil for any other failure, and for the owner, who gets
    /// the usual message.
    private func ownerStorageFull(_ error: Error, in id: GroupID) -> String? {
        guard CloudErrors.code(error) == .quotaExceeded, !isOwner(id) else { return nil }
        return "The group owner's iCloud storage is full."
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
            lastAcceptedGroup = id
            acceptCount += 1
            if let m = myMember(id), m.leftDay == nil, !m.vow.isEmpty {
                toast = "You're already in this group."
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
        // A finished vow takes no new members or vows (only a link opened after the end gets here).
        if EndDate.isFinished(s.group, now: Date()) { return }
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
        let now: Date = Date()
        // After the final day nothing is open (Settlement would ignore the check-in anyway).
        if EndDate.isFinished(s.group, now: now) { return }
        let day: Int = DayClock.currentDay(s.group, now: now)
        let epoch: Int = s.group.epoch
        let already: Bool = s.checkIns.contains(where: { $0.userID == uid && $0.day == day && $0.epoch == epoch })
        if already { return }
        // An excuse closes today's orb for good.
        if AppStore.hasExcuse(uid, day: day, in: s) { return }

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
            toast = ownerStorageFull(error, in: id) ?? "Couldn't check in. Try again."
        }
    }

    func advanceTestDay(_ id: GroupID) async {
        guard isOwner(id), !testDayInFlight.contains(id), var g = snapshots[id]?.group, g.isTest else { return }
        testDayInFlight.insert(id)
        defer { testDayInFlight.remove(id) }
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
        guard isOwner(id), !testDayInFlight.contains(id), var g = snapshots[id]?.group, g.isTest else { return }
        testDayInFlight.insert(id)
        defer { testDayInFlight.remove(id) }
        g.epoch += 1
        g.testDay = 0
        do {
            try await cloud.saveGroup(g)
            setGroup(g)
            pruneFailedPosts()
            persist()
            toast = "Group reset."
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

    // MARK: - Chat

    /// Sends today's excuse, which closes today's orb for good: it can't be withdrawn, and a day you
    /// checked in can't be excused (`canExcuse`). False if it wasn't sent; after a failed save the toast
    /// says so.
    @discardableResult
    func sendExcuse(_ text: String, in id: GroupID) async -> Bool {
        let body: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let now: Date = Date()
        guard !body.isEmpty, body.count <= Records.excuseTextLimit, canExcuse(id, now: now),
              let uid = userID, let s = snapshots[id] else { return false }
        let day: Int = DayClock.currentDay(s.group, now: now)
        let epoch: Int = s.group.epoch

        let pending = ExcuseInfo(userID: uid, day: day, epoch: epoch, text: body, serverDate: nil)
        inFlightExcuses.insert(pending)
        defer { inFlightExcuses.remove(pending) }
        var optimistic: GroupSnapshot = s
        optimistic.excuses.append(pending)
        snapshots[id] = optimistic

        do {
            let saved: ExcuseInfo = try await cloud.saveExcuse(pending, in: id)
            if var cur = snapshots[id] {
                cur.excuses.removeAll(where: { $0.userID == uid && $0.day == day && $0.epoch == epoch })
                cur.excuses.append(saved)
                snapshots[id] = cur
            }
            persist()
            refreshSoon(id)
            return true
        } catch {
            if var cur = snapshots[id] {
                cur.excuses.removeAll(where: { $0 == pending })
                snapshots[id] = cur
            }
            toast = ownerStorageFull(error, in: id) ?? "Couldn't send your excuse. Try again."
            return false
        }
    }

    /// Casts or changes your vote on `subject`'s check-in or excuse for `day`. Ignored unless you are one
    /// of its voters and voting on that day is open, and while your last vote on it is still saving: two
    /// saves of one record could land out of order. A change is also ignored in voting's last half hour
    /// (`Review.canChangeVote`), where it could land after the close and take the vote it replaces with it.
    func vote(subject: String, day: Int, counts: Bool, in id: GroupID) async {
        guard let uid = userID, uid != subject, let s = snapshots[id] else { return }
        let now: Date = Date()
        guard Review.isOpen(day: day, group: s.group, now: now),
              Review.eligibleVoters(subject: subject, day: day, snapshot: s).contains(uid) else { return }
        let pending = VoteInfo(voterID: uid, subjectID: subject, day: day, epoch: s.group.epoch, counts: counts,
                               castDay: DayClock.currentDay(s.group, now: now), serverDate: nil)
        if inFlightVotes.contains(where: { (v: VoteInfo) -> Bool in AppStore.sameVote(v, pending) }) { return }
        let previous: VoteInfo? = s.votes.first(where: { (v: VoteInfo) -> Bool in AppStore.sameVote(v, pending) })
        if previous?.counts == counts { return }
        if previous != nil && !Review.canChangeVote(day: day, group: s.group, now: now) { return }

        inFlightVotes.insert(pending)
        defer { inFlightVotes.remove(pending) }
        setVote(pending, in: id)

        do {
            let saved: VoteInfo = try await cloud.saveVote(pending, in: id)
            setVote(saved, in: id)
            persist()
        } catch {
            if let p = previous {
                setVote(p, in: id)
            } else {
                removeVote(pending, in: id)
            }
            toast = ownerStorageFull(error, in: id) ?? "Couldn't vote. Try again."
        }
    }

    /// Sets your reaction to a post: `emoji` replaces the one you had, and nil takes it back (the record keeps "",
    /// because it is overwritten, never deleted). Optimistic like a vote: pending at once, then the server's copy,
    /// or back to the reaction it replaced. A second change to the same post while one saves is ignored, because
    /// two saves of one record could land out of order. Active members only, on a post that has been sent.
    func react(_ emoji: String?, to postID: String, in id: GroupID) async {
        guard let uid = userID, let s = snapshots[id], let me = myMember(id), me.leftDay == nil,
              s.posts.contains(where: { (p: PostInfo) -> Bool in p.id == postID && p.serverDate != nil }) else { return }
        let choice: String = emoji ?? ""
        let pending = ReactionInfo(userID: uid, postID: postID, emoji: choice, serverDate: nil)
        if inFlightReactions.contains(where: { (r: ReactionInfo) -> Bool in AppStore.sameReaction(r, pending) }) { return }
        // The last copy, as `Reactions` reads them.
        let previous: ReactionInfo? = s.reactions.last(where: { (r: ReactionInfo) -> Bool in
            AppStore.sameReaction(r, pending)
        })
        if (previous?.emoji ?? "") == choice { return }

        inFlightReactions.insert(pending)
        defer { inFlightReactions.remove(pending) }
        setReaction(pending, in: id)

        do {
            let saved: ReactionInfo = try await cloud.saveReaction(pending, in: id)
            setReaction(saved, in: id)
            persist()
        } catch {
            if let p = previous {
                setReaction(p, in: id)
            } else {
                removeReaction(pending, in: id)
            }
            toast = ownerStorageFull(error, in: id) ?? "Couldn't react. Try again."
        }
    }

    /// False if it wasn't sent. A failed save keeps the message in `failedPosts`, with no toast unless the
    /// group owner's storage is full.
    @discardableResult
    func sendMessage(_ text: String, in id: GroupID) async -> Bool {
        let body: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body.count <= Records.postTextLimit, let s = snapshots[id] else { return false }
        let today: Int = DayClock.currentDay(s.group, now: Date())
        guard let post: PostInfo = newPost(body, draft: nil, day: today, in: id) else { return false }
        return await sendPost(post, draft: nil, in: id)
    }

    /// Posts a photo or video as proof for your claim on `Review.proofDay`: today's check-in or excuse, else
    /// yesterday's while the group can still vote on it. The store takes the draft: its files become the
    /// post's cached media at once, so it shows while `uploads` tracks the upload, and they go once it's
    /// sent or discarded. Refused (no proof day, or not an active member): false, the files deleted and no
    /// toast. A failed save keeps the post in `failedPosts`, with no toast unless the group owner's storage
    /// is full.
    @discardableResult
    func sendProof(_ draft: MediaDraft, caption: String, in id: GroupID) async -> Bool {
        let body: String = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard body.count <= Records.postTextLimit, let uid = userID, let s = snapshots[id],
              let day: Int = Review.proofDay(for: uid, snapshot: s, now: Date()),
              let post: PostInfo = newPost(body, draft: draft, day: day, in: id) else {
            MediaPrep.discard(draft)
            return false
        }
        MediaCache.shared.adopt(draft, postID: post.id, in: id)
        return await sendPost(post, draft: draft, in: id)
    }

    /// Sends a failed post again, as it was: same id, day and text, and a proof's draft. A proof whose
    /// voting has closed meanwhile still goes: it was sent in time. False if it failed again (it stays in
    /// `failedPosts`) or isn't a failed post.
    @discardableResult
    func retryPost(_ postID: String, in id: GroupID) async -> Bool {
        guard failedPosts.contains(postID), !inFlightPosts.contains(postID),
              let post = snapshots[id]?.posts.first(where: { $0.id == postID }) else { return false }
        let draft: MediaDraft? = failedDrafts[postID]
        // A photo or video can't go without its files.
        if post.media != MediaKind.none && draft == nil { return false }
        return await sendPost(post, draft: draft, in: id)
    }

    /// Deletes a post that failed to send, with its draft's files. Only a failed post: nothing sent is taken
    /// back.
    func discardPost(_ postID: String, in id: GroupID) {
        guard failedPosts.contains(postID), !inFlightPosts.contains(postID) else { return }
        failedPosts.remove(postID)
        if let draft: MediaDraft = failedDrafts.removeValue(forKey: postID) {
            MediaPrep.discard(draft)
        }
        MediaCache.shared.remove(postID: postID, in: id)
        if var s = snapshots[id] {
            s.posts.removeAll(where: { $0.id == postID })
            snapshots[id] = s
        }
    }

    /// The owner picks how many voters it takes to overrule a claim. The change applies from tomorrow,
    /// so no day already under way re-settles under it, and a finished vow, which has no tomorrow, keeps
    /// its rule. Refreshes first, so the change is worked out against the current log.
    func setVoteRule(_ rule: VoteRule, in id: GroupID) async {
        guard isOwner(id), snapshots[id] != nil, !voteRuleInFlight.contains(id),
              !testDayInFlight.contains(id) else { return }
        voteRuleInFlight.insert(id)
        defer { voteRuleInFlight.remove(id) }
        await refresh(id)
        let now: Date = Date()
        guard let group = snapshots[id]?.group, !EndDate.isFinished(group, now: now) else { return }
        let rules: [VoteRuleChange] = Review.changing(group, to: rule, now: now)
        if rules == (group.voteRules ?? []) { return }

        do {
            try await cloud.saveVoteRules(rules, in: id)
            if var cur = snapshots[id] {
                cur.group.voteRules = rules
                snapshots[id] = cur
            }
            persist()
            // Picking today's rule only takes back a change that was due tomorrow.
            let today: VoteRule = Review.rule(forDay: DayClock.currentDay(group, now: now), group: group)
            toast = rule == today ? "Voting rule change cancelled." : "Voting rule changes tomorrow."
        } catch {
            toast = "Couldn't change the voting rule. Try again."
        }
    }

    /// You have caught up with the group's Chat. Stores the newest server date the chat dot answers to
    /// rather than the device's clock, so a fast clock can't hide what arrives next; it never moves back.
    func markChatSeen(_ id: GroupID) {
        guard let s = snapshots[id], let newest: Date = AppStore.latestChatActivity(s, excluding: userID) else { return }
        let zone: String = id.zoneName
        if let seen: Date = chatSeenAt[zone], seen >= newest { return }
        chatSeenAt[zone] = newest
        prefs.saveChatSeen(zone: zone, date: newest)
    }

    /// A new post by you, dated with group day `day`; nil unless you are an active member.
    private func newPost(_ text: String, draft: MediaDraft?, day: Int, in id: GroupID) -> PostInfo? {
        guard let uid = userID, let s = snapshots[id], let me = myMember(id), me.leftDay == nil else { return nil }
        return PostInfo(id: "post-\(UUID().uuidString)",
                        authorID: uid,
                        text: text,
                        day: day,
                        epoch: s.group.epoch,
                        isProof: draft != nil,
                        media: draft?.kind ?? MediaKind.none,
                        aspect: draft?.aspect,
                        duration: draft?.duration,
                        serverDate: nil)
    }

    /// Shows `post` at once, then saves it with the draft's files, which are deleted once it's sent. On
    /// failure the post stays, marked in `failedPosts`, and keeps its draft for a retry, unless a reset or a
    /// removed group has taken it meanwhile.
    private func sendPost(_ post: PostInfo, draft: MediaDraft?, in id: GroupID) async -> Bool {
        let postID: String = post.id
        inFlightPosts.insert(postID)
        if failedPosts.contains(postID) {
            failedPosts.remove(postID)
        }
        if draft != nil {
            uploads[postID] = 0
        }
        defer {
            inFlightPosts.remove(postID)
            if draft != nil {
                uploads[postID] = nil
            }
        }
        setPost(post, in: id)
        let progress: @Sendable (Double) -> Void = { [weak self] (fraction: Double) in
            guard let store: AppStore = self else { return }
            Task { @MainActor in
                store.setUpload(fraction, for: postID)
            }
        }

        do {
            let saved: PostInfo = try await cloud.savePost(post, mediaURL: draft?.mediaURL, thumbURL: draft?.thumbURL,
                                                           in: id, progress: progress)
            setPost(saved, in: id)
            persist()
            failedDrafts[postID] = nil
            if let sent: MediaDraft = draft {
                MediaPrep.discard(sent)
            }
            refreshSoon(id)
            return true
        } catch {
            if let s = snapshots[id], s.group.epoch == post.epoch, s.posts.contains(where: { $0.id == postID }) {
                failedPosts.insert(postID)
                failedDrafts[postID] = draft
            } else if let orphan: MediaDraft = draft {
                MediaPrep.discard(orphan)
            }
            // A retry can't help until the owner frees space, so this one failure is said out loud.
            if let full: String = ownerStorageFull(error, in: id) {
                toast = full
            }
            return false
        }
    }

    /// After your own send: replies that landed meanwhile show without waiting for the next poll.
    private func refreshSoon(_ id: GroupID) {
        Task { await self.refresh(id) }
    }

    /// Ignores reports that hop to the main actor after the upload has ended, and steps under 1 %,
    /// which would only redraw the ring.
    private func setUpload(_ fraction: Double, for postID: String) {
        guard let current: Double = uploads[postID] else { return }
        let next: Double = min(1, max(current, fraction))
        guard next > current, next == 1 || next - current >= 0.01 else { return }
        uploads[postID] = next
    }

    // MARK: - Local state helpers

    /// Keeps optimistic (pending, still being saved) records the server doesn't know about yet, your failed
    /// posts, and server-confirmed records a fetch that started before their save didn't see. Check-ins,
    /// excuses and posts are never deleted (resets bump the epoch), so a confirmed one can always be kept.
    /// A vote is overwritten when its voter changes their mind, so yours wins over the fetched copy while
    /// it is saving, and a confirmed one only if the server changed it later than the fetched copy says.
    /// A reaction is overwritten the same way, and kept the same way.
    private func merged(_ incoming: GroupSnapshot, previous: GroupSnapshot?) -> GroupSnapshot {
        guard let prev = previous else { return incoming }
        var out: GroupSnapshot = incoming
        var checkIns: Set<DayKey> = []
        for c in out.checkIns {
            checkIns.insert(DayKey(userID: c.userID, day: c.day, epoch: c.epoch))
        }
        for c in prev.checkIns where c.serverDate != nil || inFlightCheckIns.contains(c) {
            if checkIns.insert(DayKey(userID: c.userID, day: c.day, epoch: c.epoch)).inserted {
                out.checkIns.append(c)
            }
        }
        var excuses: Set<DayKey> = []
        for e in out.excuses {
            excuses.insert(DayKey(userID: e.userID, day: e.day, epoch: e.epoch))
        }
        for e in prev.excuses where e.serverDate != nil || inFlightExcuses.contains(e) {
            if excuses.insert(DayKey(userID: e.userID, day: e.day, epoch: e.epoch)).inserted {
                out.excuses.append(e)
            }
        }
        // Index of the first fetched copy of each vote.
        var votes: [VoteKey: Int] = [:]
        for (i, v) in out.votes.enumerated() where votes[VoteKey(v)] == nil {
            votes[VoteKey(v)] = i
        }
        for v in prev.votes where v.serverDate != nil || inFlightVotes.contains(v) {
            let key: VoteKey = VoteKey(v)
            if let i = votes[key] {
                let fetchedChange: Date = out.votes[i].serverDate ?? .distantPast
                if inFlightVotes.contains(v) || (v.serverDate ?? .distantPast) > fetchedChange {
                    out.votes[i] = v
                }
            } else {
                votes[key] = out.votes.count
                out.votes.append(v)
            }
        }
        var posts: Set<String> = []
        for p in out.posts {
            posts.insert(p.id)
        }
        for p in prev.posts where p.serverDate != nil || inFlightPosts.contains(p.id) || failedPosts.contains(p.id) {
            if posts.insert(p.id).inserted {
                out.posts.append(p)
            }
        }
        // Index of the last fetched copy of each reaction, the one `Reactions` reads.
        var reactions: [ReactionKey: Int] = [:]
        for (i, r) in out.reactions.enumerated() {
            reactions[ReactionKey(r)] = i
        }
        for r in prev.reactions where r.serverDate != nil || inFlightReactions.contains(r) {
            let key: ReactionKey = ReactionKey(r)
            if let i = reactions[key] {
                let fetchedChange: Date = out.reactions[i].serverDate ?? .distantPast
                if inFlightReactions.contains(r) || (r.serverDate ?? .distantPast) > fetchedChange {
                    out.reactions[i] = r
                }
            } else {
                reactions[key] = out.reactions.count
                out.reactions.append(r)
            }
        }
        return out
    }

    /// Equal apart from when each was fetched: a refresh that brought nothing new.
    private static func sameContent(_ a: GroupSnapshot, _ b: GroupSnapshot) -> Bool {
        var aligned: GroupSnapshot = a
        aligned.fetchedAt = b.fetchedAt
        return aligned == b
    }

    /// One vote per voter, subject, day and epoch: the vote record's identity.
    private static func sameVote(_ a: VoteInfo, _ b: VoteInfo) -> Bool {
        return VoteKey(a) == VoteKey(b)
    }

    /// One reaction per user and post: the reaction record's identity.
    private static func sameReaction(_ a: ReactionInfo, _ b: ReactionInfo) -> Bool {
        return ReactionKey(a) == ReactionKey(b)
    }

    /// A check-in's or an excuse's identity, as its record name spells it: who, which day, which epoch.
    private struct DayKey: Hashable {
        let userID: String
        let day: Int
        let epoch: Int
    }

    /// A vote's identity: voting again overwrites the record.
    private struct VoteKey: Hashable {
        let voterID: String
        let subjectID: String
        let day: Int
        let epoch: Int

        init(_ v: VoteInfo) {
            voterID = v.voterID
            subjectID = v.subjectID
            day = v.day
            epoch = v.epoch
        }
    }

    /// A reaction's identity, as its record name spells it: who, on which post.
    private struct ReactionKey: Hashable {
        let userID: String
        let postID: String

        init(_ r: ReactionInfo) {
            userID = r.userID
            postID = r.postID
        }
    }

    /// Puts `vote` in place of the one it overwrites, if any.
    private func setVote(_ vote: VoteInfo, in id: GroupID) {
        guard var s = snapshots[id] else { return }
        s.votes.removeAll(where: { (v: VoteInfo) -> Bool in AppStore.sameVote(v, vote) })
        s.votes.append(vote)
        snapshots[id] = s
    }

    private func removeVote(_ vote: VoteInfo, in id: GroupID) {
        guard var s = snapshots[id] else { return }
        s.votes.removeAll(where: { $0 == vote })
        snapshots[id] = s
    }

    /// Puts `reaction` in place of the one it overwrites, if any.
    private func setReaction(_ reaction: ReactionInfo, in id: GroupID) {
        guard var s = snapshots[id] else { return }
        s.reactions.removeAll(where: { (r: ReactionInfo) -> Bool in AppStore.sameReaction(r, reaction) })
        s.reactions.append(reaction)
        snapshots[id] = s
    }

    private func removeReaction(_ reaction: ReactionInfo, in id: GroupID) {
        guard var s = snapshots[id] else { return }
        s.reactions.removeAll(where: { $0 == reaction })
        snapshots[id] = s
    }

    /// Puts `post` in place of the one with its id (a pending copy), or adds it.
    private func setPost(_ post: PostInfo, in id: GroupID) {
        guard var s = snapshots[id] else { return }
        if let i = s.posts.firstIndex(where: { $0.id == post.id }) {
            s.posts[i] = post
        } else {
            s.posts.append(post)
        }
        snapshots[id] = s
    }

    /// Skips a snapshot that brings nothing new: writing it would re-render every view that reads
    /// `snapshots`, and persisting encodes every group.
    private func upsert(_ s: GroupSnapshot) {
        let id: GroupID = s.group.id
        if let current = snapshots[id], AppStore.sameContent(s, current), groupIDs.contains(id) { return }
        snapshots[id] = s
        if !groupIDs.contains(id) {
            groupIDs.append(id)
            reorder()
        }
        pruneFailedPosts()
        persist()
    }

    /// A failed post stays failed only while it is still here, unsent, in its group's epoch: a fetch can
    /// show it saved after all (its save landed but the reply was lost), a group that has gone takes its
    /// posts with it, and a test group's reset leaves the old epoch's posts out of Chat, where nobody could
    /// retry or delete them. Either way its draft's files go, and the next fetch drops an unsent one.
    private func pruneFailedPosts() {
        if failedPosts.isEmpty { return }
        var unsent: Set<String> = []
        for s in snapshots.values {
            for p in s.posts where p.serverDate == nil && p.epoch == s.group.epoch && failedPosts.contains(p.id) {
                unsent.insert(p.id)
            }
        }
        for postID in failedPosts.subtracting(unsent) {
            failedPosts.remove(postID)
            if let draft: MediaDraft = failedDrafts.removeValue(forKey: postID) {
                MediaPrep.discard(draft)
            }
        }
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

    /// Forgets a group you left or deleted, or that has gone, with its downloaded photos and videos and what
    /// its fetches have seen.
    private func removeLocal(_ id: GroupID) {
        snapshots[id] = nil
        groupIDs.removeAll(where: { $0 == id })
        themeCache[id] = nil
        MediaCache.shared.removeGroup(id)
        cloud.forgetZone(id)
        if pendingVowPrompt == id {
            pendingVowPrompt = nil
        }
        pruneFailedPosts()
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
        let order: [GroupID] = sorted.map { $0.group.id }
        if order != groupIDs {
            groupIDs = order
        }
    }

    private func persist() {
        var list: [GroupSnapshot] = []
        for id in groupIDs {
            if var s = snapshots[id] {
                // Never cache optimistic records: they'd outlive their save attempt.
                s.checkIns.removeAll(where: { $0.serverDate == nil })
                s.excuses.removeAll(where: { $0.serverDate == nil })
                s.votes.removeAll(where: { $0.serverDate == nil })
                s.posts.removeAll(where: { $0.serverDate == nil })
                s.reactions.removeAll(where: { $0.serverDate == nil })
                list.append(s)
            }
        }
        cache.save(SnapshotCache.Payload(userID: userID, order: groupIDs, snapshots: list))
    }
}
