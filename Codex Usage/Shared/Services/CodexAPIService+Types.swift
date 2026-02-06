import Foundation

// MARK: - API Response Types

extension CodexAPIService {
    struct UsageResponse: Codable {
        let usage: [UsagePeriod]

        struct UsagePeriod: Codable {
            let period: String
            let usageType: String
            let inputTokens: Int
            let outputTokens: Int
            let cacheCreationTokens: Int?
            let cacheReadTokens: Int?

            enum CodingKeys: String, CodingKey {
                case period
                case usageType = "usage_type"
                case inputTokens = "input_tokens"
                case outputTokens = "output_tokens"
                case cacheCreationTokens = "cache_creation_tokens"
                case cacheReadTokens = "cache_read_tokens"
            }
        }
    }

    struct WHAMUsageResponse: Codable {
        let accountId: String?
        let email: String?
        let rateLimit: WHAMRateLimit?

        enum CodingKeys: String, CodingKey {
            case accountId = "account_id"
            case email
            case rateLimit = "rate_limit"
        }
    }

    struct WHAMRateLimit: Codable {
        let allowed: Bool?
        let limitReached: Bool?
        let primaryWindow: WHAMRateLimitWindow?
        let secondaryWindow: WHAMRateLimitWindow?

        enum CodingKeys: String, CodingKey {
            case allowed
            case limitReached = "limit_reached"
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    struct WHAMRateLimitWindow: Codable {
        let usedPercent: Double?
        let limitWindowSeconds: Int?
        let resetAfterSeconds: Int?
        let resetAt: Int?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case limitWindowSeconds = "limit_window_seconds"
            case resetAfterSeconds = "reset_after_seconds"
            case resetAt = "reset_at"
        }
    }

    struct AccountInfo: Codable {
        let uuid: String
        let name: String
        let capabilities: [String]
    }

    struct OverageSpendLimitResponse: Codable {
        let monthlyCreditLimit: Double?
        let currency: String?
        let usedCredits: Double?
        let isEnabled: Bool?

        enum CodingKeys: String, CodingKey {
            case monthlyCreditLimit = "monthly_credit_limit"
            case currency
            case usedCredits = "used_credits"
            case isEnabled = "is_enabled"
        }
    }

    struct CurrentSpendResponse: Codable {
        let amount: Int
        let resetsAt: String

        enum CodingKeys: String, CodingKey {
            case amount
            case resetsAt = "resets_at"
        }
    }

    struct PrepaidCreditsResponse: Codable {
        let amount: Int
        let currency: String
        let autoReloadSettings: AutoReloadSettings?

        enum CodingKeys: String, CodingKey {
            case amount
            case currency
            case autoReloadSettings = "auto_reload_settings"
        }

        struct AutoReloadSettings: Codable {
            let enabled: Bool?
            let threshold: Int?
            let reloadAmount: Int?
        }
    }

    struct ConsoleOrganization: Codable {
        let id: Int
        let uuid: String
        let name: String
    }

    enum APIError: Error, LocalizedError {
        case noSessionKey
        case invalidSessionKey
        case networkError(Error)
        case invalidResponse
        case unauthorized
        case serverError(statusCode: Int)

        var errorDescription: String? {
            switch self {
            case .noSessionKey:
                return "No session key found. Please configure your Codex session key."
            case .invalidSessionKey:
                return "Invalid session key format."
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .invalidResponse:
                return "Invalid response from Codex API."
            case .unauthorized:
                return "Unauthorized. Your session key may have expired."
            case .serverError(let code):
                return "Server error: HTTP \(code)"
            }
        }
    }
}
