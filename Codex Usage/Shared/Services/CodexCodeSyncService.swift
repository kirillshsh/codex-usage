//
//  CodexCodeSyncService.swift
//  Codex Usage
//
//  Created by Codex Code on 2026-01-07.
//

import Foundation
import Security
import Combine

struct CodexCLIAccount: Codable, Identifiable, Equatable {
    let id: UUID
    var email: String
    var accountId: String?
    var authJSON: String
    var addedAt: Date
    var lastUsedAt: Date

    init(
        id: UUID = UUID(),
        email: String,
        accountId: String? = nil,
        authJSON: String,
        addedAt: Date = Date(),
        lastUsedAt: Date = Date()
    ) {
        self.id = id
        self.email = email
        self.accountId = accountId
        self.authJSON = authJSON
        self.addedAt = addedAt
        self.lastUsedAt = lastUsedAt
    }
}

private struct CodexCLIAccountStore: Codable {
    var accounts: [CodexCLIAccount]
}

/// Manages synchronization of Codex CLI credentials between ~/.codex/auth.json and app profiles.
class CodexCodeSyncService: ObservableObject {
    static let shared = CodexCodeSyncService()

    @Published private(set) var savedAccounts: [CodexCLIAccount] = []
    @Published private(set) var activeAccountEmail: String?

    private var codexAuthFileURL: URL {
        Constants.CodexPaths.codexDirectory.appendingPathComponent("auth.json")
    }

    private var savedAccountsURL: URL {
        Constants.CodexPaths.codexDirectory
            .appendingPathComponent("usage_tracker")
            .appendingPathComponent("codex_cli_accounts.json")
    }

    private init() {
        refreshSavedAccounts()
    }

    // MARK: - Codex Auth File Access

