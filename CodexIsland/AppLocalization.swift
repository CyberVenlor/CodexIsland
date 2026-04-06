import Foundation

enum AppLanguage: String, CaseIterable {
    case english = "English"
    case chinese = "Chinese"

    init(preference: String) {
        switch preference.lowercased() {
        case "chinese", "中文", "简体中文", "zh", "zh-cn", "zh-hans":
            self = .chinese
        default:
            self = .english
        }
    }

    var isChinese: Bool {
        self == .chinese
    }

    var settingsValue: String {
        rawValue
    }

    func displayName(in language: AppLanguage) -> String {
        switch self {
        case .english:
            return language.label(english: "English", chinese: "英语")
        case .chinese:
            return language.label(english: "Chinese", chinese: "中文")
        }
    }

    func label(english: String, chinese: String) -> String {
        isChinese ? chinese : english
    }
}

struct AppLocalization {
    let language: AppLanguage

    func text(_ english: String, chinese: String) -> String {
        language.label(english: english, chinese: chinese)
    }

    func trackedSessions(_ count: Int) -> String {
        language.label(
            english: "\(count) tracked",
            chinese: "已跟踪 \(count) 个"
        )
    }

    func toolLabel(name: String) -> String {
        language.label(
            english: "tool: \(name)",
            chinese: "工具：\(name)"
        )
    }

    func toolUseIDLabel(_ id: String) -> String {
        language.label(
            english: "toolUseId: \(id)",
            chinese: "工具调用 ID：\(id)"
        )
    }

    func approvalStatusLabel(_ status: String) -> String {
        language.label(
            english: "approval: \(localizedApprovalStatus(status))",
            chinese: "审批：\(localizedApprovalStatus(status))"
        )
    }

    func localizedApprovalStatus(_ status: String) -> String {
        switch status.lowercased() {
        case "approved":
            return text("approved", chinese: "已批准")
        case "denied":
            return text("denied", chinese: "已拒绝")
        case "pending":
            return text("pending", chinese: "待处理")
        case "timed_out":
            return text("timed out", chinese: "已超时")
        default:
            return status
        }
    }

    func localizedSessionState(_ state: CodexSessionState) -> String {
        switch state {
        case .running:
            return text("running", chinese: "运行中")
        case .idle:
            return text("idle", chinese: "空闲")
        case .completed:
            return text("completed", chinese: "已完成")
        case .unknown(let value):
            return value
        }
    }
}

extension SettingsConfig {
    var appLanguage: AppLanguage {
        AppLanguage(preference: preferredLanguage)
    }
}
