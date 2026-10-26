# Spike A: iPad external display

*M0, 2026-10-25. Code: `Spikes/ExternalDisplay/` (throwaway). Status: Simulator verification done; hardware checklist for Ben below.*

## TL;DR

- **Recommendation for M4:** declare a scene configuration for `UIWindowSceneSessionRoleExternalDisplayNonInteractive` in the Info.plist scene manifest and render the audience surface in that scene from the shared `SessionState`. Treat its `willConnect`/`didDisconnect` as the display hot-plug events. This worked in every Simulator test: scene present at launch when the display is already attached, created within ~100 ms on hot-plug, torn down on unplug, counter shared with the iPad screen.
- **There is no API to put a scene on a chosen screen.** When Stage Manager uses the external display as an extended desktop, only the user can move a window there. The spike ships a second path for that case: an ordinary application window showing the audience view that the user drags onto the external display. iOS tells the app when that happens (`windowScene(_:didUpdateEffectiveGeometry:)`, "always called when a UIWindowScene moves between screens").
- **Unverified in the Simulator, needs Ben's iPad + HDMI:** whether iPadOS still creates the non-interactive scene while Stage Manager extends the desktop, what the TV shows while the app is backgrounded (the Simulator kept showing our audience view; real iPads are expected to fall back to mirroring), and how fast the scene comes back.
- **Xcode 27.1 detail that matters for all later milestones:** there is no Simulator.app any more and the new DeviceHub.app has no External Displays menu. The external display is attached from the terminal instead: `xcrun simctl io <udid> screenConfig --display=external power on`.

## What was built

`Spikes/ExternalDisplay/project.yml` (XcodeGen), one iOS app target `SpikeExternalDisplay`, bundle id `dev.lectern.spike.externaldisplay`, iOS 26.0, Swift 6 language mode with strict concurrency and warnings as errors. Build is clean (zero warnings).

| File | Purpose |
|---|---|
| `Sources/AppDelegate.swift` | Picks the scene configuration per connecting session (`Presenter`, `Audience`, or `AudienceWindow` when the activity `dev.lectern.spike.audience-window` is present) and logs discards. |
| `Sources/SceneDelegates.swift` | `PresenterSceneDelegate` (iPad screen) and `AudienceSceneDelegate` (used for both the system external-display scene and the draggable audience window). Every lifecycle callback is logged. |
| `Sources/SpikeModel.swift` | `@MainActor @Observable` singleton: counter, event log, list of connected `UIWindowScene`s, the two explicit scene requests, and the URL handler. |
| `Sources/PresenterView.swift` | Counter with −1/+1, live scene list (role, activation state, screen bounds/scale/native size, modes, mirroring), the two second-path buttons, event log. |
| `Sources/AudienceView.swift` | Huge counter on orange (system external scene) or purple (application window) with the view size. `.ignoresSafeArea()` because the external scene reports a safe-area inset (720×423 of 720×480 without it). |

Logging: `os_log` subsystem `dev.lectern.spike`, category `externaldisplay`. Follow it with

```sh
xcrun simctl spawn <udid> log stream --predicate 'subsystem == "dev.lectern.spike"' --style compact
```

Terminal control without touching the screen (the first use shows an "Open in Spike ExtDisplay?" prompt that must be tapped once):

```sh
xcrun simctl openurl <udid> 'lectern-spike://add?n=1'     # also set?n=, and window (opens the audience window)
```

### Build and run in the Simulator

```sh
cd Spikes/ExternalDisplay && xcodegen generate
UDID=3EE7277C-E5B1-49B8-B349-3458724EDC97   # iPad Pro 13-inch (M5), iOS 26.5
xcodebuild -project SpikeExternalDisplay.xcodeproj -scheme SpikeExternalDisplay \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath build/DerivedData build | xcbeautify
xcrun simctl boot $UDID; open /Applications/Xcode.app/Contents/Applications/DeviceHub.app
xcrun simctl install $UDID build/DerivedData/Build/Products/Debug-iphonesimulator/SpikeExternalDisplay.app
xcrun simctl launch $UDID dev.lectern.spike.externaldisplay
xcrun simctl io $UDID screenConfig --display=external power on      # attach the external display
xcrun simctl io $UDID screenshot --display=external ext.png          # what the "projector" shows
xcrun simctl io $UDID screenshot --display=internal ipad.png
```

