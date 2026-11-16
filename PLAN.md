# BTNotify implementation plan and design record

## Current design reference

This section records the current implementation as of 0.1.17. The [README](README.md) describes features and use. The historical checklist below records earlier states, including decisions that later changed.

### Build, distribution, and versioning

The native Xcode project owns universal architecture settings: `ARCHS = arm64 x86_64` and `ONLY_ACTIVE_ARCH = NO` for Debug and Release. Builds do not need command-line architecture overrides or a custom binary-merging step. The app requires macOS 14 or later and Swift 6. Apple silicon execution is verified on macOS 27.2; Intel execution remains untested.

GitHub Actions uses the `xcode-27` preview runner with Xcode 27.2. Pushes, pull requests, and manual runs execute core tests, build Release, check login/scripting integration, verify the ad hoc signature, and package the app. The artifact is `BTNotify-macOS`, containing `BTNotify-macOS.zip`, with 14-day retention. Each run supplies a distinct build number. The ZIP preserves bundle permissions and structure. The app is not notarized, and CI needs no signing secrets.

Semantic versions use `MARKETING_VERSION`. Build counters use `CURRENT_PROJECT_VERSION`. Run `xcrun agvtool -noscm next-version` to increment the build counter. Omit `-all` to preserve Info.plist build-setting references.

### Native architecture and notification policy

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

### Launch-at-login design

Move BTNotify to **Applications**, open its menu, and enable **Launch at login** beside **Quit**. The compact native checkbox is always visible outside the settings dropdown and uses the same small control size as Quit. This is opt-in and uses the current native ServiceManagement API, `SMAppService.mainApp`, without a helper app or launch scripts. The checkbox reads macOS's registration status rather than a separate saved preference. If macOS requires approval, the app shows that state and an **Open Login Items** button. Changes made in System Settings are reflected when the menu reopens. Turning the setting off removes the login registration without quitting BTNotify.

### Apple Events implementation

BTNotify includes a scripting dictionary for reading accessory batteries and connection status, refreshing, and standard application launch/quit. For example, run this in Script Editor after installing the updated app:

```applescript
tell application "BTNotify"
    launch
    accessory status
end tell
```

The result is a list of records with `id`, `name`, `connected`, `battery level`, `charging`, and `device type`. Unknown battery levels return AppleScript's `missing value`. `accessory status` returns the latest cached readings; use `refresh accessories` instead to poll immediately and return updated readings. A refresh follows the same notification rules as a manual refresh in the app. Neither command changes preferences or opens the menu panel.

Use `tell application "BTNotify" to quit` to stop the app. Commands are handled in Swift through `NSAppleEventManager`; the app does not run AppleScript or launch subprocesses. The dictionary is available in Script Editor's **Open Dictionary** browser.

### Verification reference

`BTNotify --check-launch-at-login` exercises registration, approval, external changes, and errors with an isolated service fixture; it never changes real login items. `BTNotify --check-apple-events` dispatches native events inside the diagnostic process with fixture readings and compiles example AppleScript against the bundled dictionary without executing it. These checks do not launch or quit the running app, open windows, or send notifications.

```sh
env CLANG_MODULE_CACHE_PATH=/private/tmp/btnotify-clang-cache \
    SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/btnotify-swift-cache \
    swift test --disable-sandbox --cache-path .build/cache \
    --config-path .build/config --security-path .build/security
```

`BTNotify --diagnose-notifications` reads permission, delivered/pending counts, session state, and app notification preferences without sending an alert. `BTNotify --check-notification-requests` checks that successive alerts have distinct identities and retain the dismissal category and title-only content, without posting them. `BTNotify --diagnose` prints native inventory and power-source readings locally, including device identifiers. `BTNotify --check-ui` checks offscreen expand/collapse fixture sizes, device symbols and installed artwork, and equal-sized hollow/red badge rendering. `BTNotify --check-battery-indicator` verifies threshold changes, charging, dismissal, missing readings, and multiple accessories independently of notification permission or delivery. `BTNotify --check-disclosure` replays expansion and collapse offscreen and checks that the footer does not slide or fade after the panel reaches its new size. `BTNotify --check-swiftui-resize` drives the real SwiftUI disclosure binding through its natural-size callback and verifies intermediate heights in both directions and that settings remain visible during the closing ease. `BTNotify --check-settings-actions` verifies ordinary, Option, and Control–Option settings actions without synthesizing desktop input. `BTNotify --check-resize` samples direct size requests over time, checks both directions and a rapid reversal, and verifies immediate nonanimated sizing. `BTNotify --check-thresholds` verifies debug choices, high-threshold persistence, validated polling intervals and their 30-second default, and the default-off reminder preference with an isolated preferences domain. These checks do not verify live onscreen motion or send notifications. Accessory rows expose the device name, connection, charging, and battery status as one accessibility element. Controls have explicit spoken names and reminder/check-time hints. Control–Option assistive activation opens the ordinary panel; Option-clicking Notification settings reveals debug controls. The retained live accessibility tools change focus/input and must only be run with explicit permission when the user is not typing. They are never run by the app or its build.

