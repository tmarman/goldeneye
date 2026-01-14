import Combine
import Foundation

/// Manages the local AgentKitServer process lifecycle
@MainActor
public final class ServerManager: ObservableObject {
    // MARK: - Singleton

    public static let shared = ServerManager()

    // MARK: - Published Properties

    @Published public private(set) var isRunning = false
    @Published public private(set) var serverPID: Int32?
    @Published public private(set) var lastError: String?
    @Published public private(set) var serverOutput: [String] = []
    @Published public private(set) var availableModels: [OllamaModel] = []
    @Published public private(set) var isCheckingOllama = false
    @Published public private(set) var ollamaAvailable = false
    @Published public private(set) var lastOllamaError: String?

    // MARK: - Configuration (synced with AppStorage)

    public var serverHost: String {
        UserDefaults.standard.string(forKey: "localAgentHost") ?? "127.0.0.1"
    }

    public var serverPort: Int {
        UserDefaults.standard.integer(forKey: "localAgentPort").nonZero ?? 8080
    }

    public var llmProvider: String {
        UserDefaults.standard.string(forKey: "llmProvider") ?? "ollama"
    }

    public var ollamaURL: String {
        UserDefaults.standard.string(forKey: "ollamaURL") ?? "http://localhost:11434"
    }

    public var selectedModel: String {
        UserDefaults.standard.string(forKey: "selectedModel") ?? "llama3.2"
    }

    public var dataDirectory: String {
        UserDefaults.standard.string(forKey: "dataDirectory") ?? "~/AgentKit"
    }

    public var logLevel: String {
        UserDefaults.standard.string(forKey: "logLevel") ?? "info"
    }

    // MARK: - Private Properties

    private var serverProcess: Process?
    private var outputPipe: Pipe?
    private var outputTask: Task<Void, Never>?
    private let maxOutputLines = 500

    // MARK: - Computed Properties

    public var serverURL: URL {
        URL(string: "http://\(serverHost):\(serverPort)")!
    }

    /// URL for remote clients to connect (uses network IP or Bonjour name)
    public var remoteURL: String {
        if let localIP = getLocalIPAddress() {
            return "http://\(localIP):\(serverPort)"
        }
        // Fallback to bonjour name
        if let hostname = Host.current().localizedName {
            return "http://\(hostname.replacingOccurrences(of: " ", with: "-")).local:\(serverPort)"
        }
        return serverURL.absoluteString
    }

    /// The machine's Bonjour name (e.g., "Tims-MacBook-Pro.local")
    public var bonjourName: String {
        if let hostname = Host.current().localizedName {
            return "\(hostname.replacingOccurrences(of: " ", with: "-")).local"
        }
        return "localhost"
    }