`xcodebuild` refuses to build when a `configFiles:` entry points at a missing file ("Unable to open base configuration reference file"), even with XcodeGen's `missingConfigFiles` validation disabled. The project therefore uses a committed `Signing.xcconfig` that does `#include? "../../Config/Local.xcconfig"`, so Simulator builds work without Ben's file and device builds pick it up when present (see `Config/README.md`).

### Simulator external display facts (Xcode 27.1, iOS 26.5 runtime)

- `screenConfig --display=external power on` adds a screen named `TVOut`, 720×480 @1x, sRGB. It appears to UIKit as `UIScreen` 720×480 with `availableModes = [720×480]`.
- `screenConfig --display=external geometry 1920x1080` only resizes the framebuffer (screenshots become 1920×1080 with the 720×480 scene in the top-left corner). UIKit still reports 720×480. Changing geometry while the screen is on **disconnects the external scene and it does not come back until the screen is power-cycled**; set the geometry while it is off if a 1080p framebuffer is wanted.
- The Simulator never mirrors the iPad to `TVOut`: with no app scene it is black, and it kept showing our audience scene while the app was in the background. Do not read anything about real-world mirroring from the Simulator.
- Clicks can be driven from the terminal with a small CoreGraphics event poster (the AppleScript `click at` did not reach the device view); the scratchpad script used for that is not part of the repo.

## Verified in the Simulator

| # | Test | Result |
|---|---|---|
| 1 | Launch with the display already attached | Presenter scene connects, then `configurationForConnecting role=externalDisplayNonInteractive` and the Audience scene connects and becomes active before the presenter does. Works on a fresh install and on relaunch (old external sessions are reported in `didDiscardSceneSessions`). |
| 2 | Hot-plug while running (`power on`) | ~100 ms from the command to `willConnect`. iOS connects, disconnects and reconnects the external scene once within 120 ms (willConnect → didBecomeActive → didDisconnect → willConnect → didBecomeActive). Code must survive two connects without duplicating state. |
| 3 | Unplug (`power off`) | `didDisconnect` on the Audience scene; nothing else changes; the presenter keeps running. |
| 4 | Shared counter | +1 taps on the iPad and `lectern-spike://add?n=7` update the big number on the external display immediately (`docs/spikes/images/A-external.png`). |
| 5 | `UISceneSessionActivationRequest(role: .windowExternalDisplayNonInteractive)` | Fails: `UISceneErrorDomain` code 1, "Scene session activation failed because the requested role "UIWindowSceneSessionRoleExternalDisplayNonInteractive" is not supported." Only the system creates this scene. |
| 6 | `UISceneSessionActivationRequest(role: .windowApplication)` with the audience activity | Works. In the default "Windowed Apps" mode the new window opened full-screen on the iPad and the presenter scene went to `background`. The session restores on relaunch with its `AudienceWindow` configuration (no `configurationForConnecting` call for restored sessions). |
| 7 | Backgrounding (launch Safari) | Order: PRESENTER willResignActive, AUDIENCE-EXT willResignActive, AUDIENCE-EXT didEnterBackground, PRESENTER didEnterBackground. The external display kept showing our scene (Simulator artefact, see above). Foreground again: willEnterForeground for both, didBecomeActive for the presenter; the external scene was reused, not recreated, same process. |
| 8 | Stage Manager (Settings → Multitasking & Gestures → Stage Manager) with `TVOut` attached | No change: the non-interactive scene stayed on the external screen, no extended desktop appeared. The Simulator's `TVOut` does not do extended desktop, so this case is **not verifiable here**. The Simulator was put back to "Windowed Apps". |
| 9 | Safe area on the external scene | Non-zero: content was laid out in 720×423 until `.ignoresSafeArea()`. |
| 10 | `screen.mirrored` | Non-nil ("mirrors another screen") while the external scene is connecting, nil once our window is shown. |

Screenshots: `docs/spikes/images/A-presenter.png` (iPad: counter, scene list with the EXTERNAL badge, event log) and `docs/spikes/images/A-external.png` (the `TVOut` framebuffer).

