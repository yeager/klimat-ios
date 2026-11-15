import Foundation
import CommonCrypto

/// Local-only protocol adapter for Mitsubishi MAC-577IF-E / MAC-577IF-2E.
/// Protocol reference: https://github.com/pymitsubishi/pymitsubishi (MIT).
enum MitsubishiLocalAdapter {
    struct State {
        let mac: String
        let isOn: Bool
        let current: Double
        let target: Double
        let mode: String
        let fan: String
        let general: [UInt8]
    }

    static func discover(host: String) async throws -> State {
        let state = try await read(host: host, timeout: 1.2)
        guard !state.mac.isEmpty || state.general.count >= 21 else { throw URLError(.cannotParseResponse) }
        return state
    }

    static func read(host: String, timeout: TimeInterval = 5) async throws -> State {
        let xml = try await exchange(host: host, payload: "<CSV></CSV>", timeout: timeout)
        return try parse(xml)
    }

    static func command(host: String, action: String, value: String?, number: Double?) async throws -> State {
        let current = try await read(host: host)
        var packet = Array(repeating: UInt8(0), count: 20)
        packet.replaceSubrange(0..<5, with: [0x41, 0x01, 0x30, 0x10, 0x01])
        packet[7] = current.general[8]; packet[8] = current.general[9]
        packet[9] = current.general[10]; packet[10] = current.general[11]
        packet[11] = current.general[12]; packet[15] = current.general[13]
        packet[17] = current.general[15] & 0x0f
        packet[18] = current.general[16] == 0 ? 0 : current.general[16]
        packet[19] = 0x41
        var mask: UInt16 = 0x0002 // Outside control flag required by the adapter.
        switch action {
        case "power": mask |= 0x0100; packet[7] = value == "on" ? 1 : 0
        case "mode":
            mask |= 0x0200
            let modes = ["Auto": UInt8(8), "Heat": 1, "Dry": 2, "Cool": 3, "Fan": 7]
            guard let mode = modes[value ?? ""] else { throw URLError(.unsupportedURL) }; packet[8] = mode
        case "temperature":
            mask |= 0x0400
            let target = max(16, min(31, number ?? current.target))
            packet[9] = UInt8(31 - Int(target)); packet[18] = UInt8(0x80 + Int(target * 2))
        case "fan":
            mask |= 0x0800
            let speeds = ["Auto": UInt8(0), "Low": 1, "Medium": 3, "High": 6]
            guard let speed = speeds[value ?? ""] else { throw URLError(.unsupportedURL) }; packet[10] = speed
        default: throw URLError(.unsupportedURL)
        }
        packet[5] = UInt8(mask >> 8); packet[6] = UInt8(mask & 0xff)
        let packetSum = packet.reduce(0) { ($0 + Int($1)) & 0xff }
        let checksum = UInt8((0x100 - packetSum) & 0xff)
        let bytes = [UInt8(0xfc)] + packet + [checksum]
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let commandXML = "<CSV><CODE><VALUE>\(hex)</VALUE></CODE></CSV>"
        _ = try await exchange(host: host, payload: commandXML, timeout: 5)
        return try await read(host: host)
    }

    private static func parse(_ xml: String) throws -> State {
        let capture = try parseXML(xml)
        var general: [UInt8]?
        var sensor: [UInt8]?
        for text in capture.codeValues {
            guard let bytes = decodeHex(text), bytes.count >= 21, bytes[0] == 0xfc else { continue }
            if bytes[5] == 0x02 { general = bytes }
            if bytes.count > 12 && bytes[5] == 0x03 { sensor = bytes }
        }
        guard let general, general.count >= 22, checksumIsValid(general) else { throw URLError(.cannotParseResponse) }
        let modeMap: [UInt8: String] = [0: "Auto", 1: "Heat", 2: "Dry", 3: "Cool", 7: "Fan"]
        let fanMap: [UInt8: String] = [0: "Auto", 1: "Low", 2: "Low", 3: "Medium", 5: "High", 6: "High"]
        let target = general[16] == 0 ? Double(31 - general[10]) : Double(general[16] - 0x80) / 2
        let current = sensor.map { Double(Int($0[11]) - 0x80) / 2 } ?? 23
        return State(mac: capture.mac, isOn: general[8] == 1, current: current, target: target,
                     mode: modeMap[general[9] & 0x07] ?? "Auto", fan: fanMap[general[11]] ?? "Auto", general: general)
    }

