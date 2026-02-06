import SwiftUI

/// Professional, native macOS Settings interface with multi-profile support
struct SettingsView: View {
    @State private var selectedSection: SettingsSection = .appearance

    var body: some View {
        HSplitView {
            // Sidebar with profile and app settings
            VStack(spacing: 0) {
                ProfileSectionContainer(selectedSection: $selectedSection)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                Spacer()

                AppSettingsSection(selectedSection: $selectedSection)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .frame(minWidth: 160, idealWidth: 170, maxWidth: 180)

            Group {
                switch selectedSection {
                case .appearance:
                    AppearanceSettingsView()
                case .general:
                    GeneralSettingsView()
                case .manageProfiles:
                    ManageProfilesView()
                case .language:
                    LanguageSettingsView()
                case .updates:
                    UpdatesSettingsView()
                case .about:
                    AboutView()
                }
            }
            .frame(minWidth: 500, maxWidth: .infinity)
        }
        .frame(width: 720, height: 580)
    }
}

// MARK: - Profile Section Container

struct ProfileSectionContainer: View {
    @Binding var selectedSection: SettingsSection
    @StateObject private var profileManager = ProfileManager.shared

    var profileSections: [SettingsSection] {
        SettingsSection.allCases.filter { $0.isProfileSetting }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Profile Switcher
            VStack(alignment: .leading, spacing: 4) {
                Text("section.active_profile".localized)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)

                Picker("", selection: Binding(
                    get: { profileManager.activeProfile?.id ?? UUID() },
                    set: { newId in
                        Task {
                            await profileManager.activateProfile(newId)
                        }
                    }
                )) {
                    ForEach(profileManager.profiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            .padding(8)

            Divider()
                .padding(.horizontal, 8)

            // Profile Settings
            VStack(alignment: .leading, spacing: 4) {
                Text("section.settings".localized)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 6)

                VStack(spacing: 4) {
                    ForEach(profileSections, id: \.self) { section in
                        Button {
                            selectedSection = section
                        } label: {
                            SettingMiniButton(
                                icon: section.icon,
                                title: section.title,
                                isSelected: selectedSection == section
                            )
                        }
                        .buttonStyle(.plain)
                        .help(section.description)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - App Settings Section

struct AppSettingsSection: View {
    @Binding var selectedSection: SettingsSection

    var sharedSections: [SettingsSection] {
        SettingsSection.allCases.filter { !$0.isProfileSetting }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("section.app".localized)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            ForEach(sharedSections, id: \.self) { section in
                SidebarItem(
                    icon: section.icon,
                    title: section.title,
                    description: section.description,
                    isSelected: selectedSection == section
                ) {
                    selectedSection = section
                }
            }
        }
    }
}

enum SettingsSection: String, CaseIterable {
    // Profile Settings
    case appearance
    case general

    // Shared Settings
    case manageProfiles
    case language
    case updates
    case about

    var title: String {
        switch self {
        case .appearance: return "section.appearance_title".localized
        case .general: return "section.general_title".localized
        case .manageProfiles: return "section.manage_profiles_title".localized
        case .language: return "language.title".localized
        case .updates: return "settings.updates".localized
        case .about: return "settings.about".localized
        }
    }

    var icon: String {
        switch self {
        case .appearance: return "paintbrush.fill"
        case .general: return "gearshape.fill"
        case .manageProfiles: return "person.2.fill"
        case .language: return "globe"
        case .updates: return "arrow.down.circle.fill"
        case .about: return "info.circle.fill"
        }
    }

    var description: String {
        switch self {
        case .appearance: return "section.appearance_desc".localized
        case .general: return "section.general_desc".localized
        case .manageProfiles: return "section.manage_profiles_desc".localized
        case .language: return "language.subtitle".localized
        case .updates: return "settings.updates.description".localized
        case .about: return "settings.about.description".localized
        }
    }

    var isProfileSetting: Bool {
        switch self {
        case .appearance, .general:
            return true
        default:
            return false
        }
    }
}

// MARK: - Sidebar Item

struct SidebarItem: View {
    let icon: String
    let title: String
    let description: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? .white : .secondary)
                    .frame(width: 12)

                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? .white : .primary)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? SettingsColors.primary : Color.clear)
            )
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(description)
    }
}

struct SettingMiniButton: View {
    let icon: String
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isSelected ? .white : .secondary)
                .frame(width: 12)

            Text(title)
                .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                .foregroundColor(isSelected ? .white : .primary)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? SettingsColors.primary : Color.clear)
        )
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
    }
}
