# Klimat Privacy Policy

**Effective date: November 14, 2026**

Klimat is an open-source iPhone app. It has no analytics, advertising, tracking, developer-operated backend, or user account. The Klimat developer does not collect or receive personal information or app-usage data through the app.

## Data on your device

Klimat stores the climate devices you add and their control state in the app's local preferences so the app can show them again. Local network addresses and device names may be included in this information. Gree protocol keys and an optional MELCloud session token are stored in the iOS Keychain. Klimat does not save your MELCloud password. Data in app preferences may be included in device backups according to your iOS backup settings.

You can remove saved devices in the app. Disconnect MELCloud to clear its session token. Removing all devices also removes saved Gree protocol keys. iOS manages Face ID authentication; Klimat receives only the authentication result and never accesses biometric data.

## Local network control

When you use discovery or control a compatible device, Klimat sends protocol requests directly between your iPhone and that device over your local Wi-Fi network. This can include the device's local IP address and commands or status such as power, temperature, mode, and fan setting. These requests are not sent to Klimat's developer. Some compatible devices use local HTTP; network privacy and encryption depend on the device protocol.

## Optional third-party services

**MELCloud Classic:** If you choose to connect, Klimat sends the email and password you enter directly to Mitsubishi Electric's MELCloud service over HTTPS to sign in. The password is not saved by Klimat. A session token and device information returned by MELCloud are used to control and display your devices; the token is kept in the iOS Keychain. MELCloud's handling of this information is governed by Mitsubishi Electric's policies and service terms. Disconnecting MELCloud clears the token stored by Klimat.

**Apple Home:** If you select Apple Home, Klimat requests access to HomeKit data needed to list and control compatible climate accessories already in your Apple Home. Apple manages this access under its own privacy terms. Klimat requests HomeKit access only when you choose the feature.

## App Store privacy label

The App Store privacy label lists Email Address and Other Data as linked to the user's identity and used for App Functionality. These declarations reflect the optional MELCloud integration: Klimat sends your sign-in email and climate control requests to Mitsubishi Electric, and receives MELCloud account and device records to display and control your equipment. Mitsubishi Electric handles that information under its own service terms. The Klimat developer does not receive it. If you use only local Wi-Fi control, device data stays on your iPhone and AC communications stay on your local network.

## Children's privacy

Klimat does not knowingly collect information from anyone, including children.

## Changes and contact

Changes to this policy will be published with the source code in this repository. For privacy questions, open a GitHub issue at [github.com/yeager/klimat-ios/issues](https://github.com/yeager/klimat-ios/issues).