    private static func exchange(host: String, payload: String, timeout: TimeInterval) async throws -> String {
        let encrypted = try encrypt(payload)
        let body = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><ESV>\(encrypted)</ESV>"
        guard let localHost = LocalWiFiIPv4.validatedHost(host),
              let url = URL(string: "http://\(localHost)/smart") else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"; request.httpBody = body.data(using: .utf8)
        request.setValue("text/plain;chrset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("close", forHTTPHeaderField: "Connection")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("KirigamineRemote/5.1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let responseXML = String(data: data, encoding: .utf8) else { throw URLError(.badServerResponse) }
        let responseCapture = try parseXML(responseXML)
        guard let plaintext = decrypt(responseCapture.esv) else { throw URLError(.badServerResponse) }
        return plaintext
    }

    fileprivate struct XMLCapture { var codeValues: [String] = []; var mac = ""; var esv = "" }
    private static func parseXML(_ xml: String) throws -> XMLCapture {
        guard let data = xml.data(using: .utf8) else { throw URLError(.cannotDecodeContentData) }
        let parser = XMLParser(data: data); let delegate = MitsubishiXMLDelegate(); parser.delegate = delegate
        guard parser.parse() else { throw parser.parserError ?? URLError(.cannotParseResponse) }
        return delegate.result
    }

    private static let key = Array("unregistered".utf8) + [0, 0, 0, 0]
    private static func encrypt(_ text: String) throws -> String {
        var input = Array(text.utf8); input.append(0x80); while input.count % 16 != 0 { input.append(0) }
        var iv = [UInt8](repeating: 0, count: 16); guard SecRandomCopyBytes(kSecRandomDefault, iv.count, &iv) == errSecSuccess else { throw URLError(.cannotCreateFile) }
        let encrypted = try aes(input, key: key, iv: iv, operation: CCOperation(kCCEncrypt))
        return Data(iv + encrypted).base64EncodedString()
    }
    private static func decrypt(_ text: String) -> String? {
        guard let data = Data(base64Encoded: text), data.count > 16 else { return nil }
        let bytes = Array(data); guard let clear = try? aes(Array(bytes.dropFirst(16)), key: key, iv: Array(bytes.prefix(16)), operation: CCOperation(kCCDecrypt)) else { return nil }
        var unpadded = clear; while unpadded.last == 0 { unpadded.removeLast() }; if unpadded.last == 0x80 { unpadded.removeLast() }
        return String(bytes: unpadded, encoding: .utf8)
    }
    private static func aes(_ input: [UInt8], key: [UInt8], iv: [UInt8], operation: CCOperation) throws -> [UInt8] {
        var output = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128); var length = 0
        let status = CCCrypt(operation, CCAlgorithm(kCCAlgorithmAES), CCOptions(0), key, kCCKeySizeAES128, iv, input, input.count, &output, output.count, &length)
        guard status == kCCSuccess else { throw URLError(.cannotDecodeContentData) }
        return Array(output.prefix(length))
    }
    private static func decodeHex(_ text: String) -> [UInt8]? {
        let chars = Array(text); guard chars.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []; bytes.reserveCapacity(chars.count / 2)
        for i in stride(from: 0, to: chars.count, by: 2) { guard let byte = UInt8(String(chars[i...i+1]), radix: 16) else { return nil }; bytes.append(byte) }
        return bytes
    }
    private static func checksumIsValid(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 22 else { return false }
        let sum = bytes[1..<21].reduce(0) { ($0 + Int($1)) & 0xff }
        return UInt8((0x100 - sum) & 0xff) == bytes[21]
    }
}

private final class MitsubishiXMLDelegate: NSObject, XMLParserDelegate {
    var result = MitsubishiLocalAdapter.XMLCapture()
    private var elements: [String] = []
    private var capturedElement: String?
    private var text = ""
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        elements.append(elementName)
        if elementName == "VALUE", elements.count >= 2, elements[elements.count - 2] == "CODE" { capturedElement = "CODE_VALUE"; text = "" }
        else if elementName == "MAC" || elementName == "ESV" { capturedElement = elementName; text = "" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if capturedElement != nil { text += string } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if let capturedElement, (capturedElement == elementName || capturedElement == "CODE_VALUE" && elementName == "VALUE") {
            switch capturedElement { case "CODE_VALUE": result.codeValues.append(text.trimmingCharacters(in: .whitespacesAndNewlines)); case "MAC": result.mac = text.trimmingCharacters(in: .whitespacesAndNewlines); case "ESV": result.esv = text.trimmingCharacters(in: .whitespacesAndNewlines); default: break }
            self.capturedElement = nil; text = ""
        }
        if !elements.isEmpty { elements.removeLast() }
    }
}
