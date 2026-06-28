import Foundation
import Security

// MARK: - Install Identity Provider (Task30 R4B-1)

protocol KeychainStoring: Sendable {
    func data(service: String, account: String) -> Data?
    func save(_ data: Data, service: String, account: String) throws
}

struct SystemKeychainStore: KeychainStoring {
    func data(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        return result as? Data
    }
    func save(_ data: Data, service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}

final class InstallIdentityProvider: @unchecked Sendable {
    static let shared = InstallIdentityProvider(store: SystemKeychainStore())
    private let store: any KeychainStoring
    private let service: String
    private var memoryID: String?
    private let lock = NSLock()

    init(store: any KeychainStoring, service: String = Bundle.main.bundleIdentifier ?? "com.relaxshort.ios") {
        self.store = store; self.service = service
    }
    func installID() -> String {
        lock.lock()
        defer { lock.unlock() }

        if let memoryID { return memoryID }

        if let data = store.data(service: service, account: "install-id"),
           let value = String(data: data, encoding: .utf8),
           UUID(uuidString: value) != nil {
            memoryID = value
            return value
        }

        let value = UUID().uuidString.lowercased()
        do { try store.save(Data(value.utf8), service: service, account: "install-id") }
        catch { Logger.analytics.error("Install ID persistence failed: \(error.localizedDescription)") }
        memoryID = value
        return value
    }
}
