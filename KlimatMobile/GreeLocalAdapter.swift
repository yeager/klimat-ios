import Foundation
import Network
import CryptoKit
import CommonCrypto
import Darwin

/// Local GREE Smart WiFi protocol adapter (UDP/7000).
/// Packet and cipher behavior is based on the MIT-licensed gree-climate reference.
enum GreeLocalAdapter {
    enum CipherKind: String { case v1, v2 }

    struct DeviceInfo {
        let mac: String
        let name: String
        let host: String
        let brand: String
        let model: String
    }

    struct State {
        let device: DeviceInfo
        let key: String
        let cipher: CipherKind
        let isOn: Bool
        let current: Double
        let target: Double
        let mode: String
        let fan: String
        let isFahrenheit: Bool
    }

    private static let port: NWEndpoint.Port = 7000
    private static let v1DefaultKey = Data("a3K8Bx%2r8Y7#xDh".utf8)
    private static let v2DefaultKey = Data("{yxAHAY_Lm6pbC/<".utf8)
    private static let v2Nonce = Data([0x54, 0x40, 0x78, 0x44, 0x49, 0x67, 0x5a, 0x51, 0x6c, 0x5e, 0x63, 0x13])

    static func discover(host: String, timeout: TimeInterval = 1.2) async throws -> DeviceInfo {
        let request: [String: Any] = ["cid": "app", "i": 1, "t": "scan", "uid": 0, "tcid": ""]
        let response = try await exchange(host: host, packet: try json(request), timeout: timeout)
        guard let device = parseDevice(response, host: host) else { throw GreeAdapterError.invalidResponse }
        return device
    }

    static func discoverAll(broadcast: String, timeout: TimeInterval = 2.0) async throws -> [DeviceInfo] {
        try await Task.detached(priority: .utility) {
            try discoverBroadcast(broadcast: broadcast, timeout: timeout)
        }.value
    }

    private static func discoverBroadcast(broadcast: String, timeout: TimeInterval) throws -> [DeviceInfo] {
        guard LocalWiFiIPv4.isCurrentBroadcast(broadcast) else { throw GreeAdapterError.invalidAddress }
        let descriptor = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { throw GreeAdapterError.networkUnavailable }
        defer { Darwin.close(descriptor) }

        var enabled: Int32 = 1
        guard setsockopt(descriptor, SOL_SOCKET, SO_BROADCAST, &enabled, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw GreeAdapterError.networkUnavailable
        }
        var local = sockaddr_in()
        local.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        local.sin_family = sa_family_t(AF_INET)
        local.sin_port = 0
        local.sin_addr = in_addr(s_addr: in_addr_t(INADDR_ANY))
        let bindResult = withUnsafePointer(to: &local) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bindResult == 0 else { throw GreeAdapterError.networkUnavailable }

        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = port.rawValue.bigEndian
        guard inet_pton(AF_INET, broadcast, &destination.sin_addr) == 1 else { throw GreeAdapterError.invalidAddress }
        let scan = try json(["cid": "app", "i": 1, "t": "scan", "uid": 0, "tcid": ""])
        let sent = scan.withUnsafeBytes { bytes in
            withUnsafePointer(to: &destination) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(descriptor, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == scan.count else { throw GreeAdapterError.networkUnavailable }

        let deadline = Date().addingTimeInterval(timeout)
        var devices: [DeviceInfo] = []
        while true {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { break }
            var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let ready = Darwin.poll(&pollDescriptor, 1, Int32(max(1, remaining * 1000)))
            if ready == 0 { break }
            guard ready > 0 else { throw GreeAdapterError.networkUnavailable }
            var bytes = [UInt8](repeating: 0, count: 4096)
            var source = sockaddr_in()
            var sourceLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let received = bytes.withUnsafeMutableBytes { buffer in
                withUnsafeMutablePointer(to: &source) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        recvfrom(descriptor, buffer.baseAddress, buffer.count, 0, $0, &sourceLength)
                    }
                }
            }
            guard received > 0 else { continue }
            let ip = UInt32(bigEndian: source.sin_addr.s_addr)
            let host = "\((ip >> 24) & 255).\((ip >> 16) & 255).\((ip >> 8) & 255).\(ip & 255)"
            if let device = parseDevice(Data(bytes.prefix(received)), host: host), !devices.contains(where: { $0.mac == device.mac }) {
                devices.append(device)
            }
        }
        return devices
    }

