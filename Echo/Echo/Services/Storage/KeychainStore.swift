//
//  KeychainStore.swift
//  Echo
//
//  Secure provider credential storage corresponding to Android's
//  EncryptedSharedPreferences-backed ProviderKeyStore.
//

import Foundation
import Security

protocol KeychainBackend {
    func read(service: String, account: String, accessGroup: String?) -> Data?
    @discardableResult
    func save(_ data: Data, service: String, account: String, accessGroup: String?) -> OSStatus
    @discardableResult
    func delete(service: String, account: String, accessGroup: String?) -> OSStatus
}

struct SecurityKeychainBackend: KeychainBackend {
    func read(service: String, account: String, accessGroup: String?) -> Data? {
        var query = baseQuery(service: service, account: account, accessGroup: accessGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    func save(_ data: Data, service: String, account: String, accessGroup: String?) -> OSStatus {
        let query = baseQuery(service: service, account: account, accessGroup: accessGroup)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard updateStatus == errSecItemNotFound else { return updateStatus }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        return SecItemAdd(addQuery as CFDictionary, nil)
    }

    func delete(service: String, account: String, accessGroup: String?) -> OSStatus {
        SecItemDelete(baseQuery(service: service, account: account, accessGroup: accessGroup) as CFDictionary)
    }

    private func baseQuery(service: String, account: String, accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}

/// In-memory backend used by unit tests. It prevents tests from touching the
/// user's real Keychain while exercising exactly the same KeychainStore API.
final class InMemoryKeychainBackend: KeychainBackend {
    private var values: [String: Data] = [:]

    func read(service: String, account: String, accessGroup: String?) -> Data? {
        values[key(service: service, account: account, accessGroup: accessGroup)]
    }

    @discardableResult
    func save(_ data: Data, service: String, account: String, accessGroup: String?) -> OSStatus {
        values[key(service: service, account: account, accessGroup: accessGroup)] = data
        return errSecSuccess
    }

    @discardableResult
    func delete(service: String, account: String, accessGroup: String?) -> OSStatus {
        values.removeValue(forKey: key(service: service, account: account, accessGroup: accessGroup))
        return errSecSuccess
    }

    private func key(service: String, account: String, accessGroup: String?) -> String {
        "\(accessGroup ?? "")|\(service)|\(account)"
    }
}

final class KeychainStore {
    static let defaultService = "com.mirailabs.echo.provider-credentials"

    private let backend: KeychainBackend
    private let service: String
    private let accessGroup: String?

    init(
        service: String = KeychainStore.defaultService,
        accessGroup: String? = nil,
        backend: KeychainBackend = SecurityKeychainBackend()
    ) {
        self.service = service
        self.accessGroup = accessGroup
        self.backend = backend
    }

    /// Saves a non-blank provider key. A blank key removes the stored key,
    /// matching Android's ProviderKeyStore.setKey behavior.
    func saveKey(_ key: String, for provider: String) {
        let account = keyAccount(provider)
        guard !key.isEmpty, !key.allSatisfy(\.isWhitespace) else {
            clearKey(for: provider)
            return
        }
        _ = backend.save(Data(key.utf8), service: service, account: account, accessGroup: accessGroup)
    }

    /// Loads a provider key, returning nil when absent or blank.
    func loadKey(for provider: String) -> String? {
        guard let data = backend.read(
            service: service,
            account: keyAccount(provider),
            accessGroup: accessGroup
        ), let value = String(data: data, encoding: .utf8),
        !value.isEmpty, !value.allSatisfy(\.isWhitespace) else { return nil }
        return value
    }

    func clearKey(for provider: String) {
        _ = backend.delete(
            service: service,
            account: keyAccount(provider),
            accessGroup: accessGroup
        )
    }

    func isConfigured(for provider: String) -> Bool {
        loadKey(for: provider) != nil
    }

    /// Loads a custom base URL override, returning nil when absent or blank.
    func loadBaseURL(for provider: String) -> String? {
        loadString(account: baseURLAccount(provider))
    }

    /// Saves a custom base URL override. A blank URL removes it.
    func saveBaseURL(_ url: String, for provider: String) {
        let account = baseURLAccount(provider)
        guard !url.isEmpty, !url.allSatisfy(\.isWhitespace) else {
            _ = backend.delete(service: service, account: account, accessGroup: accessGroup)
            return
        }
        _ = backend.save(Data(url.utf8), service: service, account: account, accessGroup: accessGroup)
    }

    func clearBaseURL(for provider: String) {
        _ = backend.delete(
            service: service,
            account: baseURLAccount(provider),
            accessGroup: accessGroup
        )
    }

    private func loadString(account: String) -> String? {
        guard let data = backend.read(service: service, account: account, accessGroup: accessGroup),
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty,
              !value.allSatisfy(\.isWhitespace) else { return nil }
        return value
    }

    private func keyAccount(_ provider: String) -> String { "key_\(provider)" }
    private func baseURLAccount(_ provider: String) -> String { "url_\(provider)" }
}
