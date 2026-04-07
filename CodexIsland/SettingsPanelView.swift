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

    private var installedVersion: InstalledAppVersion {
        InstalledAppVersion.current
    }

    private var installedVersionLabel: String {
        installedVersion.marketingVersion.rawValue
    }

    private var installedBuildLabel: String {
        installedVersion.build.map(String.init) ?? "-"
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
            if tab == .quit, selectedTab == .quit {
                NSApplication.shared.terminate(nil)
                return
            }

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
                .id("settings-icon-\(selectedTab.rawValue)")
                .transition(.gaussianBlurText)

            VStack(alignment: .leading, spacing: 2) {
                ZStack(alignment: .leading) {
                    Text(selectedTab.title(in: language))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .id("settings-title-\(selectedTab.rawValue)")
                        .transition(.gaussianBlurText)
                }

                ZStack(alignment: .leading) {
                    Text(selectedTab.subtitle(in: language))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.52))
                        .id("settings-subtitle-\(selectedTab.rawValue)")
                        .transition(.gaussianBlurText)
                }
            }
        }
        .padding(.horizontal, 4)
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
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

                    SettingsNumberStepper(
                        value: $settingsStore.config.suspiciousSessionTimeout,
                        range: 1...9999
                    )

                    Text(l10n.text(
                        "When a running session receives no new event for this many seconds, it switches to Suspicious and shows an expanded island notification.",
                        chinese: "如果运行中的 session 在这段秒数内没有收到新事件，就会切换为可疑状态，并显示一个展开的 island 提示。"
                    ))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.52))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(l10n.text("Completed island display", chinese: "Completed 弹窗显示时长"))
                        .font(.subheadline)
                        .foregroundStyle(.white)

                    SettingsNumberStepper(
                        value: $settingsStore.config.completedIslandDisplayDuration,
                        range: 0...9999
                    )

                    Text(l10n.text(
                        "How long the completed expanded island stays open. Set 0 to require mouse interaction before dismissing.",
                        chinese: "completed 展开 island 保持显示的时长。设为 0 时，需要鼠标交互后才会关闭。"
                    ))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.52))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(l10n.text("Suspicious island display", chinese: "Suspicious 弹窗显示时长"))
                        .font(.subheadline)
                        .foregroundStyle(.white)

                    SettingsNumberStepper(
                        value: $settingsStore.config.suspiciousIslandDisplayDuration,
                        range: 0...9999
                    )

                    Text(l10n.text(
                        "How long the suspicious expanded island stays open. Set 0 to require mouse interaction before dismissing.",
                        chinese: "suspicious 展开 island 保持显示的时长。设为 0 时，需要鼠标交互后才会关闭。"
                    ))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.52))
                }
            }

            settingsCard(l10n.text("System", chinese: "系统")) {
                settingsValueRow(l10n.text("Status", chinese: "状态"), value: l10n.text("Ready", chinese: "就绪"))
                settingsValueRow(l10n.text("Version", chinese: "版本"), value: installedVersionLabel)
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

            settingsCard(l10n.text("Appearance", chinese: "外观")) {
                SettingsColorPickerRow(
                    title: l10n.text("Completed color", chinese: "Completed 颜色"),
                    description: l10n.text(
                        "Used by the collapsed island session counter and cat animation when no session is running.",
                        chinese: "当没有 session 在运行时，用于 collapsed island 的 session 计数器和猫动画。"
                    ),
                    selection: Binding(
                        get: { settingsStore.config.islandCompletedColor.swiftUIColor },
                        set: { settingsStore.config.islandCompletedColor = SettingsColor(color: $0) }
                    )
                )

                SettingsColorPickerRow(
                    title: l10n.text("Running color", chinese: "Running 颜色"),
                    description: l10n.text(
                        "Used by the collapsed island session counter and cat animation while sessions are running.",
                        chinese: "当 session 正在运行时，用于 collapsed island 的 session 计数器和猫动画。"
                    ),
                    selection: Binding(
                        get: { settingsStore.config.islandRunningColor.swiftUIColor },
                        set: { settingsStore.config.islandRunningColor = SettingsColor(color: $0) }
                    )
                )
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

                    SettingsNumberStepper(
                        value: $settingsStore.config.preToolUseTimeout,
                        range: 1...9999
                    )
                    .disabled(!settingsStore.config.hooksEnabled || !settingsStore.config.enablePreToolUseHook)

                    Text(l10n.text(
                        "When approval is still pending near this timeout, CodexIsland will proactively block the tool call.",
                        chinese: "如果接近该超时时间时审批仍未完成，CodexIsland 会主动拦截这次工具调用。"
                    ))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.52))
                }
            }

            settingsCard(l10n.text("Codex Config", chinese: "Codex 配置")) {
                settingsValueRow(
                    l10n.text("External approval mode", chinese: "外部审批模式"),
                    value: settingsStore.config.codexExternalApprovalModeEnabled
                        ? l10n.text("Enabled", chinese: "已启用")
                        : l10n.text("Default", chinese: "默认")
                )

                Text(l10n.text(
                    "Write `approval_policy = \"never\"` and `sandbox_mode = \"danger-full-access\"` into `~/.codex/config.toml` so Codex relies on CodexIsland's external approval flow.",
                    chinese: "将 `approval_policy = \"never\"` 和 `sandbox_mode = \"danger-full-access\"` 写入 `~/.codex/config.toml`，让 Codex 使用 CodexIsland 的外部审批流程。"
                ))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.52))

                HStack(spacing: 10) {
                    Button(l10n.text("Apply external approval mode", chinese: "应用外部审批模式")) {
                        settingsStore.setCodexExternalApprovalModeEnabled(true)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(settingsStore.config.codexExternalApprovalModeEnabled)

                    Button(l10n.text("Restore default", chinese: "恢复默认")) {
                        settingsStore.setCodexExternalApprovalModeEnabled(false)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!settingsStore.config.codexExternalApprovalModeEnabled)
                }
            }
        }
    }

    private var aboutView: some View {
        formSection {
            settingsCard(l10n.text("Application", chinese: "应用")) {
                settingsValueRow(l10n.text("Name", chinese: "名称"), value: "CodexIsland")
                settingsValueRow(l10n.text("Version", chinese: "版本"), value: installedVersionLabel)
                settingsValueRow(l10n.text("Build", chinese: "构建号"), value: installedBuildLabel)
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
        ZStack {
            switch selectedTab {
            case .general:
                generalView
                    .id(SettingsTab.general.rawValue)
                    .transition(.gaussianBlurPanel)
            case .personalized:
                personalizedView
                    .id(SettingsTab.personalized.rawValue)
                    .transition(.gaussianBlurPanel)
            case .hooks:
                hooksView
                    .id(SettingsTab.hooks.rawValue)
                    .transition(.gaussianBlurPanel)
            case .about:
                aboutView
                    .id(SettingsTab.about.rawValue)
                    .transition(.gaussianBlurPanel)
            case .quit:
                quitView
                    .id(SettingsTab.quit.rawValue)
                    .transition(.gaussianBlurPanel)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
    }
}

private struct SettingsNumberStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 10) {
            Button {
                value = max(range.lowerBound, value - 1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .background(controlBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .disabled(value <= range.lowerBound)

            Text("\(value)")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.white)
                .frame(minWidth: 56, alignment: .center)

            Button {
                value = min(range.upperBound, value + 1)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .background(controlBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .disabled(value >= range.upperBound)

            Spacer(minLength: 0)
        }
        .foregroundStyle(.white.opacity(0.9))
    }

    private var controlBackground: Color {
        Color.white.opacity(0.08)
    }
}

private struct SettingsColorPickerRow: View {
    let title: String
    let description: String
    @Binding var selection: Color

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.white)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.52))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button {
                SharedColorPanelController.shared.present(
                    color: selection,
                    onChange: { selection = $0 }
                )
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.22))
                            .frame(width: 30, height: 30)

                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selection)
                            .frame(width: 22, height: 22)
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.white.opacity(0.24), lineWidth: 1)
                            }
                    }

                    Text("Choose")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        }
    }
}

@MainActor
private final class SharedColorPanelController: NSObject {
    static let shared = SharedColorPanelController()

    private var onChange: ((Color) -> Void)?

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePanelColorDidChange(_:)),
            name: NSColorPanel.colorDidChangeNotification,
            object: nil
        )
    }

    func present(color: Color, onChange: @escaping (Color) -> Void) {
        self.onChange = onChange

        let panel = NSColorPanel.shared
        panel.color = NSColor(color).usingColorSpace(.sRGB) ?? .systemBlue
        panel.showsAlpha = false
        panel.isContinuous = true

        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
    }

    @objc
    private func handlePanelColorDidChange(_ notification: Notification) {
        guard let panel = notification.object as? NSColorPanel else { return }
        let color = panel.color.usingColorSpace(.sRGB) ?? panel.color
        onChange?(Color(color))
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
