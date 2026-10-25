# Vow

Vow is an iOS 17 SwiftUI app about keeping one promise a day, together. You make a group with friends, everyone writes their own vow, and each day you press and hold the orb to check in. If you miss a day, you lose your stake and it goes into the pot. The pot is split among the people who kept their vow that day.

- **Real groups over iCloud.** Groups, members, check-ins, excuses, votes and chat (reactions, photos and videos included) are stored in CloudKit, in the group owner's iCloud database, and shared with members through an iCloud share. There is no server of our own and there are no accounts beyond your Apple ID.
- **Points only.** No real money moves. Stakes, pots and balances are all points ("5 pts", "+1.33 pts").
- **Chat, proof and votes.** Each group has a chat where every check-in and excuse shows up, with any photo or video proof, and where you can react to messages with an emoji. A check-in or excuse counts unless enough of the group votes "Doesn't count" by the end of the next day.
- **Excuses.** Can't keep your vow today? Send an excuse instead of checking in. If it stands, the day sits out.
- **Invite links.** Anyone with a group's link can join.
- **Testing mode.** Lets you make test groups whose days you can move forward by hand.

## Requirements

- Xcode 16 or later, with iOS 17 or later on the device or Simulator.
- An Apple Developer account (paid membership) that can use iCloud/CloudKit. Without one, the app builds but can't reach CloudKit.
- To try more than one user: two Apple IDs on two devices (a Simulator counts, since it can sign into iCloud in Settings).
- No third-party dependencies.

## Setup

1. Set your bundle ID and team **without editing the project**:

   ```sh
   cp Config/Local.xcconfig.example Config/Local.xcconfig
   ```

   The bundle ID defaults to `app.dabora.vow` (in `Config/Vow.xcconfig`). To override it or set `DEVELOPMENT_TEAM`, use `Config/Local.xcconfig`, which git ignores. Don't type a bundle ID into Xcode's Signing pane: that writes it into the project file and conflicts with pulls.
2. Open `Vow.xcodeproj` and go to the **Vow** target → **Signing & Capabilities**. Check that your team is selected and that the iCloud section lists the container `iCloud.app.dabora.vow`, ticked and **not red**. Red means the container isn't registered on your team yet: press the refresh button, and if it stays red, press **+** and enter `iCloud.app.dabora.vow` to create it. The entitlements (`Vow/Vow.entitlements`) ask for CloudKit on that container and for push.
3. Sign into iCloud on the device or Simulator, then **Run** (⌘R) the **Vow** scheme.

### First run creates the schema (Development)

Debug builds run from Xcode use the CloudKit **Development** environment. There, CloudKit creates a record type or field the first time the app saves a record that has it. Some fields are written only on certain paths, so try each of these once, with two Apple IDs in one group, before you deploy:

- create a group, and join it from the second Apple ID,
- create a group with an end date (this adds `Group.endDay`),
- check in,
- as the owner, change the voting rule (**Group** tab → **Overrule with**; this adds `Group.voteRules`),
- send an excuse (**Can't today?** on Home) from an Apple ID that hasn't checked in that day,
- from the other Apple ID, vote on that excuse or on a check-in in **Chat**,
- send a chat message,
- react to a message (hold it in **Chat** and pick an emoji),
- add proof once as a photo and once as a video (the Simulator has no camera, so use **Choose from library** there),
- in a test group, advance a day and reset the group,
- leave a group.

Then check in CloudKit Console that every type has all of its fields:

| Record type | Fields (String or Int64 unless noted) |
|---|---|
| `Group` | `name`, `stake`, `createdAt` (Date/Time), `timeZoneID`, `isTest`, `testDay`, `epoch`, `ownerUserID`, `endDay`, `voteRules` (Int64 list) |
| `Member` | `userID`, `displayName`, `vow`, `joinedDay`, `joinedEpoch`, `leftDay` |
| `CheckIn` | `userID`, `day`, `epoch` |
| `Excuse` | `userID`, `day`, `epoch`, `text` |
| `Vote` | `voterID`, `subjectID`, `day`, `epoch`, `counts`, `castDay` |
| `Post` | `authorID`, `text`, `day`, `epoch`, `isProof`, `mediaKind`, `aspect` (Double), `duration` (Double), `media` (Asset), `thumb` (Asset) |
| `Reaction` | `userID`, `postID`, `emoji` |

The app doesn't run queries (it reads each zone's changes), so it needs no indexes.

