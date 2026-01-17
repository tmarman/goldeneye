//
//  AppleScriptBridge.swift
//  AgentKit
//
//  Utility for executing AppleScript commands from Swift.
//  Used by Apple Notes, Mail, and other integrations that require AppleScript.
//

import Foundation

// MARK: - AppleScript Bridge

/// A utility actor for executing AppleScript commands safely.
///
/// This bridge handles:
/// - Script execution via osascript
/// - Input sanitization to prevent injection
/// - Timeout management
/// - Error parsing and categorization
///
/// Usage:
/// ```swift
/// let bridge = AppleScriptBridge()
/// let result = try await bridge.execute("""
///     tell application "Notes"
///         make new note at folder "Notes" with properties {name:"Title", body:"Content"}
///     end tell
/// """)
/// ```
public actor AppleScriptBridge {

    /// Default timeout for script execution (30 seconds)
    private let defaultTimeout: TimeInterval = 30

    public init() {}

    // MARK: - Script Execution

    /// Execute an AppleScript and return the result
    /// - Parameters:
    ///   - script: The AppleScript code to execute
    ///   - timeout: Optional timeout in seconds (default: 30)
    /// - Returns: The script output as a string
    /// - Throws: AppleScriptError on failure
    public func execute(_ script: String, timeout: TimeInterval? = nil) async throws -> String {
        let effectiveTimeout = timeout ?? defaultTimeout

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw AppleScriptError.executionFailed("Failed to start osascript: \(error.localizedDescription)")
        }

        // Wait with timeout
        let completed = await withTaskGroup(of: Bool.self) { group -> Bool in
            group.addTask {
                process.waitUntilExit()
                return true
            }

            group.addTask {
                try? await Task.sleep(for: .seconds(effectiveTimeout))
                return false
            }

            if let first = await group.next() {
                group.cancelAll()
                return first
            }
            return false
        }

        if !completed {
            process.terminate()
            throw AppleScriptError.timeout(effectiveTimeout)
        }

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()

        let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus != 0 {
            throw AppleScriptError.scriptError(errorOutput.isEmpty ? "Script failed with exit code \(process.terminationStatus)" : errorOutput)
        }

        return output
    }

    /// Execute an AppleScript with string substitutions
    /// - Parameters:
    ///   - template: Script template with {{placeholders}}
    ///   - substitutions: Dictionary of placeholder names to values
    ///   - timeout: Optional timeout
    /// - Returns: Script output
    public func execute(
        template: String,
        substitutions: [String: String],
        timeout: TimeInterval? = nil
    ) async throws -> String {
        var script = template

        for (key, value) in substitutions {
            let sanitized = sanitize(value)
            script = script.replacingOccurrences(of: "{{\(key)}}", with: sanitized)
        }

        return try await execute(script, timeout: timeout)
    }

    // MARK: - Input Sanitization

    /// Sanitize a string for safe use in AppleScript
    /// Escapes backslashes and quotes
    public func sanitize(_ input: String) -> String {
        input
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Build a quoted AppleScript string
    public func quoted(_ input: String) -> String {
        "\"\(sanitize(input))\""
    }

    // MARK: - Application Helpers

    /// Check if an application is running
    public func isAppRunning(_ appName: String) async throws -> Bool {
        let script = """
        tell application "System Events"
            set isRunning to (name of processes) contains "\(sanitize(appName))"
        end tell
        return isRunning
        """
        let result = try await execute(script)
        return result.lowercased() == "true"
    }

    /// Launch an application if not running
    public func launchApp(_ appName: String) async throws {
        let script = """
        tell application "\(sanitize(appName))"
            activate
        end tell
        """
        _ = try await execute(script)
    }

    /// Get application frontmost status
    public func isAppFrontmost(_ appName: String) async throws -> Bool {
        let script = """
        tell application "System Events"
            set frontApp to name of first application process whose frontmost is true
        end tell
        return frontApp is "\(sanitize(appName))"
        """
        let result = try await execute(script)
        return result.lowercased() == "true"
    }
}

// MARK: - Errors

public enum AppleScriptError: Error, LocalizedError {
    case executionFailed(String)
    case scriptError(String)
    case timeout(TimeInterval)
    case applicationNotFound(String)
    case accessDenied(String)

    public var errorDescription: String? {
        switch self {
        case .executionFailed(let reason):
            return "AppleScript execution failed: \(reason)"
        case .scriptError(let message):
            return "AppleScript error: \(message)"
        case .timeout(let seconds):
            return "AppleScript timed out after \(Int(seconds)) seconds"
        case .applicationNotFound(let app):
            return "Application '\(app)' not found"
        case .accessDenied(let app):
            return "Access denied to '\(app)'. Enable in System Settings > Privacy & Security > Automation"
        }
    }
}

// MARK: - Script Builder

/// Helper for building complex AppleScript commands
public struct AppleScriptBuilder {
    private var lines: [String] = []
    private var indentLevel: Int = 0

    public init() {}

    public mutating func tell(_ application: String, block: (inout AppleScriptBuilder) -> Void) {
        lines.append(indent + "tell application \"\(application)\"")
        indentLevel += 1
        block(&self)
        indentLevel -= 1
        lines.append(indent + "end tell")
    }

    public mutating func line(_ code: String) {
        lines.append(indent + code)
    }

    public mutating func returnValue(_ expression: String) {
        lines.append(indent + "return \(expression)")
    }

    public mutating func setVariable(_ name: String, to expression: String) {
        lines.append(indent + "set \(name) to \(expression)")
    }

    public mutating func ifBlock(_ condition: String, then block: (inout AppleScriptBuilder) -> Void) {
        lines.append(indent + "if \(condition) then")
        indentLevel += 1
        block(&self)
        indentLevel -= 1
        lines.append(indent + "end if")
    }

    public var script: String {
        lines.joined(separator: "\n")
    }

    private var indent: String {
        String(repeating: "    ", count: indentLevel)
    }
}
