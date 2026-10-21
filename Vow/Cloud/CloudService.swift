import CloudKit
import Foundation

/// App-level errors that are not CKErrors.
enum CloudError: Error {
    case groupMissing
    case invalidLink
    case ownerCannotLeave
    /// A post without the photo, video or thumbnail asked for.
    case mediaMissing
}

/// Thin async wrapper over CloudKit. One group = one custom zone in the owner's private
/// database, shared zone-wide; participants see it in their shared database.
final class CloudService: @unchecked Sendable {
    static let shared: CloudService = CloudService()

    private let injectedContainer: CKContainer?
    private let containerLock = NSLock()
    private var resolvedContainer: CKContainer? = nil

    /// The container is created lazily on first use (never at init), so merely referencing
    /// CloudService.shared doesn't touch CloudKit (unit tests run without entitlements).
    init(container: CKContainer? = nil) {
        self.injectedContainer = container
    }

    var container: CKContainer {
        containerLock.lock()
        defer { containerLock.unlock() }
        if let c = resolvedContainer { return c }
        let c: CKContainer = injectedContainer ?? CKContainer.default()
        resolvedContainer = c
        return c
    }

    private var privateDB: CKDatabase { return container.privateCloudDatabase }
    private var sharedDB: CKDatabase { return container.sharedCloudDatabase }

    func database(for id: GroupID) -> CKDatabase {
        return id.ownerName == CKCurrentUserDefaultName ? privateDB : sharedDB
    }

    // MARK: - Account

    func accountStatus() async throws -> CKAccountStatus {
        return try await container.accountStatus()
    }

    func currentUserID() async throws -> String {
        let recordID: CKRecord.ID = try await container.userRecordID()
        return recordID.recordName
    }

    // MARK: - Reading

    func fetchGroupIDs() async throws -> [GroupID] {
        var ids: [GroupID] = []
        let privateZones: [CKRecordZone] = try await privateDB.allRecordZones()
        for zone in privateZones where zone.zoneID.zoneName.hasPrefix(Records.zonePrefix) {
            ids.append(Records.groupID(zone.zoneID))
        }
        let sharedZones: [CKRecordZone] = try await sharedDB.allRecordZones()
        for zone in sharedZones where zone.zoneID.zoneName.hasPrefix(Records.zonePrefix) {
            ids.append(Records.groupID(zone.zoneID))
        }
        return ids
    }

