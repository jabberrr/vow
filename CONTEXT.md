# CONTEXT.md: Vow

A briefing for Claude Code sessions that work on Vow. `CLAUDE.md` imports it, so it loads automatically.

Sections are numbered for scanning. **Code comments that cite "§7", "§6.10" or "SPEC §3" refer to an external design spec, not to this file** (see Known issues).

---

## 1. Working rules

These rules apply to every session.

1. **Use subagents, and finish with a critic.**
   - When a task allows it, do the work with the subagent setup you judge most efficient. Run independent work in parallel and keep dependent steps in order.
   - Split the work by area, not into arbitrary pieces. For example: Domain and tests, Cloud and Store, UI. Or: one agent researches, one implements, one writes tests.
   - Subagents don't see your conversation. Brief each one with the goal, the files involved and the sections of this file that apply.
   - Do trivial changes yourself, such as a typo or a one-line fix you fully understand.
   - **Any non-trivial change ends with a critic subagent.** Give it the diff and the original goal. Ask it to check that:
     - the work is correct and meets the goal;
     - it follows the Invariants (§5) and Code style (§7);
     - nothing is half-finished: project not regenerated, README out of date, tests missing, this file not updated.
   - Fix what the critic finds before you commit. If you disagree with a finding, say why.
2. **Write high-quality, polished code with a sensible structure.**
   - Code should read as if the original author wrote it. Don't write code that merely works.
   - Put logic in the right layer (§4), name things precisely, avoid duplication, and delete what you replace.
   - Keep it efficient. Don't gold-plate, and don't widen the scope of the task.
3. **Update this file after you finish something.**
   - Record anything a future session would need: new invariants, new files or layers, changed conventions, gotchas, fixed or new known issues (§10).
   - Edit facts in place. Don't append a diary.
   - Remove anything that is no longer true.
4. **Record new work habits when asked.**
   - When the user asks for a new standing rule or work habit, add it to this section in the same format.
   - The format is a numbered, bold one-line rule, followed by indented bullets with the specifics.

---

## 2. Project brief

**Vow** is an iOS 17+ SwiftUI app for keeping one promise a day, together.
- Friends form a **group**, and each member writes their own **vow**.
- Every day each member **presses and holds the orb** to check in, or sends an **excuse** instead.
- If you miss a day, you lose the group's **stake** (1, 2, 5 or 10 pts) into the **pot**.
- The pot is split equally among those who kept their vow that day. If nobody kept, the pot carries over to the next day.
- Each group has a **Chat**: messages, and every check-in and excuse as a card with its photo or video **proof** and the group's **votes**.
  - A check-in or excuse counts unless enough of the others vote "Doesn't count" by the end of the next day. How many is the owner's **voting rule**, and a change applies from tomorrow.
  - An overruled check-in or excuse is a miss. An excuse that stands sits the day out: no stake lost, no share of the pot, and the streak pauses. An excuse closes today's orb for good.
- **Points only.** No real money is involved.
- **No backend and no accounts.** Data lives in CloudKit:
  - Each group is a record zone in the owner's private database.
  - The zone is shared through a zone-wide `CKShare` that anyone with the link can join.
  - Photos and videos are assets in that zone, so every member's media counts against the owner's iCloud storage.
- **No third-party dependencies.**
- **iPhone only, portrait only, dark only.**
- **Testing mode** (Settings → Testing mode) creates test groups whose day the owner advances by hand.

**State as of 2026-10:** about 24k lines of Swift (tests included). `cc4da4c` redesigned the UI around a single **stage**. Round 3 added optional **end dates** (`f44253f`, `9b0bc7e`, `9a3980f`) and then replaced the dock and the cards under the stage with a **shell**: a top bar with ≡, tabs per group and a sidebar, with one `Presenter` for every sheet. Round 4 polished that shell from device testing: an always-mounted sidebar, a connected flame streak calendar with a wider month range, a still Home page and a centred tab bar. Round 5 added the **Chat** tab (second of five: Home, Chat, Streak, Activity, Group) with proof, excuses and votes: the `Review` rules in Domain, a `Media` layer, the record types `Excuse`, `Vote` and `Post`, and full-screen covers in the `Presenter`. Settlement now applies the group's verdicts. The orb, the glyph, sound, the cascade's timing and the existing ledger strings were left unchanged.

**`README.md`** is the user-facing doc: setup, schema deployment, how points work and the repository layout. Keep it accurate whenever behaviour, setup or layout changes.

---

## 3. Repository map

```
Vow/
  App/        VowApp (entry, env injection, scene-phase refresh), RootView (screen routing, toast), AppDelegate+SceneDelegate (iCloud share acceptance)
  Domain/     PURE Swift, no UI or CloudKit: GroupModels, DayClock, Settlement, Review (claims, votes, verdicts, rule log, proofDay), Standing, Streaks, EndDate, StreakCalendar, CycleChain (unused), Digest(+DayWindow), ReminderPlan, Points, VowText
  Cloud/      CloudService (CloudKit I/O incl. post uploads and asset fetches, CloudError, CloudErrors), Records (CKRecord <-> models, snapshotKeys, text limits), ShareInbox (buffers accepted shares until the store is ready)
  Media/      MediaPrep (MediaDraft: photos and videos sized into Caches/vow-outbox), MediaCache (@MainActor @Observable: post assets on disk under Caches/vow-media)
  Store/      AppStore (@MainActor @Observable app state, incl. the chat sends), AppStore+Stage and AppStore+Chat (read-only helpers), Overview (aggregates, VowStatus, MenuDot), SnapshotCache (JSON on disk), Preferences (UserDefaults)
  Design/     Tokens (Ink, Fonts, Gap, Corner, Anim, StageMetrics), Styles, Buttons, Fields, SheetScaffold, Feedback (toast, banner, tag), Sphere, Flame, Formatters (incl. DayText, VoteRuleText), OrbBridge
  Features/   Main (the shell: MainView, Presenter, TopBar, VowTabBar, Sidebar with ProfileRow and AddGroupMenu, MainTab)
              Stage (Home tab: StageScreen + parts incl. StageFoot, FinishedStage), Streak (StreakPage, StreakStatsCard, StreakCalendarView)
              Chat (ChatPage, ChatFeed: the pure feed model, ClaimCard, MessageBubble, ChatComposer, ChatPlusMenu, ChatText)
              Proof (PostMediaView, CameraPicker, LibraryPicker, ProofSheet, MediaViewer with the pickers' ProofPrep and PreparingOverlay)
              Activity (ActivityPage, LedgerFormat, LedgerRow), Group (GroupPage, GroupMembersCard with MemberDay and KeptNote, which Home's strip shares, MemberSheet, VoteRuleSheet)
              Menu (SettingsSheet, ProfileSheet), Sheets (NewGroup, JoinLink, InviteLink, Vow, Excuse), Root (onboarding, status)
  Orb/        Press-and-hold check-in: OrbView, OrbHoldController, OrbTiming, ring, burst, active and sealed orb
  Glyph/      DailySeed (deterministic daily theme), GlyphModel, GlyphView (Canvas)
  Sound/      SoundEngine: synthesized build-up tone and pop (AVAudioEngine, no assets)
  Reminders/  ReminderCenter (@MainActor @Observable: local notifications and badge), ReminderOfferSheet
  Info.plist  Explicit; CKSharingSupported, NSCameraUsageDescription, NSMicrophoneUsageDescription (PHPicker needs no library permission). Vow.entitlements pins iCloud.app.dabora.vow. Assets.xcassets holds one 1024 px AppIcon.
VowTests/     XCTest unit tests for Domain (incl. Review), Design/Formatters, Store/Overview, Records, and Chat's feed and wording (ChatFeed, ChatText), hosted in Vow.app
Config/       Vow.xcconfig (bundle ID app.dabora.vow, team), which #include?s the git-ignored Local.xcconfig
project.yml               XcodeGen spec
scripts/gen_xcodeproj.py  Stdlib-Python generator for Vow.xcodeproj. Mirrors project.yml.
.github/workflows/ios.yml CI on macOS 15 with Xcode 16
```

---

## 4. Architecture and data flow

