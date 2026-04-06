import AppKit
import SwiftUI

struct SettingsPanelView: View {
    @EnvironmentObject private var settingsStore: SettingsConfigStore
    @State private var selectedTab: SettingsTab = .general

    private var language: AppLanguage {
        settingsStore.config.appLanguage
    }

    private var l10n: AppLocalization {
        AppLocalization(language: language)
    }

    var body: some View {
        HStack(spacing: 14) {
            sidebar
            detailPane
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.text("Settings", chinese: "设置"))
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

                Text(tab.title(in: language))
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
                Text(selectedTab.title(in: language))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                Text(selectedTab.subtitle(in: language))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.52))
            }
        }
        .padding(.horizontal, 4)
    }

    private var generalView: some View {
        formSection {
            settingsCard(l10n.text("Startup", chinese: "启动")) {
                Toggle(l10n.text("Launch at login", chinese: "登录时启动"), isOn: $settingsStore.config.launchAtLogin)
            }

            settingsCard(l10n.text("Notifications", chinese: "提示")) {
                Toggle(
                    l10n.text("Show session end island", chinese: "显示 session 结束提示"),
                    isOn: $settingsStore.config.showSessionEndNotifications
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(l10n.text("Suspicious session timeout", chinese: "可疑 session 超时"))
                        .font(.subheadline)
                        .foregroundStyle(.white)

                    TextField(
                        "60",
                        value: $settingsStore.config.suspiciousSessionTimeout,
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)

                    Text(l10n.text(
                        "When a running session receives no new event for this many seconds, it switches to Suspicious and shows an expanded island notification.",
                        chinese: "如果运行中的 session 在这段秒数内没有收到新事件，就会切换为可疑状态，并显示一个展开的 island 提示。"
                    ))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.52))
                }
            }

            settingsCard(l10n.text("System", chinese: "系统")) {
                settingsValueRow(l10n.text("Status", chinese: "状态"), value: l10n.text("Ready", chinese: "就绪"))
                settingsValueRow(l10n.text("Version", chinese: "版本"), value: "1.0.0")
            }
        }
    }

    private var personalizedView: some View {
        formSection {
            settingsCard(l10n.text("Profile", chinese: "资料")) {
                TextField(l10n.text("Display name", chinese: "显示名称"), text: $settingsStore.config.displayName)
                    .textFieldStyle(.roundedBorder)
            }

            settingsCard(l10n.text("Preferences", chinese: "偏好")) {
                Picker(l10n.text("Language", chinese: "语言"), selection: $settingsStore.config.preferredLanguage) {
                    ForEach(AppLanguage.allCases, id: \.self) { option in
                        Text(option.displayName(in: language)).tag(option.settingsValue)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var hooksView: some View {
        formSection {
            settingsCard(l10n.text("Hooks", chinese: "钩子")) {
                Toggle(l10n.text("Enable hooks", chinese: "启用钩子"), isOn: $settingsStore.config.hooksEnabled)
                Toggle(l10n.text("Enable PreToolUse", chinese: "启用 PreToolUse"), isOn: $settingsStore.config.enablePreToolUseHook)
                    .disabled(!settingsStore.config.hooksEnabled)
                Toggle(l10n.text("Enable PostToolUse", chinese: "启用 PostToolUse"), isOn: $settingsStore.config.enablePostToolUseHook)
                    .disabled(!settingsStore.config.hooksEnabled)

                VStack(alignment: .leading, spacing: 6) {
                    Text(l10n.text("PreToolUse timeout", chinese: "PreToolUse 超时"))
                        .font(.subheadline)
                        .foregroundStyle(.white)

                    TextField(
                        "300",
                        value: $settingsStore.config.preToolUseTimeout,
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    .disabled(!settingsStore.config.hooksEnabled || !settingsStore.config.enablePreToolUseHook)

                    Text(l10n.text(
                        "When approval is still pending near this timeout, CodexIsland will proactively block the tool call.",
                        chinese: "如果接近该超时时间时审批仍未完成，CodexIsland 会主动拦截这次工具调用。"
                    ))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.52))
                }
            }
        }
    }

    private var aboutView: some View {
        formSection {
            settingsCard(l10n.text("Application", chinese: "应用")) {
                settingsValueRow(l10n.text("Name", chinese: "名称"), value: "CodexIsland")
                settingsValueRow(l10n.text("Version", chinese: "版本"), value: "1.0.0")
                settingsValueRow(l10n.text("Build", chinese: "构建号"), value: "26A01")
            }

            settingsCard(l10n.text("Support", chinese: "支持")) {
                settingsValueRow(l10n.text("Website", chinese: "网站"), value: "rhine-lab.xyz")
                settingsValueRow(l10n.text("Email", chinese: "邮箱"), value: "catbeluga2437@gmail.com")
            }
        }
    }

    private var quitView: some View {
        formSection {
            settingsCard(l10n.text("Quit CodexIsland", chinese: "退出 CodexIsland")) {
                Text(l10n.text(
                    "Close the island overlay and terminate the app immediately.",
                    chinese: "关闭 Island 浮层并立即退出应用。"
                ))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))

                Button(role: .destructive) {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label(l10n.text("Quit CodexIsland", chinese: "退出 CodexIsland"), systemImage: "power")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
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
        case .quit:
            quitView
        }
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case personalized
    case hooks
    case about
    case quit

    var id: String { rawValue }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .general:
            language.label(english: "General", chinese: "通用")
        case .personalized:
            language.label(english: "Personal", chinese: "个人")
        case .hooks:
            language.label(english: "Hooks", chinese: "钩子")
        case .about:
            language.label(english: "About", chinese: "关于")
        case .quit:
            language.label(english: "Quit", chinese: "退出")
        }
    }

    func subtitle(in language: AppLanguage) -> String {
        switch self {
        case .general:
            language.label(english: "Startup and system behavior", chinese: "启动与系统行为")
        case .personalized:
            language.label(english: "Profile and language preferences", chinese: "资料与语言偏好")
        case .hooks:
            language.label(english: "Hook toggles and endpoint settings", chinese: "钩子开关与端点设置")
        case .about:
            language.label(english: "Build information and support", chinese: "构建信息与支持方式")
        case .quit:
            language.label(english: "Exit the application", chinese: "退出应用")
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
        case .quit:
            "power"
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
        case .quit:
            Color.red.opacity(0.16)
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
        case .quit:
            Color.red.opacity(0.9)
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
        case .quit:
            Color.red.opacity(0.95)
        }
    }

    var selectedForegroundColor: Color {
        switch self {
        case .about:
            Color.black.opacity(0.88)
        case .quit:
            Color.white
        default:
            Color.white
        }
    }
}
