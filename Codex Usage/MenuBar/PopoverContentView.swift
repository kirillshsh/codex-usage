import SwiftUI

/// Smart, minimal, and professional popover interface
struct PopoverContentView: View {
    @ObservedObject var manager: MenuBarManager
    let onRefresh: () -> Void
    let onPreferences: () -> Void
    let onQuit: () -> Void

    @State private var isRefreshing = false
    @State private var showInsights = false

    private var displayUsage: CodexUsage {
        manager.usage
    }

    var body: some View {
        VStack(spacing: 0) {
            SmartHeader(
                isRefreshing: isRefreshing,
                onRefresh: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isRefreshing = true
                    }
                    onRefresh()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isRefreshing = false
                        }
                    }
                }
            )

            SmartUsageDashboard(usage: displayUsage)

            if showInsights {
                ContextualInsights(usage: displayUsage)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }

            SmartFooter(
                usage: displayUsage,
                showInsights: $showInsights,
                onPreferences: onPreferences,
                onQuit: onQuit
            )
        }
        .frame(width: 280)
        .background(.regularMaterial)
    }
}

// MARK: - Smart Header Component

struct SmartHeader: View {
    let isRefreshing: Bool
    let onRefresh: () -> Void

    @StateObject private var cliSyncService = CodexCodeSyncService.shared
    @StateObject private var profileManager = ProfileManager.shared
    @State private var accountMessage: String?
    @State private var accountMessageColor: Color = .secondary
    @State private var usagePreviews: [UUID: CodexCLIAccountUsagePreview] = [:]
    @State private var isLoadingUsagePreviews = false

    private var currentAccountLabel: String {
        if let label = cliSyncService.activeAccountDisplayName,
           !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return label
        }

        if let email = cliSyncService.activeAccountEmail,
           !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return email
        }

        return "не авторизован"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    if cliSyncService.savedAccounts.isEmpty {
                        Text("сохранённых аккаунтов пока нет")
                    } else {
                        ForEach(cliSyncService.savedAccounts) { account in
                            Button {
                                switchToAccount(account)
                            } label: {
                                AccountSwitcherRow(
                                    title: cliSyncService.displayName(for: account),
                                    isActive: account.id == cliSyncService.activeAccountId,
                                    usagePreview: usagePreviews[account.id],
                                    isLoading: isLoadingUsagePreviews
                                )
                            }
                        }
                    }

                    Divider()

                    Button("импортировать текущий аккаунт") {
                        importCurrentAccount()
                    }

                    Button("добавить через codex login…") {
                        startCodexLoginFlow()
                    }

                    Button("обновить список аккаунтов") {
                        refreshAccountsAndPreviews()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.blue)

                        Text(currentAccountLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.1))
                    )
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.plain)

                Button(action: startCodexLoginFlow) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.blue)
                        .frame(width: 24, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.blue.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)

                Button(action: onRefresh) {
                    ZStack {
                        if isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isRefreshing)
            }

            if let accountMessage {
                Text(accountMessage)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(accountMessageColor)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        )
        .onAppear {
            refreshAccountsAndPreviews()
        }
        .onChange(of: cliSyncService.savedAccounts) {
            Task {
                await loadUsagePreviews()
            }
        }
    }

    private func switchToAccount(_ account: CodexCLIAccount) {
        do {
            let selected = try cliSyncService.switchToAccount(account.id)
            profileManager.syncActiveProfileWithCLIAccount(
                email: selected.email,
                credentialsJSON: selected.authJSON
            )
            showAccountMessage("активный аккаунт: \(cliSyncService.displayName(for: selected))", color: .green)
            NotificationCenter.default.post(name: .credentialsChanged, object: nil)
            Task {
                await loadUsagePreviews()
            }
        } catch {
            showAccountMessage("не удалось переключить аккаунт: \(error.localizedDescription)", color: .red)
        }
    }

    private func importCurrentAccount() {
        do {
            let imported = try cliSyncService.importCurrentAccount()
            profileManager.syncActiveProfileWithCLIAccount(
                email: imported.email,
                credentialsJSON: imported.authJSON
            )
            showAccountMessage("аккаунт добавлен: \(cliSyncService.displayName(for: imported))", color: .green)
            NotificationCenter.default.post(name: .credentialsChanged, object: nil)
            Task {
                await loadUsagePreviews()
            }
        } catch {
            showAccountMessage("не удалось импортировать аккаунт: \(error.localizedDescription)", color: .red)
        }
    }

    private func startCodexLoginFlow() {
        do {
            try cliSyncService.launchCodexLoginInTerminal()
            showAccountMessage(
                "открыт Terminal. Выполни вход и нажми «импортировать текущий аккаунт».",
                color: .secondary
            )
        } catch {
            showAccountMessage("не удалось запустить codex login: \(error.localizedDescription)", color: .red)
        }
    }

    private func showAccountMessage(_ message: String, color: Color) {
        accountMessage = message
        accountMessageColor = color
    }

    private func refreshAccountsAndPreviews() {
        cliSyncService.refreshSavedAccounts()
        Task {
            await loadUsagePreviews()
        }
    }

    @MainActor
    private func loadUsagePreviews() async {
        let accounts = cliSyncService.savedAccounts
        guard !accounts.isEmpty else {
            usagePreviews = [:]
            isLoadingUsagePreviews = false
            return
        }

        isLoadingUsagePreviews = true

        var previews: [UUID: CodexCLIAccountUsagePreview] = [:]
        for account in accounts {
            if let preview = await cliSyncService.fetchUsagePreview(for: account) {
                previews[account.id] = preview
            }
        }

        usagePreviews = previews
        isLoadingUsagePreviews = false
    }
}