    /// The whole zone without assets (`Records.snapshotKeys`): posts arrive as text, aspect and duration, and their
    /// photos and videos are fetched one at a time with `fetchAsset`.
    func fetchSnapshot(_ id: GroupID) async throws -> GroupSnapshot {
        let db: CKDatabase = database(for: id)
        let zoneID: CKRecordZone.ID = Records.zoneID(id)

        var token: CKServerChangeToken? = nil
        var moreComing: Bool = true
        var groupRecord: CKRecord? = nil
        var members: [String: MemberInfo] = [:]
        var checkIns: [String: CheckInInfo] = [:]
        var excuses: [String: ExcuseInfo] = [:]
        var votes: [String: VoteInfo] = [:]
        var posts: [String: PostInfo] = [:]
        var shareURL: URL? = nil

        while moreComing {
            let changes = try await db.recordZoneChanges(inZoneWith: zoneID, since: token,
                                                         desiredKeys: Records.snapshotKeys)
            for (_, result) in changes.modificationResultsByID {
                switch result {
                case .success(let modification):
                    let record: CKRecord = modification.record
                    if let share = record as? CKShare {
                        if let url = share.url { shareURL = url }
                        continue
                    }
                    let name: String = record.recordID.recordName
                    switch record.recordType {
                    case Records.groupType:
                        groupRecord = record
                    case Records.memberType:
                        if let m = Records.memberInfo(from: record) {
                            members[m.userID] = m
                        }
                    case Records.checkInType:
                        if let c = Records.checkInInfo(from: record) {
                            checkIns[name] = c
                        }
                    case Records.excuseType:
                        if let e = Records.excuseInfo(from: record) {
                            excuses[name] = e
                        }
                    case Records.voteType:
                        if let v = Records.voteInfo(from: record) {
                            votes[name] = v
                        }
                    case Records.postType:
                        if let p = Records.postInfo(from: record) {
                            posts[name] = p
                        }
                    default:
                        break
                    }
                case .failure:
                    continue
                }
            }
            token = changes.changeToken
            moreComing = changes.moreComing
        }

        guard let gRecord = groupRecord else { throw CloudError.groupMissing }
        var group: GroupInfo = Records.groupInfo(from: gRecord, id: id)

        if shareURL == nil {
            let fetched: CKRecord? = try? await db.record(for: Records.shareRecordID(in: id))
            if let share = fetched as? CKShare {
                shareURL = share.url
            }
        }
        group.shareURL = shareURL

        let memberList: [MemberInfo] = members.values.sorted { $0.userID < $1.userID }
        let checkInList: [CheckInInfo] = checkIns.values.sorted { (a: CheckInInfo, b: CheckInInfo) -> Bool in
            if a.day != b.day { return a.day < b.day }
            return a.userID < b.userID
        }
        let excuseList: [ExcuseInfo] = excuses.values.sorted { (a: ExcuseInfo, b: ExcuseInfo) -> Bool in
            if a.day != b.day { return a.day < b.day }
            if a.userID != b.userID { return a.userID < b.userID }
            return a.epoch < b.epoch
        }
        let voteList: [VoteInfo] = votes.values.sorted { (a: VoteInfo, b: VoteInfo) -> Bool in
            if a.day != b.day { return a.day < b.day }
            if a.subjectID != b.subjectID { return a.subjectID < b.subjectID }
            if a.voterID != b.voterID { return a.voterID < b.voterID }
            return a.epoch < b.epoch
        }
        let postList: [PostInfo] = posts.values.sorted { (a: PostInfo, b: PostInfo) -> Bool in
            let sentA: Date = a.serverDate ?? .distantFuture
            let sentB: Date = b.serverDate ?? .distantFuture
            if sentA != sentB { return sentA < sentB }
            return a.id < b.id
        }
        return GroupSnapshot(group: group, members: memberList, checkIns: checkInList, fetchedAt: Date(),
                             excuses: excuseList, votes: voteList, posts: postList)
    }

    /// Downloads one of a post's assets and returns CloudKit's temporary file for it. Copy the file before
    /// returning to the run loop: CloudKit may delete it.
    func fetchAsset(postID: String, key: MediaAssetKey, in id: GroupID) async throws -> URL {
        let db: CKDatabase = database(for: id)
        let recordID: CKRecord.ID = Records.postRecordID(postID, in: id)
        let results: [CKRecord.ID: Result<CKRecord, Error>] = try await db.records(for: [recordID],
                                                                                 desiredKeys: [key.rawValue])
        guard let result = results[recordID] else { throw CloudError.mediaMissing }
        let record: CKRecord = try result.get()
        guard let asset = record[key.rawValue] as? CKAsset, let url = asset.fileURL else {
            throw CloudError.mediaMissing
        }
        return url
    }

    // MARK: - Creating / joining

