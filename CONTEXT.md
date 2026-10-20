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
- Every day each member **presses and holds the orb** to check in.
- If you miss a day, you lose the group's **stake** (1, 2, 5 or 10 pts) into the **pot**.
- The pot is split equally among those who kept their vow that day. If nobody kept, the pot carries over to the next day.
- **Points only.** No real money is involved.
- **No backend and no accounts.** Data lives in CloudKit:
  - Each group is a record zone in the owner's private database.
  - The zone is shared through a zone-wide `CKShare` that anyone with the link can join.
- **No third-party dependencies.**
- **iPhone only, portrait only, dark only.**
- **Testing mode** (Settings → Testing mode) creates test groups whose day the owner advances by hand.

**State as of 2026-10:** about 15k lines of Swift (tests included). `cc4da4c` redesigned the UI around a single **stage**. Round 3 added optional **end dates** (`f44253f`, `9b0bc7e`, `9a3980f`) and then replaced the dock and the cards under the stage with a **shell**: a top bar with ≡, four tabs per group (Home, Streak, Activity, Group) and a sidebar, with one `Presenter` for every sheet. Points, the orb, the glyph and sound were left unchanged; settlement changed only by the end-date stop rule.

**`README.md`** is the user-facing doc: setup, schema deployment, how points work and the repository layout. Keep it accurate whenever behaviour, setup or layout changes.

---

## 3. Repository map

```
Vow/
  App/        VowApp (entry, env injection, scene-phase refresh), RootView (screen routing, toast), AppDelegate+SceneDelegate (iCloud share acceptance)
  Domain/     PURE Swift, no UI or CloudKit: GroupModels, DayClock, Settlement, Standing, Streaks, EndDate, StreakCalendar, CycleChain (unused), Digest(+DayWindow), ReminderPlan, Points, VowText
  Cloud/      CloudService (CloudKit I/O, CloudError, CloudErrors), Records (CKRecord <-> models), ShareInbox (buffers accepted shares until the store is ready)
  Store/      AppStore (@MainActor @Observable app state), AppStore+Stage (read-only helpers), Overview (aggregates, VowStatus, MenuDot), SnapshotCache (JSON on disk), Preferences (UserDefaults)
  Design/     Tokens (Ink, Fonts, Gap, Corner, Anim, StageMetrics), Styles, Buttons, Fields, SheetScaffold, Feedback (toast, banner, tag), Sphere, Flame, Formatters (incl. DayText), OrbBridge
  Features/   Main (the shell: MainView, Presenter, TopBar, VowTabBar, Sidebar with ProfileRow and AddGroupMenu, MainTab)
              Stage (Home tab: StageScreen + parts, FinishedStage), Streak (StreakPage, StreakStatsCard, StreakCalendarView)
              Activity (ActivityPage, LedgerFormat, LedgerRow), Group (GroupPage, GroupMembersCard, MemberSheet)
              Menu (SettingsSheet, ProfileSheet), Sheets (NewGroup, JoinLink, InviteLink, Vow), Root (onboarding, status)
  Orb/        Press-and-hold check-in: OrbView, OrbHoldController, OrbTiming, ring, burst, active and sealed orb
  Glyph/      DailySeed (deterministic daily theme), GlyphModel, GlyphView (Canvas)
  Sound/      SoundEngine: synthesized build-up tone and pop (AVAudioEngine, no assets)
  Reminders/  ReminderCenter (@MainActor @Observable: local notifications and badge), ReminderOfferSheet
  Info.plist  Explicit; CKSharingSupported. Vow.entitlements pins iCloud.app.dabora.vow. Assets.xcassets holds one 1024 px AppIcon.
VowTests/     XCTest unit tests for Domain, Design/Formatters, Store/Overview and Records' endDay mapping, hosted in Vow.app
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
```

**Layering**

- **Domain is pure and deterministic.**
  - It is made of caseless `enum` namespaces and value-type structs.
  - It has no error types: it returns nil or false.
  - Put new rules here, with tests.
- **Cloud does I/O only.**
  - `CloudService.shared` is a `final class: @unchecked Sendable` with async/await. It is not an actor.
  - It creates the container lazily, so unit tests never touch CloudKit.
