import Foundation

/// Loads Codex CLI usage data from local snapshot JSON and maps it to `CodexUsage`.
final class CodexUsageSnapshotService {
    static let shared = CodexUsageSnapshotService()

    private let snapshotURL: URL
    private let iso8601: ISO8601DateFormatter

    init(snapshotURL: URL? = nil) {
        self.snapshotURL = snapshotURL
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex/usage_tracker/latest_snapshot.json")

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.iso8601 = formatter
    }

    var hasSnapshot: Bool {
        FileManager.default.fileExists(atPath: snapshotURL.path)
    }

    func loadUsageIfAvailable() -> CodexUsage? {
        guard hasSnapshot else { return nil }

        do {
            return try loadUsage()
        } catch {
            LoggingService.shared.logError("Codex snapshot parse failed", error: error)
            return nil
        }
    }

    func loadUsage() throws -> CodexUsage {
        let data = try Data(contentsOf: snapshotURL)
        let decoder = JSONDecoder()
        let snapshot = try decoder.decode(CodexUsageSnapshot.self, from: data)

        let now = Date()

        let sessionWindow = snapshot.sessionWindow
        let weeklyWindow = snapshot.weeklyWindow

        let sessionTokens = sessionWindow?.usage?.totalTokens
            ?? snapshot.windows?.last5h?.totalTokens
            ?? 0

        let weeklyTokens = weeklyWindow?.usage?.totalTokens
            ?? snapshot.windows?.last7d?.totalTokens
            ?? 0

        let sessionUsedPercent = normalizePercent(
            sessionWindow?.usedPercent
                ?? snapshot.rateLimits?.primary?.usedPercent
                ?? percentFromLimit(usedTokens: sessionTokens, limit: snapshot.config?.sessionLimitTokens)
        )

        let weeklyUsedPercent = normalizePercent(
            weeklyWindow?.usedPercent
                ?? snapshot.rateLimits?.secondary?.usedPercent
                ?? percentFromLimit(usedTokens: weeklyTokens, limit: snapshot.config?.weekLimitTokens)
        )

        let sessionResetTime = parseResetTime(
            isoString: sessionWindow?.resetsAt ?? snapshot.rateLimits?.primary?.resetsAt,
            epoch: sessionWindow?.resetsAtEpoch ?? snapshot.rateLimits?.primary?.resetsAtEpoch,
            fallbackMinutes: sessionWindow?.windowMinutes
                ?? snapshot.config?.sessionWindowMinutes
                ?? 300,
            now: now
        )

        let weeklyResetTime = parseResetTime(
            isoString: weeklyWindow?.resetsAt ?? snapshot.rateLimits?.secondary?.resetsAt,
            epoch: weeklyWindow?.resetsAtEpoch ?? snapshot.rateLimits?.secondary?.resetsAtEpoch,
            fallbackMinutes: weeklyWindow?.windowMinutes
                ?? snapshot.config?.weekWindowMinutes
                ?? 10080,
            now: now
        )

        let sessionLimit = snapshot.config?.sessionLimitTokens
            ?? deriveLimit(usedTokens: sessionTokens, usedPercent: sessionUsedPercent)

        let weeklyLimit = snapshot.config?.weekLimitTokens
            ?? deriveLimit(usedTokens: weeklyTokens, usedPercent: weeklyUsedPercent)

        return CodexUsage(
            sessionTokensUsed: sessionTokens,
            sessionLimit: max(0, sessionLimit),
            sessionPercentage: sessionUsedPercent,
            sessionResetTime: sessionResetTime,
            weeklyTokensUsed: weeklyTokens,
            weeklyLimit: max(weeklyLimit, 1),
            weeklyPercentage: weeklyUsedPercent,
            weeklyResetTime: weeklyResetTime,
            opusWeeklyTokensUsed: 0,
            opusWeeklyPercentage: 0,
            sonnetWeeklyTokensUsed: 0,
            sonnetWeeklyPercentage: 0,
            sonnetWeeklyResetTime: nil,
            costUsed: nil,
            costLimit: nil,
            costCurrency: nil,
            lastUpdated: snapshot.generatedAt.flatMap(parseISO8601) ?? now,
            userTimezone: parseTimeZone(snapshot.timezone)
        )
    }

