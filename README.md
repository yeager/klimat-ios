# Klimat

Klimat is an open-source iPhone app and Apple Watch companion for controlling compatible air conditioners. Its main feature is direct control over your local Wi-Fi network, without internet access or a cloud account, for supported adapters.

For the full implementation guide, device compatibility boundaries, privacy/data flows, network restrictions, Watch behavior, build steps and current verification status, see [the technical overview](docs/TECHNICAL_OVERVIEW.md).

## At a glance

- **Direct local adapters:** Daikin legacy local HTTP, Mitsubishi MAC-577, Gree Smart Wi-Fi, and Midea protocol V2.
- **Optional integrations:** MELCloud Classic cloud service and Apple Home.
- **Apple Watch:** relays controls through the paired iPhone; the watch does not connect to AC hardware itself.
- **Privacy:** no analytics, tracking, advertising, developer account, or developer-operated backend.
- **Settings:** system/light/dark appearance, Celsius/Fahrenheit, and optional Face ID app lock.
- **Platforms:** iOS 17+ and watchOS 10+.

Compatibility depends on the exact adapter and firmware. The iPhone implementation for Mitsubishi, Gree, and Midea V2 still needs physical-device validation. MELCloud command control is also unverified. Do not treat simulator builds as hardware validation.

Klimat is an open-source SwiftUI app for iOS 17 and later. Its English interface is localized into Swedish, Spanish, French, German, Simplified Chinese, Hindi, Arabic, Brazilian Portuguese, Japanese, Bengali, Russian, Indonesian, Turkish, Urdu, Marathi, Telugu, Tamil, Vietnamese, Korean, Italian, Polish, and Persian. App Store Connect storefront copy is available in English, Swedish, and 20 common languages; Persian storefront localization is not supported by App Store Connect.

## Privacy first

Klimat has no analytics, advertising, tracking, developer-operated backend, or account. The app does not send usage or device data to the Klimat developer. Compatible local adapters can be discovered and controlled over the same Wi-Fi network without internet access or a cloud account. Device entries are stored in the app's local preferences; protocol keys and optional MELCloud session tokens are stored in the iOS Keychain.

Cloud services are optional. If you choose MELCloud Classic, your sign-in details are sent directly to Mitsubishi Electric's MELCloud service over HTTPS; Klimat does not save your password. Apple Home access is requested only when you choose that feature, and is handled through Apple's HomeKit framework. See [PRIVACY.md](PRIVACY.md) for details.

Gitleaks scans the complete Git history on pushes, pull requests, and a daily schedule. The workflow is in [`.github/workflows/gitleaks.yml`](.github/workflows/gitleaks.yml).

## Local device control

Klimat searches the private IPv4 subnet used by the iPhone on Wi-Fi for compatible adapters. See the [technical overview](docs/TECHNICAL_OVERVIEW.md#direct-discovery-and-network-boundary) for scan limits and protocol details.

Klimat can also read and control compatible climate services that you have already added to Apple Home. Access is requested only when you select Apple Home. Available controls depend on the accessory.

MELCloud Classic is an optional cloud connection for Mitsubishi accounts and requires internet access. Its API is unofficial and has not been verified against physical AC hardware. Other manufacturers' cloud services are not connected.

## Apple Watch companion

The companion watchOS app shows the selected device's status and lets you switch devices, power, temperature, and mode. Watch Connectivity relays commands to the paired iPhone, which uses the existing device adapter. The watch can request a fresh read through that adapter and shows when its displayed status was last confirmed; while the phone or AC is unreachable it labels the saved reading as cached. For supported local adapters, status reads and AC commands stay on the local Wi-Fi network and do not need a cloud service or internet access. The iPhone must be reachable for live watch updates and commands. Temperature units follow the iPhone setting. The latest device state is shared only with the paired watch; Klimat has no developer backend, analytics, or tracking.

Compatibility depends on the adapter, firmware, and protocol version. The desktop Klimat reference has been physically verified with two Mitsubishi MSZ-LN35VG2W units using MAC-577IF-2E. The iPhone implementations for Mitsubishi, Gree and Midea V2 still need physical-device validation. MELCloud sign-in and device enumeration have passed for one account; no AC command was sent, so command control is unverified. See [verification and build guidance](docs/TECHNICAL_OVERVIEW.md#build-and-verification).

## License

Klimat is licensed under the MIT License. Third-party protocol reference notices are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
