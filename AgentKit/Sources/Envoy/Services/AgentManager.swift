import AgentKit
import Combine
import Foundation

/// Manages connections to local and remote agents
@MainActor
public final class AgentManager: ObservableObject {
    // MARK: - Published Properties

    @Published public private(set) var localAgent: ManagedAgent?
    @Published public private(set) var remoteAgents: [ManagedAgent] = []
    @Published public private(set) var discoveredAgents: [DiscoveredAgent] = []

    // MARK: - Private Properties

    private var clients: [String: A2AClient] = [:]
    private var bonjourBrowser: BonjourBrowser?
    private var healthCheckTask: Task<Void, Never>?

    // MARK: - Initialization

    public init() {
        // Setup local agent
        localAgent = ManagedAgent(
            id: "local",
            name: "Local Agent",
            url: URL(string: "http://127.0.0.1:8080")!,
            isLocal: true
        )
    }

    // MARK: - Connection Management

    /// Connect to an agent by URL
    public func connect(to url: URL, name: String? = nil) async throws -> ManagedAgent {
        let client = A2AClient(baseURL: url)

        // Fetch agent card to verify connection
        let card = try await client.fetchAgentCard()

        let agent = ManagedAgent(
            id: UUID().uuidString,
            name: name ?? card.name,
            url: url,
            isLocal: false,
            card: card,
            status: .connected
        )

        clients[agent.id] = client

        if agent.isLocal {
            localAgent = agent
        } else {
            remoteAgents.append(agent)
        }

        startHealthChecks()
        return agent
    }

    /// Connect to the local agent
    public func connectLocal() async throws {
        guard let local = localAgent else { return }

        var updated = local
        updated.status = .connecting
        localAgent = updated

        do {
            let client = A2AClient(baseURL: local.url)
            let card = try await client.fetchAgentCard()

            clients[local.id] = client
            updated.card = card
            updated.status = .connected
            localAgent = updated

            startHealthChecks()
        } catch {
            updated.status = .error(error.localizedDescription)
            localAgent = updated
            throw error
        }
    }

    /// Disconnect from an agent
    public func disconnect(agentId: String) {
        clients.removeValue(forKey: agentId)

        if agentId == localAgent?.id {
            localAgent?.status = .disconnected
            localAgent?.card = nil
        } else {
            remoteAgents.removeAll { $0.id == agentId }
        }
    }

    /// Disconnect all agents
    public func disconnectAll() {
        clients.removeAll()
        localAgent?.status = .disconnected
        localAgent?.card = nil
        remoteAgents.removeAll()
        healthCheckTask?.cancel()
    }

    // MARK: - Task Operations

    /// Send a task to an agent
    public func sendTask(
        prompt: String,
        to agentId: String,
        streaming: Bool = true
    ) async throws -> A2ATask {
        guard let client = clients[agentId] else {
            throw AgentManagerError.notConnected
        }

        let message = A2AMessage(
            role: .user,
            parts: [.text(A2APart.TextPart(text: prompt))]
        )

        return try await client.sendMessage(message, blocking: !streaming)
    }

    /// Get task status
    public func getTask(id: String, from agentId: String) async throws -> A2ATask {
        guard let client = clients[agentId] else {
            throw AgentManagerError.notConnected
        }

        return try await client.getTask(id: id)
    }

    /// List tasks from an agent
    public func listTasks(from agentId: String, limit: Int = 50) async throws -> [A2ATask] {
        guard let client = clients[agentId] else {
            throw AgentManagerError.notConnected
        }

        return try await client.listTasks(limit: limit)
    }

    /// Cancel a task
    public func cancelTask(id: String, on agentId: String) async throws -> A2ATask {
        guard let client = clients[agentId] else {
            throw AgentManagerError.notConnected
        }

        return try await client.cancelTask(id: id)
    }

    // MARK: - Bonjour Discovery

    /// Start discovering agents on the local network
    public func startDiscovery() {
        bonjourBrowser = BonjourBrowser { [weak self] agents in
            Task { @MainActor in
                self?.discoveredAgents = agents
            }
        }
        bonjourBrowser?.start()
    }

    /// Stop discovering agents
    public func stopDiscovery() {
        bonjourBrowser?.stop()
        bonjourBrowser = nil
        discoveredAgents.removeAll()
    }

    // MARK: - Health Checks

    private func startHealthChecks() {
        healthCheckTask?.cancel()
        healthCheckTask = Task {
            while !Task.isCancelled {
                await performHealthChecks()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func performHealthChecks() async {
        for (agentId, client) in clients {
            do {
                let healthy = try await client.healthCheck()
                if !healthy {
                    updateAgentStatus(agentId, status: .error("Health check failed"))
                }
            } catch {
                updateAgentStatus(agentId, status: .error(error.localizedDescription))
            }
        }
    }

    private func updateAgentStatus(_ agentId: String, status: AgentStatus) {
        if agentId == localAgent?.id {
            localAgent?.status = status
        } else if let index = remoteAgents.firstIndex(where: { $0.id == agentId }) {
            remoteAgents[index].status = status
        }
    }
}

// MARK: - Supporting Types

public struct ManagedAgent: Identifiable, Hashable {
    public let id: String
    public var name: String
    public var url: URL
    public let isLocal: Bool
    public var card: AgentCard?
    public var status: AgentStatus = .disconnected

    public static func == (lhs: ManagedAgent, rhs: ManagedAgent) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public enum AgentStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
}

public struct DiscoveredAgent: Identifiable {
    public let id: String
    public let name: String
    public let url: URL
    public let txtRecord: [String: String]
}

public enum AgentManagerError: Error, LocalizedError {
    case notConnected
    case connectionFailed(Error)
    case taskFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Agent is not connected"
        case .connectionFailed(let error):
            return "Connection failed: \(error.localizedDescription)"
        case .taskFailed(let error):
            return "Task failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Bonjour Browser

private class BonjourBrowser: NSObject {
    private var browser: NetServiceBrowser?
    private var services: [NetService] = []
    private let onUpdate: ([DiscoveredAgent]) -> Void

    init(onUpdate: @escaping ([DiscoveredAgent]) -> Void) {
        self.onUpdate = onUpdate
        super.init()
    }

    func start() {
        browser = NetServiceBrowser()
        browser?.delegate = self
        browser?.searchForServices(ofType: "_agentkit._tcp.", inDomain: "local.")
    }

    func stop() {
        browser?.stop()
        browser = nil
        services.removeAll()
    }
}

extension BonjourBrowser: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 5.0)

        if !moreComing {
            updateDiscoveredAgents()
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        services.removeAll { $0.name == service.name }

        if !moreComing {
            updateDiscoveredAgents()
        }
    }

    private func updateDiscoveredAgents() {
        let agents = services.compactMap { service -> DiscoveredAgent? in
            guard let addresses = service.addresses, !addresses.isEmpty else { return nil }

            // Parse TXT record
            var txtRecord: [String: String] = [:]
            if let data = service.txtRecordData() {
                let dict = NetService.dictionary(fromTXTRecord: data)
                for (key, value) in dict {
                    if let str = String(data: value, encoding: .utf8) {
                        txtRecord[key] = str
                    }
                }
            }

            let port = service.port
            let host = service.hostName ?? "localhost"

            return DiscoveredAgent(
                id: service.name,
                name: txtRecord["name"] ?? service.name,
                url: URL(string: "http://\(host):\(port)")!,
                txtRecord: txtRecord
            )
        }

        onUpdate(agents)
    }
}

extension BonjourBrowser: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        updateDiscoveredAgents()
    }
}
