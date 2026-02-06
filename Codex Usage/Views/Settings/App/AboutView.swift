import SwiftUI
import AppKit

/// About page with app information
struct AboutView: View {
    @State private var showResetConfirmation = false

    private var appVersion: String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return version
        }
        return "Unknown"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.section) {
                VStack(spacing: DesignTokens.Spacing.medium) {
                    Image("AboutLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)

                    Text("Codex Usage Tracker")
                        .font(DesignTokens.Typography.pageTitle)

                    Text("Version \(appVersion)")
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(.secondary)

                    Button(action: {
                        UpdateManager.shared.checkForUpdates()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 10))
                            Text("Check for updates")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, DesignTokens.Spacing.cardPadding)

                Divider()

                SettingsContentCard {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                        Text("Links")
                            .font(DesignTokens.Typography.sectionTitle)

                        LinkButton(title: "GitHub profile", icon: "person.crop.circle") {
                            if let url = URL(string: "https://github.com/kirillshsh") {
                                NSWorkspace.shared.open(url)
                            }
                        }

                        LinkButton(title: "Send feedback", icon: "envelope") {
                            if let url = URL(string: "mailto:kirill@example.com") {
                                NSWorkspace.shared.open(url)
                            }
                        }

                        Divider()

                        LinkButton(title: "Reset app data", icon: "trash") {
                            showResetConfirmation = true
                        }
                    }
                }
                .alert("Reset app data?", isPresented: $showResetConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Reset", role: .destructive) {
                        resetAppData()
                    }
                } message: {
                    Text("This will remove local settings and restart the app.")
                }

                Spacer()
            }
            .padding(28)
        }
    }

    private func resetAppData() {
        LoggingService.shared.log("AboutView: Resetting app data...")
        MigrationService.shared.resetAppData()
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Link Button

struct LinkButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignTokens.Spacing.iconText) {
                Image(systemName: icon)
                    .font(.system(size: DesignTokens.Icons.small))
                    .foregroundColor(.secondary)
                    .frame(width: DesignTokens.Spacing.cardPadding)

                Text(title)
                    .font(DesignTokens.Typography.body)
                    .foregroundColor(.primary)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AboutView()
        .frame(width: 520, height: 600)
}
