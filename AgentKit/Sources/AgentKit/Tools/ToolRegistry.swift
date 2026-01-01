import Foundation

// MARK: - Tool Registry

/// Registry of available tools
public actor ToolRegistry {
    private var tools: [String: any Tool] = [:]

    public init() {}

    /// Register a tool
    public func register(_ tool: any Tool) {
        tools[tool.name] = tool
    }

    /// Register multiple tools
    public func register(_ newTools: [any Tool]) {
        for tool in newTools {
            tools[tool.name] = tool
        }
    }

    /// Get a tool by name
    public func get(_ name: String) -> (any Tool)? {
        tools[name]
    }

    /// Get all registered tools
    public func all() -> [any Tool] {
        Array(tools.values)
    }

    /// Get tools as array for agent configuration
    public func asArray() -> [any Tool] {
        Array(tools.values)
    }

    /// Generate tool schemas for LLM
    public func schemas() -> [[String: Any]] {
        tools.values.map { tool in
            [
                "name": tool.name,
                "description": tool.description,
                "input_schema": [
                    "type": tool.inputSchema.type,
                    "properties": tool.inputSchema.properties.mapValues { prop in
                        var dict: [String: Any] = ["type": prop.type]
                        if let desc = prop.description { dict["description"] = desc }
                        if let enumVals = prop.enumValues { dict["enum"] = enumVals }
                        return dict
                    },
                    "required": tool.inputSchema.required
                ]
            ]
        }
    }
}

// MARK: - Default Tools

extension ToolRegistry {
    /// Create registry with built-in tools
    public static func withBuiltInTools() -> ToolRegistry {
        let registry = ToolRegistry()
        Task {
            await registry.register([
                ReadTool(),
                WriteTool(),
                BashTool(),
                GlobTool(),
                GrepTool(),
            ])
        }
        return registry
    }
}
