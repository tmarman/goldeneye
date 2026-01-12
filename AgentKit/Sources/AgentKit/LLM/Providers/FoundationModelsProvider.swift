import Foundation

// Conditional import for Foundation Models (macOS 26+)
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Apple Foundation Models Provider

/// LLM provider for Apple Foundation Models framework.
///
/// Foundation Models provides access to the on-device LLM powering Apple Intelligence.
/// Available on macOS 26+, iOS 26+, iPadOS 26+, visionOS 3+.
///
/// Key features:
/// - **On-device inference**: Fast, private, no network required
/// - **Private Cloud Compute**: Larger models with E2E encryption
/// - **Streaming**: Real-time token generation
/// - **Tool calling**: Function calling support
///
/// When Foundation Models is not available, this provider gracefully returns
/// an unavailable error, allowing fallback to other providers like Ollama.
///
/// References:
/// - https://developer.apple.com/documentation/FoundationModels
/// - WWDC25: Meet the Foundation Models framework
public actor FoundationModelsProvider: LLMProvider {
    public let id = "apple-foundation-models"
    public let name = "Apple Intelligence"
    public let supportsToolCalling = true
    public let supportsStreaming = true

    private let systemInstructions: String?

    public init(instructions: String? = nil) {
        self.systemInstructions = instructions
    }

    // MARK: - LLMProvider Protocol

    public func complete(
        _ messages: [Message],
        tools: [ToolDefinition],
        options: CompletionOptions
    ) async throws -> AsyncThrowingStream<LLMEvent, Error> {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            return try await completeWithFoundationModels(messages, tools: tools, options: options)
        } else {
            return unavailableStream()
        }
        #else
        return unavailableStream()
        #endif
    }

    public func isAvailable() async -> Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            return true
        }
        #endif
        return false
    }

    // MARK: - Foundation Models Implementation

    #if canImport(FoundationModels)
    @available(macOS 26.0, iOS 26.0, *)
    private func completeWithFoundationModels(
        _ messages: [Message],
        tools: [ToolDefinition],
        options: CompletionOptions
    ) async throws -> AsyncThrowingStream<LLMEvent, Error> {
        // Build prompt from messages
        let prompt = messages.compactMap { msg -> String? in
            switch msg.role {
            case .system: return nil  // Could use Instructions API
            case .user: return "User: \(msg.textContent)"
            case .assistant: return "Assistant: \(msg.textContent)"
            }
        }.joined(separator: "\n\n")

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let session = LanguageModelSession()

                    if options.stream {
                        // Streaming response
                        let stream = session.streamResponse(to: prompt)
                        var accumulated = ""

                        for try await partial in stream {
                            let content = String(partial.content)
                            let delta = String(content.dropFirst(accumulated.count))
                            if !delta.isEmpty {
                                continuation.yield(.textDelta(delta))
                                accumulated = content
                            }
                        }
                    } else {
                        // Non-streaming
                        let response = try await session.respond(to: prompt)
                        continuation.yield(.text(response.content))
                    }

                    continuation.yield(.done)
                    continuation.finish()

                } catch {
                    continuation.yield(.error(.unknown(error.localizedDescription)))
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    #endif

    private func unavailableStream() -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                continuation.yield(.error(.providerUnavailable(
                    "Foundation Models not available. " +
                    "Requires macOS 26+ / iOS 26+ with Apple Intelligence enabled. " +
                    "Use OllamaProvider or LMStudioProvider for local inference."
                )))
                continuation.finish()
            }
        }
    }

    // MARK: - Eligibility Check

    /// Check device eligibility for Apple Intelligence
    public func checkEligibility() async -> EligibilityResult {
        var issues: [String] = []

        #if os(macOS)
        if !Self.isAppleSiliconMac() {
            issues.append("Requires Apple Silicon (M1 or later)")
        }
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        if osVersion.majorVersion < 26 {
            issues.append("Requires macOS 26 or later (current: \(osVersion.majorVersion).\(osVersion.minorVersion))")
        }
        #elseif os(iOS)
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        if osVersion.majorVersion < 26 {
            issues.append("Requires iOS 26 or later")
        }
        #else
        issues.append("Foundation Models requires macOS 26+ or iOS 26+")
        #endif

        return issues.isEmpty ? .eligible : .ineligible(reasons: issues)
    }

    public enum EligibilityResult: Sendable {
        case eligible
        case ineligible(reasons: [String])

        public var isEligible: Bool {
            if case .eligible = self { return true }
            return false
        }
    }

    // MARK: - Helpers

    #if os(macOS)
    private static func isAppleSiliconMac() -> Bool {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        guard size > 0 else { return false }

        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)

        let machineString = String(
            decoding: machine.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) },
            as: UTF8.self
        )
        return machineString.hasPrefix("arm64")
    }
    #endif
}

// MARK: - Instructions Builder

/// DSL for building Foundation Models instructions
public struct InstructionsBuilder {
    private var components: [InstructionComponent] = []

    public init(@InstructionBuilder _ build: () -> [InstructionComponent]) {
        self.components = build()
    }

    public func build() -> String {
        components.map { $0.render() }.joined(separator: "\n\n")
    }
}

public protocol InstructionComponent {
    func render() -> String
}

public struct InstructionContext: InstructionComponent {
    let text: String
    public init(_ text: String) { self.text = text }
    public func render() -> String { text }
}

public struct InstructionRule: InstructionComponent {
    let text: String
    public init(_ text: String) { self.text = text }
    public func render() -> String { "- \(text)" }
}

public struct InstructionExample: InstructionComponent {
    let input: String
    let output: String
    public init(input: String, output: String) {
        self.input = input
        self.output = output
    }
    public func render() -> String {
        "Example:\nQ: \(input)\nA: \(output)"
    }
}

@resultBuilder
public struct InstructionBuilder {
    public static func buildBlock(_ components: InstructionComponent...) -> [InstructionComponent] {
        components
    }
}
