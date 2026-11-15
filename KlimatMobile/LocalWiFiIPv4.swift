import Darwin
import Foundation

/// Restricts direct adapter traffic to the iPhone's current private Wi-Fi subnet.
enum LocalWiFiIPv4 {
    private struct Subnet {
        let address: UInt32
        let network: UInt32
        let broadcast: UInt32
        let mask: UInt32
    }

    static func hosts() -> [String] {
        guard let subnet = currentSubnet(), subnet.broadcast > subnet.network + 1 else { return [] }
        return ((subnet.network + 1)..<subnet.broadcast)
            .filter { $0 != subnet.address }
            .map(addressString)
    }

    static func broadcastAddress() -> String? {
        currentSubnet().map { addressString($0.broadcast) }
    }

    static func validatedHost(_ input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var address = in_addr()
        guard inet_pton(AF_INET, text, &address) == 1,
              let subnet = currentSubnet() else { return nil }

        let value = UInt32(bigEndian: address.s_addr)
        guard isPrivate(value),
              value != subnet.address,
              value != subnet.network,
              value != subnet.broadcast,
              (value & subnet.mask) == (subnet.address & subnet.mask) else { return nil }

        return addressString(value)
    }

    static func isCurrentBroadcast(_ input: String) -> Bool {
        guard let subnet = currentSubnet() else { return false }
        return input == addressString(subnet.broadcast)
    }

    private static func currentSubnet() -> Subnet? {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let first else { return nil }
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
            guard isPrivate(ip) else { return nil }

            let network = ip & mask
            let broadcast = network | ~mask
            guard broadcast > network, broadcast - network <= 512 else { return nil }
            return Subnet(address: ip, network: network, broadcast: broadcast, mask: mask)
        }
        return nil
    }

    private static func isPrivate(_ address: UInt32) -> Bool {
        (address >> 24) == 10 || (address >> 20) == 0xAC1 || (address >> 16) == 0xC0A8
    }

    private static func addressString(_ value: UInt32) -> String {
        "\((value >> 24) & 255).\((value >> 16) & 255).\((value >> 8) & 255).\(value & 255)"
    }
}