private struct AccountSwitcherRow: View {
    let title: String
    let isActive: Bool
    let usagePreview: CodexCLIAccountUsagePreview?
    let isLoading: Bool

    private var previewColor: Color {
        guard let usagePreview else {
            return .secondary.opacity(0.5)
        }

        switch usagePreview.combinedRemainingPercent {
        case 20...:
            return .green
        case 10..<20:
            return .blue
        default:
            return .red
        }
    }

    private var combinedPercentText: String {
        guard let usagePreview else {
            return "--%"
        }
        return "\(Int(usagePreview.combinedRemainingPercent.rounded()))%"
    }

    private var detailedPercentText: String {
        guard let usagePreview else {
            return isLoading ? "обновляю лимит…" : "лимит недоступен"
        }

        let session = Int(usagePreview.sessionRemainingPercent.rounded())
        let weekly = Int(usagePreview.weeklyRemainingPercent.rounded())
        return "5ч \(session)% • 7д \(weekly)%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isActive ? .blue : .secondary.opacity(0.45))

                Text(title)
                    .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(spacing: 6) {
                AccountLimitPreviewBar(
                    progress: usagePreview?.combinedRemainingPercent ?? 0,
                    color: previewColor
                )

                Text(combinedPercentText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(previewColor)

                Text(detailedPercentText)
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

private struct AccountLimitPreviewBar: View {
    let progress: Double
    let color: Color

    private var normalizedProgress: Double {
        min(max(progress, 0), 100)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.18))

                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.75), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * (normalizedProgress / 100.0))
            }
        }
        .frame(width: 74, height: 6)
        .accessibilityLabel("остаток лимита")
        .accessibilityValue("\(Int(normalizedProgress.rounded())) процентов")
    }
}

// MARK: - Smart Usage Dashboard
struct SmartUsageDashboard: View {
    let usage: CodexUsage
    @StateObject private var profileManager = ProfileManager.shared

    // Get the display mode from active profile's icon config
    private var showRemainingPercentage: Bool {
        profileManager.activeProfile?.iconConfig.showRemainingPercentage ?? true
    }

