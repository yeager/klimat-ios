# Klimat for iPhone

Klimat is an open-source SwiftUI app for iOS 17 and later. Its English interface is localized into Swedish, Spanish, French, German, Simplified Chinese, Hindi, Arabic, Brazilian Portuguese, Japanese, Bengali, Russian, Indonesian, Turkish, Urdu, Marathi, Telugu, Tamil, Vietnamese, Korean, Italian, Polish, and Persian. App Store Connect storefront copy is available in English, Swedish, and 20 common languages; Persian storefront localization is not supported by App Store Connect.

## Privacy first

Klimat has no analytics, advertising, tracking, developer-operated backend, or account. The app does not send usage or device data to the Klimat developer. Compatible local adapters can be discovered and controlled over the same Wi-Fi network without internet access or a cloud account. Device entries are stored in the app's local preferences; protocol keys and optional MELCloud session tokens are stored in the iOS Keychain.

Cloud services are optional. If you choose MELCloud Classic, your sign-in details are sent directly to Mitsubishi Electric's MELCloud service over HTTPS; Klimat does not save your password. Apple Home access is requested only when you choose that feature, and is handled through Apple's HomeKit framework. See [PRIVACY.md](PRIVACY.md) for details.

Gitleaks scans the complete Git history on pushes, pull requests, and a daily schedule. The workflow is in [`.github/workflows/gitleaks.yml`](.github/workflows/gitleaks.yml).

## Local device control

Klimat searches the private IPv4 subnet used by the iPhone on Wi-Fi for compatible Daikin, Mitsubishi, and Gree adapters. Manually entered addresses must be on that same Wi-Fi subnet; public addresses, hostnames, and other networks are rejected. Daikin support covers adapters with the older local HTTP API. Mitsubishi support covers MAC-577 adapters with the local `/smart` interface and encrypted traffic, including vertical and horizontal vane controls when the adapter reports those positions. Gree support covers compatible Smart Wi-Fi modules using the Gree protocol on UDP port 7000; pairing happens locally and the device key is stored in the iOS Keychain. Power, temperature, mode, fan, and status are controlled over Wi-Fi without internet or cloud access. Mitsubishi and Gree protocol implementations are based on the references [pymitsubishi](https://github.com/pymitsubishi/pymitsubishi) and [gree-climate](https://github.com/thesmokinator/gree-climate); see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Klimat can also read and control compatible climate services that you have already added to Apple Home. Access is requested only when you select Apple Home. Available controls depend on the accessory.

MELCloud Classic is an optional cloud connection for Mitsubishi accounts and requires internet access. Its API is unofficial and has not been verified against physical AC hardware. Other manufacturers' cloud services are not connected.

## Apple Watch companion

The companion watchOS app shows the selected device's status and lets you switch devices, power, temperature, and mode. Watch Connectivity relays commands to the paired iPhone, which uses the existing device adapter. The watch can request a fresh read through that adapter and shows when its displayed status was last confirmed; while the phone or AC is unreachable it labels the saved reading as cached. For supported local adapters, status reads and AC commands stay on the local Wi-Fi network and do not need a cloud service or internet access. The iPhone must be reachable for live watch updates and commands. Temperature units follow the iPhone setting. The latest device state is shared only with the paired watch; Klimat has no developer backend, analytics, or tracking.

Compatibility depends on the adapter, firmware, and protocol version. The desktop Klimat reference has been physically verified with two Mitsubishi MSZ-LN35VG2W units using MAC-577IF-2E, including status, temperature changes, and vane controls. The iPhone Swift port uses the same MAC-577 local HTTP protocol, but iPhone-specific hardware control still needs testing. The MELCloud iPhone integration has passed account sign-in and device enumeration for one account; no AC command was sent during that test, so command control remains unverified. Gree support still needs physical-device testing. Network discovery checks only the iPhone's private IPv4 Wi-Fi subnet, rejects subnets larger than 512 addresses, and is not a general scan for all AC brands.

## Build

Open `KlimatMobile.xcodeproj` in Xcode and build the `KlimatMobile` scheme. The project can also be generated from `project.yml` using XcodeGen.

## License

Klimat is licensed under the MIT License. Third-party protocol reference notices are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
