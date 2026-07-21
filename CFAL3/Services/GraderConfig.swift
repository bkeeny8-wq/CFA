import Foundation
import Security

enum GraderConfig {
    /// Cloudflare Worker that holds the Anthropic key.
    static let endpoint = URL(string: "https://cfal3-grader.bkeeny8.workers.dev")!

    /// Gate token for the worker — NOT the Anthropic key.
    static let proxyToken = "CgeWYwp2c76hA5lOeQmyQwJvb"

    private static let legacyKeychainService = "com.cfal3.anthropic-api-key"
    private static let legacyKeychainAccount = "default"

    /// One-time wipe of the old on-device Anthropic key after migrating to the proxy.
    static func purgeLegacyAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyKeychainService,
            kSecAttrAccount as String: legacyKeychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