- **AppStore owns group and app state.** `ReminderCenter.shared` owns reminder state.
  - AppStore is `@MainActor @Observable final class`. State is `private(set)`. Bookkeeping fields are `@ObservationIgnored`.
  - **Offline first:** with a cached userID and cached snapshots, it starts in `phase = .ready`.
  - **Optimistic check-ins:** it inserts a pending check-in (`serverDate == nil`), saves it, then swaps in the server copy or rolls back.
  - **Test days:** `advanceTestDay` and `resetTestGroup` return early while either is running for that group (`testDayInFlight`), so a Next day can't save the old epoch back over a reset. The ignored tap is silent.
  - `persist()` runs after mutations and strips pending check-ins.
  - `refreshAll()` fetches snapshots one at a time. It diffs against the keys it had at the start, so groups created, joined or removed during a refresh behave correctly. `merged()` keeps confirmed and in-flight check-ins.
  - **There are two error paths:**
    - Create, join and accept go through `fail()`, which sets `lastError` (shown inside `NewGroupSheet` and `JoinLinkSheet`) and `toast`.
    - Everything else sets `toast = CloudErrors.message(error)` directly.
    - Network errors are suppressed when a cache exists.
  - **Settlement is not cheap.** Every `summary(for:)` or `summaries(now:)` call runs a full Settlement pass. Compute once per render and pass the result down. The shell memoizes `summaries` per minute (`SummaryMemo`) for the top bar, sidebar, tab bar and reminder sync; each page runs one `summary(for:)` per body for its group.
- **Views use the environment for shared objects.**
  - They get `@Environment(AppStore.self)` and `@Environment(ReminderCenter.self)`, injected in `VowApp`.
  - Child views take plain values and closures (for example the `StageActions` and `GroupActions` structs), with explicit `init`s.
  - Never use `ObservableObject`, `@EnvironmentObject` or `@Bindable`.
- **Unit tests are hosted in the app.** Any launch-time side effect must return early when `AppStore.isRunningUnitTests` is true.

**Screens**

- `RootView` picks one of: onboarding (no profile), `LaunchScreen`, `ProblemScreen` (no account, or failed with no cache), or `MainView`. It also owns the toast and `roomDimmed`, and gets `toastBlocked` and `topBarHeight` from the shell.
- `MainView` is the **shell**. It has **no `NavigationStack` and no push**:
  - A pinned `TopBar`: ≡ (opens the sidebar), the selected group's name, and the iCloud retry banner under it.
  - The selected group's page for the current `MainTab`: Home (`StageScreen`), `StreakPage`, `ActivityPage`, `GroupPage`. Pages are swapped instantly, not kept alive (the orb and its timers never run off screen). Re-tapping the selected tab bumps `topToken` (scroll to top). Switching group resets the tab to Home.
  - A pinned custom `VowTabBar`, shown whenever a group's page is (not a `TabView`: it dims with the room and avoids iOS 26's floating tab bar). No groups: `EmptyStage` and no tab bar; first sync of a fresh install: a spinner.
  - A `Sidebar` overlay: Add group (a custom menu: New group, Join with a link), your groups with today's status, Settings, and you with your balance. It opens from ≡ or a swipe from the 16 pt leading edge zone and closes on the scrim, a pick, a horizontal drag or VoiceOver escape. It is mounted only while out.
    - Its drags are `@GestureState`, so a drag the system cancels (a sheet, an alert, Control Center) resets itself; never hold a live drag in plain `@State`. Every close path works whenever the panel is visible, mid-drag included.
    - ≡ and the edge zone ignore input while the room is dimmed or the presenter isn't idle (a sheet must never rise over a reopened panel). An edge drag counts as busy for `.automatic` presentations.
    - A reminder tap waits while New group is open (not only while it saves): closing it would discard what you typed.
  - The 60 s refresh of the shown group (`.task(id: shownID)`, only while its snapshot exists) lives in the shell, so it runs on every tab. Every page also has pull to refresh.
