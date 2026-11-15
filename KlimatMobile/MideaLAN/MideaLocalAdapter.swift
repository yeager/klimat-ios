import Foundation
import Network

/// Local-only support for Midea protocol version 2 air conditioners.
/// Protocol implementation is derived from MideaKit/msmart-ng; see THIRD_PARTY_NOTICES.md.
enum MideaLocalAdapter {
    struct Device: Sendable {
        let id: UInt64
        let host: String
        let port: UInt16
        let name: String
        let serialNumber: String?
    }

    struct State: Sendable {
        let isOn: Bool
        let current: Double
        let target: Double
        let mode: String
        let fan: String
    }

    static func discover(broadcastAddress: String, timeout: TimeInterval = 2.5) async throws -> [Device] {
        let devices = try await Discovery.discover(broadcastAddress: broadcastAddress, timeout: timeout)
        return devices
            .filter { $0.version == 2 && LocalWiFiIPv4.validatedHost($0.ip) != nil && $0.port > 0 }
            .map { Device(id: $0.id, host: $0.ip, port: $0.port, name: $0.name, serialNumber: $0.serialNumber) }
    }

    static func discover(host: String, timeout: TimeInterval = 2.5) async throws -> Device {
        guard let host = LocalWiFiIPv4.validatedHost(host),
              let broadcastAddress = LocalWiFiIPv4.broadcastAddress() else {
            throw MideaAdapterError.invalidAddress
        }
        let devices = try await Discovery.discover(
            broadcastAddress: broadcastAddress, timeout: timeout, unicastTargets: [host]
        )
        guard let match = devices.first(where: { $0.ip == host && $0.version == 2 && $0.port > 0 }) else {
            throw MideaAdapterError.notFound
        }
        return Device(id: match.id, host: match.ip, port: match.port, name: match.name, serialNumber: match.serialNumber)
    }

    static func read(_ device: Device) async throws -> State {
        try await withSession(device) { connection, reader in
            let state = try await queryState(connection, reader: reader, deviceID: device.id)
            return makeState(state)
        }
    }

    static func command(_ device: Device, action: String, value: String?, target: Double?) async throws -> State {
        try await withSession(device) { connection, reader in
            let current = try await queryState(connection, reader: reader, deviceID: device.id)
            var set = SetState(from: current)
            switch action {
            case "power": set.powerOn = value == "on"
            case "temperature": set.targetTemperature = max(17, min(30, target ?? current.targetTemperature))
            case "mode":
                guard let mode = ["Auto": OperationalMode.auto, "Cool": .cool, "Dry": .dry, "Heat": .heat, "Fan": .fanOnly][value ?? ""] else {
                    throw MideaAdapterError.unsupportedControl
                }
                set.mode = mode
            case "fan":
                guard let speed = ["Auto": FanSpeed.auto, "Low": .low, "Medium": .medium, "High": .high][value ?? ""] else {
                    throw MideaAdapterError.unsupportedControl
                }
                set.fanSpeed = speed
            default: throw MideaAdapterError.unsupportedControl
            }
            try await send(set.encode(), deviceID: device.id, over: connection)
            return makeState(try await reader.receiveState())
        }
    }

    private static func makeState(_ state: ACState) -> State {
        let mode: String
        switch state.mode {
        case .auto: mode = "Auto"
        case .cool: mode = "Cool"
        case .dry: mode = "Dry"
        case .heat: mode = "Heat"
        case .fanOnly: mode = "Fan"
        default: mode = "Auto"
        }
        let fan: String
        switch state.fanSpeed {
        case .auto: fan = "Auto"
        case .silent, .low: fan = "Low"
        case .medium: fan = "Medium"
        default: fan = state.fanSpeed.rawValue >= 80 ? "High" : "Medium"
        }
        return State(isOn: state.powerOn, current: state.indoorTemperature ?? 23,
                     target: state.targetTemperature, mode: mode, fan: fan)
    }

