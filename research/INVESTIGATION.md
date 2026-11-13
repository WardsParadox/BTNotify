# Accessory power-source investigation

Observed on macOS 27.2, build 26B123, on 2026-11-10.

## Shipped widget evidence

REA's `trace_dylib_resolution` record in `widget-dylib-evidence.json` identifies the shipped `BatteriesAvocadoWidgetExtension` executable and its direct `BatteryCenterUI` dependency under `/System/iOSSupport`. Evidence ID: `ev_00520e166ed2b7ddb9e8d99915374ca7705b3a18ab35848cf7ad1ded8dea92a6`. Executable SHA-256: `954ef25f050c1697ef693278588b05ca072fb27bd6e54b51c3ae848368775bd1`.

This establishes the static dependency declaration. REA's resolution scope excludes external system libraries, so it does not trace that dependency's implementation or executed battery requests. A native decompiler was unavailable; no decompilation was performed.

## Observed runtime results

- `BCBatteryDeviceController.connectedDevices` returned zero devices in a native command-line process, including after registering an observer and pumping the main run loop.
- The shared `_BCPowerSourceController` also returned zero after `_beginPowerSourceObservingIfNecessary` and `_queryConnectedDevices`. Its observer callback delivered an empty array. Running outside the sandbox did not change this result.
- Public `IOPSCopyPowerSourcesInfo()` returned one internal battery at 79% and omitted the connected Bluetooth keyboard.
- Private `IOPSCopyPowerSourcesByType(4)` returned one Bluetooth LE keyboard source at 54%. `IOPSCopyPowerSourcesByType(0)` returned both the internal battery and keyboard. Results matched inside and outside the sandbox.
- Passing either source blob through `_orderedDevicesFromPowerSourcesBlob:powerSourcesList:` produced the corresponding one or two `BCBatteryDevice` objects. Thus BatteryCenter's source-to-device conversion accepts these descriptions even though its automatic controller enumeration was empty in this process.
- The keyboard source provided `Accessory Identifier`, `Power Source ID`, `Current Capacity`, `Max Capacity`, `Name`, `Power Source State`, `Transport Type`, and accessory metadata. It omitted `Is Present` and `Is Charging`. The app reader therefore omits an explicit connection result and lets Bluetooth inventory supply connection state.

The reproducible runtime probe is `tools/probe-power-sources.m`; logs are `power-probe-sandboxed.log` and `power-probe-unsandboxed.log`. Accessory name and identifiers are redacted from retained logs. These logs are ordinary shell/runtime evidence, not REA Evidence records.

## Verified API definitions

Apple's published [IOPowerSourcesPrivate.h](https://github.com/apple-oss-distributions/IOKitUser/blob/main/ps.subproj/IOPowerSourcesPrivate.h) declares `CFTypeRef IOPSCopyPowerSourcesByType(int type)` with `kIOPSSourceAll = 0` and `kIOPSSourceForAccessories = 4`. The function is exported in the installed SDK and resolves at runtime.

Apple's [IOPSKeysPrivate.h](https://github.com/apple-oss-distributions/IOKitUser/blob/main/ps.subproj/IOPSKeysPrivate.h) documents `Accessory Identifier`, `Part Identifier`, and `Part Name`. Accessory identifiers may differ for each part; part identifiers distinguish left, right, case, single, other, and combined sources. The reader preserves part identity rather than reducing all parts to one device ID. It filters the documented `Bluetooth` and `Bluetooth LE` transport values.

## Inferences and unknowns

The powerd accessory source list supplies the battery information missing from the public Bluetooth and public power-source reads on this machine. The successful BatteryCenter conversion supports a relationship with the widget's battery representation. It does not prove the widget's exact executed call path or full device coverage.

The reason the automatic BatteryCenter controller returned an empty array remains unresolved. The comparison rules out this sandbox as the sole explanation. Entitlement requirements, process initialization, platform behavior, caching, and implementation details were not established by this probe. No decompiled implementation or observed widget call trace is available.

Only this keyboard's battery read was validated live. AirPods and other earbuds' left/right/case mapping follows Apple's published definitions but has not been exercised with live earbuds. Power-source disappearance alone is not treated as a confirmed Bluetooth disconnection. No live widget screenshot comparison was performed; widget parity is unverified.

## App integration smoke check

`tools/read-power-sources.m`, linked with `Sources/BatteryBridge/PowerSourceReader.m`, returned one keyboard with battery 54% and connection `not reported`. The reader dynamically resolves the private API, validates capacity ranges, and reports unavailable API/blob/list errors separately from a successful empty result.

The integrated Swift app's `--diagnose` command, run outside the agent sandbox, joined the keyboard source to its unique Bluetooth inventory name and reported connected with battery 54%. It parsed 11 inventory entries, with the other 10 explicitly disconnected. Inside the sandbox, `system_profiler` returned no device inventory while the power-source API still returned the keyboard; this restriction must not be mistaken for a disconnected accessory. The app runs as a normal unsandboxed local app.

All 31 core tests passed: inventory parsing, source merging, connection transitions, low-battery deduplication, charging suppression, recovery thresholds, partial observations, and baseline resets. Live notification banners and actual disconnect/reconnect transitions still require an interactive macOS permission and hardware check.
