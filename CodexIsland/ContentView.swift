//
//  ContentView.swift
//  CodexIsland
//
//  Created by n3ur0 on 4/4/26.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab: SettingsTab? = .general

    @State private var launchAtLogin = true
    @State private var openOnStartup = true
    @State private var displayName = "Modulusly"
    @State private var preferredLanguage = "English"
    @State private var hooksEnabled = true
    @State private var enablePreHook = false
    @State private var enablePostHook = true
    @State private var hookURL = "https://hooks.modulusly.dev"

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                Label(tab.title, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            Group {
                switch selectedTab ?? .general {
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
            .navigationTitle((selectedTab ?? .general).title)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 820, minHeight: 520)
    }

    private var generalView: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                Toggle("Open main window on startup", isOn: $openOnStartup)
            }

            Section("System") {
                LabeledContent("Status", value: "Ready")
                LabeledContent("Version", value: "1.0.0")
            }
        }
        .formStyle(.grouped)
    }

    private var personalizedView: some View {
        Form {
            Section("Profile") {
                TextField("Display name", text: $displayName)
            }

            Section("Preferences") {
                Picker("Language", selection: $preferredLanguage) {
                    Text("English").tag("English")
                    Text("Chinese").tag("Chinese")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var hooksView: some View {
        Form {
            Section("Hooks") {
                Toggle("Enable hooks", isOn: $hooksEnabled)
                Toggle("Enable pre-hook", isOn: $enablePreHook)
                Toggle("Enable post-hook", isOn: $enablePostHook)
            }

            Section("Endpoint") {
                TextField("Hook URL", text: $hookURL)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .formStyle(.grouped)
    }

    private var aboutView: some View {
        Form {
            Section("Application") {
                LabeledContent("Name", value: "Modulusly")
                LabeledContent("Version", value: "1.0.0")
                LabeledContent("Build", value: "26A01")
            }

            Section("Support") {
                LabeledContent("Website", value: "modulusly.dev")
                LabeledContent("Email", value: "support@modulusly.dev")
            }
        }
        .formStyle(.grouped)
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
            return "General"
        case .personalized:
            return "Personalized"
        case .hooks:
            return "Hooks"
        case .about:
            return "About"
        }
    }

    var icon: String {
        switch self {
        case .general:
            return "gearshape"
        case .personalized:
            return "person.circle"
        case .hooks:
            return "link"
        case .about:
            return "info.circle"
        }
    }
}

#Preview {
    ContentView()
}
