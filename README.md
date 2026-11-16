# BTNotify

Native macOS menu bar app for Bluetooth accessory battery and connection alerts. The runtime is entirely Swift and does not launch subprocesses.

## Build and run

Open `BTNotify.xcodeproj`, select **BTNotify**, and press **⌘R**, or build without launching:

```sh
xcodebuild -project BTNotify.xcodeproj -scheme BTNotify \
  -configuration Debug -derivedDataPath .build/xcode build
```

The app is `.build/xcode/Build/Products/Debug/BTNotify.app` (also available through the local `.build/debug/BTNotify.app` shortcut). Requires macOS 14 or later and Swift 6. Both Debug and Release build universal Apple silicon/Intel apps: the Xcode project sets `ARCHS = arm64 x86_64` and `ONLY_ACTIVE_ARCH = NO`. No architecture overrides or custom binary-merging step are needed. Runtime behavior has been verified on Apple silicon with macOS 27.2; Intel execution has not been tested.

## GitHub Actions

[macOS build](.github/workflows/build.yml) runs on pushes, pull requests, and manual dispatch. It uses GitHub's `xcode-27` preview runner with Xcode 27.2, runs the core tests, and builds a universal Apple silicon/Intel Release app with `xcodebuild`, using the project's architecture settings. No signing secrets are needed: the project uses an ad hoc signature, and the download is not notarized.

Download **BTNotify-macOS** from the workflow run's artifacts and extract the enclosed `BTNotify-macOS.zip` to get `BTNotify.app`. The inner ZIP preserves the app bundle's executable permissions and structure. Artifacts are retained for 14 days; each run supplies a distinct bundle build number.

## Missing devices or differences from System Settings

BTNotify may show fewer devices than **System Settings → Bluetooth**. System Settings includes paired devices that have not provided enough information for BTNotify to recognize them. BTNotify shows recognized accessory types and devices with observed batteries; HomePod, Apple TV, and AirPlay receivers are excluded.

**Connect a new accessory to this Mac at least once while BTNotify is running.** This lets the app learn its device type, especially for mice and keyboards whose Bluetooth device class is missing. Learned input-device types are remembered across disconnections and app restarts. Pairing alone may not provide enough information for a row to appear.

**AirPods are an exception:** iCloud-synced pairing data can make them appear before they have connected to this Mac. A listed device does not guarantee an available battery reading; battery levels remain blank until macOS supplies them.

## Behavior

One notification remains outstanding until dismissed in Notification Center; a banner sliding away automatically still leaves an outstanding notification. Ordinary events wait until it is gone and the Mac is unlocked. Native distributed lock/unlock notifications update session state, with a session check before delivery. Only the latest deferred event is retained and it is checked against current accessory readings before delivery. Old notification stacks are reduced to their newest item at startup. Each new alert uses a fresh request identifier so macOS presents it as a new notification. The previous identifier is retired only after the delivery gate confirms dismissal or permits an opted-in five-minute reminder; the dismissal category stays stable.

**Nag me!** uses a native SwiftUI checkbox and defaults off. When enabled, it replaces the single notification at most every five minutes while a connected accessory remains low and is not charging, and only while unlocked. The last low-battery delivery time persists across relaunches. Without reminders, existing battery hysteresis prevents repeated alerts for the same low-battery condition. The app requests alert-style presentation by default; macOS's per-app notification setting controls whether the alert remains onscreen and can override that default.

- Native `IOBluetoothDevice` and attached Bluetooth HID services supply connection state, sampled every 30 seconds by default and when opening or refreshing the menu. Option-click Notification settings to expose Check time choices of 10 seconds, 30 seconds, and 1–5 minutes; the selection persists and replaces the active timer. Very brief changes can be missed.
- The battery reader calls `IOPSCopyPowerSourcesByType(4)`, the same verified power-source API used by the original wrapper. The original and Swift readers both returned 53% in a live comparison. Bluetooth never supplies or estimates the percentage.
- Only recognized accessory types and devices with observed batteries appear. Bluetooth HID usage and an exact device-address match identify class-0 mice, keyboards, trackpads, controllers, and styluses when connected. Learned HID types persist across relaunches and disconnections. An unclassified device remains hidden until typed HID evidence or a battery is observed; product names do not admit devices. No device-name heuristics identify media receivers.
- Low-battery alerts default to 20%, deduplicate until a five-point recovery, and are suppressed when charging is reported. Missing data never proves disconnection. Initial connections and recovery baselines stay silent.
- Option-click **Notification settings** to reveal the source label and elapsed-time counter below settings and above Quit, plus Check time, notification permission status, Test notification, and battery alert thresholds through 90% in 5-point steps for that settings session. The source label and counter hide when settings collapse. This also works when settings are already expanded. A normal settings opening hides debug controls, and reopening the menu resets debug mode. Higher selected thresholds remain active and visible on normal opening and survive relaunch; normal threshold choices otherwise stop at 30%. Reminder timing stays at five minutes regardless of Check time. Normal openings hide debug controls. Allow Notifications disappears after permission is granted. Notification permission is requested only by that button.