    /// `endDate`: any moment on the vow's final day (nil = no end). It is stored as a day index in the
    /// group's day clock, at least 1 (the earliest end is tomorrow).
    func createGroup(name: String, stake: Int, isTest: Bool, endDate: Date?, me: MemberInfo) async throws -> GroupSnapshot {
        let zoneName: String = Records.zonePrefix + UUID().uuidString
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        let zone = CKRecordZone(zoneID: zoneID)

        let zoneResult = try await privateDB.modifyRecordZones(saving: [zone], deleting: [])
        if let r = zoneResult.saveResults[zoneID] {
            switch r {
            case .success:
                break
            case .failure(let error):
                throw error
            }
        }

        let id: GroupID = Records.groupID(zoneID)
        let now = Date()
        let tz: String = TimeZone.current.identifier
        var endDay: Int? = nil
        if let end: Date = endDate {
            let index: Int = DayClock.dayIndex(of: end, start: now, timeZoneID: tz)
            endDay = min(max(1, index), EndDate.maxEndDay)
        }
        var info = GroupInfo(
            id: id,
            name: name,
            stake: stake,
            createdAt: now,
            timeZoneID: tz,
            isTest: isTest,
            testDay: 0,
            epoch: 0,
            ownerUserID: me.userID,
            shareURL: nil,
            endDay: endDay
        )

        let groupRecord = CKRecord(recordType: Records.groupType, recordID: Records.groupRecordID(id))
        Records.apply(info, to: groupRecord)

        let memberRecord = CKRecord(recordType: Records.memberType,
                                    recordID: Records.memberRecordID(userID: me.userID, in: id))
        Records.apply(me, to: memberRecord)

        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = name as CKRecordValue
        share.publicPermission = .readWrite

        let saved: [CKRecord] = try await save([groupRecord, memberRecord, share], in: privateDB,
                                               policy: .ifServerRecordUnchanged, atomically: true)
        for record in saved {
            if let savedShare = record as? CKShare {
                info.shareURL = savedShare.url
            }
        }

        return GroupSnapshot(group: info, members: [me], checkIns: [], fetchedAt: Date())
    }