## Stage Manager / extended desktop: what the SDK says

Checked in the iOS 27.1 SDK headers (`.../iPhoneOS.sdk/System/Library/Frameworks/UIKit.framework/Headers`):

- `UIWindowScene.h`: `UIWindowSceneSessionRoleExternalDisplayNonInteractive` ("A session role which defines an interface for a non-interactive external display", iOS 16+); the older `UIWindowSceneSessionRoleExternalDisplay` is deprecated in favour of it. No role for an interactive external display exists.
- `UISceneSessionActivationRequest.h` (iOS 17+): `+requestWithRole:`, `+requestWithSession:`, `userActivity`, `options`. No screen or display parameter. Requesting the external role is rejected at runtime (test 5).
- `UISceneOptions.h`: `UISceneActivationRequestOptions` has only `requestingScene` on iOS; `collectionJoinBehavior` is Mac Catalyst only. Nothing selects a screen.
- `UIWindow.h`: `screen` is still readable; the setter `setScreen:` was deprecated in iOS 13 "with replacement setWindowScene:". A window is on whatever screen its scene is on.
- `UIScreen.h`: `+screens` deprecated in iOS 16 ("Use UIApplication.shared.openSessions to find open sessions with scenes from other screens"); `UIScreenDidConnectNotification`/`DidDisconnect` deprecated in iOS 16 ("Use UISceneDelegate or related notifications"); `mirroredScreen` still exists ("Moving a UIWindow to this screen will disable mirroring"); `availableModes`, `preferredMode`, `currentMode` (settable) remain.
- `UIWindowScene.h` delegate: `windowScene:didUpdateEffectiveGeometry:` (iOS 26) is documented "Always called when a UIWindowScene moves between screens". `UIWindowScene.displayLinkWithTarget:selector:` (iOS 27) "is automatically retargeted when the scene moves between displays". So UIKit anticipates scenes moving between screens; the move itself is user-driven.
- `UITraitCollection.h`: `sceneCaptureState` (iOS 17, `UISceneCaptureState` inactive/active) "represents whether a scene is currently being mirrored or recorded". Useful for the "switching apps exposes the iPad screen" warning in SPEC §7.

Conclusion: in extended-desktop mode the app cannot place its audience window; it can only offer one and detect where it ended up. Whether iPadOS additionally keeps the non-interactive scene alive in that mode is a hardware question.

## Recommended approach for M4 (SPEC §7)

1. **Primary path, zero configuration:** external-display scene with the non-interactive role, exactly as in this spike. The audience surface is a CALayer-backed view that fills the scene's window (`ignoresSafeArea`) and renders from `SessionState`. Expect the scene before `didBecomeActive` of the presenter, expect one connect/disconnect/connect bounce on hot-plug, and keep the presenter running when it disconnects (SPEC §6.1 hot-plug semantics apply unchanged).
2. **Extended-desktop path:** if a display is attached but no external scene arrives within ~2 s (or when the user asks), show "Open audience window" which activates an application scene carrying an `audience` user activity. Watch `didUpdateEffectiveGeometry`: when the scene's `screen` is no longer the iPad's screen, switch that window to the audience rendering and lock its UI; tell the user to make it full screen. Persist the session via `stateRestorationActivity` so it comes back after relaunch. Do not make this window the key window.
3. **Mirroring guard:** on `sceneDidEnterBackground` of the presenter scene mark the audience state as "possibly mirrored"; on return check `traitCollection.sceneCaptureState` and the external scene's presence, and show the one-time warning from SPEC §7.
4. **Prefer the external scene whenever both exist**, and render the audience window as a plain copy only when the external scene is absent, so nothing presenter-only can leak to the projector.
5. Pending Ben's results on backgrounding, add `UIApplication.shared.isIdleTimerDisabled = true` while presenting and advise against Stage Manager unless the extended-desktop path proves reliable.

## Open questions (for the hardware test)

- Does iPadOS 26/27 still create the non-interactive scene when Stage Manager has the external display as an extended desktop? If yes, the primary path covers everything and the audience-window path is only a fallback.
- What does the TV show while the app is backgrounded or the iPad is locked, and how long does the external scene take to come back?
- Does the default iPadOS 26 "Windowed Apps" mode mirror or extend the external display?
- Which resolution does the iPad drive the TV at (shown as "screen modes" in the scene list), and is it the TV's native one?

