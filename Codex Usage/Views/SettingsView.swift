import SwiftUI

/// Native macOS Settings interface without profile management.
struct SettingsView: View {
    @State private var selectedSection: SettingsSection = .appearance

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                SidebarSection(selectedSection: $selectedSection)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                Spacer()
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .frame(minWidth: 160, idealWidth: 170, maxWidth: 180)

            Group {
                switch selectedSection {
                case .appearance:
                    AppearanceSettingsView()
                case .general:
                    GeneralSettingsView()
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

struct SidebarSection: View {
    @Binding var selectedSection: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("section.settings".localized)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            ForEach(SettingsSection.allCases, id: \.self) { section in
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
    case appearance
    case general
    case language
    case updates
    case about

    var title: String {
        switch self {
        case .appearance: return "section.appearance_title".localized
        case .general: return "section.general_title".localized
        case .language: return "language.title".localized
        case .updates: return "settings.updates".localized
        case .about: return "settings.about".localized
        }
    }

    var icon: String {
        switch self {
        case .appearance: return "paintbrush.fill"
        case .general: return "gearshape.fill"
        case .language: return "globe"
        case .updates: return "arrow.down.circle.fill"
        case .about: return "info.circle.fill"
        }
    }

    var description: String {
        switch self {
        case .appearance: return "section.appearance_desc".localized
        case .general: return "section.general_desc".localized
        case .language: return "language.subtitle".localized
        case .updates: return "settings.updates.description".localized
        case .about: return "settings.about.description".localized
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
