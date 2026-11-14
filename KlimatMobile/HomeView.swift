import SwiftUI

private enum Palette {
    static let ink = Color(red: 0.12, green: 0.20, blue: 0.17)
    static let muted = Color(red: 0.48, green: 0.56, blue: 0.52)
    static let green = Color(red: 0.20, green: 0.47, blue: 0.38)
    static let wash = Color(red: 0.93, green: 0.96, blue: 0.93)
    static let line = Color(red: 0.89, green: 0.92, blue: 0.89)
}

struct HomeView: View {
    @EnvironmentObject private var store: ClimateStore
    @State private var showAdd = false
    @State private var showCloud = false
    @State private var showManual = false
    @State private var ipAddress = ""
    @State private var roomName = "Luftkonditionering"
    @State private var showSettings = false
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.955, green: 0.967, blue: 0.946).ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        if let device = store.selected { deviceCard(device) }
                        else { emptyState }
                        if !store.devices.isEmpty { deviceList }
                        quickConnect
                        cloudSection
                        footer
                    }
                    .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 28)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showAdd) { addSheet }
            .sheet(isPresented: $showCloud) { cloudSheet }
            .sheet(isPresented: $showManual) { manualSheet }
            .sheet(isPresented: $showSettings) { settingsSheet }
            .alert("Connection unavailable", isPresented: Binding(get: { store.connectionNotice != nil }, set: { if !$0 { store.connectionNotice = nil } })) {
                Button("OK", role: .cancel) { store.connectionNotice = nil }
            } message: { Text(store.connectionNotice ?? "") }
            .onChange(of: store.showCloudSetup) { _, newValue in if newValue { showCloud = true; store.showCloudSetup = false } }
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack { RoundedRectangle(cornerRadius: 12).fill(Palette.green).frame(width: 42, height: 42); Image(systemName: "wind.snow").font(.system(size: 20, weight: .semibold)).foregroundStyle(.white) }
            VStack(alignment: .leading, spacing: 1) { Text("CLIMATE CONTROL").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.5).foregroundStyle(Palette.muted); Text("Klimat").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(Palette.ink) }
            Spacer()
            Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3").font(.system(size: 17, weight: .medium)).foregroundStyle(Palette.ink).frame(width: 42, height: 42).background(.white, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line, lineWidth: 1)) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 13) {
            ZStack { Circle().fill(Palette.wash).frame(width: 72, height: 72); Image(systemName: "air.conditioner.horizontal.fill").font(.system(size: 30)).foregroundStyle(Palette.green) }
            Text("Your home, in perfect comfort").font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(Palette.ink)
            Text("Connect directly over your local network or add climate controls from Apple Home.").font(.system(size: 13)).foregroundStyle(Palette.muted).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Button { store.beginScan() } label: { Label(store.isScanning ? "Searching…" : "Search network", systemImage: store.isScanning ? "dot.radiowaves.left.and.right" : "wifi") }.buttonStyle(PrimaryButtonStyle())
            Text(store.scanMessage).font(.system(size: 11)).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
        }
        .padding(22).frame(maxWidth: .infinity).background(.white, in: RoundedRectangle(cornerRadius: 24)).overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.line, lineWidth: 1))
    }

    private func deviceCard(_ device: ClimateDevice) -> some View {
        let canControl = (device.brand == "Daikin" && device.host != nil) || (device.brand == "Apple Home" && device.homeServiceID != nil)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) { Circle().fill(device.isOn ? Palette.green : Palette.muted.opacity(0.5)).frame(width: 7, height: 7); Text(device.isOn ? "ON" : "OFF").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(Palette.muted) }
                    Text(device.name).font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(Palette.ink)
                    Text(device.connection).font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button { Task { await store.command(action: "power", value: device.isOn ? "off" : "on") } } label: { Image(systemName: "power").font(.system(size: 16, weight: .semibold)).foregroundStyle(device.isOn ? .white : Palette.green).frame(width: 42, height: 42).background(device.isOn ? Palette.green : Palette.wash, in: Circle()) }.disabled(!canControl)
                .accessibilityLabel(device.isOn ? "Turn off" : "Turn on")
            }
            HStack(alignment: .center, spacing: 8) {
                Text(String(format: "%.0f°", device.current)).font(.system(size: 58, weight: .light, design: .rounded)).tracking(-3).foregroundStyle(Palette.ink)
                VStack(alignment: .leading, spacing: 3) { Text("INDOORS").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(Palette.muted); Text(LocalizedStringKey(device.mode)).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.green) }
                Spacer()
                Image(systemName: "thermometer.medium").font(.system(size: 27, weight: .light)).foregroundStyle(Palette.green.opacity(0.68))
            }.padding(.top, 24).padding(.bottom, 18)
            Rectangle().fill(Palette.line).frame(height: 1)
            HStack {
                VStack(alignment: .leading, spacing: 3) { Text("SET POINT").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(Palette.muted); HStack(alignment: .firstTextBaseline, spacing: 3) { Text(String(format: "%.1f", device.target)).font(.system(size: 30, weight: .semibold, design: .rounded)).foregroundStyle(Palette.ink); Text("°C").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.muted) } }
                Spacer()
                HStack(spacing: 10) {
                    stepButton("minus", label: "Lower temperature") { Task { await store.command(action: "temperature", number: max(16, device.target - 0.5)) } }.disabled(!canControl)
                    stepButton("plus", label: "Raise temperature") { Task { await store.command(action: "temperature", number: min(30, device.target + 0.5)) } }.disabled(!canControl)
                }
            }.padding(.vertical, 17)
            LazyVGrid(columns: columns, spacing: 8) {
                modeButton("Cool", icon: "snowflake", selected: device.mode == "Cool") { Task { await store.command(action: "mode", value: "Cool") } }.disabled(!canControl)
                modeButton("Heat", icon: "sun.max", selected: device.mode == "Heat") { Task { await store.command(action: "mode", value: "Heat") } }.disabled(!canControl)
                modeButton("Auto", icon: "arrow.trianglehead.2.clockwise", selected: device.mode == "Auto") { Task { await store.command(action: "mode", value: "Auto") } }.disabled(!canControl)
                modeButton("Dry", icon: "drop", selected: device.mode == "Dry") { Task { await store.command(action: "mode", value: "Dry") } }.disabled(!canControl)
            }
            HStack {
                Label("Fan speed", systemImage: "wind").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.ink)
                Spacer()
                if device.brand == "Daikin" { Menu { ForEach(["Auto", "Low", "Medium", "High"], id: \.self) { fan in Button(LocalizedStringKey(fan)) { Task { await store.command(action: "fan", value: fan) } } } } label: { HStack(spacing: 5) { Text(LocalizedStringKey(device.fan)).font(.system(size: 12, weight: .semibold)); Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold)) }.foregroundStyle(Palette.green).padding(.vertical, 9).padding(.horizontal, 11).background(Palette.wash, in: Capsule()) }.disabled(!canControl) }
            }.padding(.top, 15)
            if !canControl { Text("No verified local adapter is available for this device yet.").font(.system(size: 10)).foregroundStyle(Palette.muted).padding(.top, 8) }
        }
        .padding(18).background(.white, in: RoundedRectangle(cornerRadius: 24)).overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.line, lineWidth: 1))
    }

    private func stepButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.green).frame(width: 42, height: 42).background(Palette.wash, in: Circle()) }.accessibilityLabel(label)
    }
    private func modeButton(_ title: LocalizedStringKey, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        return Button(action: action) { HStack(spacing: 8) { Image(systemName: icon).font(.system(size: 13, weight: .medium)); Text(title).font(.system(size: 11, weight: .semibold)); Spacer(minLength: 0); if selected { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) } }.foregroundStyle(selected ? Palette.green : Palette.muted).padding(.horizontal, 11).frame(height: 38).background(selected ? Palette.wash : Color.white, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Palette.green.opacity(0.16) : Palette.line, lineWidth: 1)) }
    }

    private var deviceList: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("YOUR DEVICES", trailing: "\(store.devices.count) connected")
            ForEach(store.devices) { d in
                Button { store.selectedID = d.id } label: {
                    HStack(spacing: 11) {
                        Image(systemName: d.connection.contains("Moln") ? "cloud" : "air.conditioner.horizontal").font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.green).frame(width: 38, height: 38).background(Palette.wash, in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 3) { Text(d.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink); Text(d.brand + " · " + d.connection).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1) }
                        Spacer(); Text(String(format: "%.0f°", d.current)).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(Palette.ink); Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.muted)
                    }.padding(10).background(.white, in: RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).stroke(Palette.line, lineWidth: 1))
                }.buttonStyle(.plain)
            }
        }
    }

    private var quickConnect: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("CONNECT A DEVICE")
            Button { showAdd = true } label: { HStack(spacing: 12) { Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 16)).foregroundStyle(Palette.green).frame(width: 39, height: 39).background(Palette.wash, in: RoundedRectangle(cornerRadius: 12)); VStack(alignment: .leading, spacing: 3) { Text("Search your local network").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink); Text("Find compatible Wi-Fi adapters").font(.system(size: 10)).foregroundStyle(Palette.muted) }; Spacer(); Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.muted) }.padding(12).background(.white, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.line, lineWidth: 1)) }.buttonStyle(.plain)
        }
    }

    private var cloudSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("VIA CLOUD SERVICE", trailing: "More brands")
            LazyVGrid(columns: columns, spacing: 9) {
                ForEach(store.providers.prefix(4)) { provider in
                    Button { store.selectedProvider = provider; showCloud = true } label: {
                        HStack(spacing: 8) { Image(systemName: provider.symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.green); VStack(alignment: .leading, spacing: 2) { Text(provider.title).font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.ink).lineLimit(1); Text(provider.detail).font(.system(size: 9)).foregroundStyle(Palette.muted).lineLimit(1) } }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(11).background(.white, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }
            Button { showCloud = true } label: { HStack(spacing: 6) { Image(systemName: "plus.circle.fill"); Text("See all cloud services") }.font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.green).padding(.vertical, 4) }
        }
    }

    private var footer: some View { HStack(spacing: 6) { Image(systemName: "lock.shield"); Text("Connection details stay on your device") }.font(.system(size: 10)).foregroundStyle(Palette.muted).frame(maxWidth: .infinity).padding(.top, 3) }
    private func sectionTitle(_ title: String, trailing: String? = nil) -> some View { HStack { Text(title).font(.system(size: 9, weight: .bold)).tracking(1.25).foregroundStyle(Palette.muted); Spacer(); if let trailing { Text(trailing).font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.muted) } } }

    private var addSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Connect to your home").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(Palette.ink)
                Text("Find air conditioners on the same Wi-Fi network as your iPhone.").font(.system(size: 13)).foregroundStyle(Palette.muted)
                Button { store.beginScan() } label: { Label(store.isScanning ? "Searching for devices…" : "Start network search", systemImage: "wifi") }.buttonStyle(PrimaryButtonStyle())
                Text(store.scanMessage).font(.system(size: 12)).foregroundStyle(Palette.muted)
                if store.isScanning { ProgressView().tint(Palette.green).frame(maxWidth: .infinity).padding() }
                Button { store.scanAppleHome() } label: { Label(store.isLoadingAppleHome ? "Searching Apple Home…" : "Add climate controls from Apple Home", systemImage: "house") }.buttonStyle(SecondaryButtonStyle())
                Text(store.appleHomeStatus).font(.system(size: 11)).foregroundStyle(Palette.muted)
                Button { showAdd = false; showManual = true } label: { Label("Enter device IP address", systemImage: "number") }.buttonStyle(SecondaryButtonStyle())
                VStack(alignment: .leading, spacing: 8) { Text("DIRECT CONNECTION").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(Palette.muted); Text("Daikin with the legacy local HTTP adapter. No cloud service required.").font(.system(size: 12)).foregroundStyle(Palette.ink) }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Palette.wash, in: RoundedRectangle(cornerRadius: 15))
                Spacer()
            }.padding(20).background(Color(red: 0.955, green: 0.967, blue: 0.946).ignoresSafeArea()).toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showAdd = false }.foregroundStyle(Palette.green) } }
        }.presentationDetents([.medium, .large])
    }

    private var cloudSheet: some View {
        NavigationStack {
            List {
                if let provider = store.selectedProvider {
                    Section { CloudConnectNotice(provider: provider) { store.connectCloud(provider: provider) } }
                }
                Section("Choose a manufacturer") {
                    ForEach(store.providers) { provider in
                        Button { store.selectedProvider = provider } label: { HStack(spacing: 12) { Image(systemName: "cloud").foregroundStyle(Palette.green).frame(width: 28); VStack(alignment: .leading, spacing: 3) { Text(provider.title).foregroundStyle(Palette.ink); Text(provider.detail).font(.caption).foregroundStyle(Palette.muted) }; Spacer(); if store.selectedProvider?.id == provider.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.green) } } }
                    }
                }
                Section { Text("Manufacturer connections are listed here as a preview. Cloud sign-in and control are not enabled in this version.").font(.caption).foregroundStyle(Palette.muted) }
            }.scrollContentBackground(.hidden).background(Color(red: 0.955, green: 0.967, blue: 0.946)).navigationTitle("Cloud service").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showCloud = false }.foregroundStyle(Palette.green) } }
        }.presentationDetents([.medium, .large])
    }

    private var manualSheet: some View {
        NavigationStack {
            Form { Section("Daikin local adapter") { TextField("Name", text: $roomName); TextField("IP address, e.g. 192.168.1.42", text: $ipAddress).keyboardType(.numbersAndPunctuation).textInputAutocapitalization(.never).autocorrectionDisabled() }; Section { Text("Connect directly to a Daikin Wi-Fi adapter that supports the legacy local HTTP API. The AC and iPhone must be on the same network.").font(.caption).foregroundStyle(Palette.muted) }; Section { Button("Connect to Daikin") { Task { let oldID = store.selectedID; await store.connectDaikin(host: ipAddress, name: roomName); if store.selectedID != oldID { showManual = false } } }.foregroundStyle(Palette.green).disabled(ipAddress.isEmpty) } }.scrollContentBackground(.hidden).background(Color(red: 0.955, green: 0.967, blue: 0.946)).navigationTitle("Add locally").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { showManual = false }.foregroundStyle(Palette.green) } }
        }.presentationDetents([.medium, .large])
    }

    private var settingsSheet: some View {
        NavigationStack { List { Section("About Klimat") { LabeledContent("App", value: "Klimat"); LabeledContent("Version", value: "0.1.0"); Link(destination: URL(string: "https://github.com/yeager/klimat")!) { Label("Open source on GitHub", systemImage: "arrow.up.right.square") }.foregroundStyle(Palette.green) }; Section { Button(role: .destructive) { store.devices.removeAll(); store.selectedID = nil; store.save(); showSettings = false } label: { Label("Remove all devices", systemImage: "trash") } } }.navigationTitle("Settings").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showSettings = false }.foregroundStyle(Palette.green) } } }.presentationDetents([.medium, .large])
    }
}

private struct CloudConnectNotice: View {
    let provider: CloudProvider
    let onConnect: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(provider.title).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(Palette.ink)
            Text("Cloud control requires connecting Klimat to the manufacturer’s API. This feature is not enabled in this version.").font(.system(size: 12)).foregroundStyle(Palette.muted)
            Button(action: onConnect) { Text("Check connection") }.buttonStyle(PrimaryButtonStyle())
        }.padding(.vertical, 8)
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 13).background(Palette.green.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: 13)).scaleEffect(configuration.isPressed ? 0.99 : 1) }
}
private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.green).frame(maxWidth: .infinity).padding(.vertical, 13).background(.white, in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).stroke(Palette.line, lineWidth: 1)) }
}
