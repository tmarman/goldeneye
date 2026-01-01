// AgentKit - Agent Infrastructure for Apple Platforms
//
// Core library for building AI agents that run natively on Apple devices.

// MARK: - Agent
@_exported import struct Foundation.URL
@_exported import struct Foundation.Data
@_exported import struct Foundation.Date
@_exported import struct Foundation.UUID

// Note: AgentEventStream is defined in Agent.swift

// MARK: - Version

public enum AgentKitVersion {
    public static let major = 0
    public static let minor = 1
    public static let patch = 0
    public static let string = "\(major).\(minor).\(patch)"
}
