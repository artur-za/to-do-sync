import SwiftUI
import Security
import LocalAuthentication
import CryptoKit
import FlowCore

struct SyncConfiguration: Codable {
    var endpoint: String
    var enabled: Bool
    static var file: URL { Repository().directory.appendingPathComponent("sync-config.json") }
    static func read() -> Self? { try? JSONDecoder().decode(Self.self, from: Data(contentsOf: file)) }
    func save() throws {
        guard let url = URL(string: endpoint), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { throw FlowError.invalid("Use an HTTPS sync endpoint.") }
        try FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(self).write(to: Self.file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.file.path)
    }
}
enum SyncCredential {
    static let service = "local.flodo-open.sync"
    static func save(_ token: String, endpoint: String) throws {
        guard token.count >= 32 else { throw FlowError.invalid("Sync token is too short.") }
        let key: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service, kSecAttrAccount as String:endpoint]
        let data = Data(token.utf8)
        var status = SecItemUpdate(key as CFDictionary, [kSecValueData as String:data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = key; item[kSecValueData as String] = data; item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw FlowError.invalid("Could not save sync credential to Keychain (\(status)).") }
    }
    static func read(endpoint: String, allowInteraction: Bool = false) throws -> String {
        var key: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service, kSecAttrAccount as String:endpoint, kSecReturnData as String:true, kSecMatchLimit as String:kSecMatchLimitOne]
        if !allowInteraction {
            let context = LAContext(); context.interactionNotAllowed = true
            key[kSecUseAuthenticationContext as String] = context
            // Also covers access-control prompts from the macOS login keychain.
            key[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(key as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let token = String(data: data, encoding: .utf8) else { throw SyncCredentialError(status: status) }
        return token
    }
}
struct SyncCredentialError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? {
        "Sync paused: Keychain access is needed. Open Settings → Telegram sync and click Connect once. Local changes are kept."
    }
}

/// One read per endpoint per session; background retries never show authentication UI.
final class SyncCredentialSession {
    typealias Reader = (String, Bool) throws -> String
    private let reader: Reader
    private var cached: [String: Result<String, Error>] = [:]
    init(reader: @escaping Reader = { try SyncCredential.read(endpoint: $0, allowInteraction: $1) }) { self.reader = reader }
    func token(endpoint: String) throws -> String {
        if let result = cached[endpoint] { return try result.get() }
        let result = Result { try reader(endpoint, false) }
        cached[endpoint] = result
        return try result.get()
    }
    func authorize(endpoint: String) throws {
        // Explicit Connect is the only path that may show the system prompt.
        let result = Result { try reader(endpoint, true) }
        cached[endpoint] = result
        _ = try result.get()
    }
    func remember(_ token: String, endpoint: String) { cached[endpoint] = .success(token) }
}
private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
@MainActor final class SyncController: ObservableObject {
    @Published var status = "Sync is off"
    @Published var enabled = false
    @Published var endpoint = ""
    @Published var lastSync: Date?
    @Published var conflictCount = 0
    private weak var store: Store?
    private var loop: Task<Void, Never>?
    private var running = false
    private let credentials = SyncCredentialSession()
    private let redirectGuard = NoRedirect()
    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.ephemeral; c.timeoutIntervalForRequest = 25; c.timeoutIntervalForResource = 40
        return URLSession(configuration: c, delegate: redirectGuard, delegateQueue: nil)
    }()
    init(store: Store) { self.store = store; if let c = SyncConfiguration.read() { endpoint = c.endpoint; enabled = c.enabled }; start() }
    func start() {
        loop?.cancel(); loop = nil
        guard enabled else { status = "Sync is off"; return }
        loop = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                guard let self else { return }
                do { try await self.syncOnce(); failures = 0 }
                catch let error as SyncCredentialError { self.status = error.localizedDescription; return }
                catch { if Task.isCancelled { return }; self.status = error.localizedDescription; failures += 1 }
                try? await Task.sleep(for: .seconds(failures == 0 ? 4 : min(60, 4 * pow(2, Double(min(failures,4))))))
            }
        }
    }
    func configure(endpoint: String, token: String) throws {
        let clean = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        try SyncConfiguration(endpoint: clean, enabled: false).save()
        if !token.isEmpty {
            try SyncCredential.save(token, endpoint: clean)
            credentials.remember(token, endpoint: clean)
        } else {
            try credentials.authorize(endpoint: clean)
        }
        try SyncConfiguration(endpoint: clean, enabled: true).save()
        self.endpoint = clean; enabled = true; start()
    }
    func setEnabled(_ value: Bool) throws { try SyncConfiguration(endpoint: endpoint, enabled: value).save(); enabled = value; start() }
    func syncNow() { Task { do { try await syncOnce() } catch { status = error.localizedDescription } } }
    func syncOnce() async throws {
        guard enabled, !running, let store else { return }
        running = true; defer { running = false }
        guard let url = URL(string: endpoint), url.scheme == "https" else { throw FlowError.invalid("Sync requires HTTPS.") }
        let token = try credentials.token(endpoint: endpoint)
        let digest = SHA256.hash(data: Data(endpoint.utf8)).map { String(format: "%02x", $0) }.joined()
        let stateURL = store.repository.directory.appendingPathComponent("sync-state-\(digest.prefix(16)).json")
        let state: SyncState
        if FileManager.default.fileExists(atPath: stateURL.path) { state = try JSONDecoder().decode(SyncState.self, from: Data(contentsOf: stateURL)) }
        else { state = SyncState() }
        let board = try store.repository.read()
        let ops = try BoardSync.operations(board: board, state: state)
        struct Request: Encodable { let epoch: String?; let revision: Int; let operations: [SyncOperation] }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Request(epoch: state.epoch, revision: state.records.values.map(\.version).max() ?? 0, operations: ops))
        status = "Syncing…"
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw FlowError.invalid(code == 401 ? "Sync authentication failed. Check the token." : "Sync unavailable (HTTP \(code)). Local changes are kept for retry.")
        }
        let remote = try JSONDecoder().decode(SyncSnapshot.self, from: data)
        if let epoch = state.epoch, epoch != remote.epoch { throw FlowError.invalid("Server identity changed; local tasks are safe. Check the server backup before reconnecting.") }
        if remote.unchanged == true { lastSync = Date(); status = "Up to date"; return }
        guard Set(remote.records.map(\.key)).count == remote.records.count else { throw FlowError.invalid("Invalid duplicate records from sync server.") }
        var conflicts: [SyncConflict] = []
        let merged = try store.repository.transaction { current in
            conflicts = try BoardSync.merge(board: &current, base: state, remote: remote)
            if !conflicts.isEmpty {
                let directory = store.repository.directory.appendingPathComponent("Sync Conflicts")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try JSONEncoder().encode(conflicts).write(to: directory.appendingPathComponent("\(UUID()).json"), options: .atomic)
            }
            current.reconcile()
        }
        var next = SyncState(); next.epoch = remote.epoch; next.records = Dictionary(uniqueKeysWithValues: remote.records.map { ($0.key,$0) })
        try JSONEncoder().encode(next).write(to: stateURL, options: .atomic)
        if store.board != merged { store.board = merged; store.scheduleReminders() }
        conflictCount += conflicts.count; lastSync = Date()
        status = conflicts.isEmpty ? "Up to date" : "\(conflicts.count) conflict copies saved"
    }
    func showConflicts() {
        guard let store else { return }
        let directory = store.repository.directory.appendingPathComponent("Sync Conflicts")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }
}

