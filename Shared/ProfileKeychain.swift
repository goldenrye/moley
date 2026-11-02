import Foundation
import Security

enum ProfileKeychain {
    private static var accessGroup: String {
        Bundle.main.object(forInfoDictionaryKey: "MoleyKeychainGroup") as! String
    }

    static func store(_ text: String) throws -> Data {
        let attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "Moley.WireGuardProfile",
            kSecAttrAccount: UUID().uuidString,
            kSecAttrAccessGroup: accessGroup,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable: false,
            kSecValueData: Data(text.utf8),
            kSecReturnPersistentRef: true
        ]
        var result: CFTypeRef?
        let status = SecItemAdd(attributes as CFDictionary, &result)
        guard status == errSecSuccess, let reference = result as? Data else {
            throw failure(status)
        }
        return reference
    }

    static func read(_ reference: Data) throws -> String {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecValuePersistentRef: reference,
            kSecReturnData: true
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let text = String(data: data, encoding: .utf8) else { throw failure(status) }
        return text
    }

    static func delete(_ reference: Data) throws {
        let status = SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecValuePersistentRef: reference
        ] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
    }

    private static func failure(_ status: OSStatus) -> ProfileError {
        ProfileError(message: "Secure profile storage is unavailable (\(status)). Unlock your iPhone, then try again. Check Keychain Sharing when building the app.")
    }
}