- **Sheets and dialogs:** the shell owns `Presenter` (`Features/Main/Presenter.swift`, which also declares `MainSheet`, `MainDialog` and `PresentSource`). Its one `.sheet(item:)` and one `.confirmationDialog` are the only ones in the main experience.
  - Pages and chrome call closures that the shell wires to `presenter.present(_:from: .screen)` or `confirm(_:from: .screen)`. `.screen` means a real tap on the main screen.
  - Sheet bodies close with `dismiss()` and chain with `from: .sheet` (Create → Invite, your member sheet → Edit vow). They may host their own dialog (Settings → Reset local data).
  - The vow prompt and the reminder offer use `.automatic`. They wait while the shell is busy (`setBusy`: hold, cascade, open sidebar), and `isStillWanted` re-checks them just before they show. `didClose(.vow)` clears `pendingVowPrompt`. A reminder tap calls `dismissAll()`. The store and timers never touch presentation.
  - It can't wedge: presenting and dismissing end on a 1 s deadline even with no callback (a sheet whose content never appears is cleared and retried once), the latest tap wins and closes what is up, and nothing starts within a short settle after a dismissal or during `delay(for:)` (the shell's fade-in, every sidebar slide).
  - **Rules:** no SwiftUI `Menu` leads to a sheet or dialog (build a custom menu like `AddGroupMenu`; `from: .menu` exists for an unavoidable one and has no callers). Sheet bodies never render `EmptyView`: the content's `onAppear` is the presenter's proof that a sheet is up. No `fullScreenCover` from sheet bodies. No `presentationBackgroundInteraction(.enabled)` on shell sheets.
  - Check: `grep -rn "\.sheet(\|confirmationDialog(\|\.alert(\|fullScreenCover(\|\.popover(" Vow/Features` lists only `MainView` and sheet bodies.
  - Use `.vowSheet([...])` for detents and `SheetScaffold` for layout.
- **Toast:** RootView holds a toast while the room is dimmed. While a sheet, a dialog or the sidebar is up (`toastBlocked`, from the shell), it waits at most `Anim.toastWaitNanos` (1.5 s) from when it was raised, then it is dropped. It sits below the measured top bar and takes no touches.
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
  - A check-in is valid if its server `creationDate` falls on the same group day, or is less than 600 s into the next day. The boundary is exclusive: 00:09:59 is valid and 00:10:00 is not.
  - Test groups skip this check.
  - Logic: `Settlement.isValid`.
- **Clocks:** the **device** chooses `day`, and the **server** timestamp validates it. Don't move validation onto the device clock.
- **End date:**
  - `GroupInfo.endDay` (optional, the last stored property) is the index of the vow's final day, inclusive, in the group's day clock (test groups count `testDay`). nil means no end, the default.
  - It is set only at creation (`CloudService.createGroup(…endDate:…)`: at least 1, so the earliest end is tomorrow, and at most `EndDate.maxEndDay`) and never changes.
  - **Stop rule** (`Settlement`): a check-in with `day > endDay` is invalid. Once the clock passes `endDay`, the vow is finished: days 0…endDay settle exactly as they would without an end, and nothing settles after them.
  - A finished summary has `isFinished == true`, no open day (nobody is `checkedInToday`) and `currentDay == endDay + 1` for good. Code that means "today" or "yesterday" for a finished vow must use `DayClock.currentDay` or skip it (`ActivityPage.titleDay`, `Overview.yesterdayChange`).
  - A finished vow is never open (`Digest.isOpen`) and never reminded (`reminderGroups` skips it, and `ReminderGroup.endsAt` drops reminders after the final day). `AppStore.checkIn` and `setVow` return early on it.
  - Helpers: `EndDate` (`isFinished`, `dayCounter`, `finalDate`, `endsAt`) and `StreakCalendar` (`months`, `streakStartDay`/`streakStartDate`; `CalendarDay` carries its state, `isFinal`, `isStreakStart` and `groupDay`).
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
  - **Check-in records are never deleted.** `AppStore.merged` depends on this.
  - Check-ins from another epoch are ignored.
- **Membership:**
  - A member participates on a day when `effectiveJoinedDay ≤ day < leftDay`.
  - Leaving sets `leftDay = currentDay`, so a member who leaves isn't charged for today.
  - The owner can't leave; they delete the group instead.
- **Streaks:**
  - A streak is the trailing run of kept closed days, plus 1 if today is kept. An open today doesn't break a streak.
  - Milestones are `[3,7,14,30,50,100,150,200,250,300,365]`, then every 100 after that.