    func shareMetadata(for url: URL) async throws -> CKShare.Metadata {
        let box: ResultBox<CKShare.Metadata> = ResultBox<CKShare.Metadata>()
        let container: CKContainer = self.container
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CKShare.Metadata, Error>) in
            let op = CKFetchShareMetadataOperation(shareURLs: [url])
            op.shouldFetchRootRecord = false
            op.perShareMetadataResultBlock = { (_: URL, result: Result<CKShare.Metadata, Error>) in
                box.set(result)
            }
            op.fetchShareMetadataResultBlock = { (result: Result<Void, Error>) in
                switch result {
                case .failure(let error):
                    cont.resume(throwing: error)
                case .success:
                    if let perShare = box.get() {
                        cont.resume(with: perShare)
                    } else {
                        cont.resume(throwing: CloudError.invalidLink)
                    }
                }
            }
            container.add(op)
        }
    }

    /// Accepts a zone-wide share and returns the GroupID to use locally.
    /// The owner opening their own link is a no-op that returns the private-database ID.
    func accept(_ metadata: CKShare.Metadata) async throws -> GroupID {
        let zoneID: CKRecordZone.ID = metadata.share.recordID.zoneID
        if metadata.participantRole == .owner {
            return GroupID(zoneName: zoneID.zoneName, ownerName: CKCurrentUserDefaultName)
        }
        if metadata.participantStatus == .accepted {
            return Records.groupID(zoneID)
        }
        let accepted: CKShare = try await container.accept(metadata)
        return Records.groupID(accepted.recordID.zoneID)
    }

    // MARK: - Writing

    func saveMember(_ member: MemberInfo, in id: GroupID) async throws {
        let db: CKDatabase = database(for: id)
        let recordID: CKRecord.ID = Records.memberRecordID(userID: member.userID, in: id)
        let record: CKRecord = try await existingRecord(recordID, in: db)
            ?? CKRecord(recordType: Records.memberType, recordID: recordID)
        Records.apply(member, to: record)
        _ = try await save([record], in: db, policy: .changedKeys, atomically: false)
    }

    /// Idempotent: the record name is deterministic, so a re-send that hits an existing
    /// record returns the server's existing check-in.
    func saveCheckIn(_ checkIn: CheckInInfo, in id: GroupID) async throws -> CheckInInfo {
        let record = CKRecord(recordType: Records.checkInType, recordID: Records.checkInRecordID(checkIn, in: id))
        Records.apply(checkIn, to: record)
        let saved: CKRecord = try await create(record, in: database(for: id))
        return Records.checkInInfo(from: saved) ?? checkIn
    }

    /// Idempotent like `saveCheckIn`: an excuse already on the server (a re-send, or one sent from another device)
    /// comes back as the server's copy.
    func saveExcuse(_ excuse: ExcuseInfo, in id: GroupID) async throws -> ExcuseInfo {
        let record = CKRecord(recordType: Records.excuseType, recordID: Records.excuseRecordID(excuse, in: id))
        Records.apply(excuse, to: record)
        let saved: CKRecord = try await create(record, in: database(for: id))
        return Records.excuseInfo(from: saved) ?? excuse
    }

    /// One record per (voter, subject, day): voting again overwrites it, and its server modificationDate, which
    /// dates the vote, moves with it. Re-sending the verdict already saved changes nothing, so it can't push a vote
    /// out of the window.
    func saveVote(_ vote: VoteInfo, in id: GroupID) async throws -> VoteInfo {
        let db: CKDatabase = database(for: id)
        let recordID: CKRecord.ID = Records.voteRecordID(vote, in: id)
        let existing: CKRecord? = try await existingRecord(recordID, in: db)
        if let record = existing, let current = Records.voteInfo(from: record), current.counts == vote.counts {
            return current
        }
        let record: CKRecord = existing ?? CKRecord(recordType: Records.voteType, recordID: recordID)
        Records.apply(vote, to: record)
        let saved: [CKRecord] = try await save([record], in: db, policy: .changedKeys, atomically: false)
        return Records.voteInfo(from: saved.first ?? record) ?? vote
    }

    /// Saves a new post with its files. `progress` reports the upload (0…1) on CloudKit's queue, not the main
    /// thread. Returns the post with the server's creationDate. Idempotent like `saveCheckIn`: a retry whose first
    /// save landed but whose reply was lost finds the post there and returns the server's copy, read without its
    /// photo or video.
    func savePost(_ post: PostInfo, mediaURL: URL?, thumbURL: URL?, in id: GroupID,
                  progress: @escaping @Sendable (Double) -> Void) async throws -> PostInfo {
        let db: CKDatabase = database(for: id)
        let recordID: CKRecord.ID = Records.postRecordID(post.id, in: id)
        let record = CKRecord(recordType: Records.postType, recordID: recordID)
        Records.apply(post, to: record)
        Records.attach(media: mediaURL, thumb: thumbURL, to: record)
        do {
            let saved: CKRecord = try await upload(record, in: db, progress: progress)
            return Records.postInfo(from: saved) ?? post
        } catch {
            guard CloudErrors.code(error) == .serverRecordChanged else { throw error }
            let found: [CKRecord.ID: Result<CKRecord, Error>] = try await db.records(for: [recordID],
                                                                                   desiredKeys: Records.snapshotKeys)
            guard let result = found[recordID] else { throw error }
            let existing: CKRecord = try result.get()
            return Records.postInfo(from: existing) ?? post
        }
    }

    func saveGroup(_ group: GroupInfo) async throws {
        let db: CKDatabase = database(for: group.id)
        let recordID: CKRecord.ID = Records.groupRecordID(group.id)
        let record: CKRecord = try await existingRecord(recordID, in: db)
            ?? CKRecord(recordType: Records.groupType, recordID: recordID)
        Records.apply(group, to: record)
        _ = try await save([record], in: db, policy: .changedKeys, atomically: false)
    }

    /// Sets the Group record's voteRules and nothing else, on a freshly fetched record, so a stale GroupInfo can't
    /// roll back its other fields. A missing group throws rather than creating a bare record.
    func saveVoteRules(_ rules: [VoteRuleChange], in id: GroupID) async throws {
        let db: CKDatabase = database(for: id)
        let record: CKRecord = try await db.record(for: Records.groupRecordID(id))
        Records.apply(voteRules: rules, to: record)
        _ = try await save([record], in: db, policy: .changedKeys, atomically: false)
    }

    /// Participant leaves: deleting the zone from the shared database leaves the share.
    func leave(_ id: GroupID) async throws {
        if id.ownerName == CKCurrentUserDefaultName {
            throw CloudError.ownerCannotLeave
        }
        _ = try await sharedDB.deleteRecordZone(withID: Records.zoneID(id))
    }

    /// Owner deletes the whole group (zone + share + records).
    func deleteGroup(_ id: GroupID) async throws {
        _ = try await privateDB.deleteRecordZone(withID: Records.zoneID(id))
    }

    // MARK: - Helpers

    private func existingRecord(_ recordID: CKRecord.ID, in db: CKDatabase) async throws -> CKRecord? {
        do {
            let record: CKRecord = try await db.record(for: recordID)
            return record
        } catch {
            if CloudErrors.code(error) == .unknownItem {
                return nil
            }
            throw error
        }
    }

    /// Saves a new record whose name is deterministic. If it already exists (a re-send after a lost reply, or the
    /// same claim from another device), the server's copy comes back instead.
    private func create(_ record: CKRecord, in db: CKDatabase) async throws -> CKRecord {
        do {
            let saved: [CKRecord] = try await save([record], in: db, policy: .ifServerRecordUnchanged, atomically: false)
            return saved.first ?? record
        } catch {
            guard CloudErrors.code(error) == .serverRecordChanged else { throw error }
            return try await db.record(for: record.recordID)
        }
    }

    /// Saves one new record through an operation, which (unlike `modifyRecords`) reports its upload progress.
    private func upload(_ record: CKRecord, in db: CKDatabase,
                        progress: @escaping @Sendable (Double) -> Void) async throws -> CKRecord {
        let box: ResultBox<CKRecord> = ResultBox<CKRecord>()
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CKRecord, Error>) in
            let op = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            op.savePolicy = .ifServerRecordUnchanged
            op.qualityOfService = .userInitiated
            op.perRecordProgressBlock = { (_: CKRecord, fraction: Double) in
                progress(fraction)
            }
            op.perRecordSaveBlock = { (_: CKRecord.ID, result: Result<CKRecord, Error>) in
                box.set(result)
            }
            op.modifyRecordsResultBlock = { (result: Result<Void, Error>) in
                if let saved = box.get() {
                    cont.resume(with: saved)
                    return
                }
                switch result {
                case .failure(let error):
                    cont.resume(throwing: error)
                case .success:
                    cont.resume(throwing: CKError(.internalError))
                }
            }
            db.add(op)
        }
    }

    /// Saves records and unwraps the per-record results, throwing the most meaningful error.
    private func save(_ records: [CKRecord],
                      in db: CKDatabase,
                      policy: CKModifyRecordsOperation.RecordSavePolicy,
                      atomically: Bool) async throws -> [CKRecord] {
        let result = try await db.modifyRecords(saving: records,
                                                deleting: [],
                                                savePolicy: policy,
                                                atomically: atomically)
        var saved: [CKRecord] = []
        var firstError: Error? = nil
        var firstRealError: Error? = nil
        for record in records {
            guard let r = result.saveResults[record.recordID] else { continue }
            switch r {
            case .success(let s):
                saved.append(s)
            case .failure(let error):
                if firstError == nil { firstError = error }
                if firstRealError == nil && CloudErrors.code(error) != .batchRequestFailed {
                    firstRealError = error
                }
            }
        }
        if let e = firstRealError ?? firstError {
            throw e
        }
        return saved
    }
}