```
CloudKit zone ──CloudService/Records──▶ GroupSnapshot ──AppStore (cache, merge, optimistic writes)──▶
  Settlement.summarize(snapshot, viewerID:, now:) ──▶ GroupSummary ──▶ Digest, EndDate, StreakEvents, StreakCalendar, Overview, ReminderPlan ──▶ Views
  Review.tally / tallies / proofDay(snapshot, now:) ──▶ ClaimTally per (subject, day) ──▶ Chat, Home's foot and meta line, Activity, sheets
Post assets ──CloudService.fetchAsset──▶ MediaCache (Caches/vow-media) ──▶ PostMediaView, MediaViewer
```

Settlement reaches every verdict through `Review.verdict`, so the two paths always agree.

**Layering**

- **Domain is pure and deterministic.**
  - It is made of caseless `enum` namespaces and value-type structs.
  - It has no error types: it returns nil or false.
  - Put new rules here, with tests.
- **Cloud does I/O only.**
  - `CloudService.shared` is a `final class: @unchecked Sendable` with async/await. It is not an actor.
  - It creates the container lazily, so unit tests never touch CloudKit.
  - The zone fetch passes `desiredKeys` (`Records.snapshotKeys`), so it never downloads a post's photo, video or thumbnail. `fetchAsset` gets one asset at a time; `savePost` uploads through a `CKModifyRecordsOperation` whose progress arrives on CloudKit's queue.
- **Media does files.**
  - `MediaPrep` turns a picked or captured photo or video into a `MediaDraft` in `Caches/vow-outbox`: photos at most 1,600 px on the long edge (JPEG 0.75); videos cut to their first `MediaPrep.videoLimit` (20 s, also the camera's limit and the proof sheet's note) and exported as MP4 at 960×540, falling back to medium quality; a thumbnail at most 480 px on the long edge. The budget is tight because every member's media lands in the owner's iCloud storage.
  - `MediaCache.shared` (`@MainActor @Observable`) keeps post assets under `Caches/vow-media/<zone>/`, downloads each once (concurrent requests share the download) and `adopt`s your own draft by copying it (an APFS clone, never a move), so your upload shows at once. "Reset local data" and an iCloud account change call `clearAll()`; a group you leave or delete, or that a refresh finds gone, takes its folder with it (`removeGroup`).
  - The shared `AVAudioSession` belongs to `SoundEngine` (ambient, so the orb obeys the ringer switch), with one exception: while `MediaViewer` shows a video it switches to `.playback` (`.moviePlayback`, mixing with others), so the clip is heard in silent mode, and on close it puts back the category, mode and options it captured. Photos leave the session alone.
- **AppStore owns group and app state.** `ReminderCenter.shared` owns reminder state.
  - AppStore is `@MainActor @Observable final class`. State is `private(set)`. Bookkeeping fields are `@ObservationIgnored`. The sends live in `AppStore.swift` beside the private state they write; `AppStore+Chat` holds read-only helpers only.
  - **Offline first:** with a cached userID and cached snapshots, it starts in `phase = .ready`.
  - **Optimistic writes:** check-ins, excuses, votes and posts go in pending (`serverDate == nil`) and are saved; then the server copy is swapped in or the write rolls back (a vote back to the one it replaced). In-flight sets (`inFlightCheckIns`, `inFlightExcuses`, `inFlightVotes`, `inFlightPosts`) keep them through refreshes.
    - A failed post isn't rolled back. It stays in the chat, unsent, in `failedPosts` (a proof keeps its draft in `failedDrafts`) until `retryPost` or `discardPost`. It is never cached, and it is dropped (with its draft) once a fetch shows it saved, its group has gone or a test reset leaves it in an old epoch. A proof's upload progress is `uploads[postID]` (0…1).
    - `vote` ignores a second tap on a claim while the first saves, because two saves of one record could land out of order. In a real group it also refuses to change a vote already cast in voting's last half hour (`Review.canChangeVote`: `voteChangeMargin` before `Review.closesAt`), since a change the server stamps after the close would take the vote it replaced out of every tally; a first vote goes in until the close. `setVoteRule` (owner only) refreshes first, is ignored while a rule change or a test day is saving or once the vow has finished, and isn't optimistic.
    - `sendProof` dates the post with `Review.proofDay` and refuses (false, no toast) without one. It owns the draft from the call on: sent, refused or discarded, the store deletes its outbox files. The store empties `MediaPrep.outbox` at launch, because drafts live only in memory.
    - After your own send (message, proof, retry, excuse) the store refreshes that group, so replies show before the next poll.
    - `canExcuse` (`AppStore+Chat`) is the one "can today be excused?" check: `sendExcuse` guards with it, the excuse sheet closes itself once it fails, and Chat's "+" card disables its row with `excuseBlock`'s reason. It and `checkIn` scan today's records directly (`AppStore.hasCheckIn`, `hasExcuse`), not with a Settlement pass.
  - **Test days:** `advanceTestDay` and `resetTestGroup` return early while either is running for that group (`testDayInFlight`), so a Next day can't save the old epoch back over a reset. The ignored tap is silent.
  - `persist()` runs after mutations and strips every pending record (check-ins, excuses, votes and posts).
  - `refreshAll()` fetches snapshots one at a time. It diffs against the keys it had at the start, so groups created, joined or removed during a refresh behave correctly. `merged()` keeps confirmed and in-flight check-ins, excuses and posts (indexed by identity) and your failed posts; your in-flight vote wins over the fetched copy, and a confirmed one only when its server date is newer.
  - **A fetch that brings nothing new changes nothing:** `refresh`, `refreshAll` and `acceptShare` leave `snapshots` and the cache untouched (`sameContent` compares without `fetchedAt`), so a 15 s Chat poll that finds nothing re-renders nothing.
  - **There are two error paths:**
    - Create, join and accept go through `fail()`, which sets `lastError` (shown inside `NewGroupSheet` and `JoinLinkSheet`) and `toast`.
    - Everything else sets `toast` directly: `CloudErrors.message(error)`, or a fixed "Couldn't check in. Try again.", "Couldn't send your excuse. Try again.", "Couldn't vote. Try again." or "Couldn't change the voting rule. Try again.". A failed post raises no toast: it shows "Not sent" in place.
    - When a check-in, excuse, vote or post fails with `.quotaExceeded` and you aren't the owner, the toast reads "The group owner's iCloud storage is full." (`ownerStorageFull`). It is the one case where a failed post toasts too.
    - Network errors are suppressed when a cache exists.
  - **Settlement is not cheap.** Every `summary(for:)` or `summaries(now:)` call runs a full Settlement pass. Compute once per render and pass the result down. The shell memoizes `summaries` per minute (`SummaryMemo`) for the top bar, sidebar, tab bar and reminder sync; each page runs one `summary(for:)` per body for its group. An upload's progress (`uploads`) is read only by small views of its own, Home's foot's `SendingProof` and Chat's `PostMediaView`, so its ticks never re-run a page. Chat never runs Settlement: its feed is one `Review.tallies` pass, memoized per snapshot, minute and range (`ChatFeedMemo`). `hasUnseenChat` is one pass over the group's arrays, so the tab bar may ask on every render.
- **Views use the environment for shared objects.**
  - They get `@Environment(AppStore.self)` and `@Environment(ReminderCenter.self)`, injected in `VowApp` and again by the shell's `sheetContent` for sheets and covers. No view reads the `Presenter`: the camera and library pickers hand their draft to closures (`onPicked`, `onLibrary`) that the shell wires.
  - Child views take plain values and closures (for example the `StageActions`, `ChatActions` and `GroupActions` structs), with explicit `init`s.
  - Never use `ObservableObject`, `@EnvironmentObject` or `@Bindable`.
- **Unit tests are hosted in the app.** Any launch-time side effect must return early when `AppStore.isRunningUnitTests` is true.

**Screens**

