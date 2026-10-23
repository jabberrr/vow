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
- Each group has a **Chat**: messages with emoji **reactions**, and every check-in and excuse as a card with its photo or video **proof** and the group's **votes**.
  - A check-in or excuse counts unless enough of the others vote "Doesn't count" by the end of the next day. How many is the owner's **voting rule** (More than half, Everyone, or a Custom number), and a change applies from tomorrow.
  - An overruled check-in or excuse is a miss. An excuse that stands sits the day out: no stake lost, no share of the pot, and the streak pauses. An excuse closes today's orb for good.
- **Points only.** No real money is involved.
- **No backend and no accounts.** Data lives in CloudKit:
  - Each group is a record zone in the owner's private database.
  - The zone is shared through a zone-wide `CKShare` that anyone with the link can join.
  - Photos and videos are assets in that zone, so every member's media counts against the owner's iCloud storage.
- **No third-party dependencies.**
- **iPhone only, portrait only, dark only.**
- **Testing mode** (Settings → Testing mode) creates test groups whose day the owner advances by hand.

**State as of 2026-10:** about 26k lines of Swift (tests included). `cc4da4c` redesigned the UI around a single **stage**. Round 3 added optional **end dates** (`f44253f`, `9b0bc7e`, `9a3980f`) and then replaced the dock and the cards under the stage with a **shell**: a top bar with ≡, tabs per group and a sidebar, with one `Presenter` for every sheet. Round 4 polished that shell from device testing: an always-mounted sidebar, a connected flame streak calendar with a wider month range, a still Home page and a centred tab bar. Round 5 added the **Chat** tab (second of five: Home, Chat, Streak, Activity, Group) with proof, excuses and votes: the `Review` rules in Domain, a `Media` layer, the record types `Excuse`, `Vote` and `Post`, and full-screen covers in the `Presenter`. Settlement now applies the group's verdicts. The orb, the glyph, sound, the cascade's timing and the existing ledger strings were left unchanged. Round 6 polished Chat from device testing (a taller composer, roomier bubbles with tails, green and red vote buttons with their counts beside them, a shorter status line, a "+" card that fits) and added emoji **reactions** (the record type `Reaction`), a **Custom** voting rule, the owner's crown, swiping between tabs, an Activity page drawn from structured `LedgerDay`s instead of ledger strings, and faster sync: silent pushes from CloudKit database subscriptions, per-zone delta fetches and quicker polls. The orb, the glyph, sound, the cascade's timing, Settlement's money and `Review.verdict` were left unchanged.

**`README.md`** is the user-facing doc: setup, schema deployment, how points work and the repository layout. Keep it accurate whenever behaviour, setup or layout changes.

---

## 3. Repository map

```
Vow/
  App/        VowApp (entry, env injection, scene-phase refresh), RootView (screen routing, toast), AppDelegate+SceneDelegate (iCloud share acceptance; registers for remote notifications and hands CloudKit's silent pushes to ChangeInbox)
  Domain/     PURE Swift, no UI or CloudKit: GroupModels, DayClock, Settlement, Review (claims, votes, verdicts, rule log, proofDay), Reactions (chips per post), Standing (incl. the ledger's LedgerDay), Streaks, EndDate, StreakCalendar, CycleChain (unused), Digest(+DayWindow), ReminderPlan, Points, VowText
  Cloud/      CloudService (CloudKit I/O incl. per-zone delta fetches over in-memory zone mirrors, the push subscriptions, post uploads and asset fetches, CloudError, CloudErrors), Records (CKRecord <-> models, snapshotKeys, text limits), ShareInbox (buffers accepted shares until the store is ready), ChangeInbox (hands CloudKit's pushes to the store; answers "no data" at once until it is ready, and within 25 s at most)
  Media/      MediaPrep (MediaDraft: photos and videos sized into Caches/vow-outbox), MediaCache (@MainActor @Observable: post assets on disk under Caches/vow-media)
  Store/      AppStore (@MainActor @Observable app state, incl. the chat sends), AppStore+Stage and AppStore+Chat (read-only helpers), Overview (aggregates, VowStatus, MenuDot), SnapshotCache (JSON on disk), Preferences (UserDefaults)
  Design/     Tokens (Ink, Fonts, Gap, Corner, Anim, StageMetrics), Styles, Buttons, Fields, SheetScaffold, Feedback (toast, banner, tag), Sphere, Flame, Formatters (incl. DayText, VoteRuleText), OrbBridge
  Features/   Main (the shell: MainView, Presenter, TopBar, VowTabBar, Sidebar with ProfileRow and AddGroupMenu, MainTab)
              Stage (Home tab: StageScreen + parts incl. StageFoot, FinishedStage), Streak (StreakPage, StreakStatsCard, StreakCalendarView)
              Chat (ChatPage, ChatFeed: the pure feed model, ClaimCard with VoteControl, MessageBubble with BubbleShape, ReactionPicker with ReactionChips and ScrimCutout, ChatComposer, ChatPlusMenu, ChatText)
              Proof (PostMediaView, CameraPicker, LibraryPicker, ProofSheet, MediaViewer with the pickers' ProofPrep and PreparingOverlay)
              Activity (ActivityPage, ActivityFeed: the pure day model, ActivityDayView)
              Group (GroupPage, GroupMembersCard with MemberDay, KeptNote (which Home's strip shares) and OwnerCrown, MemberSheet, VoteRuleSheet)
              Menu (SettingsSheet, ProfileSheet), Sheets (NewGroup, JoinLink, InviteLink, Vow, Excuse), Root (onboarding, status)
  Orb/        Press-and-hold check-in: OrbView, OrbHoldController, OrbTiming, ring, burst, active and sealed orb
  Glyph/      DailySeed (deterministic daily theme), GlyphModel, GlyphView (Canvas)
  Sound/      SoundEngine: synthesized build-up tone and pop (AVAudioEngine, no assets)
  Reminders/  ReminderCenter (@MainActor @Observable: local notifications and badge), ReminderOfferSheet
  Info.plist  Explicit; CKSharingSupported, NSCameraUsageDescription, NSMicrophoneUsageDescription (PHPicker needs no library permission), UIBackgroundModes = remote-notification (CloudKit's silent pushes). Vow.entitlements pins iCloud.app.dabora.vow and has aps-environment. Assets.xcassets holds one 1024 px AppIcon.
VowTests/     XCTest unit tests for Domain (incl. Review and Reactions), Design/Formatters, Store/Overview, Records, Chat's feed and wording (ChatFeed, ChatText) and Activity's days (ActivityFeed), hosted in Vow.app
Config/       Vow.xcconfig (bundle ID app.dabora.vow, team), which #include?s the git-ignored Local.xcconfig
project.yml               XcodeGen spec
scripts/gen_xcodeproj.py  Stdlib-Python generator for Vow.xcodeproj. Mirrors project.yml.
.github/workflows/ios.yml CI on macOS 15 with Xcode 16
```

---

## 4. Architecture and data flow

