import Foundation
import Security

protocol WiFiCredentialStoring: AnyObject {
    /// Resolves a credential only for a user-selected network. Callers must
    /// never invoke this while scanning nearby networks.
    func resolveCredential(for identity: WiFiNetworkIdentity) -> WiFiCredentialResult
    /// Returns false on a Keychain write failure so the UI can report that the
    /// connection succeeded but the requested remembered-password save did not.
    func save(_ password: String, for identity: WiFiNetworkIdentity) -> Bool
}

/// Reads two deliberately separate credential namespaces on demand:
///
/// - the app-owned generic-password item for passwords the user chose to
///   remember in Status Trio; and
/// - the user Keychain standard `AirPort network password` item for a
///   personal SSID, when the user has authorized access to that system item.
///
/// CoreWLAN does not provide a public API to enumerate saved passwords, and
/// `associate(password: nil)` is not treated as credential reuse. The system
/// Keychain lookup is therefore attempted only after a click and its
/// cancellation, denial, locked-keychain, and read errors remain distinct.
final class KeychainWiFiPasswordStore: WiFiCredentialStoring, @unchecked Sendable {
    private let appService: String
    private let systemAirPortService = "AirPort network password"

    init(appService: String = "com.lingsmbp.StatusTrio.wifi-password") {
        self.appService = appService
    }

    func resolveCredential(for identity: WiFiNetworkIdentity) -> WiFiCredentialResult {
        let appResult = read(
            query: appReadQuery(for: identity),
            source: .appKeychain
        )
        switch appResult {
        case .credential, .issue:
            return appResult
        case .noCredential:
            return read(
                query: systemAirPortQuery(for: identity),
                source: .systemKeychain
            )
        }
    }

    func save(_ password: String, for identity: WiFiNetworkIdentity) -> Bool {
        guard !password.isEmpty else { return false }
        let update = [kSecValueData as String: Data(password.utf8)]
        let updateStatus = SecItemUpdate(
            appUpdateQuery(for: identity) as CFDictionary,
            update as CFDictionary
        )
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        let addStatus = SecItemAdd(appAddAttributes(password, for: identity) as CFDictionary, nil)
        if addStatus == errSecSuccess { return true }
        if addStatus == errSecDuplicateItem {
            return SecItemUpdate(
                appUpdateQuery(for: identity) as CFDictionary,
                update as CFDictionary
            ) == errSecSuccess
        }
        return false
    }

    private func read(
        query: [String: Any],
        source: WiFiCredentialSource
    ) -> WiFiCredentialResult {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let password = String(data: data, encoding: .utf8),
                  !password.isEmpty else {
                return .issue(.readFailed)
            }
            return .credential(password, source)
        case errSecItemNotFound:
            return .noCredential
        case errSecUserCanceled:
            return .issue(.cancelled)
        case errSecAuthFailed:
            return .issue(.accessDenied)
        case errSecInteractionNotAllowed, errSecNotAvailable:
            return .issue(.keychainLocked)
        default:
            return .issue(.readFailed)
        }
    }

    private func appIdentity(for identity: WiFiNetworkIdentity) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: appService,
            // Preserve raw SSID whitespace and keep security classes distinct.
            kSecAttrAccount as String: "\(identity.security.rawValue):\(identity.ssid)"
        ]
    }

    private func appReadQuery(for identity: WiFiNetworkIdentity) -> [String: Any] {
        var query = appIdentity(for: identity)
        // Copy-matching controls are valid only for the read operation.
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        return query
    }

    private func appUpdateQuery(for identity: WiFiNetworkIdentity) -> [String: Any] {
        // SecItemUpdate receives only an item identity, never return controls.
        appIdentity(for: identity)
    }

    private func appAddAttributes(_ password: String, for identity: WiFiNetworkIdentity) -> [String: Any] {
        var attributes = appIdentity(for: identity)
        attributes[kSecValueData as String] = Data(password.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return attributes
    }

    private func systemAirPortQuery(for identity: WiFiNetworkIdentity) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: systemAirPortService,
            kSecAttrAccount as String: identity.ssid,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIAllow,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
    }
}
