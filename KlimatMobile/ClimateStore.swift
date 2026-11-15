import Foundation
import Darwin
import HomeKit
import Security

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
    var remoteID: Int? = nil
    var remoteBuildingID: Int? = nil
    var localCipher: String? = nil
    var verticalVane: String? = nil
    var horizontalVane: String? = nil
    var statusUpdatedAt: Date? = nil
}

struct CloudProvider: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
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
    private var appleHome: HomeKitClimateAdapter?

    let providers: [CloudProvider] = [
        .init(id: "melcloud", title: "MELCloud", detail: "Mitsubishi Electric", symbol: "cloud")
    ]

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey), let saved = try? JSONDecoder().decode([ClimateDevice].self, from: data) {
            devices = saved
            selectedID = saved.first?.id
        }
    }
    var selected: ClimateDevice? { devices.first(where: { $0.id == selectedID }) ?? devices.first }
    func save() { if let data = try? JSONEncoder().encode(devices) { UserDefaults.standard.set(data, forKey: storageKey) } }
    func connectDaikin(host: String, name: String) async {
        guard let host = LocalWiFiIPv4.validatedHost(host) else {
            connectionNotice = String(localized: "Connection unavailable"); return
        }
        do {
            let state = try await DaikinLocalAdapter.read(host: host)
            let device = ClimateDevice(id: state.id, name: name.isEmpty ? state.name : name, brand: "Daikin", connection: "Local network · \(host)", isOn: state.isOn, current: state.current, target: state.target, mode: state.mode, fan: state.fan, host: state.host, statusUpdatedAt: Date())
            if let index = devices.firstIndex(where: { $0.id == device.id }) { devices[index] = device } else { devices.append(device) }
            selectedID = device.id; save()
        } catch { connectionNotice = error.localizedDescription }
    }
    func connectMitsubishi(host: String, name: String) async {
        guard let host = LocalWiFiIPv4.validatedHost(host) else {
            connectionNotice = String(localized: "Connection unavailable"); return
        }
        do {
            let state = try await MitsubishiLocalAdapter.read(host: host)
            let identifier = state.mac.isEmpty ? host : state.mac
            let device = ClimateDevice(id: identifier, name: name.isEmpty ? "Mitsubishi Electric AC" : name, brand: "Mitsubishi Electric", connection: "Local network · \(host)", isOn: state.isOn, current: state.current, target: state.target, mode: state.mode, fan: state.fan, host: host, verticalVane: state.verticalVane, horizontalVane: state.horizontalVane, statusUpdatedAt: Date())
            if let index = devices.firstIndex(where: { $0.id == device.id || $0.host == host }) { devices[index] = device } else { devices.append(device) }
            selectedID = device.id; save()
        } catch { connectionNotice = error.localizedDescription }
    }
    func connectGree(host: String, name: String) async {
        guard let host = LocalWiFiIPv4.validatedHost(host) else {
            connectionNotice = String(localized: "Connection unavailable"); return
        }
        do {
            let info: GreeLocalAdapter.DeviceInfo
            if let broadcast = LocalWiFiIPv4.broadcastAddress(),
               let matches = try? await GreeLocalAdapter.discoverAll(broadcast: broadcast, timeout: 1.2),
               let match = matches.first(where: { $0.host == host }) {
                info = match
            } else {
                info = try await GreeLocalAdapter.discover(host: host)
            }
            let cached = GreeKeychain.load(mac: info.mac)
            let savedCipher = GreeLocalAdapter.CipherKind(rawValue: cached?.cipher ?? "v1") ?? .v1
            let state = try await GreeLocalAdapter.connect(info, savedKey: cached?.key, savedCipher: savedCipher)
            guard GreeKeychain.save(key: state.key, cipher: state.cipher, mac: info.mac) else { throw GreeControlError.keychainUnavailable }
            let device = ClimateDevice(id: "gree-\(info.mac)", name: name.isEmpty ? info.name : name, brand: "Gree", connection: "Local network · \(host)", isOn: state.isOn, current: state.current, target: state.target, mode: state.mode, fan: state.fan, host: host, localCipher: state.cipher.rawValue, statusUpdatedAt: Date())
            if let index = devices.firstIndex(where: { $0.id == device.id || $0.host == host }) { devices[index] = device } else { devices.append(device) }
            selectedID = device.id
            save()
        } catch { connectionNotice = error.localizedDescription }
    }
    func connectMELCloud(email: String, password: String) async {
        do {
            let (_, records) = try await MELCloudClassicAdapter.signIn(email: email, password: password)
            let cloudDevices = records.map { record in
                ClimateDevice(id: "melcloud-\(record.deviceID)", name: record.name, brand: "MELCloud", connection: "MELCloud · Mitsubishi Electric", isOn: record.power, current: record.roomTemperature, target: record.setTemperature, mode: Self.modeName(record.operationMode), fan: Self.fanName(record.fanSpeed), host: nil, homeServiceID: nil, remoteID: record.deviceID, remoteBuildingID: record.buildingID, statusUpdatedAt: Date())
            }
            devices.removeAll { $0.brand == "MELCloud" }
            devices.append(contentsOf: cloudDevices)
            selectedID = cloudDevices.first?.id ?? selectedID
            save()
            if cloudDevices.isEmpty { connectionNotice = String(localized: "No supported air conditioners were found in this MELCloud account.") }
        } catch { connectionNotice = error.localizedDescription }
    }
    func disconnectMELCloud() {
        MELCloudClassicAdapter.clearSession()
        devices.removeAll { $0.brand == "MELCloud" }
        if selectedID?.hasPrefix("melcloud-") == true { selectedID = devices.first?.id }
        save()
    }
    func removeAllDevices() {
        for device in devices where device.brand == "Gree" {
            GreeKeychain.delete(mac: String(device.id.dropFirst("gree-".count)))
        }
        disconnectMELCloud()
        devices.removeAll()
        selectedID = nil
        save()
    }
    func refreshDevice(deviceID: String?) async {
        guard let device = deviceID.flatMap({ id in devices.first(where: { $0.id == id }) }) ?? selected else {
            connectionNotice = String(localized: "Connection unavailable")
            return
        }
        connectionNotice = nil
        do {
            var refreshed = device
            switch device.brand {
            case "Daikin":
                guard let host = device.host else { throw URLError(.badURL) }
                let state = try await DaikinLocalAdapter.read(host: host)
                refreshed.isOn = state.isOn; refreshed.current = state.current; refreshed.target = state.target
                refreshed.mode = state.mode; refreshed.fan = state.fan
            case "Mitsubishi Electric":
                guard let host = device.host else { throw URLError(.badURL) }
                let state = try await MitsubishiLocalAdapter.read(host: host)
                refreshed.isOn = state.isOn; refreshed.current = state.current; refreshed.target = state.target
                refreshed.mode = state.mode; refreshed.fan = state.fan
                refreshed.verticalVane = state.verticalVane; refreshed.horizontalVane = state.horizontalVane
            case "Gree":
                guard let host = device.host else { throw URLError(.badURL) }
                let mac = String(device.id.dropFirst("gree-".count))
                let info = GreeLocalAdapter.DeviceInfo(mac: mac, name: device.name, host: host, brand: "Gree", model: "")
                guard let credentials = GreeKeychain.load(mac: mac),
                      let cipher = GreeLocalAdapter.CipherKind(rawValue: credentials.cipher) else { throw GreeControlError.missingPairing }
                let state = try await GreeLocalAdapter.read(info, key: credentials.key, cipher: cipher)
                refreshed.isOn = state.isOn; refreshed.current = state.current; refreshed.target = state.target
                refreshed.mode = state.mode; refreshed.fan = state.fan; refreshed.localCipher = state.cipher.rawValue
            case "MELCloud":
                let state = try await MELCloudClassicAdapter.read(device: device)
                refreshed.isOn = state.power; refreshed.current = state.roomTemperature; refreshed.target = state.setTemperature
                refreshed.mode = Self.modeName(state.operationMode); refreshed.fan = Self.fanName(state.fanSpeed)
            case "Apple Home":
                guard let serviceID = device.homeServiceID, let appleHome else { throw HomeKitControlError.serviceUnavailable }
                refreshed = try await appleHome.read(serviceID: serviceID)
            default:
                throw URLError(.unsupportedURL)
            }
            guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
            refreshed.statusUpdatedAt = Date()
            devices[index] = refreshed
            save()
        } catch {
            connectionNotice = error.localizedDescription
        }
    }
    func command(deviceID: String? = nil, action: String, value: String? = nil, number: Double? = nil) async {
        let commandDevice: ClimateDevice?
        if let deviceID {
            guard let requestedDevice = devices.first(where: { $0.id == deviceID }) else {
                connectionNotice = String(localized: "Connection unavailable")
                return
            }
            commandDevice = requestedDevice
        } else {
            commandDevice = selected
        }
        if let device = commandDevice, device.brand == "MELCloud" {
            do {
                let state = try await MELCloudClassicAdapter.command(device: device, action: action, value: value, number: number)
                guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
                devices[index].isOn = state.power; devices[index].current = state.roomTemperature; devices[index].target = state.setTemperature; devices[index].mode = Self.modeName(state.operationMode); devices[index].fan = Self.fanName(state.fanSpeed)
                devices[index].statusUpdatedAt = Date(); save()
            } catch { connectionNotice = error.localizedDescription }
            return
        }
        if let device = commandDevice, device.brand == "Apple Home", let serviceID = device.homeServiceID {
            guard let appleHome else {
                connectionNotice = String(localized: "Climate control was not found in Apple Home. Scan for devices again.")
                return
            }
            do {
                let state = try await appleHome.command(serviceID: serviceID, action: action, value: value, number: number)
                guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
                devices[index] = state
                devices[index].statusUpdatedAt = Date()
                save()
            } catch { connectionNotice = error.localizedDescription }
            return
        }
        if let device = commandDevice, device.brand == "Gree", let host = device.host {
            guard let host = LocalWiFiIPv4.validatedHost(host) else {
                connectionNotice = String(localized: "Connection unavailable"); return
            }
            do {
                let mac = String(device.id.dropFirst("gree-".count))
                let info = GreeLocalAdapter.DeviceInfo(mac: mac, name: device.name, host: host, brand: "Gree", model: "")
                guard let credentials = GreeKeychain.load(mac: mac),
                      let cipher = GreeLocalAdapter.CipherKind(rawValue: credentials.cipher) else { throw GreeControlError.missingPairing }
                let current = try await GreeLocalAdapter.read(info, key: credentials.key, cipher: cipher)
                let state = try await GreeLocalAdapter.command(current, action: action, value: value, number: number)
                guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
                devices[index].isOn = state.isOn; devices[index].current = state.current; devices[index].target = state.target
                devices[index].mode = state.mode; devices[index].fan = state.fan; devices[index].localCipher = state.cipher.rawValue
                devices[index].statusUpdatedAt = Date()
                save()
            } catch { connectionNotice = error.localizedDescription }
            return
        }
        guard let device = commandDevice, let host = device.host else {
            connectionNotice = String(localized: "This device does not have a local control adapter."); return
        }
        guard let host = LocalWiFiIPv4.validatedHost(host) else {
            connectionNotice = String(localized: "Connection unavailable"); return
        }
        do {
            let isMitsubishi = device.brand == "Mitsubishi Electric"
            let daikinState = isMitsubishi ? nil : try await DaikinLocalAdapter.command(host: host, action: action, value: value, number: number)
            let mitsubishiState = isMitsubishi ? try await MitsubishiLocalAdapter.command(host: host, action: action, value: value, number: number) : nil
            guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
            let isOn = daikinState?.isOn ?? mitsubishiState?.isOn
            let current = daikinState?.current ?? mitsubishiState?.current
            let target = daikinState?.target ?? mitsubishiState?.target
            let mode = daikinState?.mode ?? mitsubishiState?.mode
            let fan = daikinState?.fan ?? mitsubishiState?.fan
            if let isOn { devices[index].isOn = isOn }; if let current { devices[index].current = current }; if let target { devices[index].target = target }; if let mode { devices[index].mode = mode }; if let fan { devices[index].fan = fan }
            if let mitsubishiState { devices[index].verticalVane = mitsubishiState.verticalVane; devices[index].horizontalVane = mitsubishiState.horizontalVane }
            devices[index].statusUpdatedAt = Date()
            save()
        } catch { connectionNotice = error.localizedDescription }
    }
    func scanAppleHome() {
        isLoadingAppleHome = true
        appleHomeStatus = String(localized: "Searching Apple Home for climate devices…")
        homeKitAdapter().refresh()
    }

    private func homeKitAdapter() -> HomeKitClimateAdapter {
        if let appleHome { return appleHome }
        let adapter = HomeKitClimateAdapter()
        adapter.onDevicesChanged = { [weak self] homeDevices in
            guard let self else { return }
            let localDevices = self.devices.filter { $0.brand != "Apple Home" }
            self.devices = localDevices + homeDevices
            if self.selectedID == nil { self.selectedID = homeDevices.first?.id }
            self.save()
            self.isLoadingAppleHome = false
            self.appleHomeStatus = homeDevices.isEmpty ? String(localized: "No climate controls found in Apple Home.") : String(localized: "Found \(homeDevices.count) climate controls in Apple Home.")
        }
        appleHome = adapter
        return adapter
    }
    func beginScan() {
        guard !isScanning else { return }
        isScanning = true; scanMessage = String(localized: "Scanning this Wi-Fi network for compatible Daikin, Mitsubishi and Gree adapters…")
        Task { @MainActor [weak self] in
            guard let self else { return }
            let hosts = LocalWiFiIPv4.hosts()
            guard !hosts.isEmpty else {
                self.scanMessage = String(localized: "Could not determine the Wi-Fi subnet. Enter the adapter IP address instead.")
                self.isScanning = false
                return
            }
            var found: [ClimateDevice] = []
            if let broadcast = LocalWiFiIPv4.broadcastAddress(),
               let greeDevices = try? await GreeLocalAdapter.discoverAll(broadcast: broadcast) {
                for info in greeDevices {
                    guard let state = try? await GreeLocalAdapter.connect(info),
                          GreeKeychain.save(key: state.key, cipher: state.cipher, mac: info.mac) else { continue }
                    found.append(ClimateDevice(id: "gree-\(info.mac)", name: info.name, brand: "Gree", connection: "Local network · \(info.host)", isOn: state.isOn, current: state.current, target: state.target, mode: state.mode, fan: state.fan, host: info.host, localCipher: state.cipher.rawValue, statusUpdatedAt: Date()))
                }
            }
            for start in stride(from: 0, to: hosts.count, by: 24) {
                let batch = Array(hosts[start..<min(start + 24, hosts.count)])
                await withTaskGroup(of: ClimateDevice?.self) { group in
                    for host in batch {
                        group.addTask {
                            if let state = try? await DaikinLocalAdapter.discover(host: host) {
                                return ClimateDevice(id: state.id, name: state.name, brand: "Daikin", connection: "Local network · \(state.host)", isOn: state.isOn, current: state.current, target: state.target, mode: state.mode, fan: state.fan, host: state.host, statusUpdatedAt: Date())
                            }
                            if let state = try? await MitsubishiLocalAdapter.discover(host: host) {
                                let identifier = state.mac.isEmpty ? host : state.mac
                                return ClimateDevice(id: identifier, name: "Mitsubishi Electric AC", brand: "Mitsubishi Electric", connection: "Local network · \(host)", isOn: state.isOn, current: state.current, target: state.target, mode: state.mode, fan: state.fan, host: host, verticalVane: state.verticalVane, horizontalVane: state.horizontalVane, statusUpdatedAt: Date())
                            }
                            return nil
                        }
                    }
                    for await device in group { if let device { found.append(device) } }
                }
            }
            guard self.isScanning else { return }
            for device in found {
                if let index = self.devices.firstIndex(where: { $0.id == device.id || $0.host == device.host }) { self.devices[index] = device }
                else { self.devices.append(device) }
                if self.selectedID == nil { self.selectedID = device.id }
            }
            self.save()
            self.isScanning = false
            self.scanMessage = found.isEmpty
                ? String(localized: "No compatible direct AC adapters found on this Wi-Fi network. You can enter an adapter IP address manually.")
                : String(localized: "Found \(found.count) compatible AC adapter(s) on this Wi-Fi network.")
        }
    }
    private static func modeName(_ mode: Int) -> String { [0: "Auto", 8: "Auto", 1: "Heat", 2: "Dry", 3: "Cool", 7: "Fan"][mode] ?? "Auto" }
    private static func fanName(_ speed: Int) -> String { [0: "Auto", 1: "Low", 2: "Low", 3: "Medium", 4: "High", 5: "High"][speed] ?? "Auto" }
}

