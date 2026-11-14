import Foundation
import Darwin
import HomeKit

struct ClimateDevice: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var brand: String
    var connection: String
    var isOn: Bool
    var current: Double
    var target: Double
    var mode: String
    var fan: String
    var host: String?
    var homeServiceID: String? = nil
}

struct CloudProvider: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let color: String
}

@MainActor final class ClimateStore: ObservableObject {
    @Published var devices: [ClimateDevice] = []
    @Published var selectedID: String?
    @Published var isScanning = false
    @Published var scanMessage = String(localized: "Find devices on your Wi-Fi")
    @Published var showCloudSetup = false
    @Published var selectedProvider: CloudProvider?
    @Published var connectionNotice: String?
    @Published var isLoadingAppleHome = false
    @Published var appleHomeStatus = String(localized: "Add climate devices from Apple Home")
    private let storageKey = "klimat.ios.devices"
    private let appleHome = HomeKitClimateAdapter()

    let providers: [CloudProvider] = [
        .init(id: "melcloud", title: "MELCloud", detail: "Mitsubishi Electric", symbol: "cloud", color: "#4A8069"),
        .init(id: "lg", title: "LG ThinQ", detail: "LG air conditioning", symbol: "cloud", color: "#B44B68"),
        .init(id: "panasonic", title: "Panasonic Comfort Cloud", detail: "Panasonic", symbol: "cloud", color: "#4269A2"),
        .init(id: "smartthings", title: "SmartThings", detail: "Samsung", symbol: "cloud", color: "#3972C6"),
        .init(id: "toshiba", title: "Toshiba Lifestyle", detail: "Toshiba", symbol: "cloud", color: "#B04D4D"),
        .init(id: "gree", title: "Gree", detail: "Gree Cloud", symbol: "cloud", color: "#458A6A"),
        .init(id: "midea", title: "Midea", detail: "Midea Air", symbol: "cloud", color: "#D27A42")
    ]

    init() {
        appleHome.onDevicesChanged = { [weak self] homeDevices in
            guard let self else { return }
            let localDevices = self.devices.filter { $0.brand != "Apple Home" }
            self.devices = localDevices + homeDevices
            if self.selectedID == nil { self.selectedID = homeDevices.first?.id }
            self.save()
            self.isLoadingAppleHome = false
            self.appleHomeStatus = homeDevices.isEmpty ? String(localized: "No climate controls found in Apple Home.") : String(localized: "Found \(homeDevices.count) climate controls in Apple Home.")
        }
        if let data = UserDefaults.standard.data(forKey: storageKey), let saved = try? JSONDecoder().decode([ClimateDevice].self, from: data) {
            devices = saved
            selectedID = saved.first?.id
        }
    }
    var selected: ClimateDevice? { devices.first(where: { $0.id == selectedID }) ?? devices.first }
    func save() { if let data = try? JSONEncoder().encode(devices) { UserDefaults.standard.set(data, forKey: storageKey) } }
    func connectDaikin(host: String, name: String) async {
        do {
            let state = try await DaikinLocalAdapter.read(host: host)
            let device = ClimateDevice(id: state.id, name: name.isEmpty ? state.name : name, brand: "Daikin", connection: "Local network · \(host)", isOn: state.isOn, current: state.current, target: state.target, mode: state.mode, fan: state.fan, host: state.host)
            if let index = devices.firstIndex(where: { $0.id == device.id }) { devices[index] = device } else { devices.append(device) }
            selectedID = device.id; save()
        } catch { connectionNotice = error.localizedDescription }
    }
    func command(action: String, value: String? = nil, number: Double? = nil) async {
        if let device = selected, device.brand == "Apple Home", let serviceID = device.homeServiceID {
            do {
                let state = try await appleHome.command(serviceID: serviceID, action: action, value: value, number: number)
                guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
                devices[index] = state
                save()
            } catch { connectionNotice = error.localizedDescription }
            return
        }
        guard let device = selected, device.brand == "Daikin", let host = device.host else {
            connectionNotice = String(localized: "This device does not have a local control adapter."); return
        }
        do {
            let state = try await DaikinLocalAdapter.command(host: host, action: action, value: value, number: number)
            guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
            devices[index].isOn = state.isOn; devices[index].current = state.current; devices[index].target = state.target; devices[index].mode = state.mode; devices[index].fan = state.fan; save()
        } catch { connectionNotice = error.localizedDescription }
    }
    func scanAppleHome() {
        isLoadingAppleHome = true
        appleHomeStatus = String(localized: "Searching Apple Home for climate devices…")
        appleHome.refresh()
    }
    func beginScan() {
        guard !isScanning else { return }
        isScanning = true; scanMessage = String(localized: "Scanning this Wi-Fi network for compatible Daikin adapters…")
        Task { @MainActor [weak self] in
            guard let self else { return }
            let hosts = LocalSubnetDiscovery.hosts()
            guard !hosts.isEmpty else {
                self.scanMessage = String(localized: "Could not determine the Wi-Fi subnet. Enter the adapter IP address instead.")
                self.isScanning = false
                return
            }
            var found: [DaikinState] = []
            for start in stride(from: 0, to: hosts.count, by: 24) {
                let batch = Array(hosts[start..<min(start + 24, hosts.count)])
                await withTaskGroup(of: DaikinState?.self) { group in
                    for host in batch {
                        group.addTask { try? await DaikinLocalAdapter.discover(host: host) }
                    }
                    for await state in group { if let state { found.append(state) } }
                }
            }
            guard self.isScanning else { return }
            for state in found {
                let device = ClimateDevice(id: state.id, name: state.name, brand: "Daikin", connection: "Local network · \(state.host)", isOn: state.isOn, current: state.current, target: state.target, mode: state.mode, fan: state.fan, host: state.host)
                if let index = self.devices.firstIndex(where: { $0.id == device.id || $0.host == device.host }) { self.devices[index] = device }
                else { self.devices.append(device) }
                if self.selectedID == nil { self.selectedID = device.id }
            }
            self.save()
            self.isScanning = false
            self.scanMessage = found.isEmpty
                ? String(localized: "No compatible direct Daikin adapters found on this Wi-Fi network. You can enter an adapter IP address manually.")
                : String(localized: "Found \(found.count) compatible Daikin adapter(s) on this Wi-Fi network.")
        }
    }
    func connectCloud(provider: CloudProvider) {
        connectionNotice = String(localized: "\(provider.title) requires a manufacturer adapter. No sign-in was performed.")
    }
}