- **Cycle:** a cycle is 30 days. It is **display only, and the UI no longer shows it**: no "Cycle" and no "Day N of 30". `GroupSummary.cycle`/`dayInCycle` only seed the orb's daily theme. The pot and nets never reset per cycle. "Day x of y" appears only with an end date (`EndDate.dayCounter`).
  - The 30 is hard-coded in four places: `Settlement.swift` (`currentDay / 30`), `Overview.theme(day:)`, `Glyph/DailySeed.swift` (`glyphNumber`) and `CycleChain.length` (unused).
  - The daily theme is seeded from (cycle, day in cycle), so changing the length changes every day's colours.

**CloudKit records**

- **These names are part of the protocol.** Never rename them:
  - Record types `Group`, `Member` and `CheckIn`, and their field names (`Records.swift`).
  - Zone `group-<UUID>`.
  - Records `group`, `member-<userID>` and `checkin-<epoch>-<userID>-<day>`. These deterministic names make saves idempotent.
- **Field encoding:**
  - Ints and bools are stored as `Int64`.
  - `leftDay` is always written, with `-1` meaning active.
  - Decoding is lenient and falls back to defaults.
  - `Group.endDay` is optional: written only when set, absent means no end, clamped on read to 0…`EndDate.maxEndDay`. `Records.apply` never clears it, because a `GroupInfo` without it can only be stale (an older cache or build).

**Local state**

- **Cache compatibility:**
  - `SnapshotCache` decodes with `try?` and has no schema version. A new required field on a Codable domain model silently **discards every user's cache**.
  - Synthesized `Decodable` ignores property default values. A new field must be `Optional`, or the type needs a custom `init(from:)`.
- **Preferences:** every key is `vow.*`. Remove each new key in `Preferences.clearAll()` too, which "Reset local data" uses.

**Text**

- **Ledger text:**
  - `Features/Activity/LedgerFormat` parses the English ledger strings that Domain produces ("Day N · … · −2 pts").
  - SettlementTests pin those strings.
  - Change Domain, LedgerFormat and the tests together.
- **Glyph:** `Glyph/DailySeed` uses an exact port of JS `mulberry32` and FNV-1a. It must stay bit-for-bit deterministic.

**Orb and check-in**

- **Orb timing:**
  - `OrbTiming.hold = 1.4` is the single source for the ring, completion and the build-up tone.
  - `OrbBridge` keeps the old names alive for `Orb/` only. `Motion.dimGateNanos` must equal `Anim.dimGateNanos`.
  - The orb is remounted when the day changes or the group resets: `.id(orbKey)` with the key `zoneName-epoch-currentDay`.
- **Check-in reward cascade** (`StageScreen`, in this order):
  1. Settle: the caption agrees with the orb.
  2. Streak +1 with a flare.
  3. The social beat: your strip sphere (and the kept count) and the **Streak tab's flame** light together (`didLight`). Until then the shell's `holdingLightID` keeps the vow "open" everywhere (sidebar, tab bar).
  4. Milestone or new best, with embers and a success haptic.
  5. The **≡ glyph pulses once** if another vow is still open (`didKeep`).
  6. One-time reminder offer, only when no other vow is open, and never for a test group (`offerReminder`).
- **Layout during the cascade:** views show *held* values until their beat. Nothing changes height during check-in.
- **Keep the orb on screen until the seal.** `OrbHoldController.teardown()` drops a completed seal that hasn't reached `onSealed` (+0.9 s) when the orb leaves the screen. So:
  - Tabs, ≡, the edge swipe and Home's streak button are ignored while the room is dimmed (from the 200 ms gate through the seal).
  - Programmatic group or page changes (reselect after the background, an accepted invite, the vow prompt, a reminder tap) wait for `stageBusy` (dimmed, or `holdingLightID` set: through the social beat).
  - Leaving Home after the seal ends the cascade (`resetChoreography`): everything shows the store's values and the tab flame lights, and the keep's ≡ pulse and reminder offer that hadn't fired yet are delivered once (`deliverPendingKeep`). A reverted check-in delivers nothing.

---

## 6. Design system and product principles

**Visual direction: "quiet room, bright orb"**

- Chrome is neutral. The orb is the only bright, colourful thing.
- **Colour always means something:** flame = streak, gain/loss = points, the day's orb colours = kept today.

**Use the tokens in `Design/Tokens.swift`:**

