import Foundation

// Note: PacketLine is defined in GitServer.swift
// This file is a placeholder for additional git protocol utilities

// MARK: - Git Protocol Constants

public enum GitProtocol {
    /// Service names
    public enum Service: String {
        case uploadPack = "git-upload-pack"
        case receivePack = "git-receive-pack"
    }

    /// Content types
    public static func advertisementContentType(for service: Service) -> String {
        "application/x-\(service.rawValue)-advertisement"
    }

    public static func resultContentType(for service: Service) -> String {
        "application/x-\(service.rawValue)-result"
    }
}

// MARK: - Git Capabilities

public struct GitCapabilities: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let multiAck = GitCapabilities(rawValue: 1 << 0)
    public static let sideBand64k = GitCapabilities(rawValue: 1 << 1)
    public static let thinPack = GitCapabilities(rawValue: 1 << 2)
    public static let ofsDelta = GitCapabilities(rawValue: 1 << 3)
    public static let shallowClone = GitCapabilities(rawValue: 1 << 4)
    public static let noProgress = GitCapabilities(rawValue: 1 << 5)
    public static let includeTag = GitCapabilities(rawValue: 1 << 6)

    public var description: String {
        var caps: [String] = []
        if contains(.multiAck) { caps.append("multi_ack") }
        if contains(.sideBand64k) { caps.append("side-band-64k") }
        if contains(.thinPack) { caps.append("thin-pack") }
        if contains(.ofsDelta) { caps.append("ofs-delta") }
        if contains(.shallowClone) { caps.append("shallow") }
        if contains(.noProgress) { caps.append("no-progress") }
        if contains(.includeTag) { caps.append("include-tag") }
        return caps.joined(separator: " ")
    }
}
