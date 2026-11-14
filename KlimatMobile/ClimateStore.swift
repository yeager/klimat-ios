import Foundation
import Network

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
    @Published var scanMessage = "Hitta enheter på ditt Wi-Fi"
    @Published var discoveredServices: [String] = []
    @Published var showCloudSetup = false
    @Published var selectedProvider: CloudProvider?
    @Published var connectionNotice: String?
    private var browser: NWBrowser?
    private let storageKey = "klimat.ios.devices"

    let providers: [CloudProvider] = [
        .init(id: "melcloud", title: "MELCloud", detail: "Mitsubishi Electric", symbol: "cloud", color: "#4A8069"),
        .init(id: "lg", title: "LG ThinQ", detail: "LG luftkonditionering", symbol: "cloud", color: "#B44B68"),
        .init(id: "panasonic", title: "Panasonic Comfort Cloud", detail: "Panasonic", symbol: "cloud", color: "#4269A2"),
        .init(id: "smartthings", title: "SmartThings", detail: "Samsung", symbol: "cloud", color: "#3972C6"),
        .init(id: "toshiba", title: "Toshiba Lifestyle", detail: "Toshiba", symbol: "cloud", color: "#B04D4D"),
        .init(id: "gree", title: "Gree", detail: "Gree Cloud", symbol: "cloud", color: "#458A6A"),
        .init(id: "midea", title: "Midea", detail: "Midea Air", symbol: "cloud", color: "#D27A42")
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
        do {
            let state = try await DaikinLocalAdapter.read(host: host)
            let device = ClimateDevice(id: state.id, name: name.isEmpty ? state.name : name, brand: "Daikin", connection: "Lokalt nätverk · \(host)", isOn: state.isOn, current: state.current, target: state.target, mode: state.mode, fan: state.fan, host: state.host)
            if let index = devices.firstIndex(where: { $0.id == device.id }) { devices[index] = device } else { devices.append(device) }
            selectedID = device.id; save()
        } catch { connectionNotice = error.localizedDescription }
    }
    func command(action: String, value: String? = nil, number: Double? = nil) async {
        guard let device = selected, device.brand == "Daikin", let host = device.host else {
            connectionNotice = "Den här enheten saknar en lokal styradapter."; return
        }
        do {
            let state = try await DaikinLocalAdapter.command(host: host, action: action, value: value, number: number)
            guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
            devices[index].isOn = state.isOn; devices[index].current = state.current; devices[index].target = state.target; devices[index].mode = state.mode; devices[index].fan = state.fan; save()
        } catch { connectionNotice = error.localizedDescription }
    }
    func beginScan() {
        guard !isScanning else { return }
        discoveredServices = []
        isScanning = true; scanMessage = "Söker efter kompatibla enheter…"
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        let b = NWBrowser(for: .bonjour(type: "_http._tcp", domain: nil), using: params)
        browser = b
        b.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                if case .failed(let error) = state { self.scanMessage = "Sökningen misslyckades: \(error.localizedDescription)"; self.isScanning = false; b.cancel() }
            }
        }
        b.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self else { return }
                for result in results {
                    let name: String
                    if case let .service(n, _, _, _) = result.endpoint { name = n } else { continue }
                    if !self.discoveredServices.contains(name) { self.discoveredServices.append(name) }
                }
            }
        }
        b.start(queue: .main)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, self.isScanning else { return }
            self.isScanning = false
            if self.discoveredServices.isEmpty {
                self.scanMessage = "Inga Bonjour-tjänster hittades. Många AC-adaptrar annonserar inte Bonjour; anslut med IP-adress."
            } else {
                self.scanMessage = "Hittade \(self.discoveredServices.count) nätverkstjänst(er). AC-enheter behöver identifieras med sitt lokala adapterprotokoll."
            }
            self.browser?.cancel(); self.browser = nil
        }
    }
    func connectCloud(provider: CloudProvider) {
        connectionNotice = "\(provider.title) kräver en tillverkaradapter. Ingen inloggning har gjorts."
    }
}

private struct DaikinState {
    let id: String; let name: String; let isOn: Bool; let current: Double; let target: Double; let mode: String; let fan: String; let host: String
}

private enum DaikinLocalAdapter {
    static func read(host: String) async throws -> DaikinState {
        let base = endpoint(host)
        let control = try await request(base, "aircon/get_control_info")
        let sensor = try await request(base, "aircon/get_sensor_info")
        let info = (try? await request(base, "common/basic_info")) ?? [:]
        let mode: String
        switch control["mode"] ?? "0" { case "2": mode = "Avfuktning"; case "3": mode = "Kyler"; case "4": mode = "Värme"; case "6": mode = "Fläkt"; default: mode = "Auto" }
        let fanMap = ["A": "Auto", "3": "Låg", "5": "Medel", "7": "Hög"]
        return DaikinState(id: info["mac"] ?? host, name: info["name"].map { $0.removingPercentEncoding ?? $0 } ?? "Daikin AC", isOn: control["pow"] == "1", current: Double(sensor["htemp"] ?? "23") ?? 23, target: Double(control["stemp"] ?? "22") ?? 22, mode: mode, fan: fanMap[control["f_rate"] ?? "A"] ?? "Auto", host: host)
    }
    static func command(host: String, action: String, value: String?, number: Double?) async throws -> DaikinState {
        let base = endpoint(host)
        var params = try await request(base, "aircon/get_control_info")
        switch action {
        case "power": params["pow"] = value == "on" ? "1" : "0"
        case "temperature": params["stemp"] = String(format: "%g", number ?? 22)
        case "mode": params["mode"] = ["Auto":"0", "Avfuktning":"2", "Kyler":"3", "Värme":"4", "Fläkt":"6"][value ?? ""] ?? "0"
        case "fan": params["f_rate"] = ["Auto":"A", "Låg":"3", "Medel":"5", "Hög":"7"][value ?? ""] ?? "A"
        default: throw URLError(.unsupportedURL)
        }
        _ = try await request(base, "aircon/set_control_info", body: params)
        return try await read(host: host)
    }
    private static func endpoint(_ host: String) -> String { "http://\(host.trimmingCharacters(in: CharacterSet(charactersIn: "/")))" }
    private static func request(_ base: String, _ path: String, body: [String:String]? = nil) async throws -> [String:String] {
        guard let url = URL(string: "\(base)/\(path)") else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 5)
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }.sorted().joined(separator: "&").data(using: .utf8)
        }
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
