import Foundation
import Security

enum Keychain {
    private static let service = "dev.lixelv.glasschat"
    /// The API token; `decision-token` is the decision model's own one.
    static let mainAccount = "api-token"
    static let decisionAccount = "decision-token"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func token(_ account: String = mainAccount) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setToken(_ token: String?, _ account: String = mainAccount) {
        guard let token, !token.isEmpty else {
            SecItemDelete(query(account) as CFDictionary)
            return
        }
        let data = Data(token.utf8)
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query(account)
            q[kSecValueData as String] = data
            SecItemAdd(q as CFDictionary, nil)
        }
    }
}
