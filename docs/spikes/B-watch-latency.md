# Spike B: Watch latency

*Status 2026-10-25: built and wired end to end; Transport A verified on paired Simulators; Transport B compiles but needs hardware; all real latency numbers need Ben's devices.*

Code: `Spikes/WatchLatency/` (own XcodeGen project; see its README for build lines). Throwaway.

## What was built

Three apps share one 14-byte binary message (`Shared/SpikeMessage.swift`): a **ping** carries a route byte, a 32-bit id and the sender's 64-bit monotonic timestamp; a **summary** carries count, median and p95 in microseconds. The Watch stamps a ping, the far end echoes the identical bytes, and the Watch computes RTT = arrival − tSend on the thread the reply lands on, before any UI hop. One-way ≈ RTT/2.

| Target | Platform | Role |
|---|---|---|
| `SpikeWatchRemote` | watchOS 26 | Big **Next** button with `.handGestureShortcut(.primaryAction)` (system double tap). Transport picker A / A′ / B. On-screen n, last RTT, median, p95, one-way estimate, failures, in-flight, last reconnect time. Sends a summary to the host every 10 samples. Second page: timestamped log of scene-phase changes (active/inactive/background), connection events and failures. Auto-run button and `-autorun N -transport A|Aphone|B` launch arguments. |
| `SpikeWatchRelay` | iOS 26 | Transport A relay. `WCSession` to the Watch; `NWBrowser` for `_lectern-spike._tcp` plus one persistent `NWConnection` (TCP, `noDelay`, peer-to-peer enabled) to the Mac. Route `macEcho`: forward, wait for the Mac's echo, call the WatchConnectivity reply handler. Route `phoneEcho` (A′): reply immediately, which isolates the Watch↔iPhone leg. Launch argument `-host ip:port` bypasses Bonjour. |
| `SpikeWatchHost` | macOS 26 | Transport A: `NWListener` on TCP 52777 advertising `_lectern-spike._tcp`, echoing each length-prefixed frame on the connection's own queue before logging. Transport B: `CBPeripheralManager` advertising service `7E3C0C10-…` with one characteristic (`writeWithoutResponse`, `write`, `notify`); on `didReceiveWrite` it calls `updateValue(_:for:onSubscribedCentrals:)` with the same bytes. Window shows both transports' state and a log; every ping and summary is appended to `~/Library/Application Support/LecternSpikeB/<A|A-phone|B>.csv` and printed to stdout (line-buffered). |

Transport B on the Watch is a `CBCentralManager` that scans for the service UUID, connects, subscribes to notifications, writes pings `.withoutResponse`, and matches echoes by id. If a press finds the link down it records the time, reconnects, and reports "reconnect → first echo" when the first echo lands; Transport A does the same when `WCSession.isReachable` is false and flips back.

### watchOS Core Bluetooth constraints (watchOS 27.0 SDK headers)

- `CBPeripheralManager` initialisers are `API_AVAILABLE(ios(6.0), macos(10.9)) API_UNAVAILABLE(watchos, tvos)`: a Watch can only be the **central**, so the host (Mac or iPad) must be the peripheral. That is what the spike does, and iPadOS has `CBPeripheralManager`, so B would also work with an iPad host.
- `CBCentralManager` carries no watchOS unavailability marks. `scanForPeripherals` documents background scanning only for apps with the `bluetooth-central` background mode, which this spike does not declare; the Watch app has to be frontmost.
- The headers say nothing about watchOS-specific connection limits. My recollection is that WWDC 2017's Core Bluetooth session set watchOS to foreground-only use with a small connection limit; treat that as unverified until the hardware run.

## Verified in the Simulator (simulator-only numbers)

Setup: iPhone 17 Pro Max (iOS 26.5) paired with Apple Watch Series 11 46 mm (watchOS 26.5); host built ad-hoc signed and launched from the terminal on the same Mac; relay launched with `-host 127.0.0.1:52777`; Watch app launched with `-autorun 100 -transport …` (100 pings at 250 ms).

| Transport | n | failures | RTT median | RTT p95 |
|---|---|---|---|---|
| A: Watch → iPhone → Mac → back | 100 | 0 | 3811 ms | 4334 ms |
| A′: Watch → iPhone → back | 100 | 0 | 3774 ms | 4316 ms |
| iPhone → Mac → back (TCP loopback probe from a Python client) | 1 | 0 | 0.5 ms | – |

Because both Simulators share the Mac's clock, the host CSV also gives the one-way Watch-send → Mac-receive time for A: median 1702 ms, p95 2202 ms.

What this shows: the whole pipeline works (framing, id matching, reply handlers, summaries, CSV, logs) and the TCP leg is negligible. What it does not show: anything about real latency. The Simulator's WatchConnectivity bridge adds seconds per message, so these numbers say nothing about a real Watch, and Core Bluetooth does not exist in the Simulator (the Watch app shows "Bluetooth unavailable (unsupported here, e.g. Simulator)" and the host's B section reports unsupported/unauthorised without affecting A).

Also observed: on the first run the relay found the host through Bonjour at the Mac's LAN address and the first 100 pings stalled for about 63 s before all arriving at once (RTT median 62.9 s). The pattern matches TCP retransmit backoff after early packet drops. I found no TCC log entries, so the cause is unconfirmed; loopback avoided it and the hardware run uses a real network anyway.

