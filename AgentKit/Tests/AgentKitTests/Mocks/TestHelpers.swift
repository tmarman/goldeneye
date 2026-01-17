import Foundation
@testable import AgentKit

// MARK: - Test Helpers

/// Creates a ToolContext for testing
public func makeTestContext(workingDirectory: URL? = nil) -> ToolContext {
    let dir = workingDirectory ?? FileManager.default.temporaryDirectory
    let session = Session(workingDirectory: dir)
    return ToolContext(session: session, workingDirectory: dir)
}

/// Creates a ToolInput from a dictionary
public func makeInput(_ dict: [String: Any]) -> ToolInput {
    let params = dict.mapValues { AnyCodable($0) }
    return ToolInput(parameters: params)
}

/// Creates a simple text message
public func makeMessage(role: Message.Role, text: String) -> Message {
    Message(role: role, content: .text(text))
}

/// Creates an AgentTask with a text message
public func makeTask(message: String, id: String? = nil) -> AgentTask {
    AgentTask(
        id: id.map { TaskID($0) } ?? TaskID(),
        message: makeMessage(role: .user, text: message)
    )
}

// MARK: - Temporary File Helpers

/// Creates a temporary file with content and returns its URL
public func createTempFile(content: String, extension ext: String = "txt") throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory
    let fileName = UUID().uuidString + ".\(ext)"
    let fileURL = tempDir.appendingPathComponent(fileName)
    try content.write(to: fileURL, atomically: true, encoding: .utf8)
    return fileURL
}

/// Creates a temporary directory and returns its URL
public func createTempDirectory() throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory
    let dirName = UUID().uuidString
    let dirURL = tempDir.appendingPathComponent(dirName)
    try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
    return dirURL
}

/// Cleans up a temporary file or directory
public func cleanup(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

// MARK: - Async Test Helpers

/// Collects all events from an async stream into an array
public func collectEvents<T>(_ stream: AsyncThrowingStream<T, Error>) async throws -> [T] {
    var events: [T] = []
    for try await event in stream {
        events.append(event)
    }
    return events
}

/// Waits for a condition with timeout
public func waitFor(
    timeout: Duration = .seconds(5),
    condition: @escaping () async -> Bool
) async throws -> Bool {
    let deadline = Date().addingTimeInterval(timeout.seconds)
    while Date() < deadline {
        if await condition() {
            return true
        }
        try await Task.sleep(for: .milliseconds(50))
    }
    return false
}

extension Duration {
    var seconds: TimeInterval {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}
