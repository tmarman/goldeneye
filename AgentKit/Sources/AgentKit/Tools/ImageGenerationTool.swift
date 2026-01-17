import Foundation

#if canImport(Vision)
import Vision
#endif

#if os(macOS)
import AppKit
#endif

// MARK: - Image Generation Tool

/// Tool for generating images using Apple's Image Playground framework.
///
/// This tool allows agents to generate images from text descriptions using
/// Apple Intelligence's on-device image generation capabilities.
///
/// Requires macOS 26+ / iOS 26+ with Apple Intelligence enabled.
/// Currently returns a placeholder until ImagePlayground API is available.
public struct ImageGenerationTool: Tool {
    public let name = "generate_image"
    public let description = """
        Generate an image from a text description using Apple Intelligence.
        Supports styles: animation, illustration.
        Returns the path to the generated image file.
        Note: Requires macOS 26+ with Apple Intelligence.
        """

    public let inputSchema = ToolSchema(
        properties: [
            "prompt": .init(
                type: "string",
                description: "Text description of the image to generate"
            ),
            "style": .init(
                type: "string",
                description: "Visual style: animation or illustration",
                enumValues: ["animation", "illustration"]
            ),
            "outputPath": .init(
                type: "string",
                description: "File path to save the generated image (PNG format)"
            )
        ],
        required: ["prompt"]
    )

    public let requiresApproval = false
    public let riskLevel = RiskLevel.low

    public init() {}

    public func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        // ImagePlayground framework requires macOS 26+ and isn't available yet in SDK
        // This is a placeholder that will be updated when the API becomes available
        return .error(
            "Image generation requires macOS 26+ with Apple Intelligence enabled. " +
            "The ImagePlayground framework will be available in a future SDK release."
        )
    }

    public func describeAction(_ input: ToolInput) -> String {
        if let prompt = input.get("prompt", as: String.self) {
            let truncated = prompt.prefix(50)
            return "Generate image: \"\(truncated)\(prompt.count > 50 ? "..." : "")\""
        }
        return "Generate image from prompt"
    }
}

// MARK: - Image Analysis Tool

/// Tool for analyzing images using Apple's Vision framework.
///
/// Can extract text (OCR) from images.
public struct ImageAnalysisTool: Tool {
    public let name = "analyze_image"
    public let description = """
        Analyze an image to extract text (OCR).
        Returns extracted text content from the image.
        """

    public let inputSchema = ToolSchema(
        properties: [
            "imagePath": .init(
                type: "string",
                description: "Path to the image file to analyze"
            ),
            "analysis": .init(
                type: "string",
                description: "Type of analysis: text (OCR)",
                enumValues: ["text"]
            )
        ],
        required: ["imagePath"]
    )

    public let requiresApproval = false
    public let riskLevel = RiskLevel.low

    public init() {}

    public func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        let imagePath: String = try input.require("imagePath")

        guard FileManager.default.fileExists(atPath: imagePath) else {
            return .error("Image file not found: \(imagePath)")
        }

        let imageURL = URL(fileURLWithPath: imagePath)

        #if os(macOS)
        if let text = try extractText(from: imageURL) {
            return .success("**Extracted Text:**\n\(text)")
        } else {
            return .success("No text found in image")
        }
        #else
        return .error("Image analysis requires macOS")
        #endif
    }

    #if os(macOS)
    private func extractText(from url: URL) throws -> String? {
        guard let imageData = try? Data(contentsOf: url),
              let nsImage = NSImage(data: imageData),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        var extractedText: String?

        let request = VNRecognizeTextRequest { request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            let text = observations.compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
            extractedText = text.isEmpty ? nil : text
        }
        request.recognitionLevel = .accurate

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        return extractedText
    }
    #endif

    public func describeAction(_ input: ToolInput) -> String {
        if let path = input.get("imagePath", as: String.self) {
            let filename = URL(fileURLWithPath: path).lastPathComponent
            return "Analyze image: \(filename)"
        }
        return "Analyze image"
    }
}

// MARK: - Convenience Registration

extension ToolRegistry {
    /// Register all image-related tools
    public func registerImageTools() {
        register(ImageGenerationTool())
        register(ImageAnalysisTool())
    }
}