struct SyncSettingsView: View {
    @ObservedObject var sync: SyncController
    @State private var endpoint = ""
    @State private var token = ""
    @State private var error: String?
    var body: some View {
        Form {
            Section("Telegram sync") {
                TextField("HTTPS endpoint", text: $endpoint)
                SecureField("Sync token", text: $token)
                HStack {
                    Button("Connect") { do { try sync.configure(endpoint: endpoint, token: token); token = ""; error = nil } catch { self.error = error.localizedDescription } }
                    Button(sync.enabled ? "Pause" : "Resume") { do { try sync.setEnabled(!sync.enabled) } catch { self.error = error.localizedDescription } }.disabled(sync.endpoint.isEmpty)
                    Button("Sync now") { sync.syncNow() }.disabled(!sync.enabled)
                }
                Text(sync.status).foregroundStyle(.secondary)
                if let date = sync.lastSync { Text("Last sync: \(date.formatted(date: .omitted, time: .standard))").font(.caption) }
                if let error { Text(error).foregroundStyle(.red).font(.caption) }
            }
            Section("Conflicts") {
                Text("Separate field changes merge automatically. Both versions of conflicting edits are saved locally. Deletions take precedence; edited content remains in a conflict copy.").font(.caption).foregroundStyle(.secondary)
                Button("Show conflict copies") { sync.showConflicts() }
            }
        }.formStyle(.grouped).onAppear { endpoint = sync.endpoint }
    }
}
