import AgentKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            ApprovalSettingsView()
                .tabItem {
                    Label("Approvals", systemImage: "checkmark.shield")
                }

            AgentSettingsView()
                .tabItem {
                    Label("Agents", systemImage: "brain")
                }

            AdvancedSettingsView()
                .tabItem {
                    Label("Advanced", systemImage: "gearshape.2")
                }
        }
        .frame(width: 500, height: 400)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showInMenuBar") private var showInMenuBar = true
    @AppStorage("showInDock") private var showInDock = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("soundEnabled") private var soundEnabled = true

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                Toggle("Show in Menu Bar", isOn: $showInMenuBar)
                Toggle("Show in Dock", isOn: $showInDock)
            } header: {
                Text("Appearance")
            }

            Section {
                Toggle("Enable Notifications", isOn: $notificationsEnabled)
                Toggle("Play Sounds", isOn: $soundEnabled)
                    .disabled(!notificationsEnabled)
            } header: {
                Text("Notifications")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Approval Settings

struct ApprovalSettingsView: View {
    @AppStorage("defaultApprovalTimeout") private var defaultTimeout = 300
    @AppStorage("autoApproveRead") private var autoApproveRead = true
    @AppStorage("autoApproveGlob") private var autoApproveGlob = true
    @AppStorage("autoApproveGrep") private var autoApproveGrep = true
    @AppStorage("requireApprovalForWrite") private var requireWrite = true
    @AppStorage("requireApprovalForBash") private var requireBash = true

    var body: some View {
        Form {
            Section {
                Picker("Default Timeout", selection: $defaultTimeout) {
                    Text("1 minute").tag(60)
                    Text("5 minutes").tag(300)
                    Text("15 minutes").tag(900)
                    Text("1 hour").tag(3600)
                    Text("Never").tag(0)
                }
            } header: {
                Text("Timeouts")
            }

            Section {
                Toggle("Read (file reading)", isOn: $autoApproveRead)
                Toggle("Glob (file search)", isOn: $autoApproveGlob)
                Toggle("Grep (content search)", isOn: $autoApproveGrep)
            } header: {
                Text("Auto-Approve (Low Risk)")
            }

            Section {
                Toggle("Write (file modification)", isOn: $requireWrite)
                Toggle("Bash (shell commands)", isOn: $requireBash)
            } header: {
                Text("Require Approval (High Risk)")
            }

            Section {
                Button("Manage Allow List...") {
                    // Open allow list editor
                }

                Button("Manage Block List...") {
                    // Open block list editor
                }
            } header: {
                Text("Custom Rules")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Agent Settings

struct AgentSettingsView: View {
    @AppStorage("localAgentPort") private var localPort = 8080
    @AppStorage("localAgentHost") private var localHost = "127.0.0.1"
    @AppStorage("dataDirectory") private var dataDirectory = "~/AgentKit"
    @AppStorage("autoConnectLocal") private var autoConnectLocal = true
    @AppStorage("enableBonjour") private var enableBonjour = true

    var body: some View {
        Form {
            Section {
                TextField("Host", text: $localHost)
                    .textFieldStyle(.roundedBorder)

                Stepper("Port: \(localPort)", value: $localPort, in: 1024...65535)

                TextField("Data Directory", text: $dataDirectory)
                    .textFieldStyle(.roundedBorder)

                Toggle("Auto-connect on Launch", isOn: $autoConnectLocal)
            } header: {
                Text("Local Agent")
            }

            Section {
                Toggle("Enable Bonjour Discovery", isOn: $enableBonjour)

                if enableBonjour {
                    Text("AgentKit will discover other agents on your local network")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Network Discovery")
            }

            Section {
                Button("Start Local Server") {
                    // Launch server process
                }
                .buttonStyle(.borderedProminent)

                Button("Stop Local Server") {
                    // Stop server process
                }
                .buttonStyle(.bordered)
            } header: {
                Text("Server Control")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Advanced Settings

struct AdvancedSettingsView: View {
    @AppStorage("logLevel") private var logLevel = "info"
    @AppStorage("enableTelemetry") private var enableTelemetry = false
    @AppStorage("gitAutoCommit") private var gitAutoCommit = true

    var body: some View {
        Form {
            Section {
                Picker("Log Level", selection: $logLevel) {
                    Text("Trace").tag("trace")
                    Text("Debug").tag("debug")
                    Text("Info").tag("info")
                    Text("Warning").tag("warning")
                    Text("Error").tag("error")
                }
            } header: {
                Text("Logging")
            }

            Section {
                Toggle("Auto-commit Tool Executions", isOn: $gitAutoCommit)

                Text("Each tool execution will create a git commit in the session repository")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Git Integration")
            }

            Section {
                Toggle("Enable Anonymous Telemetry", isOn: $enableTelemetry)

                Text("Help improve AgentKit by sending anonymous usage data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Privacy")
            }

            Section {
                Button("Reset All Settings") {
                    // Reset to defaults
                }
                .foregroundStyle(.red)

                Button("Export Configuration...") {
                    // Export settings
                }

                Button("Import Configuration...") {
                    // Import settings
                }
            } header: {
                Text("Configuration")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