    private static func parseDevice(_ response: Data, host: String) -> DeviceInfo? {
        guard let envelope = try? decodeEnvelope(response),
              let pack = try? decryptPack(envelope, cipher: .v1, key: v1DefaultKey),
              let mac = (pack["mac"] as? String) ?? (pack["cid"] as? String), !mac.isEmpty else { return nil }
        return DeviceInfo(mac: mac, name: (pack["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? mac,
                          host: host, brand: pack["brand"] as? String ?? "Gree", model: pack["model"] as? String ?? "")
    }

    static func connect(_ device: DeviceInfo, savedKey: String? = nil, savedCipher: CipherKind = .v1) async throws -> State {
        let session: (String, CipherKind)
        if let savedKey, !savedKey.isEmpty {
            session = (savedKey, savedCipher)
        } else {
            session = try await bind(device)
        }
        return try await read(device, key: session.0, cipher: session.1)
    }

    static func read(_ device: DeviceInfo, key: String, cipher: CipherKind) async throws -> State {
        let cols = ["Pow", "Mod", "SetTem", "TemSen", "TemUn", "TemRec", "WdSpd", "hid"]
        let inner: [String: Any] = ["t": "status", "mac": device.mac, "cols": cols]
        let envelope = try makeEnvelope(inner, mac: device.mac, index: 0, cipher: cipher, key: Data(key.utf8))
        let response = try await exchange(host: device.host, packet: try json(envelope), timeout: 3)
        let values = try decryptPack(decodeEnvelope(response), cipher: cipher, key: Data(key.utf8))
        guard let type = values["t"] as? String, type == "dat" || type == "res" else { throw GreeAdapterError.invalidResponse }
        let names = (values["cols"] as? [String]) ?? (values["opt"] as? [String]) ?? []
        let raw = (values["dat"] as? [Any]) ?? (values["val"] as? [Any]) ?? (values["p"] as? [Any]) ?? []
        let props = Dictionary(uniqueKeysWithValues: zip(names, raw))
        let unit = number(props["TemUn"]) ?? 0
        let rawCurrent = number(props["TemSen"]) ?? 23
        let current = unit == 1 ? (rawCurrent - 32) * 5 / 9 : (rawCurrent > 40 ? rawCurrent - 40 : rawCurrent)
        let rawTarget = number(props["SetTem"]) ?? 24
        let target = unit == 1 ? (rawTarget - 32) * 5 / 9 : rawTarget
        let mode = [0: "Auto", 1: "Cool", 2: "Dry", 3: "Fan", 4: "Heat"][Int(number(props["Mod"]) ?? 0)] ?? "Auto"
        let fan = [0: "Auto", 1: "Low", 2: "Low", 3: "Medium", 4: "Medium", 5: "High"][Int(number(props["WdSpd"]) ?? 0)] ?? "Auto"
        return State(device: device, key: key, cipher: cipher, isOn: (number(props["Pow"]) ?? 0) > 0,
                     current: current, target: target, mode: mode, fan: fan, isFahrenheit: unit == 1)
    }

    static func command(_ state: State, action: String, value: String?, number target: Double?) async throws -> State {
        let name: String
        let raw: Int
        switch action {
        case "power": name = "Pow"; raw = value == "on" ? 1 : 0
        case "mode":
            name = "Mod"
            guard let mode = ["Auto": 0, "Cool": 1, "Dry": 2, "Fan": 3, "Heat": 4][value ?? ""] else { throw GreeAdapterError.unsupportedControl }
            raw = mode
        case "temperature":
            name = "SetTem"
            let celsius = max(16, min(30, target ?? state.target))
            raw = Int((state.isFahrenheit ? celsius * 9 / 5 + 32 : celsius).rounded())
        case "fan":
            name = "WdSpd"
            guard let speed = ["Auto": 0, "Low": 1, "Medium": 3, "High": 5][value ?? ""] else { throw GreeAdapterError.unsupportedControl }
            raw = speed
        default: throw GreeAdapterError.unsupportedControl
        }
        let inner: [String: Any] = ["t": "cmd", "mac": state.device.mac, "opt": [name], "p": [raw]]
        let envelope = try makeEnvelope(inner, mac: state.device.mac, index: 0, cipher: state.cipher, key: Data(state.key.utf8))
        _ = try await exchange(host: state.device.host, packet: try json(envelope), timeout: 3)
        return try await read(state.device, key: state.key, cipher: state.cipher)
    }

    private static func bind(_ device: DeviceInfo) async throws -> (String, CipherKind) {
        let inner: [String: Any] = ["t": "bind", "mac": device.mac, "uid": 0]
        for cipher in [CipherKind.v1, .v2] {
            let defaultKey = cipher == .v1 ? v1DefaultKey : v2DefaultKey
            let envelope = try makeEnvelope(inner, mac: device.mac, index: 1, cipher: cipher, key: defaultKey)
            guard let response = try? await exchange(host: device.host, packet: json(envelope), timeout: 1.6),
                  let values = try? decryptPack(decodeEnvelope(response), cipher: cipher, key: defaultKey),
                  values["t"] as? String == "bindok", let key = values["key"] as? String, !key.isEmpty else { continue }
            return (key, cipher)
        }
        throw GreeAdapterError.bindingFailed
    }

    private static func makeEnvelope(_ inner: [String: Any], mac: String, index: Int, cipher: CipherKind, key: Data) throws -> [String: Any] {
        let clear = try json(inner)
        let encrypted = try encrypt(clear, cipher: cipher, key: key)
        return ["cid": "app", "i": index, "t": "pack", "uid": 0, "tcid": mac, "pack": encrypted]
    }

    private static func encrypt(_ data: Data, cipher: CipherKind, key: Data) throws -> String {
        let encrypted: Data
        if cipher == .v1 {
            var output = Data(count: data.count + kCCBlockSizeAES128)
            let outputCapacity = output.count
            var length = 0
            let status = output.withUnsafeMutableBytes { outputBytes in
                data.withUnsafeBytes { inputBytes in
                    key.withUnsafeBytes { keyBytes in
                        CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode),
                                keyBytes.baseAddress, kCCKeySizeAES128, nil, inputBytes.baseAddress, data.count,
                                outputBytes.baseAddress, outputCapacity, &length)
                    }
                }
            }
            guard status == kCCSuccess else { throw GreeAdapterError.crypto }
            encrypted = output.prefix(length)
        } else {
            let aesKey = SymmetricKey(data: key)
            guard let nonce = try? AES.GCM.Nonce(data: v2Nonce),
                  let box = try? AES.GCM.seal(data, using: aesKey, nonce: nonce) else { throw GreeAdapterError.crypto }
            encrypted = box.ciphertext + box.tag
        }
        return encrypted.base64EncodedString()
    }