/// Thread-safe holder for a per-item result that an operation reports on its own queue before it completes.
private final class ResultBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<Value, Error>? = nil

    func set(_ v: Result<Value, Error>) {
        lock.lock()
        value = v
        lock.unlock()
    }

    func get() -> Result<Value, Error>? {
        lock.lock()
        let v = value
        lock.unlock()
        return v
    }
}

/// CKError -> short human messages.
enum CloudErrors {
    static func code(_ error: Error) -> CKError.Code? {
        guard let ck = error as? CKError else { return nil }
        if ck.code == .partialFailure, let parts = ck.partialErrorsByItemID {
            var fallback: CKError.Code? = nil
            for (_, part) in parts {
                if let pc = part as? CKError {
                    if pc.code != .batchRequestFailed { return pc.code }
                    if fallback == nil { fallback = pc.code }
                }
            }
            if let f = fallback { return f }
        }
        return ck.code
    }

    /// The group is gone (deleted by the owner, or we left it).
    static func isGone(_ error: Error) -> Bool {
        if let app = error as? CloudError, app == .groupMissing { return true }
        guard let c = code(error) else { return false }
        return c == .zoneNotFound || c == .userDeletedZone || c == .unknownItem
    }

    static func isNetwork(_ error: Error) -> Bool {
        guard let c = code(error) else { return false }
        return c == .networkUnavailable || c == .networkFailure
    }