> ### ⚠️ Before TestFlight or the App Store: deploy the schema to Production
>
> TestFlight and App Store builds use the CloudKit **Production** environment. Production starts empty, and the app can't create record types or fields there. Go to [CloudKit Console](https://icloud.developer.apple.com) → your container (`iCloud.app.dabora.vow`) → **Schema** → **Deploy Schema Changes…**, and deploy to Production. If you skip this, every save fails in TestFlight. If you later add a field in Development, deploy again. Chat added `Excuse`, `Vote`, `Post` and `Group.voteRules`: if you deployed before it, deploy again before shipping a build with Chat, or every excuse, vote, message, proof and voting-rule change fails to save. Reactions added `Reaction`: if you deployed before them, deploy again before shipping a build with reactions, or every reaction fails to save. (The **Custom** voting rule needs no new field.)

## How it works

**Groups.** A group has a name, a daily stake (1, 2, 5 or 10 pts) and members, and each member has their own vow. Days are real calendar days in the group's time zone, counted from the day the group was created.

**Getting around.** The app opens on your most urgent open vow. Each group has five tabs: **Home** (your vow, the orb, your streak, who kept today, and a quiet line under them: **Can't today?** before you check in, **Add proof** after), **Chat** (messages with their reactions, every check-in and excuse with its proof and votes), **Streak** (your streak and a month calendar of kept days, from the month the group began to a year ahead), **Activity** (every day's points: who kept, and an arrow from each stake lost to everyone who got a part of it) and **Group** (members, with a crown by the owner, invite, points, the voting rule, your vow, leave or delete). Swipe left or right on a page to move between tabs: the next page follows your finger, and comes in once you let go past a third of the way or flick (not while you're typing in **Chat** or its **+** menu or emoji picker is open). A small dot on **Chat** means someone else posted, sent an excuse, voted on your day or reacted to your message since you last looked. The sidebar (**≡**, a swipe from the left edge, or a swipe to the right on **Home**) lists your groups, **Add group**, **Settings** and you with your total balance; tap your name to change it.

**End dates.** A vow has no end unless you choose one when you create the group (**End date** → **Last day**). With an end date, Home shows "Day x of y" and the Streak calendar flags the last day. After the last day the vow is finished: nothing settles after it, nobody can check in or send an excuse and no reminders come. The group can still vote on the last day, and you can add proof for it, during the day after; the chat stays open. The end date is the field `Group.endDay`. Members still on an older build of the app keep settling days after the end until they update, so until then their numbers differ.

**Chat.** Every check-in and excuse appears in the group's chat as a card, with any proof inside it, alongside ordinary messages. The other members vote **Counts** (a green ✓) or **Doesn't count** (a red ✕) on each card. The number beside each button is how many voted that way, your vote fills its button green or red, and anyone can see who voted what. Hold a message to react with an emoji or copy it; tap your reaction, or its chip under the message, to take it back. While you type, tap anywhere in the chat above the message box to put the keyboard away.

**Sync.** When anything in a group changes, CloudKit sends the app a silent push (never a notification) and the app fetches what changed. As a fallback, the open group also refreshes every 5 seconds while **Chat** is shown, and every 15 seconds on the other tabs. Each refresh downloads only what changed since the last one, apart from the first after the app starts. To sync at once, pull down on **Streak**, **Activity** or **Group** (or on the first screen before you have a group); those pages otherwise hold still when they fit on screen.

**Proof.** Proof is a photo or video that shows the group you kept your vow. It's never required. When the check-in's animation is over, Home offers **Add proof** (take one, or choose one from your library); Chat's **+** offers the same. Proof goes on today's check-in or excuse, or on yesterday's while the group can still vote on it. Photos are sent at most 1,600 px on the long edge, and videos keep their first 20 seconds at 960×540. **Every member's photos and videos are stored in the group owner's iCloud storage**, because the group lives in the owner's database. If it fills up, members' check-ins, excuses, votes, reactions and posts fail until the owner frees space, and the app tells them whose storage is full.

**Excuses.** **Can't today?** on Home, or **+ → Excuse for today** in Chat, sends a short excuse (up to 280 characters) instead of checking in. It closes today's orb for good: you can't check in after it or take it back. If the group doesn't overrule it, the day sits out: you lose no stake, get no share of the pot, and your streak pauses (it neither breaks nor grows).

**Votes.** A check-in or excuse counts unless enough of the other members taking part that day vote **Doesn't count** by the end of the next day. If nobody votes, it counts, and in a group of one nothing can be overruled. How many it takes is the **voting rule** on the **Group** tab: **More than half** (the default), **Everyone**, or **Custom**: a number of the others (1 to 99) that the owner types in, or all of them on a day when fewer take part. A group already on **Two thirds**, which is no longer offered, keeps it until the owner picks another. Only the owner changes it, and a change applies from tomorrow, so a day already being voted on keeps its rule. Until voting on a day closes, that day's points and streaks can still change. You can change your vote until half an hour before voting on that day closes (in a test group, until it closes). In a test group, voting on a day ends when the owner moves two days past it.

**Invites.** Every group is a CloudKit record zone in the owner's private database, shared with a zone-wide iCloud share that anyone with the link can join. Any member can send the link with **Invite** (the last row of the members on a group's **Group** tab). When a recipient taps the link, iOS opens Vow (`CKSharingSupported` is set in `Info.plist`), the app accepts the share and then asks for their vow for that group. You can also paste a link with **≡ → Add group → Join with a link**. Invites work only between builds that use the same iCloud environment (see [Troubleshooting](#troubleshooting)).

**Points.** At the end of each day:

1. **Stake.** Every member who didn't keep their vow loses the group's stake: no check-in, or a check-in or excuse the group overruled.
2. **Excused.** A member whose excuse stands sits the day out: no stake lost, no share of the pot.
3. **Pot.** The lost stakes go into the pot.
4. **Split.** The pot is split equally among the members whose check-in stands.
5. **Carry.** If nobody kept, the pot carries over to the next day. If everyone was excused, nothing happens and the pot carries over untouched.

No device stores the results. Every device calculates them the same way from the shared check-in, excuse and vote records (`Domain/Settlement.swift`, with the votes counted in `Domain/Review.swift`), so everyone sees the same numbers. A check-in's or excuse's time comes from the iCloud server (the record's creation date), not the phone's clock, and one that reaches the server up to 10 minutes after midnight still counts for the day before. A vote's time is when the server last saw it change, and it counts if it arrives by the end of the next day, with the same 10 minutes' grace. Members still on a build from before Chat ignore excuses and votes, so their numbers differ until they update. Those builds also download every photo and video in the group on each refresh, which can use a lot of mobile data, so have every member update before anyone posts proof. Members on a build from before reactions don't see them, and they read a **Custom** voting rule as the rule before it, so their numbers differ until they update; have everyone update before the owner picks **Custom**.

**Reminders.** An optional daily local notification at a time you choose, only on days a vow is still open (an excuse counts as done).

**Testing mode.** Go to **≡ → Settings → Testing mode** and create a **test group**. Its day moves only when you, the owner, tap **Next day** (the test bar under the members on its **Home** tab). **Reset**, beside it, asks for confirmation, then starts the group over from its first day. Testing mode also shows **Reset local data**, which clears your profile, cache and downloaded photos and videos on this device. Real groups always follow the clock.

## Archive / TestFlight

1. Finish [Setup](#setup) with your own bundle ID and team.
2. **Deploy the CloudKit schema to Production** (see above).
3. Pick **Any iOS Device (arm64)** as the destination, choose **Product → Archive**, then **Distribute App → App Store Connect**.
4. If Xcode fails with `DistributionAppRecordProviderError`, the app has no App Store Connect record yet, or Xcode couldn't create one (often because the name is taken). Create it yourself: [App Store Connect](https://appstoreconnect.apple.com) → **Apps → + → New App**, pick your bundle ID, and use a unique name (e.g. "Vow – yourname"). Then distribute again.

The app uses an explicit `Vow/Info.plist` (`INFOPLIST_FILE`), which also holds the camera and microphone usage strings for proof (the library uses the system photo picker, which needs no permission) and the `remote-notification` background mode (`UIBackgroundModes`) for CloudKit's silent pushes, and a single 1024×1024 icon in `Vow/Assets.xcassets/AppIcon.appiconset`.

## Troubleshooting

**"Invite not found."** Builds run from Xcode use CloudKit's **Development** environment, and TestFlight and App Store builds use **Production**. The two keep separate data, so a group made in one, and its invite link, can't be found from the other. **≡ → Settings → About → iCloud** shows which one a copy of Vow uses: to share groups, everyone needs the same kind of build. A TestFlight build also needs the schema deployed to Production first (see the warning at the end of [Setup](#setup)), `cloudkit.share` included: Development gets that type when its first group is created.

**"The group didn't load yet."** You're in the group, but iCloud didn't show it within a few seconds. Open the link again in a minute.

## Layout

```
Vow/
  App/         Entry point (VowApp), root view, AppDelegate/SceneDelegate that pass accepted iCloud shares and CloudKit's silent pushes to the app
  Design/      Tokens and components: Sphere, FlameStreak, buttons, fields, sheet scaffold, the page scroll (still when a page fits, with its own pull to refresh); formatters
  Domain/      Pure Swift: group/member/check-in/excuse/vote/post/reaction models, DayClock, Settlement (points and the day-by-day ledger), Review (votes and verdicts), Reactions (chips per message), Points formatting, streak milestones, end date, streak calendar, cycle chain, digest, reminder plan
  Cloud/       CloudService (CloudKit zones, shares, records, fetches of what changed, push subscriptions, photo and video uploads), CloudEnvironment (which iCloud environment the build uses), record mapping, ShareInbox, ChangeInbox
  Media/       MediaPrep (photos and videos sized for sending), MediaCache (downloaded photos and videos on disk)
  Store/       AppStore (@Observable app state, incl. chat, excuses, votes and reactions), snapshot cache, preferences, Overview, and the stage and chat helpers
  Features/    Main (the shell: top bar, tab bar, the pager that swipes between tabs, sidebar, and the Presenter that shows every sheet and full-screen cover), Stage (Home), Chat (feed, claim cards, messages and reactions, composer), Proof (camera, library, proof sheet, media viewer), Streak, Activity (the day-by-day points), Group (incl. the voting rule and the owner's crown), Menu (Settings, Profile), Sheets (incl. the excuse), Root (onboarding, launch, problem)
  Reminders/   Daily reminder and its one-time offer
  Glyph/       Daily seed, constellation glyph and renderer
  Orb/         OrbView: press-and-hold check-in, ring, burst, haptic
  Sound/       SoundEngine: build-up tone and pop
  Info.plist, Vow.entitlements, Assets.xcassets
VowTests/      XCTest unit tests (Domain: day math, settlement and its ledger, votes and verdicts, reactions, end date, streak calendar, formatting, streaks, cycle chain, digest, reminder plan; record mapping; the iCloud environment and join messages; vow status; chat feed and wording; Activity's days), hosted in Vow.app
Config/        Vow.xcconfig (bundle ID + team, includes Local.xcconfig), Local.xcconfig.example
project.yml               XcodeGen spec
scripts/gen_xcodeproj.py  Python generator for Vow.xcodeproj that doesn't need XcodeGen
```

## Regenerating the project

After you add, rename or delete a Swift file in `Vow/` or `VowTests/`, regenerate the project:

- **With XcodeGen** (Mac): `xcodegen generate` (reads `project.yml`).
- **Without XcodeGen** (any machine with Python 3): `python3 scripts/gen_xcodeproj.py`. It produces the same setup (the app target, the `VowTests` target, the xcconfig and entitlements, and the shared `Vow` scheme whose Test action runs `VowTests`) and checks the project it writes. To check the committed project without rewriting it, run `python3 scripts/gen_xcodeproj.py --check`.

Run the tests with ⌘U in Xcode, or with:

```sh
xcodebuild test -project Vow.xcodeproj -scheme Vow -destination 'platform=iOS Simulator,name=iPhone 16'
```

## CI

`.github/workflows/ios.yml` runs on every push, on pull requests, and when started manually, using `macos-15` with the newest Xcode 16 and code signing turned off. Each run:

1. builds the committed `Vow.xcodeproj` for the iOS Simulator,
2. runs the `VowTests` unit tests on the newest available iPhone simulator,
3. archives an unsigned Release build and checks that the app icon and display name are in the archive.

Two checks are non-blocking: the project is also rebuilt from `project.yml` with XcodeGen, and the committed project is compared with the output of `scripts/gen_xcodeproj.py`. If a step fails, the log is uploaded as the `build-log` artifact.
