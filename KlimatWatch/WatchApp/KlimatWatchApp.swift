import SwiftUI
import WatchConnectivity

@main
struct KlimatWatchApp: App {
    @StateObject private var connectivity = WatchConnectivityModel()

    var body: some Scene {
        WindowGroup {
            KlimatWatchHomeView()
                .environmentObject(connectivity)
        }
    }
}

private struct WatchClimateDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let brand: String
    let connection: String
    let isOn: Bool
    let current: Double
    let target: Double
    let mode: String
    let fan: String

#if DEBUG
    static let preview = WatchClimateDevice(
        id: "preview-daikin",
        name: "Living Room",
        brand: "Daikin",
        connection: "Local network",
        isOn: true,
        current: 23.5,
        target: 22,
        mode: "Cool",
        fan: "Auto"
    )
#endif

    init(id: String, name: String, brand: String, connection: String, isOn: Bool, current: Double, target: Double, mode: String, fan: String) {
        self.id = id
        self.name = name
        self.brand = brand
        self.connection = connection
        self.isOn = isOn
        self.current = current
        self.target = target
        self.mode = mode
        self.fan = fan
    }

    init?(dictionary: [String: Any]) {
        guard let id = dictionary["id"] as? String,
              let name = dictionary["name"] as? String else { return nil }
        self.id = id
        self.name = name
        brand = dictionary["brand"] as? String ?? ""
        connection = dictionary["connection"] as? String ?? ""
        isOn = dictionary["isOn"] as? Bool ?? false
        current = (dictionary["current"] as? NSNumber)?.doubleValue ?? 0
        target = (dictionary["target"] as? NSNumber)?.doubleValue ?? 22
        mode = dictionary["mode"] as? String ?? "Auto"
        fan = dictionary["fan"] as? String ?? "Auto"
    }
}

@MainActor
private final class WatchConnectivityModel: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var devices: [WatchClimateDevice] = []
    @Published private(set) var selectedID = ""
    @Published private(set) var isPhoneReachable = false
    @Published private(set) var temperatureUnit = "celsius"
    @Published private(set) var message: String?

    private let session = WCSession.default
#if DEBUG
    private var isPreview = false
    private var didRunControlRelayCheck = false
#endif

    override init() {
        super.init()
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--klimat-watch-preview") {
            devices = [.preview]
            selectedID = "preview-daikin"
            isPhoneReachable = true
            isPreview = true
            return
        }
#endif
        guard WCSession.isSupported() else {
            message = String(localized: "Connection unavailable")
            return
        }
        session.delegate = self
        session.activate()
        apply(session.receivedApplicationContext)
    }

    var selectedDevice: WatchClimateDevice? {
        devices.first(where: { $0.id == selectedID }) ?? devices.first
    }

    var usesFahrenheit: Bool { temperatureUnit == "fahrenheit" }

    func refresh() {
        send(["command": "refresh"])
    }

    func select(_ device: WatchClimateDevice) {
        send(["command": "select", "deviceID": device.id])
    }

    func selectAdjacent(_ offset: Int) {
        guard !devices.isEmpty else { return }
        let currentIndex = devices.firstIndex(where: { $0.id == selectedID }) ?? 0
        let nextIndex = (currentIndex + offset + devices.count) % devices.count
        select(devices[nextIndex])
    }

    func togglePower(for device: WatchClimateDevice) {
        send(["command": "control", "deviceID": device.id, "action": "power", "value": device.isOn ? "off" : "on"])
    }

    func setTemperature(for device: WatchClimateDevice, direction: Double) {
        let displayed = usesFahrenheit ? device.target * 9 / 5 + 32 : device.target
        let step = usesFahrenheit ? 1.0 : 0.5
        let nextDisplayed = displayed + direction * step
        let nextCelsius = usesFahrenheit ? (nextDisplayed - 32) * 5 / 9 : nextDisplayed
        let bounded = min(30, max(16, nextCelsius))
        send(["command": "control", "deviceID": device.id, "action": "temperature", "number": bounded])
    }

    func setMode(_ mode: String, for device: WatchClimateDevice) {
        send(["command": "control", "deviceID": device.id, "action": "mode", "value": mode])
    }

    func displayed(_ celsius: Double) -> Double {
        usesFahrenheit ? celsius * 9 / 5 + 32 : celsius
    }

    private func send(_ message: [String: Any]) {
#if DEBUG
        if isPreview { return }
#endif
        guard session.activationState == .activated, session.isReachable else {
            isPhoneReachable = false
            self.message = String(localized: "Connection unavailable")
            return
        }
        self.message = nil
        session.sendMessage(message, replyHandler: { [weak self] reply in
            Task { @MainActor in self?.apply(reply) }
        }, errorHandler: { [weak self] _ in
            Task { @MainActor in
                self?.isPhoneReachable = false
                self?.message = String(localized: "Connection unavailable")
            }
        })
    }

    private func apply(_ context: [String: Any]) {
        if let rawDevices = context["devices"] as? [[String: Any]] {
            devices = rawDevices.compactMap(WatchClimateDevice.init(dictionary:))
        }
        if let selected = context["selectedID"] as? String { selectedID = selected }
        if let unit = context["temperatureUnit"] as? String { temperatureUnit = unit }
        message = context["error"] as? String
        isPhoneReachable = session.isReachable
    }

