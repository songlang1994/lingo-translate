import Foundation
import Security

/// Stores the API key in the login keychain.
enum APIKeyStore {
    /// The bundle identifier is stable, so it doubles as the keychain service.
    private static let service = Bundle.main.bundleIdentifier!
    private static let account = "api-key"

    static func load() -> String {
        guard let data = readItem(),
              let value = String(data: data, encoding: .utf8) else {
            return ""
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func save(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            deleteItem()
            return
        }
        writeItem(Data(trimmed.utf8))
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func readItem() -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    private static func writeItem(_ data: Data) {
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)

        switch status {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            var item = baseQuery
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "Lingo Translate API key"
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            if addStatus != errSecSuccess {
                NSLog("Lingo Translate: could not save API key to keychain (%d)", addStatus)
            }
        default:
            NSLog("Lingo Translate: could not update keychain item (%d)", status)
        }
    }

    private static func deleteItem() {
        let status = SecItemDelete(baseQuery as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            NSLog("Lingo Translate: could not remove keychain item (%d)", status)
        }
    }
}
