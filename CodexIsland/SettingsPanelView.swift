import SwiftUI

struct SettingsPanelView: View {
    @EnvironmentObject private var settingsStore: SettingsConfigStore
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            tabPicker
            ScrollView {
                activeTabContent
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.title3.weight(.semibold))
                Text("In progress module merged from the `settings` branch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("In Progress")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.14), in: Capsule())
        }
    }

    private var tabPicker: some View {
        Picker("Settings Section", selection: $selectedTab) {
            ForEach(SettingsTab.allCases) { tab in
                Label(tab.title, systemImage: tab.icon)
                    .tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
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
                LabeledContent("Status", value: "Ready")
                LabeledContent("Version", value: "1.0.0")
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
                LabeledContent("Name", value: "CodexIsland")
                LabeledContent("Version", value: "1.0.0")
                LabeledContent("Build", value: "26A01")
            }

            settingsCard("Support") {
                LabeledContent("Website", value: "rhine-lab.xyz")
                LabeledContent("Email", value: "catbeluga2437@gmail.com")
            }
        }
    }

    private func formSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
    }

    private func settingsCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            content()
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
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
            "Personalized"
        case .hooks:
            "Hooks"
        case .about:
            "About"
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
}
