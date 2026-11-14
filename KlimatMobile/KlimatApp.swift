import SwiftUI

@main
struct KlimatApp: App {
    @StateObject private var store = ClimateStore()
    var body: some Scene {
        WindowGroup { HomeView().environmentObject(store).preferredColorScheme(.light) }
    }
}
