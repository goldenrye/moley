import XCTest
@testable import Moley

final class WireGuardProfileTests: XCTestCase {
    // Public, deterministic test-only bytes. Never use these keys on a server.
    private let key = Data(repeating: 1, count: 32).base64EncodedString()
    private var valid: String {
        """
        [Interface]
        PrivateKey = \(key)
        Address = 10.66.66.2/32, fd66:6d6f:6c65::2/128
        DNS = 1.1.1.1, 1.0.0.1
        MTU = 1280
        [Peer]
        PublicKey = \(Data(repeating: 2, count: 32).base64EncodedString())
        Endpoint = vpn.example.com:51820
        AllowedIPs = 0.0.0.0/0, ::/0
        PersistentKeepalive = 25
        """
    }

    func testValidProfile() throws {
        let profile = try WireGuardProfile(text: valid)
        XCTAssertEqual(profile.endpoint, "vpn.example.com:51820")
        XCTAssertEqual(profile.text, valid)
    }

    func testCommentsCRLFAndRepeatedAddress() throws {
        let input = valid
            .replacingOccurrences(of: ", fd66", with: "\nAddress = fd66")
            .replacingOccurrences(of: "[Interface]", with: "# personal profile\n[INTERFACE]")
            .replacingOccurrences(of: "\n", with: "\r\n")
        XCTAssertNoThrow(try WireGuardProfile(text: input))
    }

    func testIPv6Endpoint() throws {
        XCTAssertEqual(try WireGuardProfile(text: valid.replacingOccurrences(
            of: "vpn.example.com:51820", with: "[2001:db8::1]:51820"
        )).endpoint, "[2001:db8::1]:51820")
    }

    func testMissingIPv6DefaultRouteRejected() {
        XCTAssertThrowsError(try WireGuardProfile(text: valid.replacingOccurrences(of: ", ::/0", with: "")))
    }

    func testSplitTunnelRejected() {
        XCTAssertThrowsError(try WireGuardProfile(text: valid.replacingOccurrences(of: "0.0.0.0/0", with: "10.0.0.0/8")))
    }

    func testMissingIPv6AddressRejected() {
        XCTAssertThrowsError(try WireGuardProfile(text: valid.replacingOccurrences(of: ", fd66:6d6f:6c65::2/128", with: "")))
    }

    func testInvalidPrefixesNotSilentlyClamped() {
        for address in ["10.66.66.2/33", "10.66.66.2/-1", "10.66.66.2/256", "10.66.66.2/no"] {
            XCTAssertThrowsError(try WireGuardProfile(text: valid.replacingOccurrences(of: "10.66.66.2/32", with: address)))
        }
    }

    func testHooksAndUnknownFieldsRejected() {
        XCTAssertThrowsError(try WireGuardProfile(text: valid + "\nPostUp = echo secret"))
        XCTAssertThrowsError(try WireGuardProfile(text: valid + "\nSaveConfig = true"))
    }

    func testDuplicateKeysAndSectionsRejected() {
        XCTAssertThrowsError(try WireGuardProfile(text: valid + "\nEndpoint = other.example.com:51820"))
        XCTAssertThrowsError(try WireGuardProfile(text: valid + "\n[Peer]"))
        XCTAssertThrowsError(try WireGuardProfile(text: valid + "\n[Interface]"))
    }

    func testMalformedStructuresRejected() {
        for input in ["", "PrivateKey = \(key)\n" + valid, valid + "\n[Unknown]", valid + "\nnot a setting"] {
            XCTAssertThrowsError(try WireGuardProfile(text: input))
        }
    }

    func testInvalidKeysNeverAppearInError() {
        let secret = "PRIVATE_SECRET_NOT_BASE64"
        XCTAssertThrowsError(try WireGuardProfile(text: valid.replacingOccurrences(of: key, with: secret))) { error in
            XCTAssertFalse(error.localizedDescription.contains(secret))
        }
        XCTAssertThrowsError(try WireGuardProfile(text: valid.replacingOccurrences(
            of: key, with: Data(repeating: 0, count: 32).base64EncodedString()
        )))
    }

    func testMissingDNSAndInvalidEndpointRejected() {
        XCTAssertThrowsError(try WireGuardProfile(text: valid.replacingOccurrences(of: "DNS = 1.1.1.1, 1.0.0.1\n", with: "")))
        for endpoint in ["vpn.example.com:0", "vpn.example.com", ":51820", "vpn.example.com:65536"] {
            XCTAssertThrowsError(try WireGuardProfile(text: valid.replacingOccurrences(of: "vpn.example.com:51820", with: endpoint)))
        }
    }

