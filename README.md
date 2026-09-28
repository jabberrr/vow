# Vow

Vow is a small iOS 17 SwiftUI app about keeping one promise a day. You pick a daily vow, a crew and a stake. Each day you press and hold the orb to check in. When someone misses, their stake goes into a pot, and the pot is split among everyone who kept their vow that day. It's a prototype: no real money moves, the crew is simulated, and all state is stored locally in `UserDefaults`.

## Requirements

- Xcode 16 or later
- An iOS 17 (or newer) simulator
- No third-party dependencies, asset catalogs or resource files

## Run

1. Open `Vow.xcodeproj`.
2. Pick the **Vow** scheme and an iPhone simulator.
3. Press Run (⌘R).

To regenerate the project:

- **With XcodeGen** (the standard way on a Mac): `xcodegen generate`. It reads `project.yml`.
- **Without XcodeGen** (any machine with Python 3): `python3 scripts/gen_xcodeproj.py`. This produces the same setup, adds every `.swift` file under `Vow/`, and checks the `project.pbxproj` it writes. Run `python3 scripts/gen_xcodeproj.py --check` to check the committed project without rewriting it.

After you add, rename or delete a Swift file, run one of these commands.

## Layout

```
Vow/
  App/         App entry point (VowApp), RootView (switches between onboarding and main), MainView (scrolling column, demo bar, toasts)
  Store/       Models, VowStore (@Observable state and day and pot rules), Persistence (JSON in UserDefaults)
  Theme/       Palette, fonts, glass card modifier, ambient background
  Glyph/       Daily seed (FNV-1a + Mulberry32), constellation glyph model and Canvas renderer, creed lines
  Orb/         OrbView: the press-and-hold check-in, with a progress ring, burst effect and haptic
  Sound/       SoundEngine: build-up tone and a pop when you check in
  Onboarding/  Choose your vow, crew and stake
  Cards/       Header, vow, creed, streak, crew, pot and ledger cards, the demo bar, and the toast
project.yml               XcodeGen spec
scripts/gen_xcodeproj.py  Python generator for Vow.xcodeproj that doesn't need XcodeGen
```

## Demo bar

A day normally lasts a real day, so the bottom of the main screen has a demo bar for testing:

- **Advance to next day →** runs end-of-day: it records whether you kept today, collects forfeits, splits or carries the pot, updates the streak and ledger, and moves the crew to the next day. After day 30, a new cycle begins. Check in with the orb first to see a kept day; skip it to see a miss.
- **Reset** asks for confirmation, then clears the saved state and goes back to onboarding.

Your crewmates' results are generated from a seed based on the cycle and day, so the same day always plays out the same way.

## CI

`.github/workflows/ios.yml` runs on every push, on pull requests, and when started manually, using `macos-15` with the newest Xcode 16. It runs `xcodebuild` against the committed `Vow.xcodeproj` for the iOS Simulator with code signing turned off. It also runs two non-blocking checks:

- It rebuilds the project from `project.yml` with XcodeGen.
- It checks that the committed project matches what `scripts/gen_xcodeproj.py` generates.

If the build fails, the log is uploaded as the `build-log` artifact.
