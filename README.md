# Vow

Vow is an iOS 17 SwiftUI app about keeping one promise a day, together. You make a group with friends, everyone writes their own vow, and each day you press and hold the orb to check in. If you miss a day, you lose your stake and it goes into the pot. The pot is split among the people who kept their vow that day.

- **Real groups over iCloud.** Groups, members and check-ins are stored in CloudKit, the group owner's iCloud database, and shared with members through an iCloud share. There is no server of our own and there are no accounts beyond your Apple ID.
- **Points only.** No real money moves. Stakes, pots and balances are all points ("5 pts", "+1.33 pts").
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

   In `Config/Local.xcconfig`, set `PRODUCT_BUNDLE_IDENTIFIER` (an ID you own, e.g. `com.yourname.vow`) and `DEVELOPMENT_TEAM` (your Team ID). Git ignores this file. `Config/Vow.xcconfig` includes it and holds the placeholders `com.example.vow` and an empty team.
2. Open `Vow.xcodeproj` and go to the **Vow** target → **Signing & Capabilities**. Check that your team is selected and that the iCloud section lists the container `iCloud.<your bundle ID>` with a check next to it. If it doesn't, press **+** to add the container or the refresh button to reload it. The entitlements (`Vow/Vow.entitlements`) ask for CloudKit on `iCloud.$(CFBundleIdentifier)` and for push.
3. Sign into iCloud on the device or Simulator, then **Run** (⌘R) the **Vow** scheme.

### First run creates the schema (Development)

Debug builds run from Xcode use the CloudKit **Development** environment. There, CloudKit creates the record types `Group`, `Member` and `CheckIn` and their fields the first time the app saves one. To create every field, try each path once before you deploy:

- create a group,
- join it from a second Apple ID,
- check in,
- in a test group, advance a day and reset the group,
- leave a group (this adds `Member.leftDay`).

The app doesn't run queries (it reads whole zones), so it needs no indexes.

> ### ⚠️ Before TestFlight or the App Store: deploy the schema to Production
>
> TestFlight and App Store builds use the CloudKit **Production** environment. Production starts empty, and the app can't create record types or fields there. Go to [CloudKit Console](https://icloud.developer.apple.com) → your container (`iCloud.<bundle ID>`) → **Schema** → **Deploy Schema Changes…**, and deploy to Production. If you skip this, every save fails in TestFlight. If you later add a field in Development, deploy again.

## How it works

**Groups.** A group has a name, a daily stake (1, 2, 5 or 10 pts) and members, and each member has their own vow. Days are real calendar days in the group's time zone, counted from the day the group was created. A cycle is 30 days, and the cycle is only used for display.

**Invites.** Every group is a CloudKit record zone in the owner's private database, shared with a zone-wide iCloud share that anyone with the link can join. Any member can send the link with the share button. When a recipient taps the link, iOS opens Vow (`CKSharingSupported` is set in `Info.plist`), the app accepts the share and then asks for their vow for that group. You can also paste a link with **Join with link** on the home screen.

**Points.** At the end of each day:

1. **Stake.** Every member who didn't check in loses the group's stake.
2. **Pot.** Those stakes go into the pot.
3. **Split.** The pot is split equally among the members who kept their vow that day.
4. **Carry.** If nobody kept, the pot carries over to the next day.

No device stores the results. Every device calculates them the same way from the shared check-in records (`Domain/Settlement.swift`), so everyone sees the same numbers. A check-in's time comes from the iCloud server (the record's creation date), not the phone's clock. A check-in that reaches the server up to 10 minutes after midnight still counts for the day before.

**Testing mode.** Go to **Settings → Testing mode** and create a **test group**. Its day moves only when you, the owner, tap **Advance to next day →** in the test bar. **Reset group** asks for confirmation, then starts the group over from its first day. Testing mode also shows **Reset local data**, which clears your profile and cache on this device. Real groups always follow the clock.

## Archive / TestFlight

1. Finish [Setup](#setup) with your own bundle ID and team.
2. **Deploy the CloudKit schema to Production** (see above).
3. Pick **Any iOS Device (arm64)** as the destination, choose **Product → Archive**, then **Distribute App → App Store Connect**.
4. If Xcode fails with `DistributionAppRecordProviderError`, the app has no App Store Connect record yet, or Xcode couldn't create one (often because the name is taken). Create it yourself: [App Store Connect](https://appstoreconnect.apple.com) → **Apps → + → New App**, pick your bundle ID, and use a unique name (e.g. "Vow – yourname"). Then distribute again.

The app uses an explicit `Vow/Info.plist` (`INFOPLIST_FILE`) and a single 1024×1024 icon in `Vow/Assets.xcassets/AppIcon.appiconset`.

## Layout

```
Vow/
  App/         Entry point (VowApp), root view, AppDelegate/SceneDelegate that pass accepted iCloud shares to the app
  Domain/      Pure Swift: group/member/check-in models, DayClock, Settlement (points), Points formatting
  Cloud/       CloudService (CloudKit zones, shares, records), record mapping, ShareInbox
  Store/       AppStore (@Observable app state), snapshot cache, preferences
  Home/        Balance, group list, create group, join with link
  Group/       Group screen (orb, members, pot, ledger, share link), test bar
  Settings/    Display name, testing mode, reset local data
  Onboarding/  Pick a display name
  Cards/       Shared cards and the toast
  Theme/       Palette, fonts, glass card modifier, ambient background
  Glyph/       Daily seed, constellation glyph and renderer, creed lines
  Orb/         OrbView: press-and-hold check-in, ring, burst, haptic
  Sound/       SoundEngine: build-up tone and pop
  Info.plist, Vow.entitlements, Assets.xcassets
VowTests/      XCTest unit tests (Domain: day math, settlement, formatting), hosted in Vow.app
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