    private static func decrypt(_ encoded: String, cipher: CipherKind, key: Data) throws -> Data {
        guard let input = Data(base64Encoded: encoded) else { throw GreeAdapterError.crypto }
        if cipher == .v1 {
            guard !input.isEmpty, input.count % kCCBlockSizeAES128 == 0 else { throw GreeAdapterError.crypto }
            var output = Data(count: input.count + kCCBlockSizeAES128)
            let outputCapacity = output.count
            var length = 0
            let status = output.withUnsafeMutableBytes { outputBytes in
                input.withUnsafeBytes { inputBytes in
                    key.withUnsafeBytes { keyBytes in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode),
                                keyBytes.baseAddress, kCCKeySizeAES128, nil, inputBytes.baseAddress, input.count,
                                outputBytes.baseAddress, outputCapacity, &length)
                    }
                }
            }
            guard status == kCCSuccess else { throw GreeAdapterError.crypto }
            return output.prefix(length)
        }
        let aesKey = SymmetricKey(data: key)
        guard let nonce = try? AES.GCM.Nonce(data: v2Nonce), input.count >= 16 else { throw GreeAdapterError.crypto }
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: input.dropLast(16), tag: input.suffix(16))
        return try AES.GCM.open(box, using: aesKey)
    }

    private static func decryptPack(_ envelope: [String: Any], cipher: CipherKind, key: Data) throws -> [String: Any] {
        guard let encoded = envelope["pack"] as? String else { throw GreeAdapterError.invalidResponse }
        let clear = try decrypt(encoded, cipher: cipher, key: key)
        guard let object = try JSONSerialization.jsonObject(with: clear) as? [String: Any] else { throw GreeAdapterError.invalidResponse }
        return object
    }

    private static func decodeEnvelope(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw GreeAdapterError.invalidResponse }
        return object
    }

    private static func json(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }
    private static func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }

    private static func exchange(host: String, packet: Data, timeout: TimeInterval) async throws -> Data {
        guard let host = LocalWiFiIPv4.validatedHost(host) else { throw GreeAdapterError.invalidAddress }
        guard let nwPort = NWEndpoint.Port(rawValue: 7000) else { throw GreeAdapterError.invalidAddress }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .udp)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let queue = DispatchQueue(label: "se.yeager.klimat.gree.udp")
            let lock = NSLock()
            var completed = false
            let finish: (Result<Data, Error>) -> Void = { result in
                lock.lock(); defer { lock.unlock() }
                guard !completed else { return }
                completed = true
                connection.cancel()
                continuation.resume(with: result)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: packet, completion: .contentProcessed { error in
                        if let error { finish(.failure(error)); return }
                        connection.receiveMessage { data, _, _, error in
                            if let data, !data.isEmpty { finish(.success(data)) }
                            else { finish(.failure(error ?? GreeAdapterError.timeout)) }
                        }
                    })
                case .failed(let error): finish(.failure(error))
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(.failure(GreeAdapterError.timeout)) }
        }
    }
}

private enum GreeAdapterError: LocalizedError {
    case invalidAddress, invalidResponse, bindingFailed, crypto, timeout, unsupportedControl, networkUnavailable
    var errorDescription: String? {
        switch self {
        case .invalidAddress: return "Enter a valid Gree adapter IP address."
        case .invalidResponse: return "The device did not return a supported Gree response."
        case .bindingFailed: return "Could not pair with this Gree adapter. Check that it is online and available for local control."
        case .crypto: return "Could not decode the Gree adapter response."
        case .timeout: return "The Gree adapter did not respond on the local network."
        case .unsupportedControl: return "This Gree control is not supported by the adapter."
        case .networkUnavailable: return "Klimat could not send or receive Gree traffic on the local network."
        }
    }
}
