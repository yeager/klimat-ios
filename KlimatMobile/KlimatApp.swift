import SwiftUI

@main
struct KlimatApp: App {
    @StateObject private var store = ClimateStore()
    @StateObject private var watchConnectivity = PhoneWatchConnectivity()
    @AppStorage("klimat.temperatureUnit") private var temperatureUnit = "celsius"
    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
                .onAppear {
                    watchConnectivity.activate(store: store)
                    watchConnectivity.updateContext(from: store, temperatureUnit: temperatureUnit)
                }
                .onChange(of: store.devices) { _, _ in watchConnectivity.updateContext(from: store, temperatureUnit: temperatureUnit) }
                .onChange(of: store.selectedID) { _, _ in watchConnectivity.updateContext(from: store, temperatureUnit: temperatureUnit) }
                .onChange(of: temperatureUnit) { _, unit in watchConnectivity.updateContext(from: store, temperatureUnit: unit) }
        }
    }
}
