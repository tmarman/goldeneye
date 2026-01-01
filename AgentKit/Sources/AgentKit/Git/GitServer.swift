import Foundation
import Hummingbird
import Logging

// MARK: - Git Server

/// Git Smart HTTP server for exposing agent workspaces
public struct GitServer<Context: RequestContext>: Sendable {
    private let reposPath: URL
    private let logger = Logger(label: "AgentKit.GitServer")

    public init(reposPath: URL) {
        self.reposPath = reposPath
    }

    /// Configure routes on a Hummingbird router
    public func configure(router: Router<Context>) {
        let repos = router.group("/repos/{name}")

        // Reference discovery
        repos.get("/info/refs") { request, context in
            try await self.handleInfoRefs(request, context)
        }

        // Upload pack (fetch/clone)
        repos.post("/git-upload-pack") { request, context in
            try await self.handleService(request, context, service: "upload-pack")
        }

        // Receive pack (push)
        repos.post("/git-receive-pack") { request, context in
            try await self.handleService(request, context, service: "receive-pack")
        }
    }

    // MARK: - Handlers

    private func handleInfoRefs(_ request: Request, _ context: Context) async throws -> Response {
        guard let name = context.parameters.get("name"),
              let service = request.uri.queryParameters.get("service"),
              service.hasPrefix("git-")
        else {
            throw HTTPError(.badRequest, message: "Invalid request")
        }

        let serviceName = String(service.dropFirst(4))  // "git-upload-pack" → "upload-pack"
        let repoPath = reposPath.appendingPathComponent(name)

        // Verify repo exists
        guard FileManager.default.fileExists(atPath: repoPath.path) else {
            throw HTTPError(.notFound, message: "Repository not found: \(name)")
        }

        // Call git binary
        let result = try await runGit(
            args: [serviceName, "--stateless-rpc", "--advertise-refs", repoPath.path]
        )

        // Build response with service announcement
        var body = Data()
        let announcement = "# service=\(service)\n"
        body.append(pktLine(announcement))
        body.append(pktFlush())
        body.append(result.stdout)

        return Response(
            status: .ok,
            headers: [
                .contentType: "application/x-\(service)-advertisement",
                .cacheControl: "no-cache",
            ],
            body: .init(byteBuffer: .init(data: body))
        )
    }

    private func handleService(
        _ request: Request,
        _ context: Context,
        service: String
    ) async throws -> Response {
        guard let name = context.parameters.get("name") else {
            throw HTTPError(.badRequest, message: "Missing repository name")
        }

        let repoPath = reposPath.appendingPathComponent(name)

        // Verify repo exists
        guard FileManager.default.fileExists(atPath: repoPath.path) else {
            throw HTTPError(.notFound, message: "Repository not found: \(name)")
        }

        let body = try await request.body.collect(upTo: .max)

        // Pipe request body to git binary
        let result = try await runGit(
            args: [service, "--stateless-rpc", repoPath.path],
            input: Data(buffer: body)
        )

        return Response(
            status: .ok,
            headers: [
                .contentType: "application/x-git-\(service)-result",
                .cacheControl: "no-cache",
            ],
            body: .init(byteBuffer: .init(data: result.stdout))
        )
    }

    // MARK: - Packet Line Helpers

    private func pktLine(_ str: String) -> Data {
        let bytes = str.utf8
        let length = bytes.count + 4
        let hex = String(format: "%04x", length)
        return Data((hex + str).utf8)
    }

    private func pktFlush() -> Data {
        Data("0000".utf8)
    }

    // MARK: - Git Process

    private func runGit(args: [String], input: Data? = nil) async throws -> (stdout: Data, stderr: Data)
    {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()

        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe

        try process.run()

        if let input = input {
            stdinPipe.fileHandleForWriting.write(input)
        }
        stdinPipe.fileHandleForWriting.closeFile()

        process.waitUntilExit()

        return (
            stdout: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
            stderr: stderrPipe.fileHandleForReading.readDataToEndOfFile()
        )
    }
}

// MARK: - Packet Line Encoding

public struct PacketLine {
    /// Encode a string as a packet line
    public static func encode(_ string: String) -> Data {
        let bytes = string.utf8
        let length = bytes.count + 4
        let hex = String(format: "%04x", length)
        return Data((hex + string).utf8)
    }

    /// Flush packet
    public static var flush: Data {
        Data("0000".utf8)
    }

    /// Delimiter packet
    public static var delimiter: Data {
        Data("0001".utf8)
    }

    /// Decode packet lines from data
    public static func decode(_ data: Data) -> [String] {
        var result: [String] = []
        var offset = 0

        while offset + 4 <= data.count {
            let lengthHex = String(data: data[offset..<offset + 4], encoding: .utf8) ?? "0000"
            guard let length = Int(lengthHex, radix: 16), length > 0 else {
                // Flush packet
                offset += 4
                continue
            }

            let contentLength = length - 4
            guard offset + 4 + contentLength <= data.count else { break }

            let content = String(
                data: data[offset + 4..<offset + 4 + contentLength],
                encoding: .utf8
            ) ?? ""
            result.append(content.trimmingCharacters(in: .newlines))

            offset += length
        }

        return result
    }
}
