import Foundation
import Security

struct MELCloudSession: Codable {
    let contextKey: String
    let expiry: String
}

struct MELCloudDeviceRecord: Identifiable {
    var id: Int { deviceID }
    let deviceID: Int
    let buildingID: Int
    let name: String
    let power: Bool
    let roomTemperature: Double
    let setTemperature: Double
    let operationMode: Int
    let fanSpeed: Int
}

enum MELCloudClassicAdapter {
    private static let base = URL(string: "https://app.melcloud.com/Mitsubishi.Wifi.Client")!
    private static let keychainService = "se.yeager.klimat.ios.melcloud"

    static func saveSession(_ session: MELCloudSession) throws {
        let data = try JSONEncoder().encode(session)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: "classic", kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: "classic"] as CFDictionary)
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw MELCloudError.secureStorage }
    }

    static func storedSession() -> MELCloudSession? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: "classic", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(MELCloudSession.self, from: data)
    }

    static func clearSession() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: "classic"] as CFDictionary)
    }

    static func signIn(email: String, password: String) async throws -> (MELCloudSession, [MELCloudDeviceRecord]) {
        let body: [String: Any] = ["AppVersion": "1.38.4.0", "Email": email, "Password": password, "Language": 0, "Persist": true]
        guard let response = try await request(path: "Login/ClientLogin3", method: "POST", body: body) as? [String: Any] else { throw MELCloudError.invalidResponse }
        guard let login = response["LoginData"] as? [String: Any], let context = login["ContextKey"] as? String, !context.isEmpty else {
            let errorID = response["ErrorId"] as? Int
            throw MELCloudError.loginRejected(errorID)
        }
        let session = MELCloudSession(contextKey: context, expiry: login["Expiry"] as? String ?? "")
        let devices = try await listDevices(session: session)
        try saveSession(session)
        return (session, devices)
    }

    static func listDevices(session: MELCloudSession) async throws -> [MELCloudDeviceRecord] {
        let response = try await request(path: "User/ListDevices", session: session)
        guard let buildings = response as? [[String: Any]] else {
            throw MELCloudError.invalidResponse
        }
        var results: [MELCloudDeviceRecord] = []
        for building in buildings { collectDevices(in: building, inheritedBuildingID: nil, into: &results) }
        return results
    }

    static func command(device: ClimateDevice, action: String, value: String?, number: Double?) async throws -> MELCloudDeviceRecord {
        guard let deviceID = device.remoteID, let buildingID = device.remoteBuildingID, let session = storedSession() else { throw MELCloudError.signInAgain }
        let query = [URLQueryItem(name: "id", value: String(deviceID)), URLQueryItem(name: "buildingId", value: String(buildingID))]
        guard var values = try await request(path: "Device/Get", session: session, query: query) as? [String: Any] else { throw MELCloudError.invalidResponse }
        let currentPower = values["Power"] as? Bool ?? device.isOn
        let currentMode = values["OperationMode"] as? Int ?? 8
        let currentTemperature = values["SetTemperature"] as? Double ?? device.target
        let currentFan = values["FanSpeed"] as? Int ?? 2
        switch action {
        case "power":
            _ = try await request(path: "Device/Power", method: "POST", session: session, body: ["DeviceIds": [deviceID], "Power": value == "on"])
        case "temperature", "mode", "fan":
            var power = currentPower, mode = currentMode, target = currentTemperature, fan = currentFan
            switch action {
            case "temperature": target = max(10, min(31, number ?? currentTemperature))
            case "mode": mode = ["Auto": 8, "Heat": 1, "Dry": 2, "Cool": 3, "Fan": 7][value ?? ""] ?? currentMode
            case "fan": fan = ["Low": 2, "Medium": 3, "High": 4, "Auto": 0][value ?? ""] ?? currentFan
            default: break
            }
            let flags: Int = action == "temperature" ? 0x4 : action == "mode" ? 0x2 : 0x8
            values = ["DeviceID": deviceID, "EffectiveFlags": flags, "Power": power, "OperationMode": mode, "SetTemperature": target, "SetFanSpeed": fan, "VaneHorizontal": values["VaneHorizontalDirection"] as? Int ?? 0, "VaneVertical": values["VaneVerticalDirection"] as? Int ?? 0]
            _ = try await request(path: "Device/SetAta", method: "POST", session: session, body: values)
        default: throw MELCloudError.unsupported
        }
        guard let refreshed = try await request(path: "Device/Get", session: session, query: query) as? [String: Any] else { throw MELCloudError.invalidResponse }
        return record(from: refreshed, deviceID: deviceID, buildingID: buildingID, name: device.name)
    }

    private static func collectDevices(in object: Any, inheritedBuildingID: Int?, into results: inout [MELCloudDeviceRecord]) {
        if let dict = object as? [String: Any] {
            let buildingID = dict["BuildingID"] as? Int ?? inheritedBuildingID
            if (dict["Type"] as? Int) == 0, let deviceID = dict["DeviceID"] as? Int,
               let payload = dict["Device"] as? [String: Any], let buildingID {
                results.append(record(from: payload, deviceID: deviceID, buildingID: buildingID, name: dict["DeviceName"] as? String ?? "Mitsubishi Electric AC"))
            }
            for value in dict.values { collectDevices(in: value, inheritedBuildingID: buildingID, into: &results) }
        } else if let array = object as? [Any] {
            for value in array { collectDevices(in: value, inheritedBuildingID: inheritedBuildingID, into: &results) }
        }
    }

    private static func record(from values: [String: Any], deviceID: Int, buildingID: Int, name: String) -> MELCloudDeviceRecord {
        let mode = values["OperationMode"] as? Int ?? 8
        return MELCloudDeviceRecord(deviceID: deviceID, buildingID: buildingID, name: name, power: values["Power"] as? Bool ?? false, roomTemperature: values["RoomTemperature"] as? Double ?? 23, setTemperature: values["SetTemperature"] as? Double ?? 22, operationMode: mode, fanSpeed: values["FanSpeed"] as? Int ?? 0)
    }

    private static func request(path: String, method: String = "GET", session: MELCloudSession? = nil, query: [URLQueryItem] = [], body: [String: Any]? = nil) async throws -> Any {
        guard var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { throw MELCloudError.invalidResponse }
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw MELCloudError.invalidResponse }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let session { request.setValue(session.contextKey, forHTTPHeaderField: "X-MitsContextKey") }
        if let body { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MELCloudError.invalidResponse }
        if http.statusCode == 401 { clearSession(); throw MELCloudError.signInAgain }
        guard (200..<300).contains(http.statusCode) else { throw MELCloudError.server(http.statusCode) }
        return try JSONSerialization.jsonObject(with: data)
    }
}

enum MELCloudError: LocalizedError {
    case loginRejected(Int?), invalidResponse, secureStorage, signInAgain, unsupported, server(Int)
    var errorDescription: String? {
        switch self {
        case .loginRejected(let id): return id.map { "MELCloud sign-in was rejected (error \($0))." } ?? "MELCloud sign-in was rejected. Check your details and try again."
        case .invalidResponse: return "MELCloud returned an unexpected response."
        case .secureStorage: return "Klimat could not save the MELCloud session securely."
        case .signInAgain: return "Your MELCloud session has expired. Connect your account again."
        case .unsupported: return "This MELCloud control is not supported."
        case .server(let status): return "MELCloud request failed (HTTP \(status))."
        }
    }
}