@MainActor private final class HomeKitClimateAdapter: NSObject, HMHomeManagerDelegate {
    var onDevicesChanged: (([ClimateDevice]) -> Void)?
    private let manager: HMHomeManager
    private var refreshTask: Task<Void, Never>?

    override init() {
        manager = HMHomeManager()
        super.init()
        manager.delegate = self
    }

    nonisolated func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        Task { @MainActor [weak self] in self?.refresh() }
    }

    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            var results: [ClimateDevice] = []
            for home in manager.homes {
                for accessory in home.accessories {
                    for service in accessory.services where service.serviceType == HMServiceTypeThermostat || service.serviceType == HMServiceTypeHeaterCooler {
                        let values = Dictionary(uniqueKeysWithValues: await service.characteristics.asyncCompactMap { characteristic -> (String, Any)? in
                            guard Self.readableTypes.contains(characteristic.characteristicType), let value = await Self.read(characteristic) else { return nil }
                            return (characteristic.characteristicType, value)
                        })
                        results.append(Self.device(home: home, accessory: accessory, service: service, values: values))
                    }
                }
            }
            onDevicesChanged?(results)
        }
    }

    func command(serviceID: String, action: String, value: String?, number: Double?) async throws -> ClimateDevice {
        guard let service = manager.homes.lazy.flatMap(\.accessories).flatMap(\.services).first(where: { $0.uniqueIdentifier.uuidString == serviceID }) else {
            throw HomeKitControlError.serviceUnavailable
        }
        let byType = Dictionary(uniqueKeysWithValues: service.characteristics.map { ($0.characteristicType, $0) })
        switch action {
        case "temperature":
            try await Self.write(number ?? 22, to: byType[HMCharacteristicTypeTargetTemperature])
        case "mode":
            let raw: Int
            switch value {
            case "Heat": raw = 1
            case "Cool": raw = 2
            case "Auto": raw = service.serviceType == HMServiceTypeThermostat ? 3 : 0
            case "Dry": throw HomeKitControlError.unsupportedMode
            default: throw HomeKitControlError.unsupportedMode
            }
            let type = service.serviceType == HMServiceTypeThermostat ? HMCharacteristicTypeTargetHeatingCooling : HMCharacteristicTypeTargetHeaterCoolerState
            try await Self.write(raw, to: byType[type])
        case "power":
            if let active = byType[HMCharacteristicTypeActive] {
                try await Self.write((value == "on" ? 1 : 0) as Int, to: active)
            } else if service.serviceType == HMServiceTypeThermostat, let mode = byType[HMCharacteristicTypeTargetHeatingCooling] {
                let current = (mode.value as? NSNumber)?.intValue ?? 3
                try await Self.write(value == "on" ? (current == 0 ? 3 : current) : 0, to: mode)
            } else {
                throw HomeKitControlError.unsupportedPowerControl
            }
        case "fan": throw HomeKitControlError.unsupportedFanControl
        default: throw HomeKitControlError.unsupportedMode
        }
        refresh()
        guard let home = manager.homes.first(where: { $0.accessories.contains(where: { $0.services.contains(where: { $0.uniqueIdentifier.uuidString == serviceID }) }) }),
              let accessory = home.accessories.first(where: { $0.services.contains(where: { $0.uniqueIdentifier.uuidString == serviceID }) }) else { throw HomeKitControlError.serviceUnavailable }
        let values = Dictionary(uniqueKeysWithValues: await service.characteristics.asyncCompactMap { characteristic -> (String, Any)? in
            guard Self.readableTypes.contains(characteristic.characteristicType), let value = await Self.read(characteristic) else { return nil }
            return (characteristic.characteristicType, value)
        })
        return Self.device(home: home, accessory: accessory, service: service, values: values)
    }

    private static let readableTypes: Set<String> = [HMCharacteristicTypeCurrentTemperature, HMCharacteristicTypeTargetTemperature, HMCharacteristicTypeCurrentHeatingCooling, HMCharacteristicTypeTargetHeatingCooling, HMCharacteristicTypeCurrentHeaterCoolerState, HMCharacteristicTypeTargetHeaterCoolerState, HMCharacteristicTypeActive]

    private static func device(home: HMHome, accessory: HMAccessory, service: HMService, values: [String: Any]) -> ClimateDevice {
        let isThermostat = service.serviceType == HMServiceTypeThermostat
        let targetModeType = isThermostat ? HMCharacteristicTypeTargetHeatingCooling : HMCharacteristicTypeTargetHeaterCoolerState
        let targetMode = (values[targetModeType] as? NSNumber)?.intValue ?? 0
        let isOn: Bool
        if isThermostat {
            isOn = targetMode != 0
        } else if let active = values[HMCharacteristicTypeActive] as? NSNumber {
            isOn = active.intValue != 0
        } else {
            isOn = ((values[HMCharacteristicTypeCurrentHeaterCoolerState] as? NSNumber)?.intValue ?? 0) != 0
        }
        let mode: String
        switch targetMode { case 1: mode = "Heat"; case 2: mode = "Cool"; default: mode = "Auto" }
        let id = service.uniqueIdentifier.uuidString
        return ClimateDevice(id: id, name: service.name.isEmpty ? accessory.name : service.name, brand: "Apple Home", connection: "Apple Home · \(home.name)", isOn: isOn, current: (values[HMCharacteristicTypeCurrentTemperature] as? NSNumber)?.doubleValue ?? 0, target: (values[HMCharacteristicTypeTargetTemperature] as? NSNumber)?.doubleValue ?? 22, mode: mode, fan: "Auto", host: nil, homeServiceID: id)
    }

    private static func read(_ characteristic: HMCharacteristic) async -> Any? {
        await withCheckedContinuation { continuation in
            characteristic.readValue { error in continuation.resume(returning: error == nil ? characteristic.value : nil) }
        }
    }

    private static func write(_ value: Any, to characteristic: HMCharacteristic?) async throws {
        guard let characteristic, characteristic.properties.contains(HMCharacteristicPropertyWritable) else { throw HomeKitControlError.characteristicUnavailable }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            characteristic.writeValue(value) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            }
        }
    }
}

