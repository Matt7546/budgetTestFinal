import Foundation
import Security

@MainActor
protocol AuthSessionStore {
    func loadSessionToken(for environment: AuthBackendEnvironment) throws -> String?
    func saveSessionToken(_ token: String, for environment: AuthBackendEnvironment) throws
    func clearSessionToken(for environment: AuthBackendEnvironment) throws
}

struct KeychainSessionStore: AuthSessionStore {

    enum KeychainError: Error {
        case encodingFailed
        case decodingFailed
        case unexpectedStatus(OSStatus)
    }

    private let service: String

    init(service: String = "com.matthewthomas.caldera.auth") {
        self.service = service
    }

    // The historical unscoped account is deliberately quarantined: no lookup,
    // fallback, migration, write, or removal of it exists in this store.
    private func sessionAccount(for environment: AuthBackendEnvironment) -> String {
        "caldera_session_token.\(environment.credentialNamespace)"
    }

    func loadSessionToken(for environment: AuthBackendEnvironment) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sessionAccount(for: environment),
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(
            query as CFDictionary,
            &result
        )

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }

        return token
    }

    func saveSessionToken(
        _ token: String,
        for environment: AuthBackendEnvironment
    ) throws {
        guard let data = token.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sessionAccount(for: environment)
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            attributes as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus != errSecItemNotFound {
            throw KeychainError.unexpectedStatus(updateStatus)
        }

        var item = query
        attributes.forEach { key, value in
            item[key] = value
        }

        let addStatus = SecItemAdd(
            item as CFDictionary,
            nil
        )

        guard addStatus == errSecSuccess else {
            throw KeychainError.unexpectedStatus(addStatus)
        }
    }

    func clearSessionToken(for environment: AuthBackendEnvironment) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sessionAccount(for: environment)
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