    private static func withSession<T>(
        _ device: Device,
        operation: (NWConnection, MideaPacketReader) async throws -> T
    ) async throws -> T {
        guard let host = LocalWiFiIPv4.validatedHost(device.host), let port = NWEndpoint.Port(rawValue: device.port) else {
            throw MideaAdapterError.invalidAddress
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        defer { connection.cancel() }
        try await waitUntilReady(connection, timeout: 5)
        return try await operation(connection, MideaPacketReader(connection: connection))
    }

    private static func waitUntilReady(_ connection: NWConnection, timeout: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let gate = MideaContinuation<Void>(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: gate.finish(.success(()))
                case .failed(let error): gate.finish(.failure(error))
                case .cancelled: gate.finish(.failure(MideaAdapterError.connectionClosed))
                default: break
                }
            }
            connection.start(queue: DispatchQueue(label: "se.yeager.klimat.midea.tcp"))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                gate.finish(.failure(MideaAdapterError.timeout))
            }
        }
    }

    private static func queryState(
        _ connection: NWConnection,
        reader: MideaPacketReader,
        deviceID: UInt64
    ) async throws -> ACState {
        try await send(Command.getState(), deviceID: deviceID, over: connection)
        return try await reader.receiveState()
    }

    private static func send(_ frame: [UInt8], deviceID: UInt64, over connection: NWConnection) async throws {
        let packet = try V2Packet.encode(deviceId: deviceID, command: frame)
        try await withCheckedThrowingContinuation { continuation in
            let gate = MideaContinuation<Void>(continuation)
            connection.send(content: Data(packet), completion: .contentProcessed { error in
                if let error { gate.finish(.failure(error)) } else { gate.finish(.success(())) }
            })
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                gate.finish(.failure(MideaAdapterError.timeout))
            }
        }
    }

    fileprivate static func receiveChunk(from connection: NWConnection, timeout: TimeInterval) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let gate = MideaContinuation<Data>(continuation)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, complete, error in
                if let error { gate.finish(.failure(error)) }
                else if let data, !data.isEmpty { gate.finish(.success(data)) }
                else if complete { gate.finish(.failure(MideaAdapterError.connectionClosed)) }
                else { gate.finish(.failure(MideaAdapterError.connectionClosed)) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if gate.finish(.failure(MideaAdapterError.timeout)) { connection.cancel() }
            }
        }
    }

}

private final class MideaPacketReader {
    private let connection: NWConnection
    private var buffer = [UInt8]()

    init(connection: NWConnection) { self.connection = connection }

    func receiveState() async throws -> ACState {
        // Like MideaKit, skip unsolicited or non-state frames. Keep unread bytes
        // between frames because one TCP receive may contain multiple packets.
        for _ in 0..<4 {
            let deadline = Date().addingTimeInterval(6)
            while Date() < deadline {
                if let packet = extractPacket() {
                    let frame = try V2Packet.decode(packet)
                    if let state = try ACState.parse(frame: frame) { return state }
                    break
                }
                let remaining = max(0.1, deadline.timeIntervalSinceNow)
                let data = try await MideaLocalAdapter.receiveChunk(from: connection, timeout: remaining)
                buffer.append(contentsOf: data)
            }
        }
        connection.cancel()
        throw MideaAdapterError.timeout
    }

    private func extractPacket() -> [UInt8]? {
        guard let start = buffer.indices.dropLast().first(where: { buffer[$0] == 0x5A && buffer[$0 + 1] == 0x5A }) else {
            buffer = buffer.suffix(1).map { $0 }
            return nil
        }
        if start > 0 { buffer.removeFirst(start) }
        guard buffer.count >= 6 else { return nil }
        let length = Int(buffer[4]) | (Int(buffer[5]) << 8)
        guard length >= 56 else { buffer.removeFirst(2); return nil }
        guard buffer.count >= length else { return nil }
        let packet = Array(buffer.prefix(length))
        buffer.removeFirst(length)
        return packet
    }
}

private final class MideaContinuation<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) { self.continuation = continuation }

    @discardableResult func finish(_ result: Result<Value, Error>) -> Bool {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        guard let continuation else { return false }
        continuation.resume(with: result)
        return true
    }
}

private enum MideaAdapterError: LocalizedError {
    case invalidAddress, notFound, timeout, connectionClosed, unsupportedControl
    var errorDescription: String? {
        switch self {
        case .invalidAddress: return "This Midea device is outside the current local Wi-Fi network."
        case .notFound: return "No Midea V2 device replied at this local Wi-Fi address."
        case .timeout: return "The Midea adapter did not respond on the local network."
        case .connectionClosed: return "The Midea adapter closed the local connection."
        case .unsupportedControl: return "This Midea control is not supported by the adapter."
        }
    }
}
