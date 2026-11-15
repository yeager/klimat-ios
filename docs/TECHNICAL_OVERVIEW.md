# Klimat technical overview

This document describes the implementation in this repository. It distinguishes code that exists from compatibility that still needs physical verification. The current App Store submission must remain untouched until Apple finishes reviewing it.

## Product and targets

Klimat is an open-source SwiftUI climate-control app. The iPhone target supports iOS 17 and later; the companion watch app supports watchOS 10 and later. XcodeGen configuration is in `project.yml`, and the generated project is `KlimatMobile.xcodeproj`. The mobile bundle identifier is `se.yeager.klimat.ios`; the watch bundle identifier is `se.yeager.klimat.ios.watchkitapp`. Version and build numbers are configured centrally in `project.yml`.

The app's primary product promise is direct control on the home Wi-Fi network, without an internet connection or manufacturer cloud account, for compatible devices. Cloud and Apple Home connections are separate, opt-in paths.

## Architecture

- `KlimatMobile/KlimatApp.swift` owns the `ClimateStore` and the phone side of Watch Connectivity.
- `KlimatMobile/ClimateStore.swift` stores the device list, routes reads and commands to adapters, coordinates discovery, and persists device records.
- `KlimatMobile/HomeView.swift` implements the iPhone interface, onboarding/add-device flows, controls, settings, Face ID gate, and service connection sheets.
- `KlimatMobile/*Adapter.swift` contains manufacturer, MELCloud, and Apple Home adapters.
- `KlimatMobile/MideaLAN/` contains the local Midea protocol V2 implementation and its third-party license notice.
- `KlimatWatch/WatchApp/KlimatWatchApp.swift` implements the watch UI and phone relay.
- `KlimatMobile/Assets.xcassets/AppIcon.appiconset/` contains the generated app icon used by the iOS target.

The app UI calls the store; the store calls an adapter. Local adapters validate their target against the current private Wi-Fi subnet before opening a connection. Optional cloud calls bypass local adapter routing only for devices explicitly added through the cloud flow.

## Device connections

| Integration | Transport and behavior | Current limitations |
| --- | --- | --- |
| Daikin local | Legacy local HTTP API; discovery and control over Wi-Fi | Only compatible adapters exposing that older API are supported. |
| Mitsubishi Electric local | MAC-577 adapter `/smart` interface, encrypted payloads, local Wi-Fi; temperature, power, mode, fan and reported vertical/horizontal vanes | iPhone adapter still needs physical-device validation. Desktop reference has been verified with two MSZ-LN35VG2W units and MAC-577IF-2E. The adapter's existing cloud setting is not changed. |
| Gree local | Gree Smart Wi-Fi protocol over UDP port 7000; local scan/bind; pairing key stored in Keychain | Compatible modules/firmware only; iPhone implementation still needs physical-device validation. |
| Midea local V2 | Midea protocol V2 discovery over local broadcast or a manually targeted local IP, and TCP control; no cloud token/account | Protocol V3 is excluded because it uses a cloud-provisioned token/key. The V2 iPhone implementation is unverified on physical hardware. |
| MELCloud Classic | Optional HTTPS login and cloud device read/control for Mitsubishi accounts | Unofficial API. Login and device enumeration were checked for one account; no AC command was sent, so control is unverified. Internet and Mitsubishi's service are required. |
| Apple Home | User-initiated HomeKit enumeration/read/control of compatible climate accessories | Apple Home access is requested when the user invokes that feature. Controls depend on accessory capabilities. |

Mode, fan, and temperature ranges vary by adapter and are clamped where implemented. Mitsubishi exposes vane controls when its adapter returns those values. A protocol or brand name alone does not guarantee compatibility: adapter model, firmware, region, and configuration matter.

## Direct discovery and network boundary

`LocalWiFiIPv4` obtains the IPv4 interface for Wi-Fi (`en0`), requires an RFC 1918 private address, calculates the current subnet, and refuses subnets with more than 512 addresses. Discovery probes only that subnet, in batches for Daikin and Mitsubishi, and uses the subnet's own broadcast address for Gree and Midea protocols. User-entered local adapter addresses must be numeric IPv4 addresses on that same subnet. Public addresses, hostnames, other interfaces, and other networks are rejected.

This is a bounded compatibility scan, not a universal AC detector. iOS asks the user for Local Network access through `NSLocalNetworkUsageDescription`. Discovery and local control require the iPhone to be on the same reachable network as the adapter; router client isolation, VLANs, firewall rules, or a sleeping adapter can prevent access. No general internet connectivity is required for local adapter commands.

## Apple Watch relay