    /// Reads Codex CLI credentials from ~/.codex/auth.json.
    func readSystemCredentials() throws -> String? {
        guard FileManager.default.fileExists(atPath: codexAuthFileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: codexAuthFileURL)
            guard let jsonString = String(data: data, encoding: .utf8) else {
                throw CodexCodeError.invalidJSON
            }
            _ = try parseJSONObject(from: jsonString)
            return jsonString
        } catch {
            LoggingService.shared.log("Failed to read Codex auth file: \(error.localizedDescription)")
            throw CodexCodeError.keychainReadFailed(status: OSStatus(-1))
        }
    }

    /// Writes Codex CLI credentials to ~/.codex/auth.json.
    func writeSystemCredentials(_ jsonData: String) throws {
        _ = try parseJSONObject(from: jsonData)

        do {
            try FileManager.default.createDirectory(
                at: codexAuthFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            try jsonData.write(to: codexAuthFileURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: codexAuthFileURL.path
            )

            LoggingService.shared.log("✅ Updated ~/.codex/auth.json")
        } catch {
            LoggingService.shared.log("❌ Failed to write Codex auth file: \(error.localizedDescription)")
            throw CodexCodeError.keychainWriteFailed(status: OSStatus(-1))
        }
    }

    // MARK: - Saved Accounts Store

    func refreshSavedAccounts() {
        do {
            var accounts = try loadSavedAccountsFromDisk()

            if let currentAuthJSON = try readSystemCredentials() {
                let email = extractEmail(from: currentAuthJSON) ?? "unknown@codex.local"
                let accountId = extractAccountId(from: currentAuthJSON)
                let now = Date()

                if let index = findAccountIndex(in: accounts, email: email, accountId: accountId) {
                    accounts[index].authJSON = currentAuthJSON
                    accounts[index].lastUsedAt = now
                    if accounts[index].accountId == nil {
                        accounts[index].accountId = accountId
                    }
                } else {
                    accounts.append(
                        CodexCLIAccount(
                            email: email,
                            accountId: accountId,
                            authJSON: currentAuthJSON,
                            addedAt: now,
                            lastUsedAt: now
                        )
                    )
                }

                activeAccountEmail = email
            } else {
                activeAccountEmail = nil
            }

            try saveSavedAccountsToDisk(accounts)
            savedAccounts = accounts.sorted(by: { $0.lastUsedAt > $1.lastUsedAt })
        } catch {
            LoggingService.shared.logError("Failed to refresh saved Codex CLI accounts", error: error)
            savedAccounts = []
            activeAccountEmail = nil
        }
    }

    @discardableResult
    func importCurrentAccount() throws -> CodexCLIAccount {
        guard let currentAuthJSON = try readSystemCredentials() else {
            throw CodexCodeError.noCredentialsFound
        }

        let email = extractEmail(from: currentAuthJSON) ?? "unknown@codex.local"
        let accountId = extractAccountId(from: currentAuthJSON)
        let now = Date()

        var accounts = try loadSavedAccountsFromDisk()

        let account: CodexCLIAccount
        if let index = findAccountIndex(in: accounts, email: email, accountId: accountId) {
            accounts[index].authJSON = currentAuthJSON
            accounts[index].lastUsedAt = now
            if accounts[index].accountId == nil {
                accounts[index].accountId = accountId
            }
            account = accounts[index]
        } else {
            let created = CodexCLIAccount(
                email: email,
                accountId: accountId,
                authJSON: currentAuthJSON,
                addedAt: now,
                lastUsedAt: now
            )
            accounts.append(created)
            account = created
        }

        try saveSavedAccountsToDisk(accounts)
        savedAccounts = accounts.sorted(by: { $0.lastUsedAt > $1.lastUsedAt })
        activeAccountEmail = email

        LoggingService.shared.log("Imported current Codex CLI account: \(email)")
        return account
    }

    @discardableResult
    func switchToAccount(_ accountId: UUID) throws -> CodexCLIAccount {
        var accounts = try loadSavedAccountsFromDisk()

        guard let index = accounts.firstIndex(where: { $0.id == accountId }) else {
            throw CodexCodeError.accountNotFound
        }

        var selected = accounts[index]
        try writeSystemCredentials(selected.authJSON)

        selected.lastUsedAt = Date()
        accounts[index] = selected

        try saveSavedAccountsToDisk(accounts)
        savedAccounts = accounts.sorted(by: { $0.lastUsedAt > $1.lastUsedAt })
        activeAccountEmail = selected.email

        LoggingService.shared.log("Switched Codex CLI account to: \(selected.email)")
        return selected
    }

    func launchCodexLoginInTerminal() throws {
        let script = """
        tell application "Terminal"
            activate
            do script "codex login"
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-"]

        let inputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardError = errorPipe

        try process.run()

        if let scriptData = script.data(using: .utf8) {
            inputPipe.fileHandleForWriting.write(scriptData)
        }
        inputPipe.fileHandleForWriting.closeFile()

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(data: errorData, encoding: .utf8) ?? "Unknown osascript error"
            LoggingService.shared.log("Failed to launch Terminal login flow: \(errorText)")
            throw CodexCodeError.keychainWriteFailed(status: process.terminationStatus)
        }

        LoggingService.shared.log("Launched codex login in Terminal")
    }

    // MARK: - Profile Sync Operations

    /// Syncs credentials from system to profile (one-time copy).
    func syncToProfile(_ profileId: UUID) throws {
        guard let jsonData = try readSystemCredentials() else {
            throw CodexCodeError.noCredentialsFound
        }

        // Save to profile directly
        var profiles = ProfileStore.shared.loadProfiles()
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else {
            throw CodexCodeError.noProfileCredentials
        }

        profiles[index].cliCredentialsJSON = jsonData
        profiles[index].hasCliAccount = true
        profiles[index].cliAccountSyncedAt = Date()

        if let email = extractEmail(from: jsonData) {
            profiles[index].name = email
        }

        ProfileStore.shared.saveProfiles(profiles)

        LoggingService.shared.log("Synced CLI credentials to profile: \(profileId)")
    }

    /// Applies profile's CLI credentials to system (overwrites current login).
    func applyProfileCredentials(_ profileId: UUID) throws {
        LoggingService.shared.log("🔄 Applying CLI credentials for profile: \(profileId)")

        let profiles = ProfileStore.shared.loadProfiles()
        guard let profile = profiles.first(where: { $0.id == profileId }),
              let jsonData = profile.cliCredentialsJSON else {
            LoggingService.shared.log("❌ No CLI credentials found for profile: \(profileId)")
            throw CodexCodeError.noProfileCredentials
        }

        try writeSystemCredentials(jsonData)
        _ = try? importCurrentAccount()

        LoggingService.shared.log("✅ Applied profile CLI credentials to system: \(profileId)")
    }

    /// Removes CLI credentials from profile (doesn't affect system).
    func removeFromProfile(_ profileId: UUID) throws {
        var profiles = ProfileStore.shared.loadProfiles()
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else {
            throw CodexCodeError.noProfileCredentials
        }

        profiles[index].cliCredentialsJSON = nil
        profiles[index].hasCliAccount = false
        profiles[index].cliAccountSyncedAt = nil
        ProfileStore.shared.saveProfiles(profiles)

        LoggingService.shared.log("Removed CLI credentials from profile: \(profileId)")
    }

    // MARK: - Access Token Extraction

    func extractAccessToken(from jsonData: String) -> String? {
        guard let json = try? parseJSONObject(from: jsonData) else {
            return nil
        }

        if let tokens = json["tokens"] as? [String: Any],
           let token = tokens["access_token"] as? String {
            return token
        }

        if let oauth = json["codexAiOauth"] as? [String: Any],
           let token = oauth["accessToken"] as? String {
            return token
        }

        return nil
    }

    func extractSubscriptionInfo(from jsonData: String) -> (type: String, scopes: [String])? {
        guard let json = try? parseJSONObject(from: jsonData) else {
            return nil
        }

        // Legacy format
        if let oauth = json["codexAiOauth"] as? [String: Any] {
            let subType = oauth["subscriptionType"] as? String ?? "unknown"
            let scopes = oauth["scopes"] as? [String] ?? []
            return (subType, scopes)
        }

        // Current Codex auth.json JWT claims
        guard let accessToken = extractAccessToken(from: jsonData),
              let claims = decodeJWTClaims(from: accessToken) else {
            return nil
        }

        let scopes = claims["scp"] as? [String] ?? []

        if let authData = claims["https://api.openai.com/auth"] as? [String: Any],
           let planType = authData["chatgpt_plan_type"] as? String {
            return (planType, scopes)
        }

        return ("unknown", scopes)
    }

    /// Extracts the token expiry date from CLI credentials JSON.
    func extractTokenExpiry(from jsonData: String) -> Date? {
        // Legacy format
        if let json = try? parseJSONObject(from: jsonData),
           let oauth = json["codexAiOauth"] as? [String: Any],
           let expiresAt = oauth["expiresAt"] as? TimeInterval {
            return Date(timeIntervalSince1970: expiresAt)
        }

        // Current JWT format
        guard let accessToken = extractAccessToken(from: jsonData),
              let claims = decodeJWTClaims(from: accessToken) else {
            return nil
        }

        if let expDouble = claims["exp"] as? TimeInterval {
            return Date(timeIntervalSince1970: expDouble)
        }

        if let expInt = claims["exp"] as? Int {
            return Date(timeIntervalSince1970: TimeInterval(expInt))
        }

        return nil
    }

    /// Checks if the OAuth token in the credentials JSON is expired.
    func isTokenExpired(_ jsonData: String) -> Bool {
        guard let expiryDate = extractTokenExpiry(from: jsonData) else {
            // No expiry info = assume valid
            return false
        }
        return Date() > expiryDate
    }

    /// Attempts to extract account email from credentials JSON.
    func extractEmail(from jsonData: String) -> String? {
        guard let json = try? parseJSONObject(from: jsonData) else {
            return nil
        }

        if let email = json["email"] as? String,
           !email.isEmpty {
            return email
        }

        if let tokens = json["tokens"] as? [String: Any],
           let idToken = tokens["id_token"] as? String,
           let claims = decodeJWTClaims(from: idToken),
           let email = claims["email"] as? String,
           !email.isEmpty {
            return email
        }

        if let accessToken = extractAccessToken(from: jsonData),
           let claims = decodeJWTClaims(from: accessToken),
           let profile = claims["https://api.openai.com/profile"] as? [String: Any],
           let email = profile["email"] as? String,
           !email.isEmpty {
            return email
        }

        return nil
    }

    func extractAccountId(from jsonData: String) -> String? {
        guard let json = try? parseJSONObject(from: jsonData) else {
            return nil
        }

        if let tokens = json["tokens"] as? [String: Any],
           let accountId = tokens["account_id"] as? String,
           !accountId.isEmpty {
            return accountId
        }

        return nil
    }

    // MARK: - Auto Re-sync Before Switching

    /// Re-syncs credentials from current Codex auth file before profile switching.
    /// This ensures we always have the latest CLI login when switching profiles.
    func resyncBeforeSwitching(for profileId: UUID) throws {
        LoggingService.shared.log("Re-syncing CLI credentials before profile switch: \(profileId)")

        // Read fresh credentials from system (if user is logged in)
        guard let freshJSON = try readSystemCredentials() else {
            // No credentials in system - user not logged into CLI anymore
            LoggingService.shared.log("No system credentials found - skipping re-sync")
            return
        }

        // Update profile's stored credentials with fresh ones
        var profiles = ProfileStore.shared.loadProfiles()
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else {
            return
        }

        profiles[index].cliCredentialsJSON = freshJSON
        profiles[index].hasCliAccount = true
        profiles[index].cliAccountSyncedAt = Date()  // Update sync timestamp

        if let email = extractEmail(from: freshJSON) {
            profiles[index].name = email
        }

        ProfileStore.shared.saveProfiles(profiles)

        _ = try? importCurrentAccount()

        LoggingService.shared.log("✓ Re-synced CLI credentials from auth file and updated timestamp")
    }

    // MARK: - Private Helpers

    private func parseJSONObject(from jsonData: String) throws -> [String: Any] {
        guard let data = jsonData.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexCodeError.invalidJSON
        }
        return json
    }

    private func loadSavedAccountsFromDisk() throws -> [CodexCLIAccount] {
        guard FileManager.default.fileExists(atPath: savedAccountsURL.path) else {
            return []
        }

        let data = try Data(contentsOf: savedAccountsURL)
        let decoded = try JSONDecoder().decode(CodexCLIAccountStore.self, from: data)
        return decoded.accounts
    }

    private func saveSavedAccountsToDisk(_ accounts: [CodexCLIAccount]) throws {
        try FileManager.default.createDirectory(
            at: savedAccountsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let payload = CodexCLIAccountStore(accounts: accounts)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        try data.write(to: savedAccountsURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: savedAccountsURL.path
        )
    }

    private func findAccountIndex(
        in accounts: [CodexCLIAccount],
        email: String,
        accountId: String?
    ) -> Int? {
        if let accountId,
           let idx = accounts.firstIndex(where: { $0.accountId == accountId }) {
            return idx
        }

        return accounts.firstIndex {
            $0.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ==
            email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

    private func decodeJWTClaims(from token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = payload.count % 4
        if remainder != 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return object
    }
}

// MARK: - CodexCodeError

enum CodexCodeError: LocalizedError {
    case noCredentialsFound
    case invalidJSON
    case keychainReadFailed(status: OSStatus)
    case keychainWriteFailed(status: OSStatus)
    case noProfileCredentials
    case accountNotFound

    var errorDescription: String? {
        switch self {
        case .noCredentialsFound:
            return "No Codex CLI credentials found in ~/.codex/auth.json. Please run codex login first."
        case .invalidJSON:
            return "Codex CLI credentials are corrupted or invalid JSON."
        case .keychainReadFailed(let status):
            return "Failed to read credentials from Codex auth storage (status: \(status))."
        case .keychainWriteFailed(let status):
            return "Failed to write credentials to Codex auth storage (status: \(status))."
        case .noProfileCredentials:
            return "This profile has no synced CLI account."
        case .accountNotFound:
            return "Selected account was not found in saved Codex CLI accounts."
        }
    }
}
