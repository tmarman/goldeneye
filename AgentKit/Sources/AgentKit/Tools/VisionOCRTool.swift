//
//  VisionOCRTool.swift
//  AgentKit
//
//  MCP tool for extracting text from images using Apple Vision OCR.
//  Supports screenshots, photos, scanned documents, and more.
//

import Foundation
#if canImport(Vision)
import Vision
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Vision OCR Tool

/// Extract text from images using Vision framework OCR
public struct VisionOCRTool: Tool {
    public let name = "ocr_extract_text"
    public let description = """
        Extract text from images using Apple Vision OCR.
        Supports:
        - Screenshots (.png, .jpg, .jpeg)
        - Photos with text
        - Scanned documents
        - HEIC images from iPhone
        Uses on-device ML for privacy - no data leaves your Mac.
        Returns all recognized text with confidence scores.
        """

    public var inputSchema: ToolSchema {
        ToolSchema(
            properties: [
                "path": .init(
                    type: "string",
                    description: "Path to the image file"
                ),
                "language": .init(
                    type: "string",
                    description: "Primary language for recognition (default: en-US)",
                    enumValues: ["en-US", "zh-Hans", "zh-Hant", "ja", "ko", "de", "fr", "es", "pt", "it"]
                ),
                "min_confidence": .init(
                    type: "number",
                    description: "Minimum confidence threshold 0.0-1.0 (default: 0.5)"
                ),
                "accurate_mode": .init(
                    type: "boolean",
                    description: "Use accurate (slower) recognition instead of fast (default: true)"
                )
            ],
            required: ["path"]
        )
    }

    public init() {}

    public func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        #if canImport(Vision) && canImport(AppKit)
        let path = try input.require("path", as: String.self)
        let language = input.get("language", as: String.self) ?? "en-US"
        let minConfidence = input.get("min_confidence", as: Double.self) ?? 0.5
        let accurateMode = input.get("accurate_mode", as: Bool.self) ?? true

        let url = URL(fileURLWithPath: path)

        guard FileManager.default.fileExists(atPath: path) else {
            return .error("File not found: \(path)")
        }

        do {
            let result = try await performOCR(
                on: url,
                language: language,
                minConfidence: Float(minConfidence),
                accurateMode: accurateMode
            )
            return .success(result)
        } catch {
            return .error("OCR failed: \(error.localizedDescription)")
        }
        #else
        return .error("Vision framework not available on this platform")
        #endif
    }

    public func describeAction(_ input: ToolInput) -> String {
        if let path = input.get("path", as: String.self) {
            let name = (path as NSString).lastPathComponent
            return "Extract text from: \(name)"
        }
        return "Extract text from image"
    }

    #if canImport(Vision) && canImport(AppKit)
    // MARK: - OCR Implementation

    private func performOCR(
        on url: URL,
        language: String,
        minConfidence: Float,
        accurateMode: Bool
    ) async throws -> String {
        // Load image
        guard let image = NSImage(contentsOf: url) else {
            throw VisionOCRError.cannotLoadImage
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw VisionOCRError.cannotCreateCGImage
        }

        // Create request handler
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        // Create text recognition request
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = accurateMode ? .accurate : .fast
        request.recognitionLanguages = [language]
        request.usesLanguageCorrection = true

        // Perform request
        try handler.perform([request])

        guard let observations = request.results else {
            return "[No text found in image]"
        }

        // Process results
        var output = "=== OCR Results ===\n"
        output += "Image: \(url.lastPathComponent)\n"
        output += "Recognition: \(accurateMode ? "Accurate" : "Fast")\n"
        output += "Language: \(language)\n\n"

        var allText: [String] = []
        var highConfidenceText: [String] = []

        for observation in observations {
            guard let topCandidate = observation.topCandidates(1).first else { continue }

            let confidence = topCandidate.confidence
            let text = topCandidate.string

            if confidence >= minConfidence {
                allText.append(text)

                if confidence >= 0.8 {
                    highConfidenceText.append(text)
                }
            }
        }

        if allText.isEmpty {
            output += "[No text found with confidence >= \(minConfidence)]\n"
        } else {
            output += "--- Extracted Text ---\n"
            output += allText.joined(separator: "\n")
            output += "\n\n"
            output += "--- Statistics ---\n"
            output += "Total lines: \(allText.count)\n"
            output += "High confidence lines (>=0.8): \(highConfidenceText.count)\n"
        }

        return output
    }
    #endif
}

// MARK: - Batch OCR Tool

/// Extract text from multiple images at once
public struct BatchVisionOCRTool: Tool {
    public let name = "ocr_extract_batch"
    public let description = """
        Extract text from multiple images in a directory.
        Useful for processing many screenshots or photos at once.
        Returns combined text with file separators.
        """

    public var inputSchema: ToolSchema {
        ToolSchema(
            properties: [
                "directory": .init(
                    type: "string",
                    description: "Path to directory containing images"
                ),
                "extensions": .init(
                    type: "string",
                    description: "Comma-separated file extensions (default: png,jpg,jpeg,heic)"
                ),
                "recursive": .init(
                    type: "boolean",
                    description: "Search subdirectories (default: false)"
                ),
                "max_files": .init(
                    type: "integer",
                    description: "Maximum number of files to process (default: 10)"
                )
            ],
            required: ["directory"]
        )
    }

    public init() {}