private enum GreeControlError: LocalizedError {
    case missingPairing, keychainUnavailable
    var errorDescription: String? {
        switch self {
        case .missingPairing: return "Reconnect to this Gree adapter to restore its secure local pairing."
        case .keychainUnavailable: return "Klimat could not securely save the local Gree pairing on this iPhone."
        }
    }
}

private enum GreeKeychain {
    private static let service = "se.yeager.klimat.gree-local"
    private struct Credentials: Codable { let key: String; let cipher: String }

    static func load(mac: String) -> (key: String, cipher: String)? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: mac, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let credentials = try? JSONDecoder().decode(Credentials.self, from: data) else { return nil }
        return (credentials.key, credentials.cipher)
    }

    @discardableResult static func save(key: String, cipher: GreeLocalAdapter.CipherKind, mac: String) -> Bool {
        guard let data = try? JSONEncoder().encode(Credentials(key: key, cipher: cipher.rawValue)) else { return false }
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: mac]
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func delete(mac: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: mac]
        SecItemDelete(query as CFDictionary)
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

    func read(serviceID: String) async throws -> ClimateDevice {
        guard let home = manager.homes.first(where: { $0.accessories.contains(where: { $0.services.contains(where: { $0.uniqueIdentifier.uuidString == serviceID }) }) }),
              let accessory = home.accessories.first(where: { $0.services.contains(where: { $0.uniqueIdentifier.uuidString == serviceID }) }),
              let service = accessory.services.first(where: { $0.uniqueIdentifier.uuidString == serviceID }) else {
            throw HomeKitControlError.serviceUnavailable
        }
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
        return ClimateDevice(id: id, name: service.name.isEmpty ? accessory.name : service.name, brand: "Apple Home", connection: "Apple Home · \(home.name)", isOn: isOn, current: (values[HMCharacteristicTypeCurrentTemperature] as? NSNumber)?.doubleValue ?? 0, target: (values[HMCharacteristicTypeTargetTemperature] as? NSNumber)?.doubleValue ?? 22, mode: mode, fan: "Auto", host: nil, homeServiceID: id, statusUpdatedAt: Date())
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
        let host = try validatedHost(host)
        let control = try await request(endpoint(host), "aircon/get_control_info", timeout: 1.2)
        guard control["ret"] == "OK", ["0", "1"].contains(control["pow"] ?? ""), control["mode"] != nil else {
            throw URLError(.cannotParseResponse)
        }
        return try await read(host: host)
    }

    static func read(host: String) async throws -> DaikinState {
        let host = try validatedHost(host)
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
        let host = try validatedHost(host)
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
    private static func validatedHost(_ host: String) throws -> String {
        guard let host = LocalWiFiIPv4.validatedHost(host) else { throw URLError(.badURL) }
        return host
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