- `RootView` picks one of: onboarding (no profile), `LaunchScreen`, `ProblemScreen` (no account, or failed with no cache), or `MainView`. It also owns the toast and `roomDimmed`, and gets `toastBlocked` and `topBarHeight` from the shell.
- `MainView` is the **shell**. It has **no `NavigationStack` and no push**:
  - A pinned `TopBar`: ≡ (opens the sidebar), the selected group's name, and the iCloud retry banner under it.
  - The selected group's page for the current `MainTab`: Home (`StageScreen`), Chat (`ChatPage`), `StreakPage`, `ActivityPage`, `GroupPage`. Pages are swapped instantly, not kept alive (the orb and its timers never run off screen). Re-tapping the selected tab bumps `topToken` (scroll to top; Chat scrolls to the latest). Switching group resets the tab to Home. Chat's unsent drafts live in the shell (`chatDrafts`, per group, memory only).
  - A pinned custom `VowTabBar`, shown whenever a group's page is (not a `TabView`: it dims with the room and avoids iOS 26's floating tab bar). Its items are centred in the bar you see (`Gap.tabBar` plus the home-indicator inset, `bottomInset` from the shell's GeometryReader), not in its top 49 pt, and each is tappable over that whole height. No groups: `EmptyStage` and no tab bar; first sync of a fresh install: a spinner.
    - The Streak flame lights only while your check-in stands (`Digest.checkInStands`), from the social beat on.
    - **The chat dot** is the app's one unread-style mark: a 7 pt `Ink.text` dot on an 11 pt `Ink.bg` rim at the Chat symbol's corner, not hit-testable, VoiceOver value "New messages". It shows when `store.hasUnseenChat(id)` and Chat isn't the page. That counts others' posts, others' excuses and votes others cast on your claims, newer than `chatSeenAt[zone]`: the newest such server date when Chat was last shown (`markChatSeen`, saved under `vow.chatSeen`; before a first visit, the last two days count). Bare check-ins never light it.
  - A `Sidebar` overlay: Add group (a custom menu: New group, Join with a link), your groups with today's status, Settings, and you with your balance. It opens from ≡ or a swipe from the 16 pt leading edge zone and closes on the scrim, a pick, a horizontal drag or VoiceOver escape. Opening it resigns the first responder, so Chat's keyboard never sits over its footer. An excused row shows a dashed sphere and your (paused) streak; an overruled one an unlit sphere and "Overruled", like "Finished".
    - It is always mounted. One state drives the panel's offset and the scrim's opacity (`panelExtent`/`panelOffset`/`panelProgress`); under Reduce Motion the panel stays put and fades. Nothing is inserted or removed mid-slide, so every row moves with the panel and a reversed slide or released drag carries on from where the panel is. Don't reintroduce `if` blocks or `.transition` for the panel or scrim.
    - Closed, the panel is parked past its shadow (`Sidebar.shadowReach`). Touches follow `sidebarShown`; VoiceOver visibility and `.isModal` follow `isOpen`. Each appearance starts with the Add menu closed (reset when `isShown` turns true), opening moves VoiceOver focus to Add group, and the group list keeps its scroll position.
    - Its footer dips into the home-indicator inset so the profile row's centre is level with the tab bar's items (`Sidebar.footerBottom`; `Gap.s` above the edge with no inset).
    - Its drags are `@GestureState`, so a drag the system cancels (a sheet, an alert, Control Center) resets itself; never hold a live drag in plain `@State`. Every close path works whenever the panel is visible, mid-drag included.
    - ≡ and the edge zone ignore input while the room is dimmed or the presenter isn't idle (a sheet must never rise over a reopened panel). An edge drag counts as busy for `.automatic` presentations.
    - A reminder tap waits while a sheet that holds unsaved work is up or queued next (`MainSheet.holdsUnsavedWork`: New group, Excuse, camera, library, Proof), not only while it saves: closing it would discard what you typed, picked or shot. `Presenter.queued` covers the gap in a chain such as camera → Proof, while `sheet` is briefly nil.
  - The refresh of the shown group (`.task(id: RefreshKey)`: every 60 s, every 15 s while Chat is shown; only while its snapshot exists) lives in the shell, so it runs on every tab. Streak, Activity and Group also have pull to refresh. Home doesn't move at all when it fits (`.scrollBounceBehavior(.basedOnSize)`, no `.refreshable`) and scrolls only when it doesn't (accessibility sizes, a test bar on a small screen). `EmptyStage` keeps pull to refresh: with no group there is no timed refresh, so it is the only way to sync there.
  - **Chat** (`Features/Chat`) has no pull to refresh (its top is history). It refreshes on appear and after your votes, and the store refreshes after your other sends.
    - `ChatFeed.build` (pure, tested) turns a snapshot into rows: day headers, messages (a run is one author's within 5 min), one claim card per check-in or excuse with its proof inside, and a pointer ("Maya added proof to yesterday's check-in") where proof came after other rows. Until Earlier is tapped it shows the week up to the newest item (`ChatFeed.recentDays`: that item's day and the six before it, today at the latest), so a quiet chat or a finished vow never opens on Earlier alone. The rule's preamble shows while two or more take part today in a vow that hasn't finished (`hasVoters`). A check-in's card stays compact until proof or a vote arrives.
    - `ChatPage` presents nothing itself: it calls `ChatActions`. The shell passes `covered` (the sidebar is showing), which closes the "+" card. The "+" card (`ChatPlusMenu`, a custom menu) lists Take photo or video (hidden without a camera), Choose from library and Excuse for today, each disabled with its reason in place.
    - The feed and the composer sit in a `VStack`, not `.safeAreaInset`, so the 1 pt bottom sentinel's `atBottom` is exact with the keyboard up; the fade, the jump button and the "+" card are overlays of the bar. It opens at the bottom once per visit (`hasOpened`, because closing a cover sends the page `onAppear` again): `OpensAtBottom` applies `.defaultScrollAnchor(.bottom, for: .initialOffset)` on iOS 18+ and the plain `.defaultScrollAnchor(.bottom)` only on iOS 17 (where it also anchors size changes), then one `Task.yield()` and a `scrollTo`. It follows new rows only while at the bottom or for your own pending send, and keeps the old first row in place after Earlier.
    - The shell ignores the keyboard (`.ignoresSafeArea(.keyboard, edges: .bottom)`), so a sheet's keyboard never moves it. Chat lifts its own composer from the keyboard notifications, only while its own field is focused. The composer's "+" and the "+" card start at x = 16, clear of the shell's edge zone.
    - It marks the chat seen on appear, on every snapshot change and on disappear, so the dot never lights for what you are reading.
    - Non-members get a read-only feed and a "Write your vow to join" bar (none once the vow has finished). A finished vow's chat stays open to members.
- **Sheets, covers and dialogs:** the shell owns `Presenter` (`Features/Main/Presenter.swift`, which also declares `MainSheet`, `MainDialog` and `PresentSource`). Its one `.sheet(item: sheetBinding)`, one `.fullScreenCover(item: coverBinding)` and one `.confirmationDialog` are the only ones in the main experience.
  - `MainSheet.isCover` (the camera, the media viewer) picks the cover. A cover shares the sheet's slot and phase machine (the `onAppear`/`onDisappear` proof, the deadlines, the settle), and a nil written through one binding never clears the other kind, so a late write from a departed sheet can't take down the cover that followed it.
  - Pages and chrome call closures that the shell wires to `presenter.present(_:from: .screen)` or `confirm(_:from: .screen)`. `.screen` means a real tap on the main screen.
  - Sheet and cover bodies close with `dismiss()` and chain with `from: .sheet`: Create → Invite, your member sheet → Edit vow, the proof chooser → camera or library, camera → library, camera or library → Proof (`MainView.proofPicked`). They may host their own dialog, hung off the control that asks for it (Settings → Reset local data, Excuse → "Send excuse?").
  - Home's Add proof asks `MainDialog.proofSource` ("Add proof": Take photo or video, Choose from library; no message, so `dialogMessage` returns nil), or presents the library at once on a device with no camera. Chat's "+" card lists both sources itself.
  - The vow prompt and the reminder offer use `.automatic`. They wait while the shell is busy (`setBusy`: hold, cascade, open sidebar), and `isStillWanted` re-checks them just before they show. `didClose(.vow)` clears `pendingVowPrompt`. A reminder tap calls `dismissAll()`. The store and timers never touch presentation.
  - It can't wedge: presenting and dismissing end on a 1 s deadline even with no callback (a sheet whose content never appears is cleared and retried once), the latest tap wins and closes what is up, and nothing starts within a short settle after a dismissal or during `delay(for:)` (the shell's fade-in, every sidebar slide).
  - **Rules:** no SwiftUI `Menu` leads to a sheet or dialog (build a custom menu like `AddGroupMenu` or `ChatPlusMenu`; `from: .menu` exists for an unavoidable one and has no callers). Sheet and cover bodies never render `EmptyView`: the content's `onAppear` is the presenter's proof that a sheet is up. Covers only at the shell: no `fullScreenCover` in pages or sheet bodies. No `presentationBackgroundInteraction(.enabled)` on shell sheets.
  - Check: `grep -rn "\.sheet(\|confirmationDialog(\|\.alert(\|fullScreenCover(\|\.popover(" Vow/Features` lists only `MainView`, `Presenter` (its own `.sheet(` case and doc comments) and the dialogs that `SettingsSheet` and `ExcuseSheet` host.
  - Use `.vowSheet([...])` for detents and `SheetScaffold` for layout; covers take no detents. A sheet without a footer uses SheetScaffold's footer-less init; never pass `footer: { EmptyView() }`, which is still a bottom inset with an opaque backing (the prime suspect for the blank Settings sheet, see Known issues).
- **Toast:** RootView holds a toast while the room is dimmed. While a sheet, a cover, a dialog or the sidebar is up (`toastBlocked`, from the shell), it waits at most `Anim.toastWaitNanos` (1.5 s) from when it was raised, then it is dropped. It sits below the measured top bar and takes no touches.
- **Dimming during a hold:** everything except the vow and the orb dims, the top bar's and tab bar's contents included (their backings stay). New stage UI and chrome must apply `.roomDim(_:)` (in `Styles.swift`).
- **Share invites:** `SceneDelegate` → `ShareInbox.deliver` (buffered) → the handler that `AppStore.installShareHandler` installs after `bootstrap()` has an account → `acceptShare` → `pendingVowPrompt` (observed with `initial: true`): the shell selects that group's Home, then presents its vow sheet from `.automatic`. For a finished group it only selects it. Already a member: `acceptCount` → that group's Home.

---

## 5. Invariants: do not break

All of these are verified in code. If a change needs to break one, raise it with the user first.

**Days and time**

- **Day index:**
  - `DayClock.dayIndex` counts calendar days in the group's `timeZoneID`, measured between noon anchors. It does not use start of day, because some zones skip midnight when DST starts.
  - Day 0 is the day the group was created. The index is clamped to 0 or more.
- **Grace period:**
  - `DayClock.graceSeconds = 600`.
  - A check-in or excuse is valid if its server `creationDate` falls on the same group day, or is less than 600 s into the next day. The boundary is exclusive: 00:09:59 is valid and 00:10:00 is not.
  - Test groups skip this check.
  - Logic: `Settlement.isOnTime` (behind both `Settlement.isValid`s), through `DayClock.lands`, which the vote window reuses.
- **Clocks:** the **device** chooses `day` (and a vote's `castDay`), and the **server** timestamp validates it: `creationDate` for check-ins, excuses and posts, `modificationDate` for votes. Test groups judge votes by `castDay`, because their days move by hand. Don't move validation onto the device clock.
- **End date:**
  - `GroupInfo.endDay` (optional, the last stored property) is the index of the vow's final day, inclusive, in the group's day clock (test groups count `testDay`). nil means no end, the default.
  - It is set only at creation (`CloudService.createGroup(…endDate:…)`: at least 1, so the earliest end is tomorrow, and at most `EndDate.maxEndDay`) and never changes.
  - **Stop rule** (`Settlement.isOnTime`): a check-in or excuse with `day > endDay` is invalid. Once the clock passes `endDay`, the vow is finished: days 0…endDay settle exactly as they would without an end, and nothing settles after them.
  - A finished summary has `isFinished == true`, no open day (nobody is `checkedInToday` or `excusedToday`) and `currentDay == endDay + 1` for good. Code that means "today" or "yesterday" for a finished vow must use `DayClock.currentDay` or skip it (`ActivityPage.titleDay`, `Overview.yesterdayChange`, `CalendarSpan`'s forward limit).
  - A finished vow is never open (`Digest.isOpen`) and never reminded (`reminderGroups` skips it, and `ReminderGroup.endsAt` drops reminders after the final day). `AppStore.checkIn`, `setVow` and `sendExcuse` return early on it. Its final day still takes votes and proof during the day after it (`Review.isOpen`, `Review.proofDay`), and its chat stays open to members.
  - Helpers: `EndDate` (`isFinished`, `dayCounter`, `finalDate`, `endsAt`), `CalendarSpan` (the streak calendar's months, from group day 0's month through max(the clock's month + `StreakCalendar.monthsAhead` (12), the final day's month), capped at `StreakCalendar.maxMonths`; `count`, `home`, `month(at:)`, built lazily) and `StreakCalendar` (`streakStartDay`/`streakStartDate`). `CalendarDay` carries its state, `isFinal`, `joinsPrevious`/`joinsNext` (a kept neighbour in the same week row) and `groupDay`.
  - Older builds ignore `endDay` (see Known issues, mixed builds).

**Settlement**

- **It must be deterministic on every device:**
  - Deduplicate members by userID; the first one wins.
  - Sort by lowercased `displayName`, then userID.
  - Keep ledger ids stable: `d<day>-<kind>-<userID>`, or `d<day>-split` and `d<day>-carry`.
  - Cap the ledger with `ledgerCap = 120`.
  - Nets always sum to −pot.
- **Stake is immutable after a group is created,** because settlement applies it to every past day. Adding a "change stake" feature needs a settlement redesign.
- **Epochs:**
  - Resetting a test group bumps `epoch` and sets `testDay = 0`.
  - **Check-in, excuse and post records are never deleted.** `AppStore.merged` depends on this. A vote record is overwritten when its voter changes their mind, never deleted.
  - Check-ins, excuses and votes from another epoch are ignored, and Chat shows only the current epoch's posts.
- **Membership:**
  - A member participates on a day when `effectiveJoinedDay ≤ day < leftDay`.
  - Leaving sets `leftDay = currentDay`, so a member who leaves isn't charged for today.
  - The owner can't leave; they delete the group instead.
- **Streaks:**
  - A streak is the trailing run of kept closed days, plus 1 if today's check-in stands. Excused days are transparent: they neither break nor extend a run (the trailing streak, the best, `StreakEvents.previousRecord`, `StreakCalendar.streakStartDay`). Only a closed `.missed` day breaks a streak; an open, excused or overruled today doesn't.
  - Milestones are `[3,7,14,30,50,100,150,200,250,300,365]`, then every 100 after that.
- **Cycle:** a cycle is 30 days. It is **display only, and the UI no longer shows it**: no "Cycle" and no "Day N of 30". `GroupSummary.cycle`/`dayInCycle` only seed the orb's daily theme. The pot and nets never reset per cycle. "Day x of y" appears only with an end date (`EndDate.dayCounter`).
  - The 30 is hard-coded in four places: `Settlement.swift` (`currentDay / 30`), `Overview.theme(day:)`, `Glyph/DailySeed.swift` (`glyphNumber`) and `CycleChain.length` (unused).
  - The daily theme is seeded from (cycle, day in cycle), so changing the length changes every day's colours.

**Review: claims, votes and verdicts** (`Domain/Review.swift`)

- **Claims:** a participating member has at most one claim per day: a valid check-in, else a valid excuse (a race that makes both keeps the check-in). An excuse is valid on exactly a check-in's terms.
- **Voters** on (subject, day) are every other member taking part that day, deduplicated. There is one vote per (voter, subject, day); voting again overwrites it. You can't vote on your own claim.
- **A vote counts** when it is in the group's epoch, by an eligible voter, and in the window: pending; in a test group, `castDay ≤ day + 1`; in a real group, served by the end of day + 1 plus the grace period. `CloudService.saveVote` doesn't re-save an unchanged verdict, so a repeat can't move its `modificationDate` out of the window.
- **Verdict:** a claim is overruled when it has voters and its "Doesn't count" votes reach `VoteRule.needed(voters:)` under the rule for its day: `majority` n / 2 + 1, `twoThirds` ⌈2n/3⌉, `everyone` n. With no votes, or no voters (a solo group), it stands. `Review.excuseStandsByDefault` (true) is the one switch that would make excuses need "Counts" votes instead.
  - **It is computed only in `Review.verdict`.** Settlement, `tally` and `tallies` all call it, and Settlement indexes the votes once per pass (`Review.Ballots`). Never write the rule a second time.
  - Day d's outcome is provisional until voting on it closes at the end of day d + 1 (`Review.isOpen`).
- **Rule log:** `GroupInfo.voteRules` (`[VoteRuleChange]?`, the last stored property). The rule for day d is the latest change with `fromDay ≤ d` (a later entry wins a tie), else `.majority`. `Review.changing` adds a change from tomorrow (`currentDay + 1`; a test group's `testDay + 1`), drops any planned from then on, adds nothing when tomorrow already has that rule, and keeps the last 64 (`Review.ruleLogCap`). A day already open to votes is never judged under a new rule.
- **Outcomes** of a closed day: a standing check-in is `.kept`; a standing excuse is `.excused` (it sits out: no stake lost, no share of the pot); no claim, or an overruled one, is `.missed` (stake into the pot). A day where everyone is excused moves nothing: no carry line, and the pot carries untouched. Ledger ids follow the same pattern (`d<day>-excused-<userID>`).
- **Today** (`MemberStanding`): `checkedInToday` means a valid check-in exists, overruled or not (the orb's seal depends on it); `excusedToday` means a valid excuse and no check-in; `todayOverruled` covers either claim. "Kept" and "excused" mean `Digest.checkInStands` and `Digest.excuseStands`. Home's strip, the Group page and the member sheet all read a member's today through `MemberDay.of`, and "{kept} of {n} kept today" is `KeptNote`, counted from those same `MemberDay`s (n leaves out the excused), so a sphere and its count never disagree. `missedYesterday` reads the verdict.
- **An excuse closes today's orb for good.** It can't be withdrawn, or sent after a check-in: `checkIn` returns early on a valid excuse today, and `sendExcuse` on a check-in or excuse today, a finished vow or a non-member.
- **Proof** attaches to `Review.proofDay`: today once you have a claim (check-in or excuse), else yesterday's claim while it is open to votes, overruled or not; nil otherwise, or when you don't take part that day. A proof post's `day` is that claim's day.

**CloudKit records**

- **These names are part of the protocol.** Never rename them:
  - Record types `Group`, `Member`, `CheckIn`, `Excuse`, `Vote` and `Post`, and their field names (`Records.swift`).
  - Zone `group-<UUID>`.
  - Records `group`, `member-<userID>`, `checkin-<epoch>-<userID>-<day>`, `excuse-<epoch>-<userID>-<day>` and `vote-<epoch>-<voterID>-<subjectID>-<day>`. These deterministic names make saves idempotent. A post is `post-<UUID>`, named on the sending device, so an optimistic post and its saved copy share an id and a retry finds the first save.
- **Trusted time:** a check-in's, excuse's or post's server `creationDate`; a vote's `modificationDate`, because a changed vote is judged by when it changed.
- **Field encoding:**
  - Ints and bools are stored as `Int64`.
  - `leftDay` is always written, with `-1` meaning active.
  - Decoding is lenient and falls back to defaults. A vote without `counts` reads as "Counts" (it can't overrule) and one without `castDay` as the day voted on; an unknown `mediaKind` reads as text; `aspect` is clamped to 0.1…10; text is cut to `Records.excuseTextLimit` (280) or `Records.postTextLimit` (2,000) on read and write. Those two limits are the only ones: the sheets and the composer clamp to them.
  - `Group.endDay` is optional: written only when set, absent means no end, clamped on read to 0…`EndDate.maxEndDay`. `Records.apply` never clears it, because a `GroupInfo` without it can only be stale (an older cache or build).
  - `Group.voteRules` is a flat `Int64` list `[fromDay, rule, …]`; absent means "More than half" from day 0. **Only `CloudService.saveVoteRules` writes it**: it fetches the Group record and sets that one key (`.changedKeys`). `Records.apply(GroupInfo)` never writes it (RecordsTests pins this), so a stale `GroupInfo` can't roll the rule back.
  - A post's photo or video and its JPEG thumbnail are the `CKAsset` fields `media` and `thumb`.
  - **`Records.snapshotKeys` must list every non-asset field of every type.** The zone fetch passes it as `desiredKeys`, so a field missing from it silently reads as its default. RecordsTests checks it against every `apply`.

**Local state**

- **Cache compatibility:**
  - `SnapshotCache` decodes with `try?` and has no schema version. A new required field on a Codable domain model silently **discards every user's cache**.
  - Synthesized `Decodable` ignores property default values. A new field must be `Optional`, or the type needs a custom `init(from:)`.
  - `GroupSnapshot` has one, in an extension so the memberwise init survives: `excuses`, `votes` and `posts` read with `decodeIfPresent ?? []`. A new stored property on it must be read there too.
- **Preferences:** every key is `vow.*`. Remove each new key in `Preferences.clearAll()` too, which "Reset local data" uses. `vow.chatSeen` maps each zone to Chat's seen date.
- **Files:** drafts live in `Caches/vow-outbox` (emptied at launch, and a sent or discarded draft's files are deleted at once), post media in `Caches/vow-media`. `failedPosts` and drafts are memory only.

**Text**

- **Ledger text:**
  - `Features/Activity/LedgerFormat` parses the English ledger strings that Domain produces ("Day N · … · −2 pts").
  - SettlementTests pin those strings. Round 5 added "Day N · Your check-in was overruled · −2 pts" (`.missed`), "Day N · Maya's check-in was overruled · −2 pts" (`.forfeit`), the same two for an excuse, and "Day N · You were excused" / "Day N · Maya was excused" (`.excused`, no amount). The plain kept and missed strings didn't change.
  - `LedgerFormat.rank` takes the line: your "You were excused" ranks with your own day (by that exact string), others' with the forfeits.
  - Change Domain, LedgerFormat and the tests together.
- **Glyph:** `Glyph/DailySeed` uses an exact port of JS `mulberry32` and FNV-1a. It must stay bit-for-bit deterministic.

**Orb and check-in**

- **Orb timing:**
  - `OrbTiming.hold = 1.4` is the single source for the ring, completion and the build-up tone.
  - `OrbBridge` keeps the old names alive for `Orb/` only. `Motion.dimGateNanos` must equal `Anim.dimGateNanos`.
  - The orb is remounted when the day changes or the group resets: `.id(orbKey)` with the key `zoneName-epoch-currentDay`.
- **Check-in reward cascade** (`StageScreen`, in this order):
  1. Settle: the caption agrees with the orb, and Home's foot lets "Can't today?" go with it.
  2. Streak +1 with a flare.
  3. The social beat: your strip sphere (and the kept count) and the **Streak tab's flame** light together (`didLight`). Until then the shell's `holdingLightID` keeps the vow "open" everywhere (sidebar, tab bar).
  4. Milestone or new best, with embers and a success haptic.
  5. The **≡ glyph pulses once** if another vow is still open (`didKeep`).
  6. One-time reminder offer, only when no other vow is open, and never for a test group (`offerReminder`). At the same beat (the end of the cascade's task, `Anim.offerNanos`), the foot shows its proof line (Add proof, or the proof's state).
- **Layout during the cascade:** views show *held* values until their beat. Nothing changes height during check-in.
  - Home's foot (`StageFoot`) keeps its 44 pt throughout and stays empty while `cascadeRunning`. The caption's check-in phrasings (open, hint, kept, overruled) are all mounted in one slot. The meta line's "Yesterday was overruled" is held while the room is dimmed or the cascade runs (`heldOverrule`).
  - An overruled check-in keeps the orb sealed but desaturated (`.saturation(0)`, opacity 0.7, applied by `StageCenter` inside the `.id(orbKey)`; nothing in `Orb/` changes). An excuse swaps the orb for a 150 pt `.excused` Sphere in the same 220 pt slot, behind the excuse sheet and never mid-hold; the orb's own `onDisappear` reports focus false, so the room can't stay dimmed.
- **Keep the orb on screen until the seal.** `OrbHoldController.teardown()` drops a completed seal that hasn't reached `onSealed` (+0.9 s) when the orb leaves the screen. So:
  - Tabs, ≡, the edge swipe, Home's streak button and the foot's "Can't today?" are ignored while the room is dimmed (from the 200 ms gate through the seal); "Can't today?" is also ignored once sealed.
  - Programmatic group or page changes (reselect after the background, an accepted invite, the vow prompt, a reminder tap) wait for `stageBusy` (dimmed, or `holdingLightID` set: through the social beat).
  - Leaving Home after the seal ends the cascade (`resetChoreography`): everything shows the store's values and the tab flame lights, and the keep's ≡ pulse and reminder offer that hadn't fired yet are delivered once (`deliverPendingKeep`). A reverted check-in delivers nothing.

---

## 6. Design system and product principles

**Visual direction: "quiet room, bright orb"**

- Chrome is neutral. The orb is the only bright, colourful thing.
- **Colour always means something:** flame = streak, gain/loss = points, the day's orb colours = kept today. Votes are neutral: never red or green, because a vote isn't points.

**Use the tokens in `Design/Tokens.swift`:**

| Token | What it covers |
|---|---|
| `Ink` | Colour roles: `bg`, `card`, `text`/`text2`/`text3`, `flame*`, `gain`, `loss`, `scrim` (behind the sidebar and Chat's "+" card), `flameEdge` (the milestone tag's border), `onFlame` (dark numerals on a kept calendar day), `missedDay` (the grey disc of a missed calendar day, or of today overruled), `chip` (your chat bubbles, your chosen vote), … |
| `Fonts` | Dynamic Type styles; SF Rounded for numbers only. `tabLabel` is a fixed 10 pt, like the system tab bar |
| `Gap` | 4-pt grid, plus `gutter`, `hit` 44, `orbSlot` 220, `tabBar` 49, `sidebarMax` 320 (the panel is 82 % of the width, at most this) |
| `Corner` | Always `.continuous`. `bubble` (18) is for chat bubbles and the composer's field |
| `Anim` | Named curves (incl. `sidebarIn`/`sidebarOut`, and `sidebarFade` under Reduce Motion) and the beat table in nanoseconds (incl. `toastWaitNanos`) |
| `StageMetrics` | Layout is compact when the safe-area height is under 700. Compact keeps the 44 pt milestone gap. `footTop` (12, compact 4) is the gap between the strip and Home's foot |

- **Colours** always come from `Ink`. The only exceptions are white/black opacity strokes and sheens, the black veils (0.35 to 0.55) and badges over photos and videos, and the media viewer, which is black with white chrome over photographs.
- **Corners** come from `Corner`, and **text styles** from `Fonts`.
- **Spacing:** use `Gap` for new spacing. Small literal paddings exist in the code; don't add more.

**Reuse the existing components:**

- `PillButton`, `PressStyle`, `cardSurface()`
- `VowTextField`, `FormGroup`, `SwitchRow`
- `SheetScaffold`, `ToastBanner`, `InlineBanner`, `Tag`
- `Sphere`, which is the one status shape: lit, open, unlit or excused (an unlit body with a dashed `Ink.text3` ring). Dashed means only excused, so the Group page's Invite seat is a solid `Ink.field` disc. An overruled claim is plain unlit.

**Product rules**

- **Hold the orb with zero taps.** The app opens on the Home tab of your most urgent open vow.
- **Colour only your own net.** Friends' nets stay `text2`, and the total balance is neutral. Of the totals, only your "Yesterday" change is coloured: the sidebar's reveal and the Profile sheet's stat.
- **The total balance lives with you:** the profile row at the bottom of the sidebar and the Profile sheet. The once-a-day "Yesterday" reveal plays when the sidebar opens (after a sync, with nothing up and the room lit). Your name is edited in the Profile sheet; Settings keeps reminder, testing and about.
- **≡ stays bare** except a flame dot while another of your vows is in its last 4 h (`Overview.menuDot`). No unread-style badges, with one exception: Chat's small white dot on its tab, never a count, never red, never on ≡ or in the sidebar.
- **Test controls** (Next day, Reset) live only on Home's test bar. A finished test vow keeps the bar, with Next day disabled.
- **End dates are optional.** A group has no end unless New group's "End date" switch sets a "Last day" (tomorrow to a year out; 30 days by default). With one, Home shows "Day x of y" and the Streak calendar flags the final day. Afterwards Home shows `FinishedStage` and the sidebar says "Finished".
- **Proof follows the orb, quietly.** Home's foot (`StageFoot`, a reserved 44 pt line under the strip) reads "Can't today?" before you check in. Once the cascade ends it offers **Add proof** (a text button, not a pill), then "Proof sent ›" (opens Chat), and Add proof again whenever your check-in stands overruled. Proof is never asked for in the moment, badged or reminded, and never prompted for an excuse. A photo in Chat is always proof: there are no general photo messages.
- **Excuses** are typed (280 characters at most), confirmed once ("Send excuse?": the orb closes for today) and never withdrawn. Home then swaps the orb for a dashed Sphere, quotes the excuse in the milestone gap and keeps the streak's number (paused). Its caption reads "Excused today", or "Excuse overruled · Voting ends …".
- **Votes** are visible to the group (who voted what, under a card's status row). Non-voters are never named; there is no anonymous voting and no list of who hasn't voted. The controls are neutral, and your choice is outlined, not filled white.
- **The voting rule** is a card on the Group tab ("Overrule with": More than half, Two thirds or Everyone of the others). Only the owner changes it, while the vow runs, through `VoteRuleSheet`; the change applies from tomorrow, and the row says "{Rule} from tomorrow" until then.
- **Streak calendar:** kept days (today included) are `Ink.flameGradient` discs with dark numerals, and a run joins into one capsule per week row, capped at row and month edges. Misses are grey discs. An excused day is a dashed `Ink.text3` ring that never joins a run (the band breaks, the streak doesn't). Today is a ring: dashed while excused, on a grey disc while overruled. ‹ › page from the month the group began to a year past the current month (or the final day's month, if later).
- **Keep it neutral and kind:**
  - No streak freezes, nudges, leaderboards or guilt-trip copy.
  - In today's status, friends show as "Not yet", "Excused today" or "Overruled", never "missed". The ledger does say "Maya missed".
- **One engagement loop:** an optional daily local reminder, only on days a vow is still open (an excuse counts as done). It is offered once, after a real check-in that leaves no other vow open. Nothing notifies you of a message, vote or proof.
- **At risk** means the last 4 hours of a real group's day (`DayWindow.atRiskSeconds`). It shows a flame ring on your open sphere (Home's strip, the sidebar row, the Group page, the calendar's today) and "· 3h left" in Home's caption; for another vow, the ≡ dot.

**Copy conventions**

- Use sentence case.
- End toasts and footers with a period ("Group created."). Buttons have no period.
- Use " · " as a separator, "…" for ellipses and U+2212 "−" for negatives.
- **Points** always read "pts" (`Points.format`), or "1 pt" where `PointsText` makes it singular.
  - In the UI, `PointsText` signs balances unless they are zero.
  - `Points.format(signed:)` prints "+0 pts".
- **Errors** in the create and join sheets read "Couldn't X. " followed by `store.lastError`.
- **Votes and verdicts:**
  - A vote reads "Counts" or "Doesn't count" everywhere (the controls, who voted).
  - "Overruled" is the one word for a claim the group voted down: the card's tag, the sidebar, captions and VoiceOver. A standing excuse is "Excused today".
  - A card's status line has one denominator, "needed": "1 of 3 needed to overrule", "3 said it doesn't count" or "2 say it counts", then the window ("Voting ends tonight", "Voting ends tomorrow night"; a test group's "Voting ends when Day N begins"). Once voting has closed it reads "Closed · 2 said it counts", or just "Closed". `ChatText.status` builds it.
  - There is no success toast for a message, a vote, proof or an excuse: the screen shows each one.

**Haptics:** prefer `.sensoryFeedback`. The orb and `TestDayBar` use UIKit generators.

**Accessibility (required)**

- Support Dynamic Type. Where a layout must cap it, use `dynamicTypeSize(...)` and add `accessibilityShowsLargeContentViewer`.
- Use `isAccessibilitySize` to switch layouts.
- For VoiceOver, give composite elements a label and a value, mark headers with `.isHeader`, and keep decorative spheres hidden.
- Respect Reduce Motion. `OrbBurst` is a known gap.
- There is no localization yet: strings are English literals and plurals are hand-rolled. There are no `#Preview` blocks.

---

## 7. Code style (match it)

Domain, Design and Features follow these conventions most strictly. Cloud, AppStore and Orb are looser; when you edit there, match the file you are in.

- **Explicit types on locals and closure parameters:**
  - `let r: Double = …`
  - `{ (a: MemberInfo, b: MemberInfo) -> Bool in … }`
- **Control flow:**
  - In functions, use an explicit `return`. Computed view properties use an implicit return.
  - Prefer `for … where` loops over long map/filter chains.
  - Write single-line `guard … else { return }`.
- **Namespaces and constants:**
  - Use caseless `enum` namespaces for pure helpers (`DayClock`, `PointsText`, `LedgerFormat`).
  - Declare constants as typed `static let`.
  - Singletons are `static let shared`.
- **Access control:** use the default internal, plus `private` and `private(set)`. Don't use `public` or `fileprivate`.
- **Comments:**
  - No file headers. A file starts with its imports, then usually a `///` doc on the main type.
  - `///` docs are short and explain *why* and edge cases, often with a concrete example ("Day 13 · Maya missed · −2 pts").
  - Inline `//` comments are rare.
  - Write British spelling in comments ("colour").
  - Use `// MARK: - Section`. A few files use `// MARK: X`; prefer the dash.
- **Views:**
  - Split `body` into small `private var`/`func` subviews. Private model structs go at the bottom of the file.
  - Views in `Features/` and `Design/` have an explicit `init`. `Orb/` views use the memberwise init.
  - Time the cascade with `Task.sleep(nanoseconds: Anim.*Nanos)` and `Task.isCancelled` checks. Trigger one-shot animations with Int tokens (`flareToken`).
- **Formatting:**
  - Use digit separators (`1_000_000`).
  - Lines run up to about 130 characters. Align wrapped arguments to the opening paren.
- **Language mode:** Swift 5 with no strict concurrency. Target iOS 17.
- **Tests:**
  - Write `final class XTests: XCTestCase` with `@testable import Vow` and `testCamelCaseDescription` names.
  - Build fixtures with private helpers (`makeGroup`, `member`, `checkIn`).
  - Use epoch-literal dates with a comment giving the local time. Use explicit zone IDs (NY, Tokyo, UTC). Pin the locale for date text (`DayText` takes `locale:`; `DayTextTests` uses `en_US`).
  - Compare doubles with `accuracy: 1e-9`.
  - ⚠️ `SettlementTests.makeGroup` defaults to `isTest: true`. Pass `isTest: false` to test real-group rules such as grace.

---

## 8. Build, test and verify

**Your session most likely runs on Linux with no Swift toolchain:** no `swift`, `xcodebuild`, `xcodegen` or `plutil`. You cannot compile or run tests locally. **CI is the compiler.** So:

- **Proofread Swift by hand.** Check types, optionals, `@MainActor` isolation, missing imports, exhaustive `switch`es and that every symbol you reference exists. Grep for every symbol you rename or remove.
- **After adding, renaming or deleting any `.swift` file in `Vow/` or `VowTests/`, run:**
  - `python3 scripts/gen_xcodeproj.py` to regenerate. Output is deterministic, and the script rejects duplicate Swift basenames.
  - `python3 scripts/gen_xcodeproj.py --check` to validate the committed project. It writes nothing.
- **Keep the generators in sync.** `project.yml` and `scripts/gen_xcodeproj.py` must describe the same project, and nothing checks this automatically. Change both together.
- **Never set `PRODUCT_BUNDLE_IDENTIFIER` or `DEVELOPMENT_TEAM` on the Vow app target.** They come only from `Config/Vow.xcconfig` and `Local.xcconfig`. The VowTests target does set its own bundle ID (`app.dabora.vow.tests`), and that is correct.
- **Validate plists with Python's `plistlib`.**
- **After pushing, check CI** with the GitHub MCP tools (`actions_list`, `get_job_logs`).
- **CI** (`.github/workflows/ios.yml`) runs on every push:
  - **Blocking:** a simulator build, `VowTests` on the newest iPhone simulator, and an unsigned Release archive with icon and display-name checks.
  - **Non-blocking:** the committed project compared with the generator's output, and an XcodeGen build.
- **On a Mac:** run `xcodebuild test -project Vow.xcodeproj -scheme Vow -destination 'platform=iOS Simulator,name=iPhone 16'`.

**Testing scope**

- Tests cover:
  - Domain, including `ReviewTests` (thresholds, the window, eligibility, Settlement agreeing with `tally` and `tallies`, `proofDay`, the rule log, the vote-change margin (`canChangeVote`), a cache from before Chat decoding), `EndDateTests` and `StreakCalendarTests`.
  - `Design/Formatters`, including `DayText` (`DayTextTests`) and `VoteRuleText`.
  - `Store/Overview`: the aggregates in `DigestTests`; `status`, `menuDot` and `theme(day:)` in `VowStatusTests`.
  - `Records`: the Excuse, Vote and Post mapping, `voteRules` and `snapshotKeys` in `RecordsTests`; `endDay` in `EndDateTests`. Both import CloudKit but never touch a container.
  - `Features/Chat`: `ChatFeed` (order, sections, the range (the week up to the newest item, so a quiet chat or a finished vow opens on its last week) and Earlier, pointers, runs, the compact predicate, who may vote and change a vote) in `ChatFeedTests`, and `ChatText` (status lines, headers, pointers, the "+" card's header and excuse reasons, the vote lock) in `ChatTextTests`.
  - `LedgerFormat`'s reading of the review lines (one test in `ReviewTests`).
- These have **no tests**, so be extra careful there:
  - AppStore (merge, optimistic writes, `failedPosts`, `hasUnseenChat` and race logic)
  - CloudService, and Records' Group, Member and CheckIn mapping beyond `endDay`
  - Media: `MediaPrep` and `MediaCache`
  - The shell: `Presenter` (covers, `queued`), `MainView` and the sidebar gestures
  - `ChatPage`'s scrolling and keyboard lift (device only), the Proof views and pickers, `MemberDay` and `KeptNote`
  - SnapshotCache and Preferences
  - ReminderCenter
  - LedgerFormat beyond the review lines
  - DailySeed
- Put new rules in Domain so they can be tested.

**CloudKit schema changes**

- In the **Development** environment, CloudKit creates record types and fields automatically on the first save that includes them. A field written only on some paths (an optional value, an asset) exists only once one of those saves has run.
- **Production must be deployed by hand** in CloudKit Console before TestFlight or App Store builds. Tell the user whenever a change adds a field or record type.
  - **The latest additions are round 5's:** the field `Group.voteRules` (Int64 list) and the record types `Excuse` (`userID`, `day`, `epoch`, `text`), `Vote` (`voterID`, `subjectID`, `day`, `epoch`, `counts`, `castDay`) and `Post` (`authorID`, `text`, `day`, `epoch`, `isProof`, `mediaKind`, `aspect` and `duration` as Double, and the Asset fields `media` and `thumb`). IDs and text are Strings, and the rest Int64. Round 3 added `Group.endDay`.
  - **To create every field in Development**, with two Apple IDs in one group: as the owner, change the voting rule (Group → Overrule with); send an excuse; vote on the other's check-in or excuse in Chat; send a message; add proof once as a photo (`aspect`, `media`, `thumb`) and once as a video (`duration`). README's schema section lists the same steps and a table of every field.
  - Until round 5's schema is in Production, every excuse, vote, message, proof and rule change fails to save in TestFlight and App Store builds. The zone fetch also names the new fields in `desiredKeys`, and whether Production accepts names it doesn't have yet is unverified (see Known issues), so deploy before shipping.
- Deployed fields can't be renamed, deleted or change type.
- The app never queries (it reads whole zones), so no indexes are needed. Adding a `CKQuery` would need them.
- Read new fields with defaults, list every new non-asset field in `Records.snapshotKeys`, and keep the fetch-then-save `.changedKeys` pattern.

---

## 9. Git and commit conventions

- **Branch:** develop on the branch the session names. So far that has been `main`.
- **Commit title:** imperative, sentence case, no period ("Fix refresh races, DST-midnight day counting and post-reset reload").
- **Commit body:** wrapped at about 72 characters. Explain what changed and why. Big changes use sections such as Structure, Engagement and Engineering, with `- ` bullets. Say what was deliberately left unchanged.
- **Trailers:** end with the attribution trailers the session provides (`Co-Authored-By`, `Claude-Session`).
- **What to commit:** the regenerated `Vow.xcodeproj`, plus README updates when user-visible behaviour, setup or layout changes.

---

## 10. Known issues and tech debt

All of these are verified in code unless marked otherwise. Fix them only when asked, or when they are in scope. Remove an entry once it is fixed.

**Correctness**

- **Re-joining rewrites history.** There is one `member-<userID>` record per user. After leaving, `AppStore.setVow` writes a fresh `joinedDay = currentDay` with `leftDay = nil`. That erases the member's past days, which changes everyone's nets and the pot.
- **`leftDay` isn't scoped to an epoch.** After a test-group reset, a member who left earlier counts again on days `0..<leftDay`. This affects test groups only.
- **Orphan zones.** If `createGroup` fails after saving the zone, an empty `group-` zone is left behind. Every later refresh skips it silently, because loading it fails with `groupMissing`.
- **Client clock fallback.** `Records.checkInInfo` falls back to the client's `Date()` when a record has no `creationDate` (a fetched or saved record always has one). Excuses, votes and posts read as pending instead.
- **Two time zones.** Reminders use the device calendar, but group days use the group's `timeZoneID`. They can disagree for members in other zones; the impact is unverified.
- **Mixed builds and end dates.** Builds from before round 3 ignore `Group.endDay` and keep settling after the final day (forfeits, pots, streaks). A group with an end date shows different numbers on those members' devices until they update.
- **Mixed builds and round 5.** Builds from before round 5 ignore excuses and votes and have no Chat: there an overruled check-in still counts and an excused day is a miss, so those members see different points and streaks until they update. They also fetch zones without `desiredKeys`, so they download every post's photo, video and thumbnail on every refresh (each minute, with a nil change token): tens of MB a minute on cellular in a group that posts videos. Every member should update before anyone posts proof.
- **A late vote change can still drop a vote.** A changed vote is one overwritten record, judged by its `modificationDate`, so a change the server takes after voting closes falls out of every tally (the earlier choice doesn't come back) and re-settles a closed day. `vote` refuses changes in a real group's last 30 min by the device clock; a device clock slower than that, or a save delayed that long, still loses the vote.
- **The rule log's limits.** It keeps the last 64 changes (`Review.ruleLogCap`); past that, the oldest days fall back to "More than half" and could re-settle (it takes 64 changes on separate days). It isn't scoped to an epoch either: after a test-group reset the old log still applies by day number until the owner changes the rule. That part affects test groups only.

**Sync and security**

- **Every refresh downloads every zone in full** (nil change token, assets aside), one group after another. Check-ins, excuses, votes and posts are never deleted, so the data only grows, and Chat polls the shown group every 15 s.
- **No retry or backoff, no subscriptions or push.** The `aps-environment` entitlement is unused, and there is no `CKAccountChanged` observer. Chat, votes and the tab's dot update only while the app is open (every 15 s on Chat, 60 s on other tabs, and on returning to the app); nobody is notified of a message, vote or proof. A failed post waits for a manual Retry.
- **The owner's iCloud storage holds everyone's data,** photos and videos included, and nothing prunes old posts. When it is full, members' check-ins, excuses, votes and posts fail ("The group owner's iCloud storage is full."), and only the owner can free space.
- **`desiredKeys` with names a record lacks is unverified on a device.** `Records.snapshotKeys` names every field of every type, so each record type lacks most of them, and before round 5's schema is in Production some exist in no type at all. CloudKit is expected to skip such names; a fetch that rejected them would fail every refresh.
- **Authorization is client-side only.** The share is `.readWrite`, so any participant can write any record, a vote or an excuse in someone else's name included. Owner-only actions (the voting rule among them) are gated only by `isOwner` in the UI.

**Media**

- **`Caches/vow-media` is pruned only by group.** A group you leave or delete, or that has gone, takes its folder with it (`MediaCache.removeGroup`); otherwise photos and videos stay, however old, until "Reset local data", an iCloud account change or the system purges Caches. `PostMediaView`'s in-memory thumbnail cache (80 images) isn't emptied by "Reset local data" either; that is harmless, because nothing can show them without the snapshot.
- **A picked photo or video is lost if its proof sheet never appears** (the presenter's one retry fails too). Its outbox files go at the next launch.

**Dead code**

- `AppStore.theme(for:)`, `themeCache` and `totalBalance` have no callers.
- `MemberStatus` and `MemberStanding.status(isViewer:)` in `Standing.swift` are used only by tests, and they label friends "missed". Don't wire them into the UI.
- `VowApp`'s `.onOpenURL` is likely dead. There is no `CFBundleURLTypes`, and share links arrive through `SceneDelegate`. Not confirmed on a device.
- `CycleChain` and `ChainBead` are used only by `CycleChainTests`. Delete both together.

**UI**

- `InviteLinkSheet.copied` never resets, so a second Copy gives no haptic.
- `OrbBurst` ignores Reduce Motion.
- **The blank Settings sheet's root cause is unconfirmed on a device.** Round 4 removed the Settings-only suspects: the empty `SheetScaffold` footer inset (most likely), the dialog on the sheet root and the authorization `.task`. If it is still blank, the remaining suspect is the compact time picker, which is in the first frame only while the reminder is on.
- The Tasks started by `FlameStreak.flare` are never cancelled on disappear.
- `vowSheet` sets `presentationCornerRadius(Corner.sheet)`, which overrides iOS 26's device-matched corners on floating detented sheets. This is visual only and unverified on a device.
- **Chat's scrolling is unverified on a device:** the bottom anchor over a `LazyVStack`, the sentinel-based `atBottom`, and the first-appear flag that keeps your place when the camera or the media viewer closes. Content arriving while you're scrolled up must not move the view. On iOS 17 the plain anchor also anchors size changes, so there a message arriving, or a compact card opening up under your vote, may still shift what you are reading.
- **Also unverified on a device:** PHPicker and the camera inside SwiftUI hosts with the preparing overlay on top; whether the media viewer's swipe-down competes with `VideoPlayer`'s scrubber; whether a Reduce Motion close really skips the cover's animation; the media viewer's switch to a mixable `.playback` session for a video (so it plays in silent mode) and its restore on close, around `SoundEngine`'s ambient session.
- While an edge swipe drags the sidebar out over Chat with the keyboard up, the keyboard stays until the panel opens.

**Duplicated constants** (keep each set equal)

- `Motion.dimGateNanos` and `Anim.dimGateNanos`
- `MainView.crossfade` (0.35 s) and `Anim.screen`
- The sidebar slide: `MainView.sidebarSlide` (0.35 s) and `ProfileRow.revealDelayNanos` (the slide + 300 ms) assume that `Anim.sidebarIn`/`sidebarOut` settle within 0.35 s over the panel's width plus `Sidebar.shadowReach` (56 pt).
- The tab bar's item line: `Sidebar.footerBottom` centres the profile row (`SidebarMetrics.profile`, 60) on `(bottomInset + Gap.tabBar) / 2`, where `VowTabBar` centres its items (offset by `bottomInset / 2`). Change both together.
- `RootView.barHeight` (52, used until the shell measures the bar) = TopBar's 44 pt row + 2 × `StageMetrics.regular.barPadding`
- The orb size: literal `220` throughout `Orb/`, and `Gap.orbSlot`
- `vowTapPadding` in `StageCenter` and in `EmptyStage`
- The 700 pt compact threshold, which is repeated in `OnboardingScreen`
- The cycle length of 30, in four places (see Invariants)
- The shell's 16 pt edge zone (`MainView.edgeWidth`) and the leading `Gap.l` of Chat's composer and "+" card, which keep "+" clear of it

**Stale docs**

- `Config/Local.xcconfig.example` still describes the container as `iCloud.<bundle ID>`. It is pinned to `iCloud.app.dabora.vow`.
- The `teardown` doc comment in `OrbHoldController` is out of date:
  - It mentions `store.seal()`, but the closure now goes through `handleSealed` to `store.checkIn`.
  - It says the orb disappears only on a day change (`.id(cycle-day)`) or a reset. The key is `zoneName-epoch-currentDay`, and the orb also leaves with a tab or group switch (which is why those wait while the room is dimmed).
- Code comments cite "SPEC §…" and "§6.x"/"§7" from a design spec that **isn't in the repo**. Treat them as labels.

**Tests**

- The single `VowText` test lives in `PointsTests.swift`.
