import Foundation
import Security

/// The alert webhook contains a key that lets anyone post to the user's group, so it is kept in
/// the macOS Keychain instead of the settings file.
enum Keychain {
    private static let service = "轻舟助手"

    static func read(_ account: String) -> String? {
        var query = base(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Saves the value (an empty one removes it). false = the Keychain refused.
    @discardableResult
    static func save(_ value: String, account: String) -> Bool {
        let removed = SecItemDelete(base(account) as CFDictionary)
        guard !value.isEmpty else { return removed == errSecSuccess || removed == errSecItemNotFound }
        var query = base(account)
        query[kSecValueData as String] = Data(value.utf8)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private static func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
