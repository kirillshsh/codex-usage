//
//  Profile.swift
//  Codex Usage
//
//  Created by Codex Code on 2026-01-07.
//

import Foundation

/// Represents a complete isolated profile with all credentials and settings
struct Profile: Codable, Identifiable, Equatable {
    // MARK: - Identity
    let id: UUID
    var name: String

    // MARK: - Credentials (stored directly in profile)
    var codexSessionKey: String?
    var organizationId: String?
    var apiSessionKey: String?
    var apiOrganizationId: String?
    var cliCredentialsJSON: String?

    // MARK: - CLI Account Sync Metadata
    var hasCliAccount: Bool
    var cliAccountSyncedAt: Date?

    // MARK: - Usage Data (Per-Profile)
    var codexUsage: CodexUsage?
    var apiUsage: APIUsage?

    // MARK: - Appearance Settings (Per-Profile)
    var iconConfig: MenuBarIconConfiguration

    // MARK: - Behavior Settings (Per-Profile)
    var refreshInterval: TimeInterval
    var autoStartSessionEnabled: Bool
    var checkOverageLimitEnabled: Bool

    // MARK: - Notification Settings (Per-Profile)
    var notificationSettings: NotificationSettings

    // MARK: - Display Configuration
    var isSelectedForDisplay: Bool  // For multi-profile menu bar mode

    // MARK: - Metadata
    var createdAt: Date
    var lastUsedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        codexSessionKey: String? = nil,
        organizationId: String? = nil,
        apiSessionKey: String? = nil,
        apiOrganizationId: String? = nil,
        cliCredentialsJSON: String? = nil,
        hasCliAccount: Bool = false,
        cliAccountSyncedAt: Date? = nil,
        codexUsage: CodexUsage? = nil,
        apiUsage: APIUsage? = nil,
        iconConfig: MenuBarIconConfiguration = .default,
        refreshInterval: TimeInterval = 30.0,
        autoStartSessionEnabled: Bool = false,
        checkOverageLimitEnabled: Bool = true,
        notificationSettings: NotificationSettings = NotificationSettings(),
        isSelectedForDisplay: Bool = true,
        createdAt: Date = Date(),
        lastUsedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.codexSessionKey = codexSessionKey
        self.organizationId = organizationId
        self.apiSessionKey = apiSessionKey
        self.apiOrganizationId = apiOrganizationId
        self.cliCredentialsJSON = cliCredentialsJSON
        self.hasCliAccount = hasCliAccount
        self.cliAccountSyncedAt = cliAccountSyncedAt
        self.codexUsage = codexUsage
        self.apiUsage = apiUsage
        self.iconConfig = iconConfig
        self.refreshInterval = refreshInterval
        self.autoStartSessionEnabled = autoStartSessionEnabled
        self.checkOverageLimitEnabled = checkOverageLimitEnabled
        self.notificationSettings = notificationSettings
        self.isSelectedForDisplay = isSelectedForDisplay
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }

    // MARK: - Computed Properties
    var hasCodexAI: Bool {
        codexSessionKey != nil && organizationId != nil
    }

    var hasAPIConsole: Bool {
        apiSessionKey != nil && apiOrganizationId != nil
    }

    /// True if local Codex usage snapshot exists.
    var hasCodexSnapshot: Bool {
        let snapshotPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/usage_tracker/latest_snapshot.json")
            .path
        return FileManager.default.fileExists(atPath: snapshotPath)
    }

    /// True if local Codex usage snapshot is available.
    var hasUsageCredentials: Bool {
        hasCodexSnapshot
    }

    /// True if profile has CLI OAuth credentials that are not expired
    var hasValidCLIOAuth: Bool {
        guard let cliJSON = cliCredentialsJSON else { return false }
        // Check if not expired
        return !CodexCodeSyncService.shared.isTokenExpired(cliJSON)
    }

    /// True if system Keychain has valid CLI OAuth credentials (fallback)
    var hasValidSystemCLIOAuth: Bool {
        guard let systemCredentials = try? CodexCodeSyncService.shared.readSystemCredentials() else {
            return false
        }
        // Check if not expired and has valid access token
        return !CodexCodeSyncService.shared.isTokenExpired(systemCredentials) &&
               CodexCodeSyncService.shared.extractAccessToken(from: systemCredentials) != nil
    }

    var hasAnyCredentials: Bool {
        hasCodexSnapshot
    }
}

// MARK: - ProfileCredentials (for compatibility)
/// Simple struct for passing credentials around
struct ProfileCredentials {
    var codexSessionKey: String?
    var organizationId: String?
    var apiSessionKey: String?
    var apiOrganizationId: String?
    var cliCredentialsJSON: String?

    var hasCodexAI: Bool {
        codexSessionKey != nil && organizationId != nil
    }

    var hasAPIConsole: Bool {
        apiSessionKey != nil && apiOrganizationId != nil
    }

    var hasCLI: Bool {
        cliCredentialsJSON != nil
    }
}