    public func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        let directory = try input.require("directory", as: String.self)
        let extensionsStr = input.get("extensions", as: String.self) ?? "png,jpg,jpeg,heic,webp,tiff"
        let recursive = input.get("recursive", as: Bool.self) ?? false
        let maxFiles = input.get("max_files", as: Int.self) ?? 10

        let extensions = Set(extensionsStr.components(separatedBy: ",").map {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        })

        let directoryURL = URL(fileURLWithPath: directory)

        guard FileManager.default.fileExists(atPath: directory) else {
            return .error("Directory not found: \(directory)")
        }

        // Find matching files
        let enumerator: FileManager.DirectoryEnumerator?
        if recursive {
            enumerator = FileManager.default.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        } else {
            enumerator = FileManager.default.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )
        }

        var files: [(url: URL, date: Date)] = []
        while let url = enumerator?.nextObject() as? URL {
            let ext = url.pathExtension.lowercased()
            if extensions.contains(ext) {
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                files.append((url, date))
            }
        }

        // Sort by modification date (newest first) and take max
        files.sort { $0.date > $1.date }
        let filesToProcess = Array(files.prefix(maxFiles))

        if filesToProcess.isEmpty {
            return .success("No matching images found in: \(directory)")
        }

        // Process each file
        let ocrTool = VisionOCRTool()
        var results: [String] = []
        var successCount = 0

        for (url, _) in filesToProcess {
            let ocrInput = ToolInput(parameters: [
                "path": AnyCodable(url.path),
                "accurate_mode": AnyCodable(false) // Use fast mode for batch
            ])

            let output = try await ocrTool.execute(ocrInput, context: context)

            if !output.isError {
                successCount += 1
                results.append("=== \(url.lastPathComponent) ===")
                results.append(output.content)
                results.append("")
            }
        }

        return .success("Processed \(successCount)/\(filesToProcess.count) images:\n\n\(results.joined(separator: "\n"))")
    }

    public func describeAction(_ input: ToolInput) -> String {
        if let dir = input.get("directory", as: String.self) {
            return "OCR images in: \(dir)"
        }
        return "OCR images in directory"
    }
}

// MARK: - Screenshot Text Tool

/// Specialized tool for extracting text from recent screenshots
public struct ScreenshotTextTool: Tool {
    public let name = "ocr_recent_screenshots"
    public let description = """
        Extract text from recent screenshots on your Desktop.
        Automatically finds the most recent screenshots and extracts their text.
        Useful for quickly capturing information from screenshots.
        """

    public var inputSchema: ToolSchema {
        ToolSchema(
            properties: [
                "count": .init(
                    type: "integer",
                    description: "Number of recent screenshots to process (default: 3)"
                ),
                "screenshot_directory": .init(
                    type: "string",
                    description: "Directory containing screenshots (default: ~/Desktop)"
                )
            ],
            required: []
        )
    }

    public init() {}

    public func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        let count = input.get("count", as: Int.self) ?? 3
        let screenshotDir = input.get("screenshot_directory", as: String.self)
            ?? (NSHomeDirectory() as NSString).appendingPathComponent("Desktop")

        let directoryURL = URL(fileURLWithPath: screenshotDir)

        // Find screenshot files (Screen Shot*.png or Screenshot*.png)
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return .error("Cannot access directory: \(screenshotDir)")
        }

        var screenshots: [(url: URL, date: Date)] = []

        while let url = enumerator.nextObject() as? URL {
            let name = url.lastPathComponent.lowercased()
            let ext = url.pathExtension.lowercased()

            // Match common screenshot naming patterns
            if ext == "png" && (
                name.hasPrefix("screen shot") ||
                name.hasPrefix("screenshot") ||
                name.hasPrefix("cleanshot") ||
                name.contains("screenshot")
            ) {
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                screenshots.append((url, date))
            }
        }

        if screenshots.isEmpty {
            return .success("No screenshots found in: \(screenshotDir)")
        }

        // Sort by date (newest first)
        screenshots.sort { $0.date > $1.date }
        let recentScreenshots = Array(screenshots.prefix(count))

        // Extract text from each
        let ocrTool = VisionOCRTool()
        var results: [String] = []

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short

        for (url, date) in recentScreenshots {
            let ocrInput = ToolInput(parameters: [
                "path": AnyCodable(url.path)
            ])

            let output = try await ocrTool.execute(ocrInput, context: context)

            results.append("=== \(url.lastPathComponent) ===")
            results.append("Taken: \(dateFormatter.string(from: date))")
            results.append("")
            results.append(output.content)
            results.append("")
        }

        return .success("Found \(recentScreenshots.count) recent screenshots:\n\n\(results.joined(separator: "\n"))")
    }

    public func describeAction(_ input: ToolInput) -> String {
        let count = input.get("count", as: Int.self) ?? 3
        return "Extract text from \(count) recent screenshots"
    }
}

// MARK: - Errors

public enum VisionOCRError: Error, LocalizedError {
    case cannotLoadImage
    case cannotCreateCGImage
    case ocrFailed(String)
    case unsupportedPlatform

    public var errorDescription: String? {
        switch self {
        case .cannotLoadImage:
            return "Cannot load image file"
        case .cannotCreateCGImage:
            return "Cannot create CGImage from file"
        case .ocrFailed(let reason):
            return "OCR failed: \(reason)"
        case .unsupportedPlatform:
            return "Vision OCR not available on this platform"
        }
    }
}
