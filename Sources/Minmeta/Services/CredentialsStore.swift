import Foundation

/// Local credential store backed by a 0600-mode JSON file in
/// `~/Library/Application Support/Minmeta/credentials.json`.
///
/// We deliberately don't use the macOS Keychain. The legacy Keychain attaches
/// an ACL bound to the saving binary's code signature; rebuilding the app
/// produces a new ad-hoc signature, so every build's first read triggers an
/// "Allow / Always Allow" dialog. The data-protection Keychain avoids this
/// but requires a Developer ID + entitlements.
///
/// Threat model for this file:
///  - Anyone running as the same user can read it (it's plaintext on disk).
///  - Other macOS users on the same machine cannot (mode 0600).
///  - Anyone with disk access (e.g. a stolen laptop without FileVault) can
///    read it.
/// If you need stronger protection than that, set up Apple Developer signing
/// and switch to the data-protection Keychain.
enum CredentialsStore {

    static func read(account: String) -> String? {
        guard let url = fileURL(),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return nil }
        let v = dict[account]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (v?.isEmpty == false) ? v : nil
    }

    static func save(account: String, value: String) {
        guard let url = fileURL() else { return }
        let dir = url.deletingLastPathComponent()

        var dict: [String: String] = [:]
        if let existing = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: String].self, from: existing) {
            dict = decoded
        }
        dict[account] = value

        guard let data = try? JSONEncoder().encode(dict) else { return }

        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        do {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        } catch {
            // best-effort — losing the credentials store is recoverable;
            // the user can re-enter the key on the lock screen.
        }
    }

    static func delete(account: String) {
        guard let url = fileURL(),
              let data = try? Data(contentsOf: url),
              var dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }

        dict.removeValue(forKey: account)
        if dict.isEmpty {
            try? FileManager.default.removeItem(at: url)
        } else if let out = try? JSONEncoder().encode(dict) {
            try? out.write(to: url, options: .atomic)
        }
    }

    /// Visible to the lock screen so we can show "stored at: …/credentials.json".
    static var displayPath: String {
        fileURL()?.path ?? "~/Library/Application Support/Minmeta/credentials.json"
    }

    private static func fileURL() -> URL? {
        guard let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
        else { return nil }
        return appSupport
            .appendingPathComponent("Minmeta", isDirectory: true)
            .appendingPathComponent("credentials.json")
    }
}