    /// Get the local network IP address
    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return nil
        }

        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family

            // Check for IPv4 interface
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)

                // Skip loopback and prefer en0 (WiFi) or en1 (Ethernet)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                    address = String(cString: hostname)
                    break
                }
            }
        }
        return address
    }

    // MARK: - Initialization

    private init() {
        // Check if server is already running on startup
        Task {
            await checkExistingServer()
            await refreshOllamaModels()
        }
    }

    // MARK: - Server Lifecycle

    /// Start the AgentKitServer process
    public func startServer() async throws {
        guard !isRunning else {
            throw ServerManagerError.alreadyRunning
        }

        lastError = nil
        serverOutput.removeAll()

        // Find the server executable
        let serverPath = try findServerExecutable()

        // Build command arguments
        var arguments: [String] = [
            "--host", serverHost,
            "--port", String(serverPort),
            "--data-dir", dataDirectory,
            "--log-level", logLevel,
            "--llm-provider", llmProvider,
            "--model", selectedModel
        ]

        // Add provider-specific URL
        if llmProvider == "ollama" {
            arguments.append(contentsOf: ["--llm-url", ollamaURL])
        } else if llmProvider == "lmstudio" {
            let lmStudioURL = UserDefaults.standard.string(forKey: "lmStudioURL") ?? "http://localhost:1234"
            arguments.append(contentsOf: ["--llm-url", lmStudioURL])
        }

        // Create and configure process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: serverPath)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())

        // Setup output capture
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // Handle process termination
        process.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                self?.handleTermination(exitCode: process.terminationStatus)
            }
        }

        do {
            try process.run()
            self.serverProcess = process
            self.outputPipe = pipe
            self.serverPID = process.processIdentifier
            self.isRunning = true

            // Start reading output
            startOutputReader(pipe: pipe)

            // Wait briefly and verify server is responding
            try await Task.sleep(for: .seconds(2))

            let healthy = await checkServerHealth()
            if !healthy {
                throw ServerManagerError.startupFailed("Server started but not responding")
            }

            appendOutput("Server started successfully on \(serverURL)")
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    /// Stop the AgentKitServer process
    public func stopServer() {
        guard let process = serverProcess, isRunning else { return }

        // Send SIGTERM for graceful shutdown
        process.terminate()

        // Give it a moment to shut down gracefully, then force kill if needed
        let processToKill = process
        Task {
            try? await Task.sleep(for: .seconds(2))
            if processToKill.isRunning {
                processToKill.interrupt() // SIGINT
            }
        }
    }

    /// Restart the server with current settings
    public func restartServer() async throws {
        if isRunning {
            stopServer()
            // Wait for termination
            try await Task.sleep(for: .seconds(2))
        }
        try await startServer()
    }

    // MARK: - Ollama Integration

    /// Refresh available models from Ollama
    public func refreshOllamaModels() async {
        guard llmProvider == "ollama" else {
            availableModels = []
            ollamaAvailable = false
            lastOllamaError = nil
            return
        }

        isCheckingOllama = true
        lastOllamaError = nil
        defer { isCheckingOllama = false }

        do {
            let url = URL(string: ollamaURL)!.appendingPathComponent("api/tags")
            var request = URLRequest(url: url)
            request.timeoutInterval = 5

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                ollamaAvailable = false
                availableModels = []
                lastOllamaError = "Invalid response from Ollama"
                return
            }

            guard httpResponse.statusCode == 200 else {
                ollamaAvailable = false
                availableModels = []
                lastOllamaError = "Ollama returned HTTP \(httpResponse.statusCode)"
                return
            }

            ollamaAvailable = true

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let result = try decoder.decode(OllamaModelsResponse.self, from: data)
            availableModels = result.models.sorted { $0.name < $1.name }

            if availableModels.isEmpty {
                lastOllamaError = "Connected but no models found. Pull a model with: ollama pull llama3.2"
            }
        } catch let error as URLError {
            ollamaAvailable = false
            availableModels = []
            switch error.code {
            case .timedOut:
                lastOllamaError = "Connection timed out - is Ollama running?"
            case .cannotConnectToHost:
                lastOllamaError = "Cannot connect to \(ollamaURL)"
            default:
                lastOllamaError = "Network error: \(error.localizedDescription)"
            }
        } catch {
            ollamaAvailable = false
            availableModels = []
            lastOllamaError = "Failed to fetch models: \(error.localizedDescription)"
        }
    }

    /// Pull a model from Ollama registry
    public func pullModel(_ modelName: String) async throws {
        let url = URL(string: ollamaURL)!.appendingPathComponent("api/pull")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["name": modelName]
        request.httpBody = try JSONEncoder().encode(body)

        // This is a streaming endpoint, but we'll just wait for completion
        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ServerManagerError.modelPullFailed(modelName)
        }

        // Refresh model list
        await refreshOllamaModels()
    }

    // MARK: - Health Checks

    /// Check if the server is healthy
    public func checkServerHealth() async -> Bool {
        let url = serverURL.appendingPathComponent("health")

        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }

    /// Check if a server is already running on the configured port
    private func checkExistingServer() async {
        let healthy = await checkServerHealth()
        if healthy {
            isRunning = true
            appendOutput("Found existing server running on \(serverURL)")
        }
    }

    // MARK: - Private Helpers

    private func findServerExecutable() throws -> String {
        // First, check if running from Xcode build
        let bundlePath = Bundle.main.bundlePath
        let possiblePaths = [
            // Adjacent to console app in build directory
            URL(fileURLWithPath: bundlePath)
                .deletingLastPathComponent()
                .appendingPathComponent("AgentKitServer")
                .path,
            // In derived data
            URL(fileURLWithPath: bundlePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Debug/AgentKitServer")
                .path,
            // Installed in /usr/local/bin
            "/usr/local/bin/agentkit-server",
            // In home directory
            NSHomeDirectory() + "/.local/bin/agentkit-server",
            // Swift build directory
            URL(fileURLWithPath: #file)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(".build/debug/AgentKitServer")
                .path
        ]

        for path in possiblePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        throw ServerManagerError.serverNotFound(possiblePaths)
    }

    private func startOutputReader(pipe: Pipe) {
        outputTask?.cancel()
        outputTask = Task {
            let handle = pipe.fileHandleForReading

            do {
                for try await line in handle.bytes.lines {
                    guard !Task.isCancelled else { break }
                    appendOutput(line)
                }
            } catch {
                // Stream ended or was cancelled
            }
        }
    }

    private func appendOutput(_ line: String) {
        serverOutput.append(line)
        if serverOutput.count > maxOutputLines {
            serverOutput.removeFirst(serverOutput.count - maxOutputLines)
        }
    }

    private func handleTermination(exitCode: Int32) {
        isRunning = false
        serverPID = nil
        outputTask?.cancel()

        if exitCode != 0 {
            lastError = "Server exited with code \(exitCode)"
            appendOutput("Server terminated with exit code \(exitCode)")
        } else {
            appendOutput("Server stopped")
        }

        serverProcess = nil
        outputPipe = nil
    }
}

// MARK: - Supporting Types

public struct OllamaModel: Codable, Identifiable, Hashable {
    public var id: String { name }
    public let name: String
    public let modifiedAt: String?
    public let size: Int64?
    public let digest: String?

    enum CodingKeys: String, CodingKey {
        case name
        case modifiedAt = "modified_at"
        case size
        case digest
    }

    public var formattedSize: String {
        guard let size = size else { return "Unknown" }
        let gb = Double(size) / 1_000_000_000
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        } else {
            let mb = Double(size) / 1_000_000
            return String(format: "%.0f MB", mb)
        }
    }
}

private struct OllamaModelsResponse: Codable {
    let models: [OllamaModel]
}

public enum ServerManagerError: Error, LocalizedError {
    case alreadyRunning
    case serverNotFound([String])
    case startupFailed(String)
    case modelPullFailed(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "Server is already running"
        case .serverNotFound(let paths):
            return "Could not find AgentKitServer executable. Searched:\n\(paths.joined(separator: "\n"))"
        case .startupFailed(let reason):
            return "Server startup failed: \(reason)"
        case .modelPullFailed(let model):
            return "Failed to pull model: \(model)"
        }
    }
}

// MARK: - Extensions

private extension Int {
    var nonZero: Int? {
        self == 0 ? nil : self
    }
}