private enum HomeKitControlError: LocalizedError {
    case serviceUnavailable, characteristicUnavailable, unsupportedMode, unsupportedPowerControl, unsupportedFanControl
    var errorDescription: String? {
        switch self {
        case .serviceUnavailable: return String(localized: "Climate control was not found in Apple Home. Scan for devices again.")
        case .characteristicUnavailable: return String(localized: "This device does not support this control.")
        case .unsupportedMode: return String(localized: "This operating mode is not supported by the Apple Home device.")
        case .unsupportedPowerControl: return String(localized: "Power control is not supported by the Apple Home device.")
        case .unsupportedFanControl: return String(localized: "Fan speed cannot be controlled through Apple Home for this device.")
        }
    }
}

private extension Array {
    func asyncCompactMap<T>(_ transform: (Element) async -> T?) async -> [T] {
        var result: [T] = []
        for element in self { if let value = await transform(element) { result.append(value) } }
        return result
    }
}

private struct DaikinState: Sendable {
    let id: String; let name: String; let isOn: Bool; let current: Double; let target: Double; let mode: String; let fan: String; let host: String
}

private enum DaikinLocalAdapter {
    static func discover(host: String) async throws -> DaikinState {
        let control = try await request(endpoint(host), "aircon/get_control_info", timeout: 1.2)
        guard control["ret"] == "OK", ["0", "1"].contains(control["pow"] ?? ""), control["mode"] != nil else {
            throw URLError(.cannotParseResponse)
        }
        return try await read(host: host)
    }

