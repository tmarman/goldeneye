# Getting Started with AgentKit Development

## Prerequisites

- macOS 14+ (Sonoma or later)
- Xcode 15+
- Swift 5.9+
- Apple Developer account (for iCloud entitlements)

## Project Setup

### 1. Clone Repository

```bash
git clone https://github.com/[org]/agentkit.git
cd agentkit
```

### 2. Open in Xcode

```bash
open AgentKit.xcworkspace
```

### 3. Configure Signing

1. Select the AgentKit target
2. Set your development team
3. Enable iCloud capability
4. Select iCloud container

### 4. Build & Run

```bash
# Or use Xcode's build button
swift build
```

## Project Structure

```
agentkit/
├── Sources/
│   ├── AgentKit/           # Core framework
│   │   ├── Agent/          # Agent runtime
│   │   ├── Tools/          # Tool system
│   │   ├── Context/        # Context management
│   │   ├── Storage/        # iCloud persistence
│   │   └── A2A/            # Protocol implementation
│   └── AgentKitUI/         # SwiftUI components
├── Tests/
│   ├── AgentKitTests/
│   └── IntegrationTests/
├── Examples/
│   ├── ResearchAgent/      # Example: research assistant
│   └── TripPlanner/        # Example: trip planning
└── FlightPlan/             # Project documentation
```

## Quick Start: Your First Agent

```swift
import AgentKit

// 1. Define a simple agent
struct GreeterAgent: Agent {
    let id = AgentID()

    @Tool("Get current time")
    func currentTime() -> String {
        Date().formatted()
    }

    func greet(name: String) async throws -> String {
        let time = currentTime()
        return "Hello \(name)! The time is \(time)."
    }
}

// 2. Run it
let agent = GreeterAgent()
let greeting = try await agent.greet(name: "World")
print(greeting)
```

## Development Workflow

1. **Read the architecture** → `FlightPlan/Charts/Technical/`
2. **Pick a Flight** → `FlightPlan/Flight/Backlog/`
3. **Move to Active** → `FlightPlan/Flight/Active/`
4. **Implement and test**
5. **Mark complete** → `FlightPlan/Flight/Completed/`

## Running Tests

```bash
swift test

# Or specific test
swift test --filter AgentKitTests.AgentCoreTests
```

## Common Tasks

### Adding a New Tool

See `FlightPlan/Charts/Technical/swift-patterns.md` for the `@Tool` macro pattern.

### Debugging Agent Execution

```swift
// Enable verbose logging
AgentKit.logLevel = .debug

// Or use structured logging
agent.events.sink { event in
    print("Agent event: \(event)")
}
```

### Testing with Mock LLM

```swift
let mockLLM = MockLLMProvider(responses: [
    "What is 2+2?" : "4"
])
let agent = TestAgent(llm: mockLLM)
```

## Next Steps

- Read `FlightPlan/Mission/Active/M001-foundation.md` for current priorities
- Check `FlightPlan/Flight/Backlog/` for available work
- Review open questions in Flight documents