Right-click (or Control-click) the menu bar icon for the app version and Quit. The current version is **0.1.17**, managed by `MARKETING_VERSION` in the Xcode project. Use `xcrun agvtool -noscm next-version` to increment the build counter; set semantic releases with `MARKETING_VERSION`. Keep the Info.plist version references intact by omitting `-all`. A normal click opens accessories. Accessory notifications contain only their title, such as “Magic Keyboard battery is low”; percentages remain in the accessory list.

SwiftUI uses intrinsic content sizing and `ViewThatFits`; only an oversized accessory list scrolls. SwiftUI reports the fixed natural content size through a one-way `onGeometryChange` callback. Automatic preferred-size updates are disabled so they cannot bypass the nonblocking native AppKit animation, which supplies intermediate sizes over 0.28 seconds with ease-in/ease-out. Reduce Motion applies the final size immediately; a rapid reversal starts at the current size. The popover’s internal resize animation is disabled during this transition so it cannot override the timing. The content stays aligned to the top during resizing. A SwiftUI disclosure style retains outgoing settings during the closing ease instead of clipping them away immediately. Its opacity transition also respects Reduce Motion. The outlined native Quit button follows the panel bottom, and the redundant footer text is removed. A small AppKit anchor connects the native SwiftUI view to the menu bar popover. There are no geometry-preference height loops or forced app-activation calls. The bundled AppIcon supplies the app and notification icon. On launch the app registers its current bundle with Launch Services before initializing notifications and sets its application icon from the system icon service. The app icon retains its Bluetooth mark, red notification dot, and blue gradients. The menu bar uses the Bluetooth mark with a round notification badge. The hollow and filled menu bar dots share the same 6.2-point outer diameter. The dot fills with native macOS system red whenever a known accessory battery is at or below Alert at. It remains filled during charging until all known low batteries rise above that threshold, without the notification policy’s five-point recovery margin. Notification delivery, permission, dismissal, and opening the menu do not affect the dot. Missing or unknown readings and disconnection do not establish recovery; the last known battery levels are retained during the current run. Changing Alert at immediately reevaluates the indicator. The icon updates with system colors and appearance. The app icon’s editable source is `resources/AppIcon.icon`, an Icon Composer document with a simplified Bluetooth vector and an original notification dot. The app icon retains blue gradients in Default and Dark appearances; Apple’s SF Symbols are used only within the app UI. Xcode compiles system-rendered materials and default, dark, tinted light/dark, and clear light/dark appearances for macOS 27; Xcode also generates images for older macOS deployment targets. The same-named PNG catalog contains all ten macOS icon sizes refreshed from the Composer Default export; Xcode prefers the layered Composer document. `tools/generate-app-icon.swift` resizes that 1024px export without duplicating the vector drawing. Offscreen previews of all six appearances are in `.build/icon-previews/AllAppearances.png`. See [Apple guidance and verification](research/MACOS-27-ICON-GUIDANCE.md).

Device rows load the installed macOS Bluetooth UI artwork through Foundation/AppKit resource APIs, using Apple vendor/product IDs from the power source for model-specific images when available. These system resources are not bundled or linked as a framework dependency; their layout can change, so SF Symbols provide a fallback. Bluetooth class and power-source category identify device types; recognizable names refine otherwise unclassified BLE icons. Product-name icon refinements never control accessory inclusion or alerts; native HID usage is separate eligibility evidence. HID enumeration reads properties without opening input devices or observing input events.

The battery entry point is private and may change with macOS updates. Unknown battery levels remain blank; read failures are shown as errors. The app never pairs devices or initiates connections. Keep it running for alerts.

## Launch at login

Move BTNotify to **Applications**, open its menu, and enable **Launch at login** beside **Quit**. The compact native checkbox is always visible outside the settings dropdown and uses the same small control size as Quit. This is opt-in and uses the current native ServiceManagement API, `SMAppService.mainApp`, without a helper app or launch scripts. The checkbox reads macOS's registration status rather than a separate saved preference. If macOS requires approval, the app shows that state and an **Open Login Items** button. Changes made in System Settings are reflected when the menu reopens. Turning the setting off removes the login registration without quitting BTNotify.

## AppleScript / Apple Events