### Secret-check design

With [mise](https://mise.jdx.dev/) installed, set up the development tools and repository hooks:

```sh
mise install
mise run hooks:install
```

The project pins the official [awslabs/git-secrets](https://github.com/awslabs/git-secrets) 1.3.0 script by version and SHA-256 through mise's HTTP backend. hk runs through `mise x`, so hooks resolve that pinned copy. The setup installs hooks for this repository without replacing global Git settings or installing git-secrets' separate hooks.

Pre-commit checks the Git index; commit-msg checks the proposed message; pre-push checks file contents across all local history, including secrets removed in later commits. These checks do not modify or stage files. Shared rules in [.git-secrets](.git-secrets) detect AWS credentials, GitHub tokens, private-key headers, Slack tokens, Google API keys, and Stripe keys. The setup does not read credentials from your home directory or add broad allowlists.

Run `mise run secrets:check` for tracked and eligible untracked files, or `mise run secrets:history` for committed file history. These are pattern-based checks; the reviewed scope and results are recorded in [the security review](research/SECURITY-REVIEW.md).

### Research provenance

The requested [REA skill](.agents/skills/reverse-engineer-anything/SKILL.md) is installed for this project. See [the investigation](research/INVESTIGATION.md) and [the draft API report](research/BATTERY-API-BUG-DRAFT.md). Incorrect Bluetooth percentages have not been reproduced; the report has not been submitted. The original Objective-C battery reader is retained only as a comparison reference under `research/reference-battery-reader`; it is not an app dependency.

Exact widget parity and live AirPods component battery coverage remain unverified.

### README and screenshot verification

The README uses the requested [ASD-STE100 skill](https://github.com/danyuchn/asd-ste100-skill) for short, unambiguous prose. The skill is installed in the user skills directory, not bundled with this app. Its structural linter reports zero findings. This is a clarity check, not certified dictionary compliance.

`docs/images/main-window.png` captures the real `AccessoryPanelContent` with example keyboard, mouse, and AirPods readings. A temporary copy of the native Xcode project supplied fixture data and an offscreen hosting window. The copied app used a separate bundle identifier and an isolated preferences domain. It exited through diagnostics before normal startup. The installed app, notification settings, login items, and production source files were unchanged. The screenshot uses an opaque native light background for legibility in the README.

Verification includes visual image review, local documentation links, the skill linter, `git diff --check`, and `mise run secrets:check`. The isolated native screenshot build passed. No desktop input or live notifications were used.

## Historical implementation checklist

1. [x] Install the requested REA skill in `.agents/skills`.
2. [x] Establish a usable accessory battery data source and test standalone access. The widget's precise executed call path remains unverified.
3. [x] Package and launch the menu bar app; signature verified, 31 tests pass, and release diagnostics report keyboard connected at 54%.

Interactive verification remains: allow notifications and send a test banner; connect/disconnect accessories to validate real hardware transitions. AirPods component levels and exact widget parity remain unverified.

UI repair:
1. [x] Reproduce the unusable panel using actual window geometry; opening the original status item produces no panel at least 300×200.
2. [x] Replace SwiftUI MenuBarExtra presentation with AppKit NSStatusItem/NSPopover hosting SwiftUI; add a native Xcode project and shared scheme; remove build-app.sh.
3. [x] Build with xcodebuild, relaunch, and verify the real visible panel and its controls: 386×566 outer window; accessibility confirms keyboard connected at 53% and settings/list content.

Accessory filtering:
1. [x] Exclude explicit HomePod/Apple TV/AirPlay types and unclassified entries without batteries, while retaining recognized battery accessories.
2. [x] Validate 34 tests and a native xcodebuild build; live diagnostics retain keyboard at 53%, one mouse, and AirPods while removing room/media entries.

Panel refinements:
1. [x] Gate the elapsed-time counter on Option held at opening; verify normal → Option → normal through real accessibility clicks. Polling remains every 15 seconds.
2. [x] Replace the fixed panel height with measured content height; reproduce 566 → 566 before the fix, verify expansion grows and collapse shrinks afterward. Cap large lists and retain scrolling.
3. [x] Hide Allow Notifications when authorized; confirm live macOS permission is allowed and the button is absent.
4. [x] Generate native vector icon assets, compile AppIcon.icns/Assets.car with xcodebuild, and verify the app signature and icon metadata.

Scope: macOS accessories, battery levels and explicit connection changes. Keep unknown values unknown. Document private API limitations and investigation evidence.

Native simplification and interruption recovery:
1. [x] Replace geometry height feedback with SwiftUI intrinsic sizing and ViewThatFits; actual accessibility bounds passed three expand/collapse cycles before GUI automation stopped.
2. [x] Remove runtime subprocesses and the compiled Objective-C dependency. Native Bluetooth supplies connections; the Swift power-source wrapper matches the reference reader at 53%.
3. [x] Hide both the source label and elapsed counter on normal opening; Option-only checks passed.
4. [x] Stop BTNotify and Accessibility Inspector after live automation interrupted typing. Do not launch apps or synthesize input without a new explicit request. Remove forced activation/key-window calls from the app.
5. [x] Retain an unsubmitted API discrepancy draft; 24 current core tests pass after deleting the unused subprocess-report parser and its obsolete tests.

macOS 27 icon:
1. [x] Verify current Apple guidance and original artwork provenance.
2. [x] Add a native Icon Composer document with separate SVG headphone/battery layers and system effects; keep the same-named legacy catalog.
3. [x] Build with Xcode 27.2, verify compiled vector layers and light/dark/tinted appearances, render with design-generation 27, and verify the signature. App stays closed.

Bluetooth identity:
1. [x] Replace the menu bar headphones with a native Bluetooth path and app.badge SF Symbol overlay.
2. [x] Replace the app icon with separate Bluetooth and original notification-indicator vectors; confine the SF Symbol to UI under Apple's usage rules.
3. [x] Verify offscreen artwork and native build without launching the app.

Complete icon appearances and app icon set:
1. [x] Set explicit default/dark/monochrome layer colors; keep the notification indicator opaque and legible.
2. [x] Export and inspect all six macOS 27 appearances; refresh the ten PNG appiconset slots from the same source. Replace the obsolete headphone generator with a native resizer.
3. [x] Rebuild with xcodebuild; verify PNG dimensions, compiled vector/appearance stacks, and code signature. Copy the rebuilt app to dist without launching.

Finder icon cache repair:
1. [x] Reproduce stale macOS icon-service output offscreen: Debug bundle contains Bluetooth, but NSWorkspace returned headphones.
2. [x] Move CFBundleVersion to Xcode CURRENT_PROJECT_VERSION (build 2), rebuild, update bundle timestamps, and force registration of only the two BTNotify bundles.
3. [x] Verify NSWorkspace now returns the new Bluetooth icon; code signature passes. No application was launched and Finder was not restarted.

Blue gradient refinement:
1. [x] Add explicit blue linear-gradient backgrounds for Default and Dark, preserving system tinted/clear styling.
2. [x] Verify all six offscreen renders, refresh the ten PNG slots, and rebuild as build 3; signature passes.

GitHub Actions build:
1. [x] Add push/PR/manual workflow on GitHub's xcode-27 preview runner with Xcode 27.2; run core tests and native Release build, verify signature, and upload a preserved app ZIP.
2. [x] Set ARCHS = arm64 x86_64 and ONLY_ACTIVE_ARCH = NO in both Xcode project configurations; CI uses these settings without architecture overrides or a custom binary-merging step.
3. [x] Validate workflow syntax (allowing the documented preview runner label), 24 core tests, universal Debug and Release builds, signature, and extracted ZIP permissions/signature. Hosted execution awaits a push; no GUI was launched.

Distribution review:
1. [x] Review all repository text, including this plan and bundled public skill, for organization-specific names and private-service links; none found.
2. [x] Verify clean Debug and Release builds contain both arm64 and x86_64 slices directly from project settings. Validate signatures and the packaged ZIP; refresh the default Debug and dist app outputs.

Bell indicator and device artwork:
1. [x] Match app/menu bar identity with original Bluetooth and bell outlines; keep the bell empty when idle and accent-filled after macOS accepts an authorized notification. Acknowledge on menu open or notification click; refresh on system color/appearance changes.
2. [x] Enable native anchored popover resize animation with Reduce Motion support, top-align content during resizing, and use natural initial sizing. Offscreen expand/collapse dimensions return to baseline; live animation remains unverified because GUI automation is stopped.
3. [x] Use installed macOS Bluetooth UI device artwork through resource APIs, selecting model images from power-source vendor/product metadata. Preserve typed metadata through battery merging and use SF Symbol fallbacks. Device filtering remains independent.
4. [x] Verify 32 core tests, all six app icon appearances, hollow/accent bell pixels, expand/collapse sizing for 0/1/20 accessories, nine installed artwork types and a model-specific keyboard image. No notifications were sent and no windows were opened.

Simple alerts and context menu:
1. [x] Remove percentages and redundant bodies from accessory alerts; keep the device name and event in the title. Battery percentages remain visible in the panel.
2. [x] Add a native right-click/Control-click menu with version/build and Quit, preserving the normal left-click accessory panel.
3. [x] Rebuild Debug and Release as version 0.1.0 (5), verify signatures, and refresh dist and its ZIP. Live menu interaction was not exercised; the app remains closed.

App icon restoration and semantic version:
1. [x] Restore the previous Bluetooth/red-dot app icon and blue gradients exactly from its saved vector/Composer sources; retain the menu bar notification bell. Regenerate all six appearances and the ten PNG sizes.
2. [x] Set MARKETING_VERSION = 0.1.5 in both Xcode configurations and expand it into CFBundleShortVersionString. Show Version 0.1.5 in the right-click menu; retain the separate native build identifier as metadata.
3. [x] Rebuild Debug/Release, verify their semantic version and code signatures, and refresh dist and its ZIP. No app windows were opened.

Disclosure transition correction:
1. [x] Inspect the supplied recording and reproduce the delayed footer in an offscreen, same-host animated disclosure replay. The prior final-size-only check could not detect it.
2. [x] Disable the disclosure animation transaction at the panel root, including VStack siblings. Keep native popover resizing; separate panel content from its local expansion state to replay the real binding path.
3. [x] Verify the transition regression fails before the fix and passes afterward in both directions. Retain --check-disclosure without desktop input or visible windows; existing size/icon checks also pass. Live popover motion still requires manual verification.
4. [x] Rebuild Debug and Release as version 0.1.5, verify signatures and the optimized transition check, and refresh dist and its ZIP. No app was opened.

Patch version bump:
1. [x] Set semantic version 0.1.6 in MARKETING_VERSION for Debug and Release. Format project build settings on separate lines so Xcode's agvtool can read them; use agvtool -noscm next-version to bump the build counter to 6, preserving Info.plist build-setting references.
2. [x] Rebuild Debug and Release, verify both compiled versions are 0.1.6 (6) and all signatures pass, and refresh dist and its ZIP. No app was opened.

Round menu bar badge:
1. [x] Replace the menu bar bell with the app artwork's circular badge. Preserve a hollow idle state, OS-accent fill after an accepted notification, and the existing acknowledgement behavior.
2. [x] Verify hollow/accent pixels offscreen, rebuild Debug and Release, verify signatures, and refresh dist and its ZIP. Version remains 0.1.6; no app was opened.

Settings resize easing:
1. [x] Wrap the hosting controller preferred-size update and content-size callback in one native animation context with a 0.22-second ease-in/ease-out curve. Disable implicit animation for hidden windows or Reduce Motion and refresh the popover motion preference on resize.
2. [x] Preserve the panel-wide SwiftUI animation suppression that prevents the delayed footer. Offscreen footer and size/icon checks pass; Debug and Release builds pass. Live AppKit easing remains for manual verification.

Fresh visible output:
1. [x] Repair the .build/debug shortcut, which pointed to a nonexistent directory, to use xcode/Build/Products/Debug.
2. [x] Bump semantic version to 0.1.7 and use agvtool to increment the build to 7. Rebuild Debug and Release, verify compiled versions and signatures, refresh dist and its ZIP, and update bundle timestamps. No app was opened.

Measured resize easing and Option thresholds:
1. [x] Add --check-resize through the real hosting-controller size setter and an offscreen NSPopover. The prior context-only implementation fails with all samples already at the target height in both directions.
2. [x] Replace the timing hint with a nonblocking main-run-loop NSAnimation that publishes eased intermediate sizes over 0.28 seconds. Keep the automatic preferred-size update and manual content-size callback on that same interpolated value; disable NSPopover's internal animation for the whole resize and restore native presentation animation afterward. Rapid reversals retain their current size, and Reduce Motion skips interpolation.
3. [x] Add Option-only 35–90% thresholds in 5-point steps. Preserve selected high values on normal opening and through relaunch; retain the selected high value as a valid normal picker tag. Check persistence with isolated preferences, without changing the user's saved settings.
4. [x] Verify timed intermediate sizes, smooth reversal, immediate nonanimated sizing, threshold persistence, and existing footer/layout/icon checks. Rebuild Debug/Release as 0.1.8 (8), verify versions and signatures, and refresh dist and its ZIP. Live onscreen appearance remains for manual verification; no app windows or desktop input were used.

Real disclosure sizing and notification lifecycle:
1. [x] Observe only the running app's window bounds while the user toggles settings: 0.1.8 jumps from 326 to 509 points. Verify Reduce Motion is off and the installed app is the expected version. The previous direct-setter regression missed SwiftUI's automatic preferred-size path.
2. [x] Add --check-swiftui-resize to drive the actual disclosure binding. Reproduce the bypass, then disable automatic preferred sizing and use one-way onGeometryChange reporting from fixed natural content to the native animator. Interpolated heights are never fed back into SwiftUI state. The real-path test now passes in Debug and Release; existing footer, direct timing, layout, threshold, and badge checks pass.
3. [x] Use one stable notification ID, serialize asynchronous attempts, and retain accepted-delivery state across the initial empty-delivery-read race. Check current delivered notifications and unlock state before posting. Subscribe natively to distributed lock/unlock notifications, retain only the latest still-relevant deferred event, and reduce old stacks to one item at startup.
4. [x] Add the default-off Nag me! setting for reminders at most every five minutes while low, connected, not charging, and unlocked. Persist the last battery-alert time and setting. Ordinary alerts do not repeat while the same low condition remains latched. Request alert-style presentation through Info.plist; the user's macOS notification style can override it.
5. [x] Verify the installed bundle's icon renders correctly through the system icon service; refresh its scoped Launch Services registration. Register the running bundle and set its application icon before initializing notifications on future launches. Missing notification-banner artwork was not reproduced offscreen and still needs a new banner check; no global caches or notification databases were cleared.
6. [x] Pass 42 core tests, including acceptance/delivery races, dismissal, lock changes, and exact reminder intervals. Rebuild Debug/Release as 0.1.9 (9), verify versions, signatures, alert metadata and bundled icon, and refresh dist and its ZIP. No GUI app was launched or restarted and no input was synthesized; visible motion in the new build remains for manual verification.

Polling controls and accessibility:
1. [x] Default accessory polling to 30 seconds. Persist validated choices of 10/30 seconds and 1–5 minutes; invalidate and replace the running timer when changed. Keep reminders at five minutes.
2. [x] Place Check time, notification status, and Test notification inside Option-click debug mode. Retain Allow Notifications during normal use until permission is granted.
3. [x] Delegate accessibility changes: preserve Control–Option assistive activation, add spoken labels and hints, group device state and battery readings, mark the title as a heading, and improve footer readability. Source review passes; live VoiceOver focus, keyboard navigation, and larger-text behavior remain unverified.
4. [x] Inspect an offscreen multi-height control replay. The reported switch-background artifact is not reproduced by the hidden-window renderer. Following the user's localization to the Nag me! switch background, use a native SwiftUI checkbox for that secondary opt-in setting, removing the affected switch surface without a custom renderer. Retain the confirmed 0.28-second easing; live appearance remains for manual verification.
5. [x] Pass 42 core tests and isolated polling-preference checks. Build Debug and Release as 0.1.10 (10), verify universal architectures and signatures, and refresh the canonical Debug app plus dist package. No app windows were shown, desktop input was synthesized, or test notifications were sent.

Reverse easing and settings entry:
1. [x] Extend the real SwiftUI sizing replay to inspect outgoing settings pixels. Reproduce the defect: the native window eases closed while settings ink drops from 2069 to zero on the first sampled frame. Re-enabling animations on the standard disclosure still fails, isolating its immediate clipping.
2. [x] Use a native SwiftUI DisclosureGroupStyle with a retained opacity removal transition over the same 0.28-second ease-in/ease-out as the panel. Respect Reduce Motion. The closing replay now preserves settings pixels as the panel shrinks; both directions, reversal, and nonanimated sizing pass.
3. [x] Remove “Battery & connection alerts,” give Quit the native bordered button style, and anchor it to the animated panel bottom. Check the actual Quit region for delayed motion/fading; outgoing settings to its left are intentionally retained during collapse.
4. [x] Move debug entry to Option-click on Notification settings, including when settings are already open. Normal settings opening hides debug controls; Control–Option remains ordinary activation. Test the actual settings action with injected modifiers, without sending desktop events. Reset debug mode when the menu reopens.
5. [x] Build Debug/Release as 0.1.11 (11), verify signatures and offscreen checks, and refresh the canonical Debug app plus dist package. Live mouse/contrast/VoiceOver appearance remains for manual checking; no GUI or input automation is authorized.

Battery-driven menu indicator:
1. [x] Reproduce the dot mismatch with an offscreen 8× raster check: the hollow dot is one point larger overall because its centered stroke extends beyond the filled path. Derive both from shared 6.2-point outer bounds; the pixel regression now passes.
2. [x] Replace unread-notification state with an indicator driven by last known accessory battery levels. Fill at or below Alert at; clear above it without notification hysteresis. Menu opening, delivery, permission, and dismissal do not change the indicator. Charging alone, missing readings, or disconnection do not establish recovery. Retain known readings during the current run and reevaluate immediately when the threshold changes.
3. [x] Check dismissal, charging, exact threshold recovery, missing/unknown observations, multiple accessories, and disabled notifications through an isolated app-bundle diagnostic. Preserve native notification delivery gating and its existing hysteresis. Update the accessible menu label to announce low battery rather than unread notifications.
4. [x] Build Debug/Release as 0.1.12 (12), pass both lifecycle and pixel checks, verify signatures, and refresh the canonical Debug app and dist package. No GUI windows, desktop input, or test notifications were used.

Source placement, system red, and notification presentation:
1. [x] Move the hidden source-reading label and update counter below Notification settings and above Quit. Keep normal-mode reading errors visible in their existing position.
2. [x] Use NSColor.systemRed for the filled dot. Preserve equal outer bounds and the battery-driven lifecycle. Compare rendered semantic-color swatches so HDR tone mapping does not create a false failure against raw NSColor components.
3. [x] Read notification permission, queue, session, preferences, current battery eligibility, and scoped system logs without posting an alert. Confirm a connected, noncharging battery qualifies below the saved threshold, authorization is granted, and the old stable request ID is accepted but updates notification history with present:false instead of presenting a fresh banner.
4. [x] Reproduce request-identity reuse through the actual request factory, then give each alert a fresh UUID while retaining its stable dismissal category. Retire the previous delivered/history identity only after the single-delivery gate permits a new alert or opted-in reminder. Persist the last accepted identity for scoped cleanup across relaunches. Use the public on-console dictionary key for the session check.
5. [x] Pass 42 core tests, the request-factory regression, indicator lifecycle, rendered dot bounds/system color, panel sizes, and both-direction disclosure easing. Build Debug/Release as 0.1.13 (13), verify signatures, and refresh the canonical Debug app and dist package. The new live banner remains for the user's next app launch; no test notifications, desktop input, or GUI app launches were performed.

Hide source details with settings:
1. [x] Require both Option debug mode and an expanded Notification settings dropdown before rendering the source-reading label and update counter. Preserve the position below settings and above Quit.
2. [x] Build Debug/Release as 0.1.14 (14), pass existing settings-action and both-direction disclosure checks, verify signatures, and refresh the canonical Debug app and dist package. No GUI or notification automation was used.

Native HID discovery and notification verification:
1. [x] Diagnose the missing M550 row: the disconnected paired device exposes Bluetooth class 0/0, no cached input services, and no battery reading. Add property-only native IOHIDManager enumeration matched by Bluetooth address and recognized HID usage; never open devices or read input. Remember learned input-device types across disconnects and relaunches. Battery values continue to come exclusively from macOS power sources.
2. [x] Validate five new HID tests, including Bluetooth LE identity/type and rejection of USB, virtual, unknown, and invalid devices; all 47 core tests pass. Native integration identifies the connected keyboard at 53%. The M550 still requires one connected observation before its type can be learned; live mouse behavior remains unverified.
3. [x] Confirm the original disconnect alert was blocked by an existing delivered notification under the requested global single-alert rule. Retain that rule. Observe macOS present a new persistent alert after dismissal; the user confirms the keyboard disconnect alert appeared with the correct blue Bluetooth/red-dot app icon.
4. [x] Remove stale test-bundle registrations that shared the production identifier. Give the generated UI-check bundle its own identifier and re-sign it; register the installed app and verify macOS resolves its correct icon. No global caches were cleared.
5. [x] Build Debug/Release as 0.1.15 (15), pass notification identity, battery indicator, and offscreen panel/icon checks, verify signatures, and refresh the canonical Debug app and dist ZIP. No GUI apps were launched or restarted, desktop input synthesized, or test notifications sent by the agent; the user performed the live keyboard test.

Launch at login and Apple Events:
1. [x] Add an opt-in launch-at-login checkbox using SMAppService.mainApp, with system-owned status, approval guidance, and visible errors. Refresh status on menu opening and activation. Keep the control at the bottom of settings so outgoing content does not overlap Quit during collapse.
2. [x] Bundle an AppleScript dictionary and install native NSAppleEventManager handlers before initial launch events. Accessory status returns cached typed records; refresh polls once and returns updated records. Unknown batteries remain missing value. Retain NSApplication's standard launch/quit behavior; scripts do not change preferences.
3. [x] Pass 47 core tests, isolated login registration/approval/error scenarios, real in-process Apple Events dispatch, and AppleScript compilation without execution. Verify both-direction easing, stable footer, settings activation, panel/icon checks, and notification identities. Build signed universal Debug/Release apps as 0.1.16 (16), refresh dist and its ZIP, document usage, and add login/scripting checks to CI. Live login startup and external script-driven launch/quit remain unverified; no live login items were changed, GUI apps launched/restarted, input synthesized, or notifications sent during verification.

Compact launch-at-login control:
1. [x] Move the native checkbox outside the settings dropdown to the footer beside Quit. Give both controls the same small native control size. Show approval guidance and errors above the footer only when needed; keep installation guidance in the checkbox tooltip.
2. [x] Clip outgoing content above the footer using its native measured height, keeping both controls clear throughout expansion and collapse. Extend the existing footer regression to cover the entire control row. Both Debug and Release pass; real SwiftUI easing, panel sizing, settings actions, and icon checks also pass.
3. [x] Build signed Debug/Release apps as 0.1.17 (17) and refresh the canonical Debug app, dist app, and ZIP. Live login settings remain unchanged; no GUI apps were launched or input synthesized.

Secret audit and commit protection:
1. [x] Review both commits, all advertised refs, commit metadata, current files, and all local Git objects, including 11 local-only staged file versions. Run checksum-verified Gitleaks over history, exported content, CI logs, and the existing app artifact. No secrets or organization-specific references detected; retained logs are redacted and image metadata contains only dimensions. Record scope and limitations in research/SECURITY-REVIEW.md.
2. [x] Pin the official awslabs/git-secrets 1.3.0 script and checksum in mise.toml. Install it through mise, verify the installed bytes, and configure repository-local hk hooks through mise for staged files, commit messages, and file history before push. Keep shared rules versioned without credential providers or broad allowlists.
3. [x] Verify current/history scans and 13 real-hook scenarios in disposable local repositories, using synthetic invalid credentials only. Source, app builds, and published Git history remain unchanged; setup and documentation changes are not committed during this audit.

Prerelease preparation, v0.1.17:
1. [x] Rewrite README feature and installation guidance with the requested ASD-STE100 skill. Add an offscreen capture of the real SwiftUI panel with example devices. Preserve technical decisions in this plan.
2. [x] Build the native universal Release app in a fresh derived-data directory. Confirm version 0.1.17 (17), arm64/x86_64 architectures, and the code signature. All 47 core tests and ten Release integration checks pass, including both resize directions, login fixtures, and Apple Events.
3. [x] Package BTNotify-macOS.zip with a SHA-256 checksum. Extract the ZIP and verify its signature, executable permissions, and binary bytes. README lint, whitespace, and file/history secret checks pass.

The release uses GitHub's prerelease flag with tag v0.1.17. It remains ad hoc signed and not notarized. Intel execution, live VoiceOver navigation, and AirPods component coverage remain unverified.
