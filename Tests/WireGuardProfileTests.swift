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
}
