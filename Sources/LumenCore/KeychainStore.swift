import Foundation
import Security

public enum KeychainStore {
    private static let service = "com.lumen.desktop.provider-keys"

    public static func read(provider: AIProvider) throws -> String? {
        guard provider != .chatGPT else { return nil }
        var query = baseQuery(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainStoreError.operationFailed(status) }
        guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            throw KeychainStoreError.invalidStoredKey
        }
        return key
    }

    public static func save(_ key: String, provider: AIProvider) throws {
        guard provider != .chatGPT else { throw KeychainStoreError.unsupportedProvider }
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.rangeOfCharacter(from: .newlines) == nil else {
            throw KeychainStoreError.invalidKey
        }
        let query = baseQuery(provider)
        let updates = [kSecValueData as String: Data(value.utf8)]
        let status = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = Data(value.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainStoreError.operationFailed(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainStoreError.operationFailed(status)
        }
    }

    public static func delete(provider: AIProvider) throws {
        guard provider != .chatGPT else { return }
        let status = SecItemDelete(baseQuery(provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.operationFailed(status)
        }
    }

    private static func baseQuery(_ provider: AIProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecAttrSynchronizable as String: false,
        ]
    }
}

public enum KeychainStoreError: LocalizedError {
    case unsupportedProvider, invalidKey, invalidStoredKey
    case operationFailed(OSStatus)
    public var errorDescription: String? {
        switch self {
        case .unsupportedProvider: return "ChatGPT uses account sign-in, not an API key."
        case .invalidKey: return "Enter a nonempty API key without line breaks."
        case .invalidStoredKey: return "The saved API key could not be read. Save it again in Settings."
        case .operationFailed(let status):
            return "Keychain could not complete this operation (\(status)). "
                + ((SecCopyErrorMessageString(status, nil) as String?) ?? "Check access to the login keychain.")
        }
    }
}