#if DEBUG
    private func runControlRelayCheckIfRequested() {
        guard !didRunControlRelayCheck,
              ProcessInfo.processInfo.arguments.contains("--klimat-watch-control-relay-check"),
              session.activationState == .activated,
              session.isReachable else { return }
        didRunControlRelayCheck = true
        // The unknown device ID is rejected by the phone before any adapter can send AC traffic.
        send([
            "command": "control",
            "deviceID": "__klimat_missing_device_relay_check__",
            "action": "power",
            "value": "on"
        ])
    }
#endif

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isPhoneReachable = session.isReachable
            self.apply(session.receivedApplicationContext)
#if DEBUG
            self.runControlRelayCheckIfRequested()
#endif
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isPhoneReachable = session.isReachable
#if DEBUG
            self.runControlRelayCheckIfRequested()
#endif
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor [weak self] in self?.apply(applicationContext) }
    }
}

private struct KlimatWatchHomeView: View {
    @EnvironmentObject private var connectivity: WatchConnectivityModel

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                if connectivity.devices.count > 1 {
                    HStack(spacing: 4) {
                        Button { connectivity.selectAdjacent(-1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Previous device")
                        Text(connectivity.selectedDevice?.name ?? "Klimat")
                            .font(.headline)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                        Button { connectivity.selectAdjacent(1) } label: { Image(systemName: "chevron.right") }
                            .accessibilityLabel("Next device")
                    }
                    .buttonStyle(.plain)
                    .disabled(!connectivity.isPhoneReachable)
                } else {
                    Text(connectivity.selectedDevice?.name ?? "Klimat")
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                }

                if let device = connectivity.selectedDevice {
                    HStack(spacing: 5) {
                        Circle().fill(connectivity.isPhoneReachable ? .green : .orange).frame(width: 6, height: 6)
                        Text(device.isOn ? "ON" : "OFF")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(device.isOn ? .green : .secondary)
                        Text("·")
                        Text(LocalizedStringKey(device.mode)).font(.caption2)
                    }

                    HStack(alignment: .center, spacing: 4) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("INDOORS").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text("\(connectivity.displayed(device.current), specifier: "%.1f")°")
                                    .font(.system(size: 22, weight: .medium, design: .rounded))
                                    .monospacedDigit()
                                Text(connectivity.usesFahrenheit ? "F" : "C")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer(minLength: 2)

                        VStack(alignment: .trailing, spacing: 1) {
                            Text("SET POINT").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                            HStack(spacing: 5) {
                                Button { connectivity.setTemperature(for: device, direction: -1) } label: {
                                    Image(systemName: "minus").font(.caption2.weight(.bold))
                                        .frame(width: 28, height: 28)
                                        .background(.gray.opacity(0.2), in: Circle())
                                }
                                .accessibilityLabel("Lower temperature")

                                Text("\(connectivity.displayed(device.target), specifier: "%.1f")°")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .frame(minWidth: 42)

                                Button { connectivity.setTemperature(for: device, direction: 1) } label: {
                                    Image(systemName: "plus").font(.caption2.weight(.bold))
                                        .frame(width: 28, height: 28)
                                        .background(.gray.opacity(0.2), in: Circle())
                                }
                                .accessibilityLabel("Raise temperature")
                            }
                            .buttonStyle(.plain)
                            .disabled(!connectivity.isPhoneReachable)
                        }
                    }

                    HStack(spacing: 8) {
                        Button { connectivity.togglePower(for: device) } label: {
                            Image(systemName: "power").font(.caption.weight(.semibold))
                                .frame(width: 32, height: 32)
                                .background(device.isOn ? Color.green : Color.gray, in: Circle())
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(device.isOn ? "Turn off" : "Turn on")

                        Button {
                            let modes = ["Auto", "Cool", "Heat", "Dry", "Fan"]
                            let next = ((modes.firstIndex(of: device.mode) ?? 0) + 1) % modes.count
                            connectivity.setMode(modes[next], for: device)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.trianglehead.2.clockwise")
                                Text(LocalizedStringKey(device.mode))
                            }
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 9)
                            .frame(height: 28)
                            .background(.gray.opacity(0.2), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Change mode")
                    }
                    .disabled(!connectivity.isPhoneReachable)

                    if !connectivity.isPhoneReachable {
                        Text("Connection unavailable")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    Text("Connection unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let message = connectivity.message {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 5)
        }
        .task { connectivity.refresh() }
    }
}