```
CloudKit zone ──CloudService (changes since the zone mirror's token)/Records──▶ GroupSnapshot ──AppStore (cache, merge, optimistic writes)──▶
  Settlement.summarize(snapshot, viewerID:, now:) ──▶ GroupSummary (incl. days: [LedgerDay]) ──▶ Digest, EndDate, StreakEvents, StreakCalendar, Overview, ReminderPlan, ActivityFeed ──▶ Views
  Review.tally / tallies / proofDay(snapshot, now:) ──▶ ClaimTally per (subject, day) ──▶ Chat, Home's foot and meta line, Activity, sheets
  Reactions.counts(snapshot, viewerID:) ──▶ [ReactionCount] per post ──▶ Chat's chips and picker
Post assets ──CloudService.fetchAsset──▶ MediaCache (Caches/vow-media) ──▶ PostMediaView, MediaViewer
Silent push ──AppDelegate──▶ ChangeInbox ──▶ AppStore.refreshAll
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
  - **Delta fetches:** `fetchSnapshot` keeps a private `ZoneMirror` per zone, in memory only: the last server change token and every record it has seen, parsed and keyed by record name. Each fetch asks for the changes since that token, applies deletions and then changes to a copy, and builds the same `GroupSnapshot` as a full fetch would (the same sorts, the share URL, `groupMissing` without the Group record).
    - With no mirror, or on `.changeTokenExpired`, it fetches the zone in full. The copy replaces the mirror only when every changed record arrived and no forget of that zone (`zoneGenerations`) or of every zone (`mirrorGeneration`) came after the fetch began (`MirrorStamp`), so a record that failed comes again next time.
    - Fetches of one zone run one after another (`fetchTails`) until the zone is forgotten, so an older change never lands on a newer one. `mirrorLock` is taken only in synchronous helpers, never across an `await`.
    - `forgetZone` (a group you leave or delete, or that a fetch or refresh finds gone) and `forgetAllZones` ("Reset local data", another iCloud account) drop mirrors and fetch tails, so the next fetch doesn't wait for one that keeps nothing. Forgetting one zone never costs another zone's fetch its delta. Mirrors aren't cached, so each launch fetches every zone in full once.
  - **Push:** `ensureSubscriptions() -> Bool` saves one content-available `CKDatabaseSubscription` on the private database (`vow-private`) and one on the shared database (`vow-shared`), and is true only when both saves succeed. The store's `subscribeIfNeeded` calls it from every `refreshAll` round whose zone listing succeeded, until one succeeds: once per launch and account (the account-change branch resets `subscribed`, and a save that ends after the account changed doesn't count). Until then the polls sync.
    - `AppDelegate` registers for remote notifications at launch (never in unit tests) and hands CloudKit's pushes to `ChangeInbox`; anything else is answered `.noData`. The store's handler runs `refreshAll` (a push doesn't say which zone changed) and answers `.newData` or `.noData`.
    - `ChangeInbox.deliver` answers within `deadlineNanos` (25 s) at the latest, with `.noData` if the refresh hasn't ended, because iOS ends the app if a silent push isn't answered within about 30 s; the refresh carries on. It doesn't buffer: a push that comes before the store installs its handler is answered `.noData` at once, because the first refresh fetches it anyway and a background launch may never get that far.
- **Media does files.**
  - `MediaPrep` turns a picked or captured photo or video into a `MediaDraft` in `Caches/vow-outbox`: photos at most 1,600 px on the long edge (JPEG 0.75); videos cut to their first `MediaPrep.videoLimit` (20 s, also the camera's limit and the proof sheet's note) and exported as MP4 at 960×540, falling back to medium quality; a thumbnail at most 480 px on the long edge. The budget is tight because every member's media lands in the owner's iCloud storage.
  - `MediaCache.shared` (`@MainActor @Observable`) keeps post assets under `Caches/vow-media/<zone>/`, downloads each once (concurrent requests share the download) and `adopt`s your own draft by copying it (an APFS clone, never a move), so your upload shows at once. "Reset local data" and an iCloud account change call `clearAll()`; a group you leave or delete, or that a refresh finds gone, takes its folder with it (`removeGroup`).
  - The shared `AVAudioSession` belongs to `SoundEngine` (ambient, so the orb obeys the ringer switch), with one exception: while `MediaViewer` shows a video it switches to `.playback` (`.moviePlayback`, mixing with others), so the clip is heard in silent mode, and on close it puts back the category, mode and options it captured. Photos leave the session alone.
- **AppStore owns group and app state.** `ReminderCenter.shared` owns reminder state.
  - AppStore is `@MainActor @Observable final class`. State is `private(set)`. Bookkeeping fields are `@ObservationIgnored`. The sends live in `AppStore.swift` beside the private state they write; `AppStore+Chat` holds read-only helpers only.
  - **Offline first:** with a cached userID and cached snapshots, it starts in `phase = .ready`.
  - **Optimistic writes:** check-ins, excuses, votes, reactions and posts go in pending (`serverDate == nil`) and are saved; then the server copy is swapped in or the write rolls back (a vote or a reaction back to the one it replaced). In-flight sets (`inFlightCheckIns`, `inFlightExcuses`, `inFlightVotes`, `inFlightReactions`, `inFlightPosts`) keep them through refreshes.
    - A failed post isn't rolled back. It stays in the chat, unsent, in `failedPosts` (a proof keeps its draft in `failedDrafts`) until `retryPost` or `discardPost`. It is never cached, and it is dropped (with its draft) once a fetch shows it saved, its group has gone or a test reset leaves it in an old epoch. A proof's upload progress is `uploads[postID]` (0…1).
    - `vote` ignores a second tap on a claim while the first saves, because two saves of one record could land out of order. In a real group it also refuses to change a vote already cast in voting's last half hour (`Review.canChangeVote`: `voteChangeMargin` before `Review.closesAt`), since a change the server stamps after the close would take the vote it replaced out of every tally; a first vote goes in until the close. `setVoteRule` (owner only) refreshes first, is ignored while a rule change or a test day is saving or once the vow has finished, and isn't optimistic.
    - `react(_:to:in:)` is a vote's twin, for active members on sent posts only. It ignores a second change to one post while the first saves and does nothing when the emoji is already yours; nil saves "" (taken back), because the record is overwritten, never deleted. `CloudService.saveReaction` fetches first and skips re-saving an unchanged emoji. It doesn't refresh afterwards.
    - `sendProof` dates the post with `Review.proofDay` and refuses (false, no toast) without one. It owns the draft from the call on: sent, refused or discarded, the store deletes its outbox files. The store empties `MediaPrep.outbox` at launch, because drafts live only in memory.
    - After your own send (message, proof, retry, excuse) the store refreshes that group, so replies show before the next poll.
    - `canExcuse` (`AppStore+Chat`) is the one "can today be excused?" check: `sendExcuse` guards with it, the excuse sheet closes itself once it fails, and Chat's "+" card disables its row with `excuseBlock`'s reason. It and `checkIn` scan today's records directly (`AppStore.hasCheckIn`, `hasExcuse`), not with a Settlement pass.
  - **Test days:** `advanceTestDay` and `resetTestGroup` return early while either is running for that group (`testDayInFlight`), so a Next day can't save the old epoch back over a reset. The ignored tap is silent.
  - `persist()` runs after mutations and strips every pending record (check-ins, excuses, votes, reactions and posts).
  - `refreshAll()` lists both databases' zones and fetches snapshots one at a time. A call while one runs (a push, a pull to refresh, the return to the app) doesn't start another: it sets `refreshAllAgain`, the running one goes round once more when it ends, and every waiting call returns with that round (`refreshAllWaiters`). `refreshAllChanges` counts the rounds that changed `snapshots`, so a push can answer `.newData`. Each round diffs against the keys it had at its start, so groups created, joined or removed during a refresh behave correctly. `merged()` keeps confirmed and in-flight check-ins, excuses and posts (indexed by identity) and your failed posts; your in-flight vote or reaction wins over the fetched copy, and a confirmed one only when its server date is newer.
  - **A fetch that brings nothing new changes nothing:** `refresh`, `refreshAll` and `acceptShare` leave `snapshots` and the cache untouched (`sameContent` compares without `fetchedAt`), so a poll or a push that finds nothing re-renders nothing.
  - **There are two error paths:**
    - Create, join and accept go through `fail()`, which sets `lastError` (shown inside `NewGroupSheet` and `JoinLinkSheet`) and `toast`.
    - Everything else sets `toast` directly: `CloudErrors.message(error)`, or a fixed "Couldn't check in. Try again.", "Couldn't send your excuse. Try again.", "Couldn't vote. Try again.", "Couldn't react. Try again." or "Couldn't change the voting rule. Try again.". A failed post raises no toast: it shows "Not sent" in place.
    - When a check-in, excuse, vote, reaction or post fails with `.quotaExceeded` and you aren't the owner, the toast reads "The group owner's iCloud storage is full." (`ownerStorageFull`). It is the one case where a failed post toasts too.
    - Network errors are suppressed when a cache exists.
  - **Settlement is not cheap.** Every `summary(for:)` or `summaries(now:)` call runs a full Settlement pass. Compute once per render and pass the result down. The shell memoizes `summaries` per minute (`SummaryMemo`) for the top bar, sidebar, tab bar and reminder sync; each page runs one `summary(for:)` per body for its group. An upload's progress (`uploads`) is read only by small views of its own, Home's foot's `SendingProof` and Chat's `PostMediaView`, so its ticks never re-run a page. Chat never runs Settlement: its feed is one `Review.tallies` and one `Reactions.counts` pass, memoized per snapshot, minute and range (`ChatFeedMemo`); rows never count reactions themselves. Activity words `summary.days` once per body (`ActivityFeed.build`) into a `LazyVStack`. A tab swipe never re-runs a page's body per frame (`SwipeablePage` holds the drag); Home's swipe to the sidebar and the edge swipe still do (see Known issues). `hasUnseenChat` is one pass over the group's arrays, which allocates only once the group has reactions, so the tab bar may ask on every render.
- **Views use the environment for shared objects.**
  - They get `@Environment(AppStore.self)` and `@Environment(ReminderCenter.self)`, injected in `VowApp` and again by the shell's `sheetContent` for sheets and covers. No view reads the `Presenter`: the camera and library pickers hand their draft to closures (`onPicked`, `onLibrary`) that the shell wires.
  - Child views take plain values and closures (for example the `StageActions`, `ChatActions` and `GroupActions` structs), with explicit `init`s.
  - Never use `ObservableObject`, `@EnvironmentObject` or `@Bindable`.
- **Unit tests are hosted in the app.** Any launch-time side effect must return early when `AppStore.isRunningUnitTests` is true.

**Screens**

- `RootView` picks one of: onboarding (no profile), `LaunchScreen`, `ProblemScreen` (no account, or failed with no cache), or `MainView`. It also owns the toast and `roomDimmed`, and gets `toastBlocked` and `topBarHeight` from the shell.
- `MainView` is the **shell**. It has **no `NavigationStack` and no push**:
  - A pinned `TopBar`: ≡ (opens the sidebar), the selected group's name, and the iCloud retry banner under it.
  - The selected group's page for the current `MainTab`: Home (`StageScreen`), Chat (`ChatPage`), `StreakPage`, `ActivityPage`, `GroupPage`. Pages are swapped, not kept alive (the orb and its timers never run off screen). A tab-bar tap is an instant swap. Re-tapping the selected tab bumps `topToken` (scroll to top; Chat scrolls to the latest). Switching group resets the tab to Home. Chat's unsent drafts live in the shell (`chatDrafts`, per group, memory only).
    - **Swiping between tabs:** each page sits in a private `SwipeablePage<Content>` wrapper (in `MainView.swift`). Its clearly horizontal drag (a `.simultaneousGesture`, so scrolls, the orb and Chat's long presses keep theirs) moves to the next or previous tab in tab-bar order (`MainTab.next`/`previous`) through `selectTab`. The wrapper owns the drag (`@GestureState drag: PageDrag?`: owns, toSidebar, dx) and its release (`@State latch: SwipeLatch?`), applies the follow offset, `.disabled` and the gesture to its content, and talks to the shell only through `SwipeHooks` (`canStart`, `canContinue`, `changed`, `commit`, `releaseToSidebar`, `heldLong`). Constants live in `SwipeMetrics`.
    - The first change decides for the whole drag. It is blocked when not clearly horizontal, with the sidebar open or an edge drag under way, while `!canOpenSidebar`, while Chat holds the touch (`SwipeGuard.overlay`: its "+" card or reaction picker is up, or you are typing, so a drag across a scrim or one that moves the cursor or selects text never switches tabs), or while Home may owe a seal (`SwipeGuard.owesSeal`, see §5). It drops out if the room dims, a presentation starts or the sidebar opens under it. A blocked drag never disables the page, so Chat's keyboard stays.
    - While dragging, the page follows with resistance (at most 40 % of the width toward a neighbour, 10 % at the first and last tab). Released past a third of the width (by predicted travel), the new page slides in a width away as the old one slides out (`PageSlide`, `slideTransition(forward:width:)`), both riding the wrapper's offset as it springs back: only then, for about 0.35 s, are two pages mounted. Reduce Motion: no follow, a crossfade.
    - While a swipe owns its touch the page is `.disabled`, so a lift over a button doesn't press it and a hold the swipe began on the orb lets go. The shell renders only when a swipe takes its touch, turns round or ends (`pageSwipe: PageSwipe?`, written only on change), plus every frame of Home's swipe to the sidebar (`.sidebar(travel:)`). Scrolls never render the shell, and a tab swipe never runs a page's body per frame (Home's swipe to the sidebar does, like the edge swipe). `swipeOwnsTouch` (`pageSwipe != nil`) only feeds `setBusy`.
    - On Home, a swipe to the right opens the sidebar instead, exactly as one from the edge (`sidebarSwipeTravel`, `openIfPassed`); a swipe to the left goes to Chat.
    - `SwipeGuard` is a reference, so neither Chat's overlays coming and going nor a long drag on Home renders the shell. Chat reports through `ChatActions.overlay`, and the shell also clears the flag when `refreshKey` moves away from Chat, in case Chat's own `onDisappear` comes late.
  - A pinned custom `VowTabBar`, shown whenever a group's page is (not a `TabView`: it dims with the room and avoids iOS 26's floating tab bar). Its items are centred in the bar you see (`Gap.tabBar` plus the home-indicator inset, `bottomInset` from the shell's GeometryReader), not in its top 49 pt, and each is tappable over that whole height. No groups: `EmptyStage` and no tab bar; first sync of a fresh install: a spinner.
    - The Streak flame lights only while your check-in stands (`Digest.checkInStands`), from the social beat on.
    - **The chat dot** is the app's one unread-style mark: a 7 pt `Ink.text` dot on an 11 pt `Ink.bg` rim at the Chat symbol's corner, not hit-testable, VoiceOver value "New messages". It shows when `store.hasUnseenChat(id)` and Chat isn't the page. That counts others' posts, others' excuses, votes others cast on your claims and others' reactions to your posts (not one taken back), newer than `chatSeenAt[zone]`: the newest such server date when Chat was last shown (`markChatSeen`, saved under `vow.chatSeen`; before a first visit, the last two days count). Bare check-ins never light it.
  - A `Sidebar` overlay: Add group (a custom menu: New group, Join with a link), your groups with today's status, Settings, and you with your balance. It opens from ≡, a swipe from the 16 pt leading edge zone (an overlay over the page, so it never reaches the page's own swipe) or a swipe to the right anywhere on Home (the same follow and thresholds), and closes on the scrim, a pick, a horizontal drag or VoiceOver escape. Opening it resigns the first responder, so Chat's keyboard never sits over its footer. An excused row shows a dashed sphere and your (paused) streak; an overruled one an unlit sphere and "Overruled", like "Finished".
    - It is always mounted. One state drives the panel's offset and the scrim's opacity (`panelExtent`/`panelOffset`/`panelProgress`); under Reduce Motion the panel stays put and fades. Nothing is inserted or removed mid-slide, so every row moves with the panel and a reversed slide or released drag carries on from where the panel is. Don't reintroduce `if` blocks or `.transition` for the panel or scrim.
    - Closed, the panel is parked past its shadow (`Sidebar.shadowReach`). Touches follow `sidebarShown`; VoiceOver visibility and `.isModal` follow `isOpen`. Each appearance starts with the Add menu closed (reset when `isShown` turns true), opening moves VoiceOver focus to Add group, and the group list keeps its scroll position.
    - Its footer dips into the home-indicator inset so the profile row's centre is level with the tab bar's items (`Sidebar.footerBottom`; `Gap.s` above the edge with no inset).
    - Its drags are `@GestureState`, so a drag the system cancels (a sheet, an alert, Control Center) resets itself; never hold a live drag in plain `@State`. The one exception is `pageSwipe`, which mirrors `SwipeablePage`'s gesture state for the shell and is cleared when the drag ends, when the gesture state resets and when the wrapper disappears. Every close path works whenever the panel is visible, mid-drag included.
    - ≡, the edge zone and page swipes ignore input while the room is dimmed or the presenter isn't idle (`canOpenSidebar`; a sheet must never rise over a reopened panel). An edge drag, or a page swipe that owns its touch, counts as busy for `.automatic` presentations.
    - A reminder tap waits while a sheet that holds unsaved work is up or queued next (`MainSheet.holdsUnsavedWork`: New group, Excuse, camera, library, Proof), not only while it saves: closing it would discard what you typed, picked or shot. `Presenter.queued` covers the gap in a chain such as camera → Proof, while `sheet` is briefly nil.
  - The refresh of the shown group (`.task(id: RefreshKey)`: every 15 s, every 5 s while Chat is shown; only while its snapshot exists) lives in the shell, so it runs on every tab. It is the fallback for the silent pushes, and each poll fetches only the zone's changes. Streak, Activity and Group also have pull to refresh. Home doesn't move at all when it fits (`.scrollBounceBehavior(.basedOnSize)`, no `.refreshable`) and scrolls only when it doesn't (accessibility sizes, a test bar on a small screen). `EmptyStage` keeps pull to refresh: with no group there is no timed refresh, so it is the only way to sync there.
  - **Chat** (`Features/Chat`) has no pull to refresh (its top is history). It refreshes on appear and after your votes, and the store refreshes after your other sends.
    - `ChatFeed.build` (pure, tested) turns a snapshot into rows: day headers, messages with their reaction chips (a run is one author's within 5 min; its last bubble has the tail), one claim card per check-in or excuse with its proof inside, and a pointer ("Maya added proof to yesterday's check-in") where proof came after other rows. Until Earlier is tapped it shows the week up to the newest item (`ChatFeed.recentDays`: that item's day and the six before it, today at the latest), so a quiet chat or a finished vow never opens on Earlier alone. The rule's preamble shows while two or more take part today in a vow that hasn't finished (`hasVoters`). A check-in's card stays compact until proof or a vote arrives.
    - `ChatPage` presents nothing itself: it calls `ChatActions` (and the store directly for votes and reactions). The shell passes `covered` (the sidebar is showing), which closes the "+" card and the reaction picker. Chat reports through `ChatActions.overlay` whether it holds the touch (`holdsTouch`: the "+" card or the picker is up, or the composer is focused), on every change, again on `onAppear` (a cover sends `onDisappear` but the page keeps its state) and false on `onDisappear`. The "+" card (`ChatPlusMenu`, a custom menu) lists Take photo or video (hidden without a camera), Choose from library and Excuse for today, each disabled with its reason in place.
    - The feed and the composer sit in a `VStack`, not `.safeAreaInset`, so the 1 pt bottom sentinel's `atBottom` is exact with the keyboard up. The fade, the jump button and the "+" card (over its scrim, which covers the feed only) are overlays of the feed area's bottom edge, which is the bar's top. The card is laid out at its own height in the space above the bar, `Gap.s` above it, and scrolls inside only when that space is too short (`ViewThatFits`). Never overlay something tall on the bar: an overlay is proposed its base's size, which squeezed, clipped and misplaced the old card. It opens at the bottom once per visit (`hasOpened`, because closing a cover sends the page `onAppear` again): `OpensAtBottom` applies `.defaultScrollAnchor(.bottom, for: .initialOffset)` on iOS 18+ and the plain `.defaultScrollAnchor(.bottom)` only on iOS 17 (where it also anchors size changes), then one `Task.yield()` and a `scrollTo`. It follows new rows only while at the bottom or for your own pending send, and keeps the old first row in place after Earlier.
    - The shell ignores the keyboard (`.ignoresSafeArea(.keyboard, edges: .bottom)`), so a sheet's keyboard never moves it. Chat lifts its own composer from the keyboard notifications, only while its own field is focused. The composer's "+" and the "+" card start at x = 16, clear of the shell's edge zone.
    - **Reactions** (text messages only): a member holds a sent message for 0.3 s (`BubblePress`, with a medium haptic) to open `ReactionPicker`: `Reactions.choices` in a pill, then Copy, because the hold replaces the context menu. An empty `onTapGesture` before the long press is the usual guard against it stopping the scroll view. Messages still sending or not sent, and anyone who isn't an active member, keep a context menu with Copy instead.
      - Opening the picker first scrolls the message the least it takes to show it whole (never under the bar, where the cut-out would lay the composer bare). The picker sits over an `Ink.scrim` that covers the whole page, the bar included, and leaves the held bubble lit (`ScrimCutout`, an even-odd fill of `BubbleShape`). It sits above the bubble, or below when there's no room, and follows it through `ReactionAnchorKey`, which only the held bubble reports. It closes on a tap on the scrim, or once the feed no longer shows the held message (`lostHeld`); under Reduce Motion it only fades in and out.
      - Your emoji is ringed; tapping it, or your chip under the message (`ReactionChips`), takes it back. A chip's target reaches `Gap.s` above and below it, never sideways.
      - VoiceOver: the message is one element, so VoiceOver never visits the chips. Its value lists the reactions ("8:21 PM, 2 ❤️, 1 😂") and its actions read "React with ❤️"/"Remove ❤️". The chips' text stops at `.xxLarge`, so each chip shows in the large content viewer.
    - It marks the chat seen on appear, on every snapshot change and on disappear, so the dot never lights for what you are reading.
    - Non-members get a read-only feed and a "Write your vow to join" bar (none once the vow has finished). A finished vow's chat stays open to members.
- **Sheets, covers and dialogs:** the shell owns `Presenter` (`Features/Main/Presenter.swift`, which also declares `MainSheet`, `MainDialog` and `PresentSource`). Its one `.sheet(item: sheetBinding)`, one `.fullScreenCover(item: coverBinding)` and one `.confirmationDialog` are the only ones in the main experience.
  - `MainSheet.isCover` (the camera, the media viewer) picks the cover. A cover shares the sheet's slot and phase machine (the `onAppear`/`onDisappear` proof, the deadlines, the settle), and a nil written through one binding never clears the other kind, so a late write from a departed sheet can't take down the cover that followed it.
  - Pages and chrome call closures that the shell wires to `presenter.present(_:from: .screen)` or `confirm(_:from: .screen)`. `.screen` means a real tap on the main screen.
  - Sheet and cover bodies close with `dismiss()` and chain with `from: .sheet`: Create → Invite, your member sheet → Edit vow, the proof chooser → camera or library, camera → library, camera or library → Proof (`MainView.proofPicked`). They may host their own dialog, hung off the control that asks for it (Settings → Reset local data, Excuse → "Send excuse?").
  - Home's Add proof asks `MainDialog.proofSource` ("Add proof": Take photo or video, Choose from library; no message, so `dialogMessage` returns nil), or presents the library at once on a device with no camera. Chat's "+" card lists both sources itself.
  - The vow prompt and the reminder offer use `.automatic`. They wait while the shell is busy (`setBusy`: hold, cascade, open sidebar, an edge drag, a page swipe that owns its touch), and `isStillWanted` re-checks them just before they show. `didClose(.vow)` clears `pendingVowPrompt`. A reminder tap calls `dismissAll()`. The store and timers never touch presentation.
  - It can't wedge: presenting and dismissing end on a 1 s deadline even with no callback (a sheet whose content never appears is cleared and retried once), the latest tap wins and closes what is up, and nothing starts within a short settle after a dismissal or during `delay(for:)` (the shell's fade-in, every sidebar slide).
  - **Rules:** no SwiftUI `Menu` leads to a sheet or dialog (build a custom menu like `AddGroupMenu` or `ChatPlusMenu`; `from: .menu` exists for an unavoidable one and has no callers). Sheet and cover bodies never render `EmptyView`: the content's `onAppear` is the presenter's proof that a sheet is up. Covers only at the shell: no `fullScreenCover` in pages or sheet bodies. No `presentationBackgroundInteraction(.enabled)` on shell sheets.
  - Check: `grep -rn "\.sheet(\|confirmationDialog(\|\.alert(\|fullScreenCover(\|\.popover(" Vow/Features` lists only `MainView`, `Presenter` (its own `.sheet(` case and doc comments) and the dialogs that `SettingsSheet` and `ExcuseSheet` host.
  - Use `.vowSheet([...])` for detents and `SheetScaffold` for layout; covers take no detents. A sheet without a footer uses SheetScaffold's footer-less init; never pass `footer: { EmptyView() }`, which is still a bottom inset with an opaque backing (the prime suspect for the blank Settings sheet, see Known issues).
- **Toast:** RootView holds a toast while the room is dimmed. While a sheet, a cover, a dialog or the sidebar is up (`toastBlocked`, from the shell), it waits at most `Anim.toastWaitNanos` (1.5 s) from when it was raised, then it is dropped. It sits below the measured top bar and takes no touches.
- **Dimming during a hold:** everything except the vow and the orb dims, the top bar's and tab bar's contents included (their backings stay). New stage UI and chrome must apply `.roomDim(_:)` (in `Styles.swift`).
- **Share invites:** `SceneDelegate` → `ShareInbox.deliver` (buffered) → the handler that `AppStore.installInboxes` installs after `bootstrap()` has an account (with `ChangeInbox`'s) → `acceptShare` → `pendingVowPrompt` (observed with `initial: true`): the shell selects that group's Home, then presents its vow sheet from `.automatic`. For a finished group it only selects it. Already a member: `acceptCount` → that group's Home.

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
  - The ledger is `GroupSummary.days`: one `LedgerDay` per day (joined, left, kept, excused, `forfeits` with a `Forfeit.Reason`, `carriedIn`, `share`, `carriedOut`), every list in Settlement's member order. It is the same for every viewer and holds no English (`LedgerPerson.name` is the stored name; the UI says "You").
  - A keeper gets `amount / kept.count` from each forfeit plus `carriedIn / kept.count`, which add up to `share`. With nobody keeping, `carriedOut` is `carriedIn` plus the day's forfeits.
  - A closed day is listed when anyone took part or someone joined or left. Today (`isClosed == false`) is listed only for joins and leaves and carries no money: its carry is `GroupSummary.pot`.
  - List at most `Settlement.dayCap = 120` days, newest first; every day still settles.
  - Nets always sum to −pot.
- **Stake is immutable after a group is created,** because settlement applies it to every past day. Adding a "change stake" feature needs a settlement redesign.
- **Epochs:**
  - Resetting a test group bumps `epoch` and sets `testDay = 0`.
  - **Check-in, excuse and post records are never deleted.** `AppStore.merged` depends on this. A vote or reaction record is overwritten when its author changes their mind, never deleted (a reaction of "" is one taken back).
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
- **Verdict:** a claim is overruled when it has voters and its "Doesn't count" votes reach `VoteRule.needed(voters:)` under the rule for its day: `majority` n / 2 + 1, `twoThirds` ⌈2n/3⌉ (legacy, no longer offered), `everyone` n, `count(k)` min(k, n) with k kept within `VoteRule.customRange` (1…99). With no votes, or no voters (a solo group), it stands. `Review.excuseStandsByDefault` (true) is the one switch that would make excuses need "Counts" votes instead.
  - **It is computed only in `Review.verdict`.** Settlement, `tally` and `tallies` all call it, and Settlement indexes the votes once per pass (`Review.Ballots`). Never write the rule a second time.
  - Day d's outcome is provisional until voting on it closes at the end of day d + 1 (`Review.isOpen`).
- **Rule log:** `GroupInfo.voteRules` (`[VoteRuleChange]?`, the last stored property). The rule for day d is the latest change with `fromDay ≤ d` (a later entry wins a tie), else `.majority`. `Review.changing` adds a change from tomorrow (`currentDay + 1`; a test group's `testDay + 1`), drops any planned from then on, adds nothing when tomorrow already has that rule, and keeps the last 64 (`Review.ruleLogCap`). A day already open to votes is never judged under a new rule.
- **Outcomes** of a closed day: a standing check-in is `.kept`; a standing excuse is `.excused` (it sits out: no stake lost, no share of the pot); no claim, or an overruled one, is `.missed` (stake into the pot, a `Forfeit` whose reason says which). A day where everyone is excused moves nothing: no forfeits, and `carriedOut == carriedIn`.
- **Today** (`MemberStanding`): `checkedInToday` means a valid check-in exists, overruled or not (the orb's seal depends on it); `excusedToday` means a valid excuse and no check-in; `todayOverruled` covers either claim. "Kept" and "excused" mean `Digest.checkInStands` and `Digest.excuseStands`. Home's strip, the Group page and the member sheet all read a member's today through `MemberDay.of`, and "{kept} of {n} kept today" is `KeptNote`, counted from those same `MemberDay`s (n leaves out the excused), so a sphere and its count never disagree. `missedYesterday` reads the verdict.
- **An excuse closes today's orb for good.** It can't be withdrawn, or sent after a check-in: `checkIn` returns early on a valid excuse today, and `sendExcuse` on a check-in or excuse today, a finished vow or a non-member.
- **Proof** attaches to `Review.proofDay`: today once you have a claim (check-in or excuse), else yesterday's claim while it is open to votes, overruled or not; nil otherwise, or when you don't take part that day. A proof post's `day` is that claim's day.

**Reactions** (`Domain/Reactions.swift`)

- One per (user, post): the last copy in the snapshot wins, and "" means taken back. They never touch points, votes, verdicts or streaks.
- `Reactions.counts` (one pass for the whole chat) groups each post's reactions by emoji: `Reactions.choices` (❤️ 👍 😂 😮 🔥 👏) first in that order, then any other non-empty emoji (a later build's) as it first appears. Who reacted is in Settlement's member order, members who left included, then non-members by userID.

**CloudKit records**

- **These names are part of the protocol.** Never rename them:
  - Record types `Group`, `Member`, `CheckIn`, `Excuse`, `Vote`, `Post` and `Reaction`, and their field names (`Records.swift`).
  - Zone `group-<UUID>`.
  - Records `group`, `member-<userID>`, `checkin-<epoch>-<userID>-<day>`, `excuse-<epoch>-<userID>-<day>`, `vote-<epoch>-<voterID>-<subjectID>-<day>` and `reaction-<userID>-<postID>`. These deterministic names make saves idempotent, and a changed vote or reaction overwrites its record. A post is `post-<UUID>`, named on the sending device, so an optimistic post and its saved copy share an id and a retry finds the first save.
- **Trusted time:** a check-in's, excuse's or post's server `creationDate`; a vote's or reaction's `modificationDate`, because a changed one is judged (or dated) by when it changed.
- **Field encoding:**
  - Ints and bools are stored as `Int64`.
  - `leftDay` is always written, with `-1` meaning active.
  - Decoding is lenient and falls back to defaults. A vote without `counts` reads as "Counts" (it can't overrule) and one without `castDay` as the day voted on; an unknown `mediaKind` reads as text; `aspect` is clamped to 0.1…10; a reaction without `emoji` reads as "" (taken back). Text is cut to `Records.excuseTextLimit` (280) or `Records.postTextLimit` (2,000), and an emoji to `Records.emojiLimit` (16 characters), on read and write. Those are the only limits: the sheets and the composer clamp to the first two.
  - `Group.endDay` is optional: written only when set, absent means no end, clamped on read to 0…`EndDate.maxEndDay`. `Records.apply` never clears it, because a `GroupInfo` without it can only be stale (an older cache or build).
  - `Group.voteRules` is a flat `Int64` list `[fromDay, code, …]` (`VoteRule.code`: 1 More than half, 2 Two thirds, 3 Everyone, 100 + k for Custom k; 4…100 are left for later fixed rules); absent means "More than half" from day 0. A pair whose code this build doesn't know is skipped. **Only `CloudService.saveVoteRules` writes it**: it fetches the Group record and sets that one key (`.changedKeys`). `Records.apply(GroupInfo)` never writes it (RecordsTests pins this), so a stale `GroupInfo` can't roll the rule back.
  - A post's photo or video and its JPEG thumbnail are the `CKAsset` fields `media` and `thumb`.
  - **`Records.snapshotKeys` must list every non-asset field of every type.** The zone fetch passes it as `desiredKeys`, so a field missing from it silently reads as its default. RecordsTests checks it against every `apply`.

**Local state**

- **Cache compatibility:**
  - `SnapshotCache` decodes with `try?` and has no schema version. A new required field on a Codable domain model silently **discards every user's cache**.
  - Synthesized `Decodable` ignores property default values. A new field must be `Optional`, or the type needs a custom `init(from:)`.
  - `GroupSnapshot` has one, in an extension so the memberwise init survives: `excuses`, `votes`, `posts` and `reactions` read with `decodeIfPresent ?? []`. A new stored property on it must be read there too.
  - `VoteRule` is Codable as one Int, its `code`, so a cache from before Custom (1, 2 or 3 there) still decodes. An unknown code throws and discards that cache, as an unknown raw value always did.
- **Preferences:** every key is `vow.*`. Remove each new key in `Preferences.clearAll()` too, which "Reset local data" uses. `vow.chatSeen` maps each zone to Chat's seen date.
- **Files:** drafts live in `Caches/vow-outbox` (emptied at launch, and a sent or discarded draft's files are deleted at once), post media in `Caches/vow-media`. `failedPosts`, drafts and the zone mirrors are memory only.

**Text**

- **Activity's wording:** Domain's ledger has no text; `Features/Activity/ActivityFeed.build` words `GroupSummary.days` once per render.
  - A day opens with who kept and who was excused ("You and Sam kept · Alex was excused", "Everyone kept", "Nobody kept", "Everyone was excused"), and ends with who joined or left.
  - Each stake lost ("Maya missed", "Your check-in was overruled", "Maya's excuse was overruled"; yours first) is followed by one ↳ line per keeper with their part (`amount / kept.count`), or by "Carried to <next day>" when nobody kept ("Left in the pot" after the final day).
  - The carried-in pot shows only on the day it is paid out ("Carried over from earlier days"), not on the days it passes through.
  - `ActivityFeedTests` pins the wording; change `ActivityFeed` and its tests together.
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
  - Tabs, page swipes, ≡, the edge swipe, Home's streak button and the foot's "Can't today?" are ignored while the room is dimmed (from the 200 ms gate through the seal); "Can't today?" is also ignored once sealed.
  - The orb's hold ignores movement, so a drag that began on it and moved within the dim gate can complete the hold with the room lit. On Home, while its orb can still be held (`Digest.isOpen`), a swipe is therefore never committed `MainView.homeSwipeLimit` (`OrbTiming.hold` − 2 × the dim gate, 1.0 s) or more after its first change.
  - Nothing else keeps Home on screen for such a hold, so any drag on Home that lasts `homeSwipeLimit` (any axis, a swipe or not) while the orb can still be held opens `SwipeGuard`'s window from the lift: `OrbTiming.sealDelay` (0.9 s) + 0.2 s. During it `selectTab` and new swipes are ignored (`SwipeGuard.owesSeal`).
  - Programmatic group or page changes (reselect after the background, an accepted invite, the vow prompt, a reminder tap) wait for `stageBusy` (dimmed, or `holdingLightID` set: through the social beat).
  - Leaving Home after the seal ends the cascade (`resetChoreography`): everything shows the store's values and the tab flame lights, and the keep's ≡ pulse and reminder offer that hadn't fired yet are delivered once (`deliverPendingKeep`). A reverted check-in delivers nothing.

---

## 6. Design system and product principles

**Visual direction: "quiet room, bright orb"**

- Chrome is neutral. The orb is the only bright, colourful thing.
- **Colour always means something:** flame = streak, gain/loss = points, the day's orb colours = kept today, green/red on a vote = its choice. The vote colours are their own roles (`Ink.voteCounts`, `voteAgainst` and their fills), though they share `gain`'s and `loss`'s hues: a vote isn't points.

**Use the tokens in `Design/Tokens.swift`:**

| Token | What it covers |
|---|---|
| `Ink` | Colour roles: `bg`, `card`, `text`/`text2`/`text3`, `flame*`, `gain`, `loss`, `scrim` (behind the sidebar, Chat's "+" card and the reaction picker), `flameEdge` (the milestone tag's border), `onFlame` (dark numerals on a kept calendar day), `missedDay` (the grey disc of a missed calendar day, or of today overruled), `chip` (your chat bubbles, your reaction's chip and its ring in the picker, the outline of a vote button you can't use), `voteCounts`/`voteAgainst` (a vote's green ✓ and red ✕), `voteCountsFill`/`voteAgainstFill` (your vote's whole button, with `text` on it), … |
| `Fonts` | Dynamic Type styles; SF Rounded for numbers only. `tabLabel` is a fixed 10 pt, like the system tab bar |
| `Gap` | 4-pt grid, plus `gutter`, `hit` 44, `orbSlot` 220, `tabBar` 49, `sidebarMax` 320 (the panel is 82 % of the width, at most this) |
| `Corner` | Always `.continuous`, except `BubbleShape`'s circular corners, which its tail must meet smoothly. `bubble` (18) is for chat bubbles and the composer's field |
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
- **Votes** are visible to the group (who voted what, with its ✓ or ✕, under a card's status row). Non-voters are never named; there is no anonymous voting and no list of who hasn't voted.
  - "Counts" carries a green ✓ and "Doesn't count" a red ✕ on an `Ink.field` button; your vote fills its whole button (`voteCountsFill`/`voteAgainstFill`). A compact card's two round buttons carry the same coloured glyphs.
  - Each choice's count sits just before its button (a zero in `text3`), with a wider gap (`Gap.xl`) before the "Doesn't count" number so it can't be read as the "Counts" one. The two stack when the row doesn't fit.
  - Without a vote to cast (your own claim, a day you don't take part in, voting closed) the buttons only show the counts: outlined, with your past vote still filled. They are hidden only when nobody has voted and you can't vote.
- **The voting rule** is a card on the Group tab ("Overrule with"). Only the owner changes it, while the vow runs, through `VoteRuleSheet`: More than half, Everyone, or Custom, a number of the others (1 to 99, in a "Votes needed" box) that takes all of them on a day fewer take part. Each choice shows what it takes among the other active members ("2 of 3 others"). The change applies from tomorrow, and the row says "{Rule} from tomorrow" until then ("2 votes from tomorrow"). A legacy Two thirds still in force shows as its title in the row, and the sheet then preselects nothing.
- **The owner's crown:** `OwnerCrown` (`crown.fill` in the name's own font, small, `Ink.text2`) sits by the owner's name on the Group page and in the member sheet. It is a role, not a status, so it is never coloured; VoiceOver hears "Maya, owner" (`MemberText.spokenName`).
- **Reactions** are for text messages: hold one to react, one emoji per member and message, and tap yours (in the picker or its chip) to take it back. Your chip is outlined on `Ink.chip`, others' sit on `Ink.field`. Nothing notifies anyone of a reaction; the chat dot counts others' reactions to your posts.
- **Streak calendar:** kept days (today included) are `Ink.flameGradient` discs with dark numerals, and a run joins into one capsule per week row, capped at row and month edges. Misses are grey discs. An excused day is a dashed `Ink.text3` ring that never joins a run (the band breaks, the streak doesn't). Today is a ring: dashed while excused, on a grey disc while overruled. ‹ › page from the month the group began to a year past the current month (or the final day's month, if later).
- **Keep it neutral and kind:**
  - No streak freezes, nudges, leaderboards or guilt-trip copy.
  - In today's status, friends show as "Not yet", "Excused today" or "Overruled", never "missed". Activity does say "Maya missed".
- **One engagement loop:** an optional daily local reminder, only on days a vow is still open (an excuse counts as done). It is offered once, after a real check-in that leaves no other vow open. Nothing notifies you of a message, vote, reaction or proof: CloudKit's pushes are silent and only sync.
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
  - A card's status line says what the buttons' counts and the "Overruled" tag don't: "2 needed to overrule · " then the window ("Voting ends tonight", "Voting ends tomorrow night"; a test group's "Voting ends when Day N begins"), and only the window once the claim is overruled. Once voting has closed it reads "Closed". `ChatText.status` builds it; a solo claim has none.
  - There is no success toast for a message, a vote, a reaction, proof or an excuse: the screen shows each one.

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
  - Use caseless `enum` namespaces for pure helpers (`DayClock`, `PointsText`, `ActivityFeed`).
  - Declare constants as typed `static let`.
  - Singletons are `static let shared`.
- **Access control:** use the default internal, plus `private` and `private(set)`. Don't use `public` or `fileprivate`.
- **Comments:**
  - No file headers. A file starts with its imports, then usually a `///` doc on the main type.
  - `///` docs are short and explain *why* and edge cases, often with a concrete example ("You and Sam kept · Alex was excused").
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
  - Use epoch-literal dates with a comment giving the local time. Use explicit zone IDs (NY, Tokyo, UTC). Pin the locale for date text (`DayText` and `ActivityFeed.build` take `locale:`; their tests use `en_US`).
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
  - Domain, including `ReviewTests` (thresholds incl. Custom counts, the window, eligibility, Settlement agreeing with `tally` and `tallies`, `proofDay`, the rule log, the vote-change margin (`canChangeVote`), rule codes and their JSON, a cache from before Chat and a rule log from before Custom decoding), `SettlementTests` (the structured `LedgerDay`s: splits, carries, forfeit reasons, today's joins and leaves, the day cap, the same ledger for every viewer), `ReactionsTests`, `EndDateTests` and `StreakCalendarTests`.
  - `Design/Formatters`, including `DayText` (`DayTextTests`) and `VoteRuleText`.
  - `Store/Overview`: the aggregates in `DigestTests`; `status`, `menuDot` and `theme(day:)` in `VowStatusTests`.
  - `Records`: the Excuse, Vote, Post and Reaction mapping (incl. `emojiLimit`), `voteRules` (incl. Custom codes) and `snapshotKeys` in `RecordsTests`; `endDay` in `EndDateTests`. Both import CloudKit but never touch a container.
  - `Features/Chat`: `ChatFeed` (order, sections, the range (the week up to the newest item, so a quiet chat or a finished vow opens on its last week) and Earlier, pointers, runs, the compact predicate, who may vote and change a vote, reaction chips and the picker's lookup) in `ChatFeedTests`, and `ChatText` (status lines, vote counts, headers, pointers, reactions' VoiceOver value and actions, the "+" card's header and excuse reasons, the vote lock) in `ChatTextTests`.
  - `Features/Activity`: `ActivityFeed` (an arrow per keeper with you first, the rounding of parts, every forfeit reason, the carry and where it goes, the carried-in pot, notes, quiet days, titles for test groups and other years) in `ActivityFeedTests`.
- These have **no tests**, so be extra careful there:
  - AppStore (merge, optimistic writes incl. `react`, `failedPosts`, `hasUnseenChat`, `refreshAll`'s coalescing and race logic)
  - CloudService (incl. the zone mirrors and the subscriptions), `ChangeInbox`, and Records' Group, Member and CheckIn mapping beyond `endDay`
  - Media: `MediaPrep` and `MediaCache`
  - The shell: `Presenter` (covers, `queued`), `MainView` (the sidebar gestures, `SwipeablePage` and `SwipeGuard`)
  - `ChatPage`'s scrolling, keyboard lift and reaction picker (placement, long press; device only), the Proof views and pickers, `MemberDay` and `KeptNote`
  - `ActivityPage`/`ActivityDayView` layout (the quiet line's `ViewThatFits`, the lazy list) and `VoteRuleSheet`
  - SnapshotCache and Preferences
  - ReminderCenter
  - DailySeed
- Put new rules in Domain so they can be tested.

**CloudKit schema changes**

- In the **Development** environment, CloudKit creates record types and fields automatically on the first save that includes them. A field written only on some paths (an optional value, an asset) exists only once one of those saves has run.
- **Production must be deployed by hand** in CloudKit Console before TestFlight or App Store builds. Tell the user whenever a change adds a field or record type.
  - **The latest addition is round 6's:** the record type `Reaction` (`userID`, `postID`, `emoji`, all String). Custom rules add no field: they are codes 101…199 in `Group.voteRules`. Round 5 added the field `Group.voteRules` (Int64 list) and the record types `Excuse` (`userID`, `day`, `epoch`, `text`), `Vote` (`voterID`, `subjectID`, `day`, `epoch`, `counts`, `castDay`) and `Post` (`authorID`, `text`, `day`, `epoch`, `isProof`, `mediaKind`, `aspect` and `duration` as Double, and the Asset fields `media` and `thumb`); IDs and text are Strings, and the rest Int64. Round 3 added `Group.endDay`.
  - **To create every field in Development**, with two Apple IDs in one group: as the owner, change the voting rule (Group → Overrule with); send an excuse; vote on the other's check-in or excuse in Chat; send a message; react to a message (hold it in Chat); add proof once as a photo (`aspect`, `media`, `thumb`) and once as a video (`duration`). README's schema section lists the same steps and a table of every field.
  - **Production must be deployed again for round 6.** Until `Reaction` is there, every reaction fails to save in TestFlight and App Store builds (and until round 5's schema is, every excuse, vote, message, proof and rule change). The zone fetch also names the new fields in `desiredKeys`, and whether Production accepts names it doesn't have yet is unverified (see Known issues), so deploy before shipping.
- Deployed fields can't be renamed, deleted or change type.
- The app never queries (it reads zones' changes), so no indexes are needed. Adding a `CKQuery` would need them. The database subscriptions need none either.
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
- **Client clock fallback.** `Records.checkInInfo` falls back to the client's `Date()` when a record has no `creationDate` (a fetched or saved record always has one). Excuses, votes, posts and reactions read as pending instead.
- **Two time zones.** Reminders use the device calendar, but group days use the group's `timeZoneID`. They can disagree for members in other zones; the impact is unverified.
- **Mixed builds and end dates.** Builds from before round 3 ignore `Group.endDay` and keep settling after the final day (forfeits, pots, streaks). A group with an end date shows different numbers on those members' devices until they update.
- **Mixed builds and round 5.** Builds from before round 5 ignore excuses and votes and have no Chat: there an overruled check-in still counts and an excused day is a miss, so those members see different points and streaks until they update. They also fetch zones without `desiredKeys`, so they download every post's photo, video and thumbnail on every refresh (each minute, with a nil change token): tens of MB a minute on cellular in a group that posts videos. Every member should update before anyone posts proof.
- **Mixed builds and round 6.** Round-5 builds ignore `Reaction` records (no chips, no dot for them) and skip rule codes of 100 and up, so on their devices a Custom rule reads as the rule before it (More than half if there was none): their verdicts, points and streaks differ until they update. Have every member update before the owner picks Custom.
- **A late vote change can still drop a vote.** A changed vote is one overwritten record, judged by its `modificationDate`, so a change the server takes after voting closes falls out of every tally (the earlier choice doesn't come back) and re-settles a closed day. `vote` refuses changes in a real group's last 30 min by the device clock; a device clock slower than that, or a save delayed that long, still loses the vote.
- **The rule log's limits.** It keeps the last 64 changes (`Review.ruleLogCap`); past that, the oldest days fall back to "More than half" and could re-settle (it takes 64 changes on separate days). It isn't scoped to an epoch either: after a test-group reset the old log still applies by day number until the owner changes the rule. That part affects test groups only.

**Sync and security**

- **Each launch downloads every zone in full once** (assets aside), because the zone mirrors are memory only; later fetches download only changes. Check-ins, excuses, votes, reactions and posts are never deleted, so that first fetch only grows. `refreshAll` still lists both databases' zones (two requests) and asks every zone for its changes, one after another in listing order, on every push, pull to refresh and return to the app, because a database push doesn't say which zone changed. With several groups, the open chat's zone may come last.
- **No retry or backoff, and pushes are best effort.** iOS may delay, coalesce or drop CloudKit's silent pushes; the polls (every 5 s on Chat, 15 s on other tabs, the shown group only) remain the fallback. None of the push path is verified on a device: delivery in the foreground and the background, whether CloudKit pushes to the device that made the change, re-saving the subscriptions on every launch, the 25 s answer deadline, a participant's shared-database subscription firing, the `.changeTokenExpired` path, and pushes on the Simulator. There is no `CKAccountChanged` observer. Nothing visible notifies anyone of a message, vote, reaction or proof. A failed post waits for a manual Retry.
- **The owner's iCloud storage holds everyone's data,** photos and videos included, and nothing prunes old posts. When it is full, members' check-ins, excuses, votes, reactions and posts fail ("The group owner's iCloud storage is full."), and only the owner can free space.
- **`desiredKeys` with names a record lacks is unverified on a device.** `Records.snapshotKeys` names every field of every type, so each record type lacks most of them, and before round 5's and round 6's schema is in Production some exist in no type at all. CloudKit is expected to skip such names; a fetch that rejected them would fail every refresh.
- **Authorization is client-side only.** The share is `.readWrite`, so any participant can write any record, a vote, an excuse or a reaction in someone else's name included. Owner-only actions (the voting rule among them) are gated only by `isOwner` in the UI.

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
- **Chat's scrolling is unverified on a device:** the bottom anchor over a `LazyVStack`, the sentinel-based `atBottom`, and the first-appear flag that keeps your place when the camera or the media viewer closes. Content arriving while you're scrolled up must not move the view. On iOS 17 the plain anchor also anchors size changes, so there a message arriving, a compact card opening up under your vote, or a reaction chip appearing may still shift what you are reading.
- **Reactions are unverified on a device:** the 0.3 s hold inside the feed's scroll view against scrolling and the tab swipe (with its empty-tap guard), the scroll that brings the held message into view, the picker following its bubble (`ReactionAnchorKey`), the scrim's cut-out, and whether the chips' large content viewer works inside the message's single VoiceOver element. A chip's touch area is about 42 pt tall, just under the 44 pt rule.
- **The "+" card's fix is diagnosed, not reproduced.** The old card was an overlay of the composer bar, so it was laid out in the bar's height: squeezed, clipped and placed too low. It now hangs off the feed area's bottom edge at its own height; confirm on a device, with and without the keyboard, that it sits whole just above the composer.
- **The tab swipe is unverified on a device:** whether `SwipeablePage`'s `.disabled`, turning on mid-touch, cleanly cancels a button's press and the orb's drag, and whether the leaving page really keeps the transition of its last render.
- **Home's swipe to the sidebar re-runs Home's body every frame,** as the edge swipe does on every page: the shell writes the panel's travel each frame (`PageSwipe.sidebar(travel:)`), and its new closures re-run `SwipeablePage` and `StageScreen` (one Settlement pass a frame). Moving the travel into a small observed reference read only by the sidebar layer would fix both.
- **After any drag of 1 s or more on Home while its orb is open** (`homeSwipeLimit`, any axis), tab taps and swipes are ignored for about 1.1 s from the lift (`SwipeGuard.owesSeal`), silently, even when no hold was under it. Picking another group from the sidebar during that window isn't guarded, so it could still take an owed seal's orb away.
- **A late `onDisappear` of an old `ChatPage`** (after the new Chat has reported) could clear `SwipeGuard.overlay` early, so a swipe could start over Chat's "+" card, picker or keyboard. An edge case; the reset on leaving Chat covers the usual order.
- **Activity's layout is unverified on a device:** whether a quiet day's note fits on its header line (`ViewThatFits`) where expected, and the ↳ arrow's baseline beside its line.
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
  - It says the orb disappears only on a day change (`.id(cycle-day)`) or a reset. The key is `zoneName-epoch-currentDay`, and the orb also leaves with a tab or group switch, a swipe included (which is why those wait while the room is dimmed).
- Code comments cite "SPEC §…" and "§6.x"/"§7" from a design spec that **isn't in the repo**. Treat them as labels.

**Tests**

- The single `VowText` test lives in `PointsTests.swift`.
