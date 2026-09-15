import Foundation
import Security

enum GraderConfig {
    /// Cloudflare Worker that holds the Anthropic key.
    static let endpoint = URL(string: "https://cfal3-grader.bkeeny8.workers.dev")!

    /// Gate token for the worker — NOT the Anthropic key.
    ///
    /// Substituted into Info.plist from `GRADER_PROXY_TOKEN`, defined in the
    /// gitignored `Config/Secrets.xcconfig`. It used to be a literal here, and
    /// this repository is public, so it sat readable on GitHub for eight weeks.
    ///
    /// Done with build-setting substitution rather than a Run Script phase on
    /// purpose. A script that rewrote the built Info.plist ran before the
    /// plist existed on some builds and after it on others, and the target has
    /// user script sandboxing enabled, so the write was refused — giving a
    /// build that succeeded with grading silently unconfigured.
    ///
    /// To be clear about what this does and does not achieve: the value still
    /// ships inside the binary and anyone can recover it with `strings`. What
    /// changed is that it is no longer published in source and history, and it
    /// can be rotated without rewriting either. The real protection has to live
    /// in the worker, which only accepts grading-shaped requests, and in the
    /// fact that rotating PROXY_TOKEN revokes every client at once — because a
    /// shared secret handed to every install was never going to stay secret.
    ///
    /// Empty on a clone without the file: the app builds and runs, and essay
    /// grading reports that it is not configured rather than failing obscurely.
    static var proxyToken: String {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "GraderProxyToken") as? String) ?? ""
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // An undefined build setting normally expands to nothing, but some
        // toolchain paths leave the literal "$(GRADER_PROXY_TOKEN)" behind.
        // That is absence, not a token — sending it would earn a puzzling 401.
        return value.hasPrefix("$(") ? "" : value
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
