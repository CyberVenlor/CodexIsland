import SwiftUI

struct SettingsPanelView: View {
    @EnvironmentObject private var settingsStore: SettingsConfigStore
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        HStack(spacing: 14) {
            sidebar
            detailPane
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.top, 4)

            VStack(spacing: 4) {
                ForEach(SettingsTab.allCases) { tab in
                    sidebarRow(for: tab)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(width: 156, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func sidebarRow(for tab: SettingsTab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 16)

                Text(tab.title)
                    .font(.system(size: 12, weight: .medium))

                Spacer(minLength: 0)
            }
            .foregroundStyle(selectedTab == tab ? tab.selectedForegroundColor : tab.foregroundColor)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(backgroundStyle(for: tab), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func backgroundStyle(for tab: SettingsTab) -> some ShapeStyle {
        if selectedTab == tab {
            return AnyShapeStyle(tab.selectedBackgroundColor)
        } else {
            return AnyShapeStyle(tab.backgroundColor)
        }
    }

    private var detailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                detailHeader
                activeTabContent
            }
            .padding(.top, 16)
            .padding(.leading, 2)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var detailHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: selectedTab.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(selectedTab.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                Text(selectedTab.subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.52))
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var activeTabContent: some View {
        switch selectedTab {
        case .general:
            generalView
        case .personalized:
            personalizedView
        case .hooks:
            hooksView
        case .about:
            aboutView
        }
    }

    private var generalView: some View {
        formSection {
            settingsCard("Startup") {
                Toggle("Launch at login", isOn: $settingsStore.config.launchAtLogin)
                Toggle("Open main window on startup", isOn: $settingsStore.config.openOnStartup)
            }

            settingsCard("System") {
                settingsValueRow("Status", value: "Ready")
                settingsValueRow("Version", value: "1.0.0")
            }
        }
    }

    private var personalizedView: some View {
        formSection {
            settingsCard("Profile") {
                TextField("Display name", text: $settingsStore.config.displayName)
                    .textFieldStyle(.roundedBorder)
            }

            settingsCard("Preferences") {
                Picker("Language", selection: $settingsStore.config.preferredLanguage) {
                    Text("English").tag("English")
                    Text("Chinese").tag("Chinese")
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var hooksView: some View {
        formSection {
            settingsCard("Hooks") {
                Toggle("Enable hooks", isOn: $settingsStore.config.hooksEnabled)
                Toggle("Enable pre-hook", isOn: $settingsStore.config.enablePreHook)
                Toggle("Enable post-hook", isOn: $settingsStore.config.enablePostHook)
            }

            settingsCard("Endpoint") {
                TextField("Hook URL", text: $settingsStore.config.hookURL)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var aboutView: some View {
        formSection {
            settingsCard("Application") {
                settingsValueRow("Name", value: "CodexIsland")
                settingsValueRow("Version", value: "1.0.0")
                settingsValueRow("Build", value: "26A01")
            }

            settingsCard("Support") {
                settingsValueRow("Website", value: "rhine-lab.xyz")
                settingsValueRow("Email", value: "catbeluga2437@gmail.com")
            }
        }
    }

    private func formSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
    }

    private func settingsCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }

    private func settingsValueRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.white.opacity(0.72))

            Spacer(minLength: 12)

            Text(value)
                .foregroundStyle(.white)
        }
        .font(.subheadline)
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case personalized
    case hooks
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            "General"
        case .personalized:
            "Personal"
        case .hooks:
            "Hooks"
        case .about:
            "About"
        }
    }

    var subtitle: String {
        switch self {
        case .general:
            "Startup and system behavior"
        case .personalized:
            "Profile and language preferences"
        case .hooks:
            "Hook toggles and endpoint settings"
        case .about:
            "Build information and support"
        }
    }

    var icon: String {
        switch self {
        case .general:
            "gearshape"
        case .personalized:
            "person.circle"
        case .hooks:
            "link"
        case .about:
            "info.circle"
        }
    }

    var backgroundColor: Color {
        switch self {
        case .general:
            Color.blue.opacity(0.16)
        case .personalized:
            Color.green.opacity(0.16)
        case .hooks:
            Color.orange.opacity(0.18)
        case .about:
            Color.gray.opacity(0.18)
        }
    }

    var selectedBackgroundColor: Color {
        switch self {
        case .general:
            Color.blue.opacity(0.88)
        case .personalized:
            Color.green.opacity(0.86)
        case .hooks:
            Color.orange.opacity(0.9)
        case .about:
            Color.white.opacity(0.9)
        }
    }

    var foregroundColor: Color {
        switch self {
        case .general:
            Color.blue.opacity(0.95)
        case .personalized:
            Color.green.opacity(0.95)
        case .hooks:
            Color.orange.opacity(0.95)
        case .about:
            Color.white.opacity(0.88)
        }
    }

    var selectedForegroundColor: Color {
        switch self {
        case .about:
            Color.black.opacity(0.88)
        default:
            Color.white
        }
    }
}