## Ben device checklist

Everything below runs from the terminal except the taps on the iPad. The iPad named "BL iPad" (iPadOS 27.0.1) is already visible to this Mac in DeviceHub, so no pairing should be needed.

**One-time setup**

1. `cp Config/Local.xcconfig.example Config/Local.xcconfig` and put your Team ID in `DEVELOPMENT_TEAM` (read the `OU=` field of `security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject`, or developer.apple.com → Membership; Xcode 27 no longer shows it in Settings).
2. Xcode must be signed in to that Apple ID once (Xcode → Settings → Accounts → +). This lets `xcodebuild` create the signing profile itself.
3. `xcrun devicectl list devices` and note the identifier of "BL iPad".

**Build, install, run**

```sh
cd Spikes/ExternalDisplay && xcodegen generate
xcodebuild -project SpikeExternalDisplay.xcodeproj -scheme SpikeExternalDisplay \
  -destination 'platform=iOS,name=BL iPad' -allowProvisioningUpdates \
  -derivedDataPath build/DerivedData build | xcbeautify
xcrun devicectl device install app --device <identifier> build/DerivedData/Build/Products/Debug-iphoneos/SpikeExternalDisplay.app
xcrun devicectl device process launch --device <identifier> dev.lectern.spike.externaldisplay
```

The first launch of an app signed with your developer certificate stops with "Untrusted Developer": on the iPad go to Settings → General → VPN & Device Management, tap your Apple ID under Developer App, tap Trust, then launch again. The app's own event list (bottom of the screen, text is selectable) is the log; Console.app on the Mac with the iPad selected and filter `dev.lectern.spike` shows the same lines.

**Test 1, default mode, plug after launch.** Settings → Multitasking & Gestures must be on "Windowed Apps" (the default) or "Full Screen Apps". Launch the spike, then connect the USB-C→HDMI adapter and TV. Expected: the TV shows the orange "AUDIENCE: external display scene" view; the scene list gets an "Audience EXTERNAL" row. Record the screen bounds, scale and "screen modes" of that row (this is the resolution the iPad drives the TV at). Tap +1 three times: the TV number must follow instantly. Note whether the events show one or two willConnect lines.

**Test 2, plug before launch.** Quit the app (swipe up, swipe it away), keep the TV connected, launch again. Expected: the external row is present immediately and the TV shows orange, not a mirror of the iPad.

**Test 3, unplug and replug mid-session.** Pull the HDMI cable, wait 5 s, plug it back. Record what the TV shows in between (black? mirror?), the events (didDisconnect, then willConnect), and roughly how long the orange view takes to return.

**Test 4, backgrounding.** With the TV connected, press Home (or swipe up). Record what the TV shows (expected: a mirror of the iPad home screen). Open the spike again from the app switcher. Record what the TV shows, how long until orange returns, and whether the events show only willEnterForeground/didBecomeActive (scene kept) or a fresh willConnect (scene recreated). Repeat once by locking the iPad with the top button and unlocking.

**Test 5, Stage Manager / extended desktop.** Settings → Multitasking & Gestures → Stage Manager. With the TV connected, the TV should become a second desktop (its own Dock, no mirroring). Launch the spike and record: (a) is there still an "Audience EXTERNAL" row and does orange appear on the TV, or does the TV stay a desktop? (b) Tap "Open audience window (application scene)". A purple window opens. Drag it by its top edge onto the TV (or use the window's ••• menu if it offers a move-to-display option) and make it as large as possible. Record what the scene list shows for the "AudienceWindow" row afterwards (its screen bounds should become the TV's size) and whether a didUpdateEffectiveGeometry event fired. (c) Tap +1 on the iPad: does the TV window update? (d) Press Home: what does the TV show, and does the purple window survive? Switch back to "Windowed Apps" afterwards.

**Test 6, iPhone (optional).** Same build runs on "BL iPhone"; plug a Lightning/USB-C HDMI adapter if available and repeat Test 1 to see whether the phone behaves identically.

Send back the event list text or screenshots for each test; the M4 design decision in "Recommended approach" depends on Tests 4 and 5.