Not verified: double tap (cannot be triggered in the Simulator; the modifier compiles and is attached to the button), Transport B end to end, wrist-down and reconnect behaviour, and the relay with the iPhone app in the background or the phone locked.

## Measurement procedure for Ben

Everything below assumes Xcode 27.1 and your `DEVELOPMENT_TEAM` in `Config/Local.xcconfig`.

1. **Generate and open.** `cd Spikes/WatchLatency && xcodegen generate && open WatchLatency.xcodeproj`. Xcode creates one scheme per target automatically (the scheme menu is top centre of the window).
2. **Enable Developer Mode** once on the iPhone (Settings → Privacy & Security → Developer Mode) and on the Watch (same path in the Watch's Settings app). Connect the iPhone by cable, unlock it, tap Trust.
3. **Mac host.** In the terminal: `xcodebuild -project WatchLatency.xcodeproj -scheme SpikeWatchHost -destination 'platform=macOS' build | xcbeautify`, then `open "$(xcodebuild -project WatchLatency.xcodeproj -scheme SpikeWatchHost -showBuildSettings | awk '/ BUILT_PRODUCTS_DIR/{print $3}')/SpikeWatchHost.app"`. Accept the two prompts (Bluetooth, local network). The window should say "advertising LecternSpike" and "listening on port 52777".
4. **iPhone relay.** In Xcode pick scheme `SpikeWatchRelay`, destination your iPhone, press ⌘R. First run only: on the iPhone go to Settings → General → VPN & Device Management and trust your developer certificate, then run again. Accept the local network prompt. The relay should show "connected to …".
5. **Watch app.** Pick scheme `SpikeWatchRemote`, destination "Apple Watch via iPhone", ⌘R. Installing over the air takes a minute. Allow Bluetooth when asked (only matters for B).
6. **Transport A, 100+ presses.** On the Watch choose "A: iPhone → Mac". Double tap (thumb and index finger, twice, with the screen awake) until n reaches 100 or more; the button also works. Read median/p95 from the Watch screen; the host window and `~/Library/Application Support/LecternSpikeB/A.csv` have the same summaries. Press Reset before switching transports.
7. **Transport A′.** Choose "A′: iPhone only", repeat. The difference A − A′ is the iPhone↔Mac Wi-Fi cost.
8. **Transport B.** Choose "B: Bluetooth". The status line should walk through scanning → connecting → subscribed. Repeat 100+ presses. The relay app and the iPhone are not involved; you can even switch the iPhone off to prove it.
9. **Wrist down / dimmed screen, per transport.** Lower your wrist for 30 s, raise it, double tap once. On the log page look for "scene → background/active" and "reconnect → first echo N ms"; the main page shows "reconnect" with the last value. Repeat a few times; also try 2 minutes down. For A, also try with the relay app in the background (swipe home on the iPhone) and with the iPhone locked.
10. **Report** the per-transport median and p95 from step 6–8, what happened in step 9, and the reconnect times. The CSVs plus `log show --predicate 'subsystem == "dev.lectern.spike"' --last 1h` on the Mac cover everything the window showed.

If the relay never finds the host, both devices must be on the same Wi-Fi or within AWDL range; as a fallback, in Xcode edit the `SpikeWatchRelay` scheme → Run → Arguments and add `-host <mac-ip>:52777`.

## Decision rule

Targets from SPEC §11: one-way median < 100 ms and p95 < 200 ms, i.e. RTT median < 200 ms and RTT p95 < 400 ms as the Watch reports them.

- Both pass: prefer **B**. It needs no iPhone, works with a Mac or an iPad host, and has no relay app to keep alive. Choose A only if B's reconnect after wrist-down is clearly worse than A's.
- Only A passes: use **A**, but the iPhone must be nearby with the relay running (M7 makes the iPhone remote that relay, so this is cheap), and the iPad-host case still needs the phone.
- Only B passes: **B**, and note the Watch app must stay frontmost (document the Wake Screen setting per SPEC §9.3).
- Neither passes: the fallback worth a look is the Watch talking straight to the host over Wi-Fi with Network framework, which the watchOS 27 SDK ships; it is outside this spike.

Non-latency factors either way: double tap exists only on Series 9 / Ultra 2 or newer (open decision in SPEC §13 on button-only Watches), and the Watch must be awake for the gesture regardless of transport, so wrist-down reconnect time matters more than the steady-state median.

## Provisional recommendation

Lean to **Transport B (Core Bluetooth)** for M8 because it removes the iPhone from the critical path and works with both hosts; confirm with the hardware numbers above, and fall back to A if B's p95 or its wrist-down reconnect misses the targets. Keep the protocol in `PresenterProtocol` transport-agnostic so the choice stays reversible.

## Open questions

- Real numbers for A, A′, B, and reconnect times (Ben).
- Whether the Mac's Bluetooth peripheral stays discoverable while the Lectern host app is in the background or the Mac display is asleep during a talk.
- Whether watchOS keeps the BLE link alive across short wrist-downs or drops it every time (determines whether M8 needs a keep-awake strategy).