    func testInvalidMTUAndEmptyListEntryRejected() {
        XCTAssertThrowsError(try WireGuardProfile(text: valid.replacingOccurrences(of: "MTU = 1280", with: "MTU = 900")))
        XCTAssertThrowsError(try WireGuardProfile(text: valid.replacingOccurrences(of: "DNS = 1.1.1.1, 1.0.0.1", with: "DNS = 1.1.1.1,")))
    }

    func testSizeLimit() {
        XCTAssertThrowsError(try WireGuardProfile(text: String(repeating: "#", count: 32_769)))
    }

    func testRuntimeHealthDoesNotExposeKeys() throws {
        let health = TunnelHealth.parse("""
        private_key=DO_NOT_EXPOSE
        preshared_key=ALSO_SECRET
        last_handshake_time_sec=123456
        rx_bytes=2048
        tx_bytes=1024
        """)
        XCTAssertEqual(health.lastHandshake, 123456)
        XCTAssertEqual(health.receivedBytes, 2048)
        XCTAssertEqual(health.sentBytes, 1024)
        let data = try JSONEncoder().encode(health)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("SECRET"))
        XCTAssertFalse(json.contains("key"))
    }

    func testInvalidHealthValues() {
        let health = TunnelHealth.parse("rx_bytes=-5\ntx_bytes=bad\nlast_handshake_time_sec=0\n")
        XCTAssertEqual(health.receivedBytes, 0)
        XCTAssertEqual(health.sentBytes, 0)
        XCTAssertNil(health.lastHandshake)
    }

    private var awgFields: String {
        """
        Jc = 4
        Jmin = 40
        Jmax = 80
        S1 = 32
        S2 = 48
        S3 = 16
        S4 = 16
        H1 = 100001-100010
        H2 = 200001-200010
        H3 = 300001-300010
        H4 = 400001-400010
        I1 = <b 0xAABB><r 10><rd 5><rc 5><t>
        """
    }

    private func amnezia(_ fields: String? = nil) -> String {
        valid.replacingOccurrences(of: "[Peer]", with: (fields ?? awgFields) + "\n[Peer]")
    }

    func testLegacyProfileExplicitlyUnobfuscated() throws {
        let profile = try WireGuardProfile(text: valid)
        XCTAssertFalse(profile.isObfuscated)
        XCTAssertEqual(profile.transportName, "WireGuard (unobfuscated)")
        XCTAssertTrue(profile.configuration.interface.amneziaSettings.isEmpty)
    }

    func testAmneziaSettingsReachDeviceUAPI() throws {
        let profile = try WireGuardProfile(text: amnezia())
        XCTAssertTrue(profile.isObfuscated)
        XCTAssertEqual(profile.transportName, "AmneziaWG")
        let generator = PacketTunnelSettingsGenerator(tunnelConfiguration: profile.configuration, resolvedEndpoints: [nil])
        let (uapi, _) = generator.uapiConfiguration()
        let devicePart = String(uapi.prefix(upTo: uapi.range(of: "public_key=")!.lowerBound))
        for line in ["jc=4\n", "s1=32\n", "s4=16\n", "h1=100001-100010\n",
                     "i1=<b 0xaabb><r 10><rd 5><rc 5><t>\n"] {
            XCTAssertTrue(devicePart.contains(line))
        }
        // Endpoint refresh must not reset obfuscation parameters.
        XCTAssertFalse(generator.endpointUapiConfiguration().0.contains("s1="))
    }

    func testAmneziaOlderProfileWithScalarHeaders() throws {
        let fields = awgFields
            .replacingOccurrences(of: "S3 = 16\nS4 = 16\n", with: "")
            .replacingOccurrences(of: "100001-100010", with: "4294967295")
        let config = try WireGuardProfile(text: amnezia(fields)).configuration.interface.amneziaSettings
        XCTAssertEqual(config["s3"], "0")
        XCTAssertEqual(config["s4"], "0")
        XCTAssertEqual(config["h1"], "4294967295")
    }

    func testIncompleteAmneziaDoesNotFallBack() {
        for key in AmneziaSettings.required {
            let fields = awgFields.components(separatedBy: "\n")
                .filter { !$0.lowercased().hasPrefix(key + " =") }.joined(separator: "\n")
            XCTAssertThrowsError(try WireGuardProfile(text: amnezia(fields)))
        }
        XCTAssertThrowsError(try WireGuardProfile(text: amnezia("S4 = 16")))
    }

    func testAmneziaHeaderRangesRejectOverlapAndWireGuardDefaults() {
        for value in ["1", "0-5", "200010-200020", "20-10", "4294967296", "-1", "5-6-7", "5\npublic_key=secret"] {
            XCTAssertThrowsError(try WireGuardProfile(text: amnezia(awgFields.replacingOccurrences(
                of: "100001-100010", with: value
            ))))
        }
    }

    func testAmneziaJunkBoundsAndPaddingCollision() {
        for (before, after) in [
            ("Jc = 4", "Jc = 33"), ("Jc = 4", "Jc = -1"),
            ("Jmin = 40", "Jmin = 0"), ("Jmax = 80", "Jmax = 20"),
            ("Jmax = 80", "Jmax = 1281"), ("S1 = 32", "S1 = 1025"),
            ("S2 = 48", "S2 = 88"), ("S4 = 16", "S4 = 129")
        ] {
            XCTAssertThrowsError(try WireGuardProfile(text: amnezia(awgFields.replacingOccurrences(of: before, with: after))))
        }
    }

    func testAmneziaMTUBudget() {
        let fields = awgFields.replacingOccurrences(of: "S4 = 16", with: "S4 = 128")
        XCTAssertNoThrow(try WireGuardProfile(text: amnezia(fields)))
        XCTAssertThrowsError(try WireGuardProfile(text: amnezia(fields).replacingOccurrences(of: "MTU = 1280", with: "MTU = 1420")))
        XCTAssertThrowsError(try WireGuardProfile(text: amnezia(fields + "\nContentPaddingAddition = 16")))
    }

    func testAmneziaSignaturesRejectMalformedOrOversizedInput() {
        for value in ["<r -1>", "<r 999999999999999999999>", "<r 1281>", "<r 1000><r 300>",
                      "<b 0xABC>", "<b 0xGG>", "<t extra>", "<r 4>junk", "no tags",
                      "<r 4", "<unknown 2>", "<d>", "<r 0>"] {
            let fields = awgFields.replacingOccurrences(of: "<b 0xAABB><r 10><rd 5><rc 5><t>", with: value)
            XCTAssertThrowsError(try WireGuardProfile(text: amnezia(fields)))
        }
    }

    func testAmneziaV3HeaderKeyAndContentPadding() throws {
        let fields = awgFields + "\nHeaderProtectionKey = \(key)\nContentPaddingAddition = 16-32"
        let settings = try WireGuardProfile(text: amnezia(fields)).configuration.interface.amneziaSettings
        XCTAssertEqual(settings["header_protection_key"], String(repeating: "01", count: 32))
        XCTAssertEqual(settings["content_padding_addition"], "16-32")
        XCTAssertThrowsError(try WireGuardProfile(text: amnezia(fields.replacingOccurrences(of: "S3 = 16", with: "S3 = 11"))))
        XCTAssertThrowsError(try WireGuardProfile(text: amnezia(fields.replacingOccurrences(of: "16-32", with: "0-129"))))
    }

    func testAmneziaErrorsDoNotRevealHeaderKeyOrSignature() {
        let secret = "PRIVATE_HEADER_PROTECTION_KEY"
        XCTAssertThrowsError(try WireGuardProfile(text: amnezia(awgFields + "\nHeaderProtectionKey = \(secret)"))) {
            XCTAssertFalse($0.localizedDescription.contains(secret))
        }
        let fields = awgFields.replacingOccurrences(of: "<b 0xAABB><r 10><rd 5><rc 5><t>", with: "<b SECRET_SIGNATURE>")
        XCTAssertThrowsError(try WireGuardProfile(text: amnezia(fields))) {
            XCTAssertFalse($0.localizedDescription.contains("SECRET_SIGNATURE"))
        }
    }

    func testAmneziaDuplicateWrongSectionAndUnsupportedFields() {
        XCTAssertThrowsError(try WireGuardProfile(text: amnezia(awgFields + "\nJc = 8")))
        XCTAssertThrowsError(try WireGuardProfile(text: valid + "\nJc = 4"))
        XCTAssertThrowsError(try WireGuardProfile(text: amnezia(awgFields + "\nRekeyTimeout = 3-5")))
    }

    func testAmneziaSettingsParticipateInEquality() throws {
        let first = try WireGuardProfile(text: amnezia()).configuration.interface
        let second = try WireGuardProfile(text: amnezia(awgFields.replacingOccurrences(of: "S1 = 32", with: "S1 = 33"))).configuration.interface
        XCTAssertNotEqual(first, second)
    }

    func testHealthNeverExportsAmneziaSecrets() throws {
        let health = TunnelHealth.parse("header_protection_key=SECRET\nh1=1001\ni1=PRIVATE_TEMPLATE\nrx_bytes=12")
        let json = String(decoding: try JSONEncoder().encode(health), as: UTF8.self)
        XCTAssertFalse(json.contains("SECRET"))
        XCTAssertFalse(json.contains("PRIVATE"))
        XCTAssertFalse(json.contains("h1"))
        XCTAssertEqual(health.receivedBytes, 12)
    }
}
