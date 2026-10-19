import Foundation
import Security

/// Stores the ConnectLife login in the iOS Keychain (needed because the API has no long-lived refresh path we can rely on).
enum Keychain {
    private static let service = "com.soum91.coldfront.account"

    static func save(user: String, pass: String) {
        clear()
        let payload = try? JSONSerialization.data(withJSONObject: ["u": user, "p": pass])
        let q: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "default",
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData: payload ?? Data()
        ]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func load() -> (user: String, pass: String)? {
        let q: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "default",
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let u = obj["u"], let p = obj["p"] else { return nil }
        return (u, p)
    }

    static func clear() {
        let q: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service]
        SecItemDelete(q as CFDictionary)
    }
}
