import Foundation
import WatchConnectivity

@MainActor
final class PhoneWatchConnectivity: NSObject, ObservableObject, WCSessionDelegate {
    private weak var store: ClimateStore?
    private var temperatureUnit = "celsius"

    func activate(store: ClimateStore) {
        self.store = store
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func updateContext(from store: ClimateStore, temperatureUnit: String? = nil) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        if let temperatureUnit { self.temperatureUnit = temperatureUnit }
        var context = snapshot(for: store)
        context["temperatureUnit"] = self.temperatureUnit
        do { try WCSession.default.updateApplicationContext(context) }
        catch { /* The next state change will retry the latest snapshot. */ }
    }

    private func handle(_ message: [String: Any]) async -> [String: Any] {
        guard let store else { return ["error": String(localized: "Connection unavailable")] }
        let command = message["command"] as? String ?? "refresh"

        if command == "select", let deviceID = message["deviceID"] as? String,
           store.devices.contains(where: { $0.id == deviceID }) {
            store.selectedID = deviceID
            await store.refreshDevice(deviceID: deviceID)
        } else if command == "refresh" {
            store.connectionNotice = nil
            await store.refreshDevice(deviceID: message["deviceID"] as? String ?? store.selectedID)
        } else if command == "control" {
            guard let action = message["action"] as? String,
                  ["power", "temperature", "mode", "fan"].contains(action) else {
                return snapshot(for: store, error: String(localized: "This device does not support this control."))
            }
            store.connectionNotice = nil
            let deviceID = message["deviceID"] as? String
            let value = message["value"] as? String
            let number = (message["number"] as? NSNumber)?.doubleValue
            await store.command(deviceID: deviceID, action: action, value: value, number: number)
            let error = store.connectionNotice
            updateContext(from: store)
            return snapshot(for: store, error: error)
        }

        let error = store.connectionNotice
        updateContext(from: store)
        return snapshot(for: store, error: error)
    }

    private func snapshot(for store: ClimateStore, error: String? = nil) -> [String: Any] {
        let devices = store.devices.map { device -> [String: Any] in
            var item: [String: Any] = [
                "id": device.id,
                "name": device.name,
                "brand": device.brand,
                "connection": device.connection,
                "isOn": device.isOn,
                "current": device.current,
                "target": device.target,
                "mode": device.mode,
                "fan": device.fan
            ]
            if let updatedAt = device.statusUpdatedAt { item["statusUpdatedAt"] = updatedAt.timeIntervalSince1970 }
            return item
        }
        var result: [String: Any] = [
            "devices": devices,
            "selectedID": store.selectedID ?? store.selected?.id ?? "",
            "updatedAt": Date().timeIntervalSince1970,
            "temperatureUnit": temperatureUnit
        ]
        if let error { result["error"] = error }
        return result
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self, let store = self.store else { return }
            self.updateContext(from: store)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            guard let self, let store = self.store else { return }
            self.updateContext(from: store)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor [weak self] in
            guard let self else {
                replyHandler(["error": String(localized: "Connection unavailable")])
                return
            }
            replyHandler(await self.handle(message))
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