The watch cannot directly reach the AC. It sends a small Watch Connectivity message to the paired iPhone containing a command, device ID, and control value. `PhoneWatchConnectivity` validates the command and routes it through `ClimateStore`; the phone then uses the selected device's adapter. A state snapshot is sent back to the watch and is also shared as the latest application context. Snapshots contain device IDs/names, connection label, power, temperatures, mode, fan, supported temperature bounds, selected ID, update time, and temperature unit. They do not include protocol keys or cloud credentials.

Live commands need a reachable iPhone and, for local adapters, the iPhone's local Wi-Fi connection to the AC. The watch may display a cached snapshot while disconnected; it cannot execute AC commands independently. The watch settings/control surface currently offers power, temperature, mode, selection and refresh; it does not expose phone-only settings or all fan/vane controls.

## Preferences, privacy and security

Klimat has no analytics, advertising, tracking, developer account, or developer-operated backend. The developer does not receive device inventory, usage, or local commands.

- Device records and selected-device state are encoded into app preferences (`UserDefaults`, key `klimat.ios.devices`). This can include user-assigned names, local IPs, device state, and adapter identifiers. iOS backup behavior follows device settings.
- Gree pairing keys and the optional MELCloud session token are stored in the iOS Keychain. The MELCloud password is sent directly to Mitsubishi Electric over HTTPS and is cleared from the form after sign-in; Klimat does not persist it.
- Local traffic stays between phone and AC on Wi-Fi. Encryption is protocol/device dependent; the legacy Daikin HTTP interface is not end-to-end encrypted by Klimat.
- Face ID is optional (`klimat.requireFaceID`). LocalAuthentication returns only success/failure to the app; biometric data is never accessible to Klimat. The lock is applied when the app opens or returns from background.
- Appearance is selectable as system, light, or dark (`klimat.appearance`). Temperature display is selectable as Celsius or Fahrenheit (`klimat.temperatureUnit`).
- HomeKit access is requested only when Apple Home is selected. Apple governs its Home data handling.
- Privacy manifest: `KlimatMobile/PrivacyInfo.xcprivacy`. User-facing policy: `PRIVACY.md`.

The App Store privacy label declares email and other data linked to identity for app functionality because of optional MELCloud use. That does not mean the Klimat developer receives those details: they are sent to Mitsubishi Electric for the service. Local-only use does not send AC data off the local network.

## Localization and store content

The app UI has English source strings and 22 localized catalogs (including Swedish) under `KlimatMobile/*.lproj/Localizable.strings`. Store listing drafts are under `store-listings/`. Listings exist for English, Swedish and 20 common App Store languages; Persian is present in-app but not offered as a storefront listing because App Store Connect does not support that locale. Keep local/offline operation as the leading store message, and do not imply unverified physical compatibility.

## Build and verification

Open `KlimatMobile.xcodeproj` in Xcode and select the `KlimatMobile` or `KlimatWatchApp` scheme. To regenerate the Xcode project after changing the spec, run `xcodegen generate --spec project.yml`.

Useful checks when explicitly requested include an iOS simulator build, watchOS simulator build, `plutil -lint` on localized `.strings` catalogs, `git diff --check`, and Gitleaks. A simulator build verifies compilation only; it does not verify local radio/network behavior, real adapter protocols, Watch Connectivity on paired devices, cloud command semantics, or App Store review. Gitleaks also runs in GitHub Actions on pushes, pull requests, manual dispatch, and daily schedule (`.github/workflows/gitleaks.yml`).

## Release and validation status

The user has explicitly asked that no new build be submitted to Apple until the version currently in review is approved. Do not upload or submit a replacement before that condition is met. The current App Store Connect state previously observed was **Waiting for Review**. Re-check status before any later release action; no local build or upload implies approval or publication.

Physical iPhone verification is deferred. Before describing mobile compatibility as hardware-verified, check each adapter against a real compatible device, including discovery, state read, power, temperature, mode, fan, and any supported vanes. Also verify offline behavior with WAN unavailable. MELCloud commands need separate explicit confirmation and safe hardware testing; the earlier account check only established sign-in and enumeration.

## Reference protocol projects and notices

Protocol references and their MIT attributions are documented in `THIRD_PARTY_NOTICES.md`. Key references: [pymitsubishi](https://github.com/pymitsubishi/pymitsubishi), [gree-climate](https://github.com/thesmokinator/gree-climate), [MideaKit](https://github.com/hafacc/MideaKit), and [msmart-ng](https://github.com/mill1000/midea-msmart). MELCloud Classic is an unofficial API. See the project license (`LICENSE`) and third-party notices before redistributing modified protocol code.