    static func read(host: String) async throws -> DaikinState {
        let base = endpoint(host)
        let control = try await request(base, "aircon/get_control_info")
        let sensor = try await request(base, "aircon/get_sensor_info")
        let info = (try? await request(base, "common/basic_info")) ?? [:]
        let mode: String
        switch control["mode"] ?? "0" { case "2": mode = "Dry"; case "3": mode = "Cool"; case "4": mode = "Heat"; case "6": mode = "Fan"; default: mode = "Auto" }
        let fanMap = ["A": "Auto", "3": "Low", "5": "Medium", "7": "High"]
        return DaikinState(id: info["mac"] ?? host, name: info["name"].map { $0.removingPercentEncoding ?? $0 } ?? "Daikin AC", isOn: control["pow"] == "1", current: Double(sensor["htemp"] ?? "23") ?? 23, target: Double(control["stemp"] ?? "22") ?? 22, mode: mode, fan: fanMap[control["f_rate"] ?? "A"] ?? "Auto", host: host)
    }
    static func command(host: String, action: String, value: String?, number: Double?) async throws -> DaikinState {
        let base = endpoint(host)
        var params = try await request(base, "aircon/get_control_info")
        switch action {
        case "power": params["pow"] = value == "on" ? "1" : "0"
        case "temperature": params["stemp"] = String(format: "%g", number ?? 22)
        case "mode": params["mode"] = ["Auto":"0", "Dry":"2", "Cool":"3", "Heat":"4", "Fan":"6"][value ?? ""] ?? "0"
        case "fan": params["f_rate"] = ["Auto":"A", "Low":"3", "Medium":"5", "High":"7"][value ?? ""] ?? "A"
        default: throw URLError(.unsupportedURL)
        }
        _ = try await request(base, "aircon/set_control_info", parameters: params)
        return try await read(host: host)
    }
    private static func endpoint(_ host: String) -> String { "http://\(host.trimmingCharacters(in: CharacterSet(charactersIn: "/")))" }
    private static func request(_ base: String, _ path: String, parameters: [String:String]? = nil, timeout: TimeInterval = 5) async throws -> [String:String] {
        guard var components = URLComponents(string: "\(base)/\(path)") else { throw URLError(.badURL) }
        if let parameters { components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = components.url else { throw URLError(.badURL) }
        let request = URLRequest(url: url, timeoutInterval: timeout)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, let text = String(data: data, encoding: .utf8) else { throw URLError(.badServerResponse) }
        var result: [String:String] = [:]
        for component in text.replacingOccurrences(of: ",", with: "&").split(separator: "&") {
            let pair = component.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if pair.count == 2 { result[String(pair[0])] = String(pair[1]) }
        }
        guard result["ret"].map({ $0 == "OK" }) ?? true else { throw URLError(.cannotWriteToFile) }
        return result
    }
}

private enum LocalSubnetDiscovery {
    static func hosts() -> [String] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let first else { return [] }
        defer { freeifaddrs(first) }

        var item: UnsafeMutablePointer<ifaddrs>? = first
        while let current = item {
            defer { item = current.pointee.ifa_next }
            let interface = current.pointee
            guard String(cString: interface.ifa_name) == "en0",
                  let address = interface.ifa_addr,
                  let netmask = interface.ifa_netmask,
                  address.pointee.sa_family == UInt8(AF_INET),
                  netmask.pointee.sa_family == UInt8(AF_INET) else { continue }

            let ip = UInt32(bigEndian: UnsafePointer<sockaddr_in>(OpaquePointer(address)).pointee.sin_addr.s_addr)
            let mask = UInt32(bigEndian: UnsafePointer<sockaddr_in>(OpaquePointer(netmask)).pointee.sin_addr.s_addr)
            let isPrivate = (ip >> 24) == 10 || (ip >> 20) == 0xAC1 || (ip >> 16) == 0xC0A8
            guard isPrivate else { return [] }
            let network = ip & mask
            let broadcast = network | ~mask
            guard broadcast > network, broadcast - network <= 512 else { return [] }

            return ((network + 1)..<broadcast).filter { $0 != ip }.map { value in
                "\((value >> 24) & 255).\((value >> 16) & 255).\((value >> 8) & 255).\(value & 255)"
            }
        }
        return []
    }
}