BTNotify includes a scripting dictionary for reading accessory batteries and connection status, refreshing, and standard application launch/quit. For example, run this in Script Editor after installing the updated app:

```applescript
tell application "BTNotify"
    launch
    accessory status
end tell
```

The result is a list of records with `id`, `name`, `connected`, `battery level`, `charging`, and `device type`. Unknown battery levels return AppleScript's `missing value`. `accessory status` returns the latest cached readings; use `refresh accessories` instead to poll immediately and return updated readings. A refresh follows the same notification rules as a manual refresh in the app. Neither command changes preferences or opens the menu panel.

Use `tell application "BTNotify" to quit` to stop the app. Commands are handled in Swift through `NSAppleEventManager`; the app does not run AppleScript or launch subprocesses. The dictionary is available in Script Editor's **Open Dictionary** browser.

## Verification

`BTNotify --check-launch-at-login` exercises registration, approval, external changes, and errors with an isolated service fixture; it never changes real login items. `BTNotify --check-apple-events` dispatches native events inside the diagnostic process with fixture readings and compiles example AppleScript against the bundled dictionary without executing it. These checks do not launch or quit the running app, open windows, or send notifications.

```sh
env CLANG_MODULE_CACHE_PATH=/private/tmp/btnotify-clang-cache \
    SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/btnotify-swift-cache \
    swift test --disable-sandbox --cache-path .build/cache \
    --config-path .build/config --security-path .build/security
```

`BTNotify --diagnose-notifications` reads permission, delivered/pending counts, session state, and app notification preferences without sending an alert. `BTNotify --check-notification-requests` checks that successive alerts have distinct identities and retain the dismissal category and title-only content, without posting them. `BTNotify --diagnose` prints native inventory and power-source readings locally, including device identifiers. `BTNotify --check-ui` checks offscreen expand/collapse fixture sizes, device symbols and installed artwork, and equal-sized hollow/red badge rendering. `BTNotify --check-battery-indicator` verifies threshold changes, charging, dismissal, missing readings, and multiple accessories independently of notification permission or delivery. `BTNotify --check-disclosure` replays expansion and collapse offscreen and checks that the footer does not slide or fade after the panel reaches its new size. `BTNotify --check-swiftui-resize` drives the real SwiftUI disclosure binding through its natural-size callback and verifies intermediate heights in both directions and that settings remain visible during the closing ease. `BTNotify --check-settings-actions` verifies ordinary, Option, and Control–Option settings actions without synthesizing desktop input. `BTNotify --check-resize` samples direct size requests over time, checks both directions and a rapid reversal, and verifies immediate nonanimated sizing. `BTNotify --check-thresholds` verifies debug choices, high-threshold persistence, validated polling intervals and their 30-second default, and the default-off reminder preference with an isolated preferences domain. These checks do not verify live onscreen motion or send notifications. Accessory rows expose the device name, connection, charging, and battery status as one accessibility element. Controls have explicit spoken names and reminder/check-time hints. Control–Option assistive activation opens the ordinary panel; Option-clicking Notification settings reveals debug controls. The retained live accessibility tools change focus/input and must only be run with explicit permission when the user is not typing. They are never run by the app or its build.

## Secret checks and Git hooks

With [mise](https://mise.jdx.dev/) installed, set up the development tools and repository hooks:

```sh
mise install
mise run hooks:install
```

The project pins the official [awslabs/git-secrets](https://github.com/awslabs/git-secrets) 1.3.0 script by version and SHA-256 through mise's HTTP backend. hk runs through `mise x`, so hooks resolve that pinned copy. The setup installs hooks for this repository without replacing global Git settings or installing git-secrets' separate hooks.

Pre-commit checks the Git index; commit-msg checks the proposed message; pre-push checks file contents across all local history, including secrets removed in later commits. These checks do not modify or stage files. Shared rules in [.git-secrets](.git-secrets) detect AWS credentials, GitHub tokens, private-key headers, Slack tokens, Google API keys, and Stripe keys. The setup does not read credentials from your home directory or add broad allowlists.

Run `mise run secrets:check` for tracked and eligible untracked files, or `mise run secrets:history` for committed file history. These are pattern-based checks; the reviewed scope and results are recorded in [the security review](research/SECURITY-REVIEW.md).

## Research

The requested [REA skill](.agents/skills/reverse-engineer-anything/SKILL.md) is installed for this project. See [the investigation](research/INVESTIGATION.md) and [the draft API report](research/BATTERY-API-BUG-DRAFT.md). Incorrect Bluetooth percentages have not been reproduced; the report has not been submitted. The original Objective-C battery reader is retained only as a comparison reference under `research/reference-battery-reader`; it is not an app dependency.

Exact widget parity and live AirPods component battery coverage remain unverified.