| Token | What it covers |
|---|---|
| `Ink` | Colour roles: `bg`, `card`, `text`/`text2`/`text3`, `flame*`, `gain`, `loss`, `scrim` (behind the sidebar), `flameTint`/`flameEdge` (kept calendar days; the edge is also the milestone tag's border), … |
| `Fonts` | Dynamic Type styles; SF Rounded for numbers only. `tabLabel` is a fixed 10 pt, like the system tab bar |
| `Gap` | 4-pt grid, plus `gutter`, `hit` 44, `orbSlot` 220, `tabBar` 49, `sidebarMax` 320 (the panel is 82 % of the width, at most this) |
| `Corner` | Always `.continuous` |
| `Anim` | Named curves (incl. `sidebarIn`/`sidebarOut`, and `sidebarFade` under Reduce Motion) and the beat table in nanoseconds (incl. `toastWaitNanos`) |
| `StageMetrics` | Layout is compact when the safe-area height is under 700. Compact keeps the 44 pt milestone gap |

- **Colours** always come from `Ink`. The only exceptions are white/black opacity strokes and sheens.
- **Corners** come from `Corner`, and **text styles** from `Fonts`.
- **Spacing:** use `Gap` for new spacing. Small literal paddings exist in the code; don't add more.

**Reuse the existing components:**

- `PillButton`, `PressStyle`, `cardSurface()`
- `VowTextField`, `FormGroup`, `SwitchRow`
- `SheetScaffold`, `ToastBanner`, `InlineBanner`, `Tag`
- `Sphere`, which is the one status shape: lit, open or unlit.

**Product rules**

- **Hold the orb with zero taps.** The app opens on the Home tab of your most urgent open vow.
- **Colour only your own net.** Friends' nets stay `text2`, and the total balance is neutral. Of the totals, only your "Yesterday" change is coloured: the sidebar's reveal and the Profile sheet's stat.
- **The total balance lives with you:** the profile row at the bottom of the sidebar and the Profile sheet. The once-a-day "Yesterday" reveal plays when the sidebar opens (after a sync, with nothing up and the room lit). Your name is edited in the Profile sheet; Settings keeps reminder, testing and about.
- **≡ stays bare** except a flame dot while another of your vows is in its last 4 h (`Overview.menuDot`). No unread-style badges.
- **Test controls** (Next day, Reset) live only on Home's test bar. A finished test vow keeps the bar, with Next day disabled.
- **End dates are optional.** A group has no end unless New group's "End date" switch sets a "Last day" (tomorrow to a year out; 30 days by default). With one, Home shows "Day x of y" and the Streak calendar flags the final day. Afterwards Home shows `FinishedStage` and the sidebar says "Finished".
- **Keep it neutral and kind:**
  - No streak freezes, nudges, leaderboards or guilt-trip copy.
  - In today's status, friends show as "Not yet", never "missed". The ledger does say "Maya missed".
- **One engagement loop:** an optional daily local reminder, only on days a vow is still open. It is offered once, after a real check-in that leaves no other vow open.
- **At risk** means the last 4 hours of a real group's day (`DayWindow.atRiskSeconds`). It shows a flame ring on your open sphere (Home's strip, the sidebar row, the Group page, the calendar's today) and "· 3h left" in Home's caption; for another vow, the ≡ dot.

**Copy conventions**

- Use sentence case.
- End toasts and footers with a period ("Group created."). Buttons have no period.
- Use " · " as a separator, "…" for ellipses and U+2212 "−" for negatives.
- **Points** always read "pts" (`Points.format`), or "1 pt" where `PointsText` makes it singular.
  - In the UI, `PointsText` signs balances unless they are zero.
  - `Points.format(signed:)` prints "+0 pts".
- **Errors** in the create and join sheets read "Couldn't X. " followed by `store.lastError`.

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
  - Domain, including `EndDateTests` and `StreakCalendarTests`.
  - `Design/Formatters`, including `DayText` (`DayTextTests`).
  - `Store/Overview`: the aggregates in `DigestTests`; `status`, `menuDot` and `theme(day:)` in `VowStatusTests`.
  - `Records`' `endDay` mapping only (in `EndDateTests`, which imports CloudKit but never touches a container).
- These have **no tests**, so be extra careful there:
  - AppStore (merge and race logic)
  - CloudService, and Records beyond `endDay`
  - The shell: `Presenter`, `MainView` and the sidebar gestures
  - SnapshotCache and Preferences
  - ReminderCenter
  - LedgerFormat
  - DailySeed
- Put new rules in Domain so they can be tested.

**CloudKit schema changes**

- In the **Development** environment, CloudKit creates record types and fields automatically on the first save.
- **Production must be deployed by hand** in CloudKit Console before TestFlight or App Store builds. Tell the user whenever a change adds a field or record type.
  - The latest addition is `Group.endDay` (round 3). Until it is deployed to Production, creating a group with an end date fails in TestFlight and App Store builds; groups without an end never write the field.
- Deployed fields can't be renamed, deleted or change type.
- The app never queries (it reads whole zones), so no indexes are needed. Adding a `CKQuery` would need them.
- Read new fields with defaults, and keep the fetch-then-save `.changedKeys` pattern.

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
- **Client clock fallbacks.** When the server date is missing, `serverDate` falls back to the client's `Date()` (`CloudService.swift`, `Records.swift`).
- **Two time zones.** Reminders use the device calendar, but group days use the group's `timeZoneID`. They can disagree for members in other zones; the impact is unverified.
- **Mixed builds and end dates.** Builds from before round 3 ignore `Group.endDay` and keep settling after the final day (forfeits, pots, streaks). A group with an end date shows different numbers on those members' devices until they update.

**Sync and security**

- **Every refresh downloads every zone in full** (nil change token), one group after another. Check-ins are never deleted, so the data only grows.
- **No retry or backoff, no subscriptions or push.** The `aps-environment` entitlement is unused, and there is no `CKAccountChanged` observer.
- **Authorization is client-side only.** The share is `.readWrite`, so any participant can write any record. Owner-only actions are gated only by `isOwner` in the UI.

**Dead code**

- `AppStore.theme(for:)`, `themeCache` and `totalBalance` have no callers.
- `MemberStatus` and `MemberStanding.status(isViewer:)` in `Standing.swift` are used only by tests, and they label friends "missed". Don't wire them into the UI.
- `VowApp`'s `.onOpenURL` is likely dead. There is no `CFBundleURLTypes`, and share links arrive through `SceneDelegate`. Not confirmed on a device.
- `CycleChain` and `ChainBead` are used only by `CycleChainTests`. Delete both together.

**UI**

- `InviteLinkSheet.copied` never resets, so a second Copy gives no haptic.
- `OrbBurst` ignores Reduce Motion.
- The Tasks started by `FlameStreak.flare` are never cancelled on disappear.
- `vowSheet` sets `presentationCornerRadius(Corner.sheet)`, which overrides iOS 26's device-matched corners on floating detented sheets. This is visual only and unverified on a device.

**Duplicated constants** (keep each set equal)

- `Motion.dimGateNanos` and `Anim.dimGateNanos`
- `MainView.crossfade` (0.35 s) and `Anim.screen`
- The sidebar slide: `MainView.sidebarSlide` (0.35 s) and `ProfileRow.revealDelayNanos` (the slide + 300 ms) assume that `Anim.sidebarIn`/`sidebarOut` settle within 0.35 s.
- `RootView.barHeight` (52, used until the shell measures the bar) = TopBar's 44 pt row + 2 × `StageMetrics.regular.barPadding`
- The orb size: literal `220` throughout `Orb/`, and `Gap.orbSlot`
- `vowTapPadding` in `StageCenter` and in `EmptyStage`
- The 700 pt compact threshold, which is repeated in `OnboardingScreen`
- The cycle length of 30, in four places (see Invariants)

**Stale docs**

- `Config/Local.xcconfig.example` and the README's Production-deploy note still describe the container as `iCloud.<bundle ID>`. It is pinned to `iCloud.app.dabora.vow`.
- README says leaving a group "adds `Member.leftDay`", but `leftDay` is always written.
- The `teardown` doc comment in `OrbHoldController` is out of date:
  - It mentions `store.seal()`, but the closure now goes through `handleSealed` to `store.checkIn`.
  - It says the orb disappears only on a day change (`.id(cycle-day)`) or a reset. The key is `zoneName-epoch-currentDay`, and the orb also leaves with a tab or group switch (which is why those wait while the room is dimmed).
- Code comments cite "SPEC §…" and "§6.x"/"§7" from a design spec that **isn't in the repo**. Treat them as labels.

**Tests**

- The single `VowText` test lives in `PointsTests.swift`.
