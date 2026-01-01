import Foundation

// MARK: - Tool Protocol

/// Protocol for tools that agents can use
public protocol Tool: Sendable {
    /// Unique name for the tool
    var name: String { get }

    /// Human-readable description
    var description: String { get }

    /// JSON Schema for input parameters
    var inputSchema: ToolSchema { get }

    /// Whether this tool requires human approval
    var requiresApproval: Bool { get }

    /// Risk level for approval UI
    var riskLevel: RiskLevel { get }

    /// Execute the tool with given input
    func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput

    /// Generate human-readable description of what this action will do
    func describeAction(_ input: ToolInput) -> String
}

// MARK: - Default Implementations

extension Tool {
    public var requiresApproval: Bool { false }
    public var riskLevel: RiskLevel { .low }

    public func describeAction(_ input: ToolInput) -> String {
        "\(name) with \(input.parameters.count) parameters"
    }
}

// MARK: - Risk Level

public enum RiskLevel: String, Sendable, Codable, Comparable {
    case low        // Informational, auto-approve option
    case medium     // Requires explicit approval
    case high       // Requires approval, shows warning
    case critical   // Requires approval + confirmation

    public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        let order: [RiskLevel] = [.low, .medium, .high, .critical]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

// MARK: - Tool Schema

/// JSON Schema for tool input
public struct ToolSchema: Sendable, Codable {
    public let type: String
    public let properties: [String: PropertySchema]
    public let required: [String]

    public init(
        type: String = "object",
        properties: [String: PropertySchema],
        required: [String] = []
    ) {
        self.type = type
        self.properties = properties
        self.required = required
    }

    public struct PropertySchema: Sendable, Codable {
        public let type: String
        public let description: String?
        public let enumValues: [String]?

        public init(type: String, description: String? = nil, enumValues: [String]? = nil) {
            self.type = type
            self.description = description
            self.enumValues = enumValues
        }

        enum CodingKeys: String, CodingKey {
            case type, description
            case enumValues = "enum"
        }
    }
}

// MARK: - Tool Input/Output

/// Input to a tool
public struct ToolInput: Sendable {
    public let parameters: [String: AnyCodable]

    public init(parameters: [String: AnyCodable]) {
        self.parameters = parameters
    }

    /// Get a parameter value
    public func get<T>(_ key: String, as type: T.Type = T.self) -> T? {
        parameters[key]?.value as? T
    }

    /// Get a required parameter, throwing if missing
    public func require<T>(_ key: String, as type: T.Type = T.self) throws -> T {
        guard let value = get(key, as: type) else {
            throw ToolError.missingParameter(key)
        }
        return value
    }

    /// Summary for logging
    public var summary: String {
        parameters.keys.joined(separator: ", ")
    }
}

/// Output from a tool
public struct ToolOutput: Sendable {
    public let content: String
    public let isError: Bool
    public let metadata: [String: AnyCodable]?

    public init(content: String, isError: Bool = false, metadata: [String: AnyCodable]? = nil) {
        self.content = content
        self.isError = isError
        self.metadata = metadata
    }

    public static func success(_ content: String) -> ToolOutput {
        ToolOutput(content: content, isError: false)
    }

    public static func error(_ message: String) -> ToolOutput {
        ToolOutput(content: message, isError: true)
    }
}

// MARK: - Tool Context

/// Context provided to tools during execution
public struct ToolContext: Sendable {
    public let session: Session
    public let workingDirectory: URL

    public init(session: Session, workingDirectory: URL) {
        self.session = session
        self.workingDirectory = workingDirectory
    }
}

// MARK: - Tool Errors

public enum ToolError: Error, Sendable {
    case missingParameter(String)
    case invalidParameter(String, expected: String)
    case executionFailed(String)
    case permissionDenied(String)
}