    /// Why groups can't be used with this iCloud account status (any status but .available).
    static func accountMessage(_ status: CKAccountStatus) -> String {
        switch status {
        case .restricted:
            return "iCloud is restricted on this device. Groups need iCloud."
        case .couldNotDetermine:
            return "Couldn't check your iCloud account. Make sure you're signed in, then try again."
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable. Check Settings > iCloud, then try again."
        default:
            return "Sign in to iCloud in Settings to use groups."
        }
    }

    /// The underlying CloudKit error (the first real one inside a partial failure).
    private static func detail(_ error: Error) -> CKError? {
        guard let ck = error as? CKError else { return nil }
        if ck.code == .partialFailure, let parts = ck.partialErrorsByItemID {
            for (_, part) in parts {
                if let pc = part as? CKError, pc.code != .batchRequestFailed { return pc }
            }
        }
        return ck
    }

    static func message(_ error: Error) -> String {
        if let app = error as? CloudError {
            switch app {
            case .groupMissing: return "That group no longer exists."
            case .invalidLink: return "That invite link doesn't work."
            case .ownerCannotLeave: return "You own this group. Delete it instead."
            case .mediaMissing: return "That photo or video isn't available."
            }
        }
        guard let c = code(error) else {
            return "Something went wrong."
        }
        switch c {
        case .networkUnavailable, .networkFailure:
            return "You're offline."
        case .notAuthenticated:
            return "Sign in to iCloud."
        case .quotaExceeded:
            return "Your iCloud storage is full."
        case .zoneNotFound, .unknownItem, .userDeletedZone:
            return "That group no longer exists."
        case .permissionFailure:
            return "You don't have access to that group."
        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return "iCloud is busy. Try again in a moment."
        case .participantMayNeedVerification:
            return "Open the invite link again to verify your account."
        case .serverRecordChanged:
            return "Someone else changed this. Pull to refresh."
        case .badContainer, .missingEntitlement:
            return "This build isn't set up for iCloud: turn on iCloud > CloudKit for the app and check its container (code \(c.rawValue))."
        case .accountTemporarilyUnavailable:
            return "iCloud is temporarily unavailable. Check Settings > iCloud, then try again."
        default:
            let text: String = detail(error)?.localizedDescription ?? ""
            if text.localizedCaseInsensitiveContains("production schema") {
                return "The iCloud schema hasn't been deployed to Production yet. Deploy it in the CloudKit Console, or use a build run from Xcode (code \(c.rawValue))."
            }
            if text.isEmpty {
                return "Something went wrong (code \(c.rawValue))."
            }
            return "Something went wrong (code \(c.rawValue)): \(text)"
        }
    }
}