    var body: some View {
        VStack(spacing: 16) {
            // Primary Usage Card
            SmartUsageCard(
                title: "menubar.session_usage".localized,
                subtitle: "menubar.5_hour_window".localized,
                usedPercentage: usage.sessionPercentage,
                showRemaining: showRemainingPercentage,
                resetTime: usage.sessionResetTime,
                isPrimary: true
            )

            // Secondary Usage Cards
            HStack(spacing: 12) {
                SmartUsageCard(
                    title: "menubar.weekly".localized,
                    subtitle: "menubar.weekly".localized,
                    usedPercentage: usage.weeklyPercentage,
                    showRemaining: showRemainingPercentage,
                    resetTime: usage.weeklyResetTime,
                    isPrimary: false
                )

                if usage.opusWeeklyTokensUsed > 0 {
                    SmartUsageCard(
                        title: "menubar.opus_usage".localized,
                        subtitle: "menubar.weekly".localized,
                        usedPercentage: usage.opusWeeklyPercentage,
                        showRemaining: showRemainingPercentage,
                        resetTime: nil,
                        isPrimary: false
                    )
                }

                if usage.sonnetWeeklyTokensUsed > 0 {
                    SmartUsageCard(
                        title: "menubar.sonnet_usage".localized,
                        subtitle: "menubar.weekly".localized,
                        usedPercentage: usage.sonnetWeeklyPercentage,
                        showRemaining: showRemainingPercentage,
                        resetTime: usage.sonnetWeeklyResetTime,
                        isPrimary: false
                    )
                }
            }

        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Smart Usage Card
struct SmartUsageCard: View {
    let title: String
    let subtitle: String
    let usedPercentage: Double
    let showRemaining: Bool
    let resetTime: Date?
    let isPrimary: Bool

    /// Display percentage based on mode
    private var displayPercentage: Double {
        UsageStatusCalculator.getDisplayPercentage(
            usedPercentage: usedPercentage,
            showRemaining: showRemaining
        )
    }

    /// Status level based on display mode
    private var statusLevel: UsageStatusLevel {
        UsageStatusCalculator.calculateStatus(
            usedPercentage: usedPercentage,
            showRemaining: showRemaining
        )
    }

    /// Color based on status level
    private var statusColor: Color {
        switch statusLevel {
        case .safe: return .green
        case .moderate: return .blue
        case .critical: return .red
        }
    }

    private var statusIcon: String {
        switch statusLevel {
        case .safe: return "checkmark.circle.fill"
        case .moderate: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.circle.fill"
        }
    }

    var body: some View {
        VStack(spacing: isPrimary ? 12 : 8) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: isPrimary ? 13 : 11, weight: .semibold))
                        .foregroundColor(.primary)

                    Text(subtitle)
                        .font(.system(size: isPrimary ? 10 : 9, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Status indicator
                HStack(spacing: 4) {
                    Image(systemName: statusIcon)
                        .font(.system(size: isPrimary ? 12 : 10, weight: .medium))
                        .foregroundColor(statusColor)

                    Text("\(Int(displayPercentage))%")
                        .font(.system(size: isPrimary ? 16 : 14, weight: .bold, design: .monospaced))
                        .foregroundColor(statusColor)
                }
            }

            // Progress visualization
            VStack(spacing: 6) {
                // Animated progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.15))

                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [statusColor, statusColor.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * min(displayPercentage / 100.0, 1.0))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .animation(.easeInOut(duration: 0.8), value: displayPercentage)
                    }
                }
                .frame(height: 8)

                // Reset time information
                if let reset = resetTime {
                    HStack {
                        Spacer()
                        Text("menubar.resets_time".localized(with: reset.resetTimeString()))
                            .font(.system(size: isPrimary ? 9 : 8, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(isPrimary ? 16 : 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        )
    }
}

// MARK: - Contextual Insights
struct ContextualInsights: View {
    let usage: CodexUsage

    private var insights: [Insight] {
        var result: [Insight] = []

        // Session insights
        if usage.sessionPercentage > 80 {
            result.append(Insight(
                icon: "exclamationmark.triangle.fill",
                color: .blue,
                title: "usage.high_session".localized,
                description: "usage.high_session.desc".localized
            ))
        }

        // Weekly insights
        if usage.weeklyPercentage > 90 {
            result.append(Insight(
                icon: "clock.fill",
                color: .red,
                title: "usage.weekly_approaching".localized,
                description: "usage.weekly_approaching.desc".localized
            ))
        }

        // Efficiency insights
        if usage.sessionPercentage < 20 && usage.weeklyPercentage < 30 {
            result.append(Insight(
                icon: "checkmark.circle.fill",
                color: .green,
                title: "usage.efficient".localized,
                description: "usage.efficient.desc".localized
            ))
        }

        return result
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(insights, id: \.title) { insight in
                HStack(spacing: 10) {
                    Image(systemName: insight.icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(insight.color)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(insight.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary)

                        Text(insight.description)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(insight.color.opacity(0.08))
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct Insight {
    let icon: String
    let color: Color
    let title: String
    let description: String
}

// MARK: - Smart Footer
struct SmartFooter: View {
    let usage: CodexUsage
    @Binding var showInsights: Bool
    let onPreferences: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, 16)

            // Action buttons
            HStack(spacing: 8) {
                SmartActionButton(
                    icon: "gearshape.fill",
                    title: "common.settings".localized,
                    action: onPreferences
                )

                SmartActionButton(
                    icon: "power",
                    title: "common.quit".localized,
                    isDestructive: true,
                    action: onQuit
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Smart Action Button
struct SmartActionButton: View {
    let icon: String
    let title: String
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isDestructive ? .red : .secondary)
                    .frame(width: 14)

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isDestructive ? .red : .primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        isHovered
                        ? (isDestructive ? Color.red.opacity(0.1) : Color.accentColor.opacity(0.1))
                        : Color.clear
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}
