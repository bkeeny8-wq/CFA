import Foundation
import Security

enum GraderConfig {
    /// Cloudflare Worker that holds the Anthropic key.
    static let endpoint = URL(string: "https://cfal3-grader.bkeeny8.workers.dev")!

    /// Gate token for the worker — NOT the Anthropic key.
    ///
    /// Injected at build time from `Secrets/proxy-token.txt`, which is
    /// gitignored. It used to be a literal here, and this repository is public,
    /// so it sat readable on GitHub for eight weeks.
    ///
    /// To be clear about what this does and does not achieve: the value still
    /// ships inside the binary and anyone can recover it with `strings`. What
    /// changed is that it is no longer published in source and history, and it
    /// can be rotated without rewriting either. The real protection has to live
    /// in the worker — spend caps and an instant revoke — because a shared
    /// secret handed to every install was never going to stay secret.
    ///
    /// Empty on a clone without the file: the app builds and runs, and essay
    /// grading reports that it is not configured rather than failing obscurely.
    static var proxyToken: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "GraderProxyToken") as? String
        return value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static var isGraderConfigured: Bool { !proxyToken.isEmpty }

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
