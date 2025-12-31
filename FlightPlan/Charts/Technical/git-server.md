# Git Server Integration

AgentKit exposes agent workspaces as Git repositories, enabling version control, inspection, and collaboration using standard Git tooling.

## Why Git?

| Benefit | Description |
|---------|-------------|
| **Version History** | Every agent action becomes a commit |
| **Branching** | Fork tasks, explore alternatives |
| **Inspection** | `git diff` to see what changed |
| **Recovery** | `git revert` to undo agent mistakes |
| **Sync** | Standard push/pull for backup |
| **Tooling** | Works with GitHub, VS Code, etc. |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    AgentKit Server                           │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                  Hummingbird Router                     │ │
│  │                                                         │ │
│  │  /a2a/*                    → A2A Protocol               │ │
│  │  /repos/:name/info/refs    → Git ref discovery          │ │
│  │  /repos/:name/git-*        → Git pack protocol          │ │
│  │  /.well-known/agent.json   → Agent Card                 │ │
│  └────────────────────────────────────────────────────────┘ │
│                           │                                  │
│                           ▼                                  │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                   Git Backend                           │ │
│  │                                                         │ │
│  │  Option A: Shell out to git binaries                   │ │
│  │  Option B: libgit2 via SwiftGitX (client ops only)     │ │
│  └────────────────────────────────────────────────────────┘ │
│                           │                                  │
│                           ▼                                  │
│  ┌────────────────────────────────────────────────────────┐ │
│  │              ~/AgentKit/repos/                          │ │
│  │                                                         │ │
│  │  agent-research/    (bare git repo)                    │ │
│  │  agent-coding/      (bare git repo)                    │ │
│  │  agent-planning/    (bare git repo)                    │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

---

## Git Smart HTTP Protocol

### Endpoints Required

| Method | Endpoint | Purpose | Content-Type |
|--------|----------|---------|--------------|
| GET | `/repos/:name/info/refs?service=git-upload-pack` | Ref discovery (fetch) | `application/x-git-upload-pack-advertisement` |
| GET | `/repos/:name/info/refs?service=git-receive-pack` | Ref discovery (push) | `application/x-git-receive-pack-advertisement` |
| POST | `/repos/:name/git-upload-pack` | Fetch pack data | `application/x-git-upload-pack-result` |
| POST | `/repos/:name/git-receive-pack` | Push pack data | `application/x-git-receive-pack-result` |

### Packet-Line Format

Git uses a simple framing format:
```
<4-byte hex length><data><LF>
```

Examples:
```
0032want 0a53e9ddeaddad63ad106860237bbf53411d11a7\n
0000                                              # flush packet (end)
```

Length includes the 4 bytes for the length itself.

### Reference Discovery Response

```
001e# service=git-upload-pack\n
0000
004895dcfa3633004da0049d3d0fa03f80589cbcaf31 refs/heads/main\0multi_ack side-band-64k\n
003c2cb58b79488a98d2721cea644875a8dd0026b115 refs/tags/v1.0\n
0000
```

---

## Implementation: Shell to Git Binaries

The simplest approach — proxy HTTP to the git binaries which handle all pack protocol complexity.

### Swift Implementation

```swift
import Hummingbird
import Foundation

struct GitServer {
    let reposPath: URL

    func configure(router: Router<some RequestContext>) {
        let git = router.group("/repos/{name}")

        // Reference discovery
        git.get("/info/refs") { req, context in
            try await handleInfoRefs(req, context)
        }

        // Upload pack (fetch/clone)
        git.post("/git-upload-pack") { req, context in
            try await handleService(req, context, service: "upload-pack")
        }

        // Receive pack (push)
        git.post("/git-receive-pack") { req, context in
            try await handleService(req, context, service: "receive-pack")
        }
    }

    func handleInfoRefs(_ req: Request, _ context: some RequestContext) async throws -> Response {
        guard let name = context.parameters.get("name"),
              let service = req.uri.queryParameters.get("service"),
              service.hasPrefix("git-") else {
            throw HTTPError(.badRequest)
        }

        let serviceName = String(service.dropFirst(4))  // "git-upload-pack" → "upload-pack"
        let repoPath = reposPath.appendingPathComponent(name)

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
                .cacheControl: "no-cache"
            ],
            body: .init(data: body)
        )
    }

    func handleService(_ req: Request, _ context: some RequestContext, service: String) async throws -> Response {
        guard let name = context.parameters.get("name") else {
            throw HTTPError(.badRequest)
        }

        let repoPath = reposPath.appendingPathComponent(name)
        let body = try await req.body.collect(upTo: .max)

        // Pipe request body to git binary
        let result = try await runGit(
            args: [service, "--stateless-rpc", repoPath.path],
            input: body
        )

        return Response(
            status: .ok,
            headers: [
                .contentType: "application/x-git-\(service)-result",
                .cacheControl: "no-cache"
            ],
            body: .init(data: result.stdout)
        )
    }

    // MARK: - Helpers

    func pktLine(_ str: String) -> Data {
        let bytes = str.utf8
        let length = bytes.count + 4
        let hex = String(format: "%04x", length)
        return Data((hex + str).utf8)
    }

    func pktFlush() -> Data {
        return Data("0000".utf8)
    }

    func runGit(args: [String], input: Data? = nil) async throws -> (stdout: Data, stderr: Data) {
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

        if let input {
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
```

---

## Agent Integration

### Workspace as Git Repo

Each agent session has a working directory that's a Git repo:

```swift
actor AgentSession {
    let id: SessionID
    let workingDirectory: URL  // Git working tree
    let gitRepo: URL           // .git directory or bare repo

    func commit(message: String) async throws {
        try await runGit(["add", "-A"], cwd: workingDirectory)
        try await runGit(["commit", "-m", message], cwd: workingDirectory)
    }

    func checkpoint(_ description: String) async throws {
        // Called after each tool execution
        try await commit(message: "[\(toolName)] \(description)")
    }
}
```

### Automatic Commits

```swift
// In AgentLoop
func executeToolAndCommit(_ tool: Tool, input: ToolInput) async throws -> ToolOutput {
    let output = try await tool.execute(input, context: toolContext)

    // Commit changes
    try await session.checkpoint("\(tool.name): \(input.summary)")

    return output
}
```

Commit history looks like:
```
* [Write] Created report.md
* [Bash] Ran analysis script
* [Read] Read input data
* Initial task: Analyze sales data
```

---

## Usage Examples

### Clone Agent Workspace

```bash
# Clone to inspect
git clone http://localhost:8080/repos/agent-research ./research-agent
cd research-agent
git log --oneline
```

### Watch Agent Work (Real-time)

```bash
# In one terminal
watch -n 1 'git fetch && git log --oneline -10'
```

### Push Files to Agent

```bash
# Add context for agent
echo "Focus on cost analysis" > instructions.md
git add .
git commit -m "Added instructions"
git push
```

### Revert Agent Mistake

```bash
# Agent broke something
git revert HEAD
git push
```

### Branch for Exploration

```bash
# Fork for alternative approach
git checkout -b alternative-approach
# Make changes...
git push -u origin alternative-approach
```

---

## Repository Lifecycle

### Creation

```swift
func createAgentRepo(name: String) async throws -> URL {
    let repoPath = reposPath.appendingPathComponent(name)

    // Create bare repo for remote access
    try await runGit(["init", "--bare", repoPath.path])

    // Or working tree if agent needs to read/write
    try await runGit(["init", repoPath.path])

    return repoPath
}
```

### Agent Working Directory

Two options:

**Option A: Agent works in repo directly**
```
~/AgentKit/repos/agent-1/
├── .git/
├── task.md
├── outputs/
└── ...
```

**Option B: Separate bare repo + working tree**
```
~/AgentKit/repos/agent-1.git    # Bare repo (for HTTP access)
~/AgentKit/work/agent-1/        # Working tree (for agent)
```

---

## Security Considerations

### V1 (Local Only)
- No authentication (local network only)
- All repos readable/writable

### Future
- HTTP Basic Auth
- Per-repo permissions
- Read-only mode for inspection
- Signed commits for audit trail

---

## Open Questions

1. **Bare vs working tree** — Does agent work in the repo directly?
2. **Commit granularity** — Every tool call? Batched?
3. **Large files** — Git LFS for artifacts?
4. **Branches** — One branch per task? Per session?

---

## References

- [Git HTTP Protocol](https://git-scm.com/docs/http-protocol)
- [Git Smart HTTP](https://git-scm.com/book/en/v2/Git-on-the-Server-Smart-HTTP)
- [Pack Protocol](https://git-scm.com/docs/pack-protocol)
- [SwiftGitX](https://github.com/ibrahimcetin/SwiftGitX) (client-side only)