    private func parseResetTime(
        isoString: String?,
        epoch: Int?,
        fallbackMinutes: Int,
        now: Date
    ) -> Date {
        if let isoString, let parsed = parseISO8601(isoString) {
            return parsed
        }

        if let epoch {
            return Date(timeIntervalSince1970: TimeInterval(epoch))
        }

        return now.addingTimeInterval(TimeInterval(max(1, fallbackMinutes) * 60))
    }

    private func parseISO8601(_ value: String) -> Date? {
        if let date = iso8601.date(from: value) {
            return date
        }

        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: value)
    }

    private func parseTimeZone(_ value: String?) -> TimeZone {
        guard let value, !value.isEmpty else { return .current }

        if let zone = TimeZone(identifier: value) {
            return zone
        }

        if let zone = TimeZone(abbreviation: value) {
            return zone
        }

        return .current
    }

    private func percentFromLimit(usedTokens: Int, limit: Int?) -> Double? {
        guard let limit, limit > 0 else { return nil }
        return (Double(usedTokens) / Double(limit)) * 100.0
    }

    private func deriveLimit(usedTokens: Int, usedPercent: Double) -> Int {
        guard usedPercent > 0 else { return usedTokens }
        let limit = (Double(usedTokens) * 100.0) / usedPercent
        return max(Int(limit.rounded()), usedTokens)
    }

    private func normalizePercent(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 0 }
        return min(max(value, 0), 100)
    }
}

// MARK: - Snapshot DTO

private struct CodexUsageSnapshot: Decodable {
    let generatedAt: String?
    let timezone: String?
    let windows: WindowsSnapshot?
    let sessionWindow: UsageWindowSnapshot?
    let weeklyWindow: UsageWindowSnapshot?
    let rateLimits: RateLimitsSnapshot?
    let config: CodexTrackerConfig?

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case timezone
        case windows
        case sessionWindow = "session_window"
        case weeklyWindow = "weekly_window"
        case rateLimits = "rate_limits"
        case config
    }
}

private struct WindowsSnapshot: Decodable {
    let last5h: TokenUsageSnapshot?
    let last7d: TokenUsageSnapshot?

    enum CodingKeys: String, CodingKey {
        case last5h = "last_5h"
        case last7d = "last_7d"
    }
}

private struct UsageWindowSnapshot: Decodable {
    let windowMinutes: Int?
    let usage: TokenUsageSnapshot?
    let usedPercent: Double?
    let resetsAt: String?
    let resetsAtEpoch: Int?

    enum CodingKeys: String, CodingKey {
        case windowMinutes = "window_minutes"
        case usage
        case usedPercent = "used_percent"
        case resetsAt = "resets_at"
        case resetsAtEpoch = "resets_at_epoch"
    }
}

private struct TokenUsageSnapshot: Decodable {
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case totalTokens = "total_tokens"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalTokens = try container.decodeIfPresent(Int.self, forKey: .totalTokens) ?? 0
    }
}

private struct RateLimitsSnapshot: Decodable {
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
}

private struct RateLimitWindow: Decodable {
    let usedPercent: Double?
    let resetsAt: String?
    let resetsAtEpoch: Int?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case resetsAt = "resets_at"
        case resetsAtEpoch = "resets_at_epoch"
    }
}

private struct CodexTrackerConfig: Decodable {
    let sessionLimitTokens: Int?
    let weekLimitTokens: Int?
    let sessionWindowMinutes: Int?
    let weekWindowMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case sessionLimitTokens = "session_limit_tokens"
        case weekLimitTokens = "week_limit_tokens"
        case sessionWindowMinutes = "session_window_minutes"
        case weekWindowMinutes = "week_window_minutes"
    }
}
