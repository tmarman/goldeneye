//
//  SpeechTranscriptionTool.swift
//  AgentKit
//
//  MCP tool for transcribing audio files using Apple Speech framework.
//  On-device speech recognition for privacy - no data leaves your Mac.
//

import Foundation
#if canImport(Speech)
import Speech
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif

// MARK: - Speech Transcription Tool

/// Transcribe audio files using Apple Speech framework
public struct SpeechTranscriptionTool: Tool {
    public let name = "transcribe_audio"
    public let description = """
        Transcribe speech from audio files using Apple's on-device speech recognition.
        Supports:
        - WAV, MP3, M4A, CAF, AIFF audio files
        - Multiple languages (English, Spanish, French, German, Chinese, Japanese, etc.)
        - On-device processing for privacy - no data sent to cloud
        Returns transcribed text with timing information.
        """

    public var inputSchema: ToolSchema {
        ToolSchema(
            properties: [
                "path": .init(
                    type: "string",
                    description: "Path to the audio file"
                ),
                "language": .init(
                    type: "string",
                    description: "Language code for recognition (default: en-US)",
                    enumValues: ["en-US", "en-GB", "es-ES", "es-MX", "fr-FR", "de-DE", "it-IT", "pt-BR", "zh-CN", "zh-TW", "ja-JP", "ko-KR"]
                ),
                "include_timing": .init(
                    type: "boolean",
                    description: "Include word-level timing information (default: false)"
                ),
                "include_alternatives": .init(
                    type: "boolean",
                    description: "Include alternative transcriptions (default: false)"
                )
            ],
            required: ["path"]
        )
    }

    public init() {}

    public func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        #if canImport(Speech)
        let path = try input.require("path", as: String.self)
        let language = input.get("language", as: String.self) ?? "en-US"
        let includeTiming = input.get("include_timing", as: Bool.self) ?? false
        let includeAlternatives = input.get("include_alternatives", as: Bool.self) ?? false

        let url = URL(fileURLWithPath: path)

        guard FileManager.default.fileExists(atPath: path) else {
            return .error("File not found: \(path)")
        }

        // Check authorization
        let authStatus = await checkAuthorization()
        guard authStatus == .authorized else {
            return .error("Speech recognition not authorized. Please enable in System Settings > Privacy & Security > Speech Recognition")
        }

        do {
            let result = try await transcribe(
                url: url,
                language: language,
                includeTiming: includeTiming,
                includeAlternatives: includeAlternatives
            )
            return .success(result)
        } catch {
            return .error("Transcription failed: \(error.localizedDescription)")
        }
        #else
        return .error("Speech framework not available on this platform")
        #endif
    }

    public func describeAction(_ input: ToolInput) -> String {
        if let path = input.get("path", as: String.self) {
            let name = (path as NSString).lastPathComponent
            return "Transcribe: \(name)"
        }
        return "Transcribe audio"
    }

    #if canImport(Speech)
    // MARK: - Authorization

    private func checkAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    // MARK: - Transcription

    private func transcribe(
        url: URL,
        language: String,
        includeTiming: Bool,
        includeAlternatives: Bool
    ) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)) else {
            throw SpeechError.languageNotSupported(language)
        }

        guard recognizer.isAvailable else {
            throw SpeechError.recognizerNotAvailable
        }

        // Create recognition request
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = true // Privacy: on-device only

        // Get audio duration for progress info
        let duration = try await getAudioDuration(url: url)

        // Perform recognition and extract results
        let transcriptionData: TranscriptionData = try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !hasResumed else { return }

                if let error = error {
                    hasResumed = true
                    continuation.resume(throwing: error)
                    return
                }

                if let result = result, result.isFinal {
                    hasResumed = true
                    // Extract data to avoid sendability issues with SFSpeechRecognitionResult
                    let data = TranscriptionData(
                        text: result.bestTranscription.formattedString,
                        segments: result.bestTranscription.segments.map { segment in
                            TranscriptionSegment(
                                text: segment.substring,
                                timestamp: segment.timestamp,
                                confidence: segment.confidence
                            )
                        },
                        alternatives: result.transcriptions.dropFirst().prefix(3).map { $0.formattedString }
                    )
                    continuation.resume(returning: data)
                }
            }
        }

        // Format output
        return formatTranscription(
            data: transcriptionData,
            url: url,
            language: language,
            duration: duration,
            includeTiming: includeTiming,
            includeAlternatives: includeAlternatives
        )
    }

    // MARK: - Helper Types

    private struct TranscriptionData: Sendable {
        let text: String
        let segments: [TranscriptionSegment]
        let alternatives: [String]
    }

    private struct TranscriptionSegment: Sendable {
        let text: String
        let timestamp: TimeInterval
        let confidence: Float
    }

    private func getAudioDuration(url: URL) async throws -> TimeInterval {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return CMTimeGetSeconds(duration)
    }

    private func formatTranscription(
        data: TranscriptionData,
        url: URL,
        language: String,
        duration: TimeInterval,
        includeTiming: Bool,
        includeAlternatives: Bool
    ) -> String {
        var output = "=== Transcription ===\n"
        output += "File: \(url.lastPathComponent)\n"
        output += "Language: \(language)\n"
        output += "Duration: \(formatDuration(duration))\n"

        let avgConfidence = data.segments.isEmpty ? 0 : data.segments.reduce(Float(0)) { $0 + $1.confidence } / Float(data.segments.count)
        output += "Confidence: \(String(format: "%.1f%%", avgConfidence * 100))\n"
        output += "\n"

        // Main transcription
        output += "--- Text ---\n"
        output += data.text
        output += "\n\n"

        // Word-level timing if requested
        if includeTiming {
            output += "--- Word Timing ---\n"
            for segment in data.segments {
                let timestamp = formatTimestamp(segment.timestamp)
                let confidence = String(format: "%.0f%%", segment.confidence * 100)
                output += "[\(timestamp)] \(segment.text) (\(confidence))\n"
            }
            output += "\n"
        }

        // Alternative transcriptions if requested
        if includeAlternatives && !data.alternatives.isEmpty {
            output += "--- Alternatives ---\n"
            for (index, alt) in data.alternatives.enumerated() {
                output += "\(index + 1). \(alt)\n"
            }
        }

        return output
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if minutes > 0 {
            return "\(minutes)m \(secs)s"
        }
        return "\(secs)s"
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, secs, ms)
    }
    #endif
}

// MARK: - Batch Transcription Tool

/// Transcribe multiple audio files at once
public struct BatchTranscriptionTool: Tool {
    public let name = "transcribe_audio_batch"
    public let description = """
        Transcribe multiple audio files in a directory.
        Useful for processing collections of voice memos, recordings, or audio assets.
        Returns combined transcriptions with file separators.
        """

    public var inputSchema: ToolSchema {
        ToolSchema(
            properties: [
                "directory": .init(
                    type: "string",
                    description: "Path to directory containing audio files"
                ),
                "extensions": .init(
                    type: "string",
                    description: "Comma-separated file extensions (default: wav,mp3,m4a,caf)"
                ),
                "language": .init(
                    type: "string",
                    description: "Language code for all files (default: en-US)"
                ),
                "max_files": .init(
                    type: "integer",
                    description: "Maximum number of files to process (default: 10)"
                ),
                "recursive": .init(
                    type: "boolean",
                    description: "Search subdirectories (default: false)"
                )
            ],
            required: ["directory"]
        )
    }

    public init() {}

    public func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        let directory = try input.require("directory", as: String.self)
        let extensionsStr = input.get("extensions", as: String.self) ?? "wav,mp3,m4a,caf,aiff,aif"
        let language = input.get("language", as: String.self) ?? "en-US"
        let maxFiles = input.get("max_files", as: Int.self) ?? 10
        let recursive = input.get("recursive", as: Bool.self) ?? false

        let extensions = Set(extensionsStr.components(separatedBy: ",").map {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        })

        let directoryURL = URL(fileURLWithPath: directory)

        guard FileManager.default.fileExists(atPath: directory) else {
            return .error("Directory not found: \(directory)")
        }

        // Find audio files
        let enumerator: FileManager.DirectoryEnumerator?
        if recursive {
            enumerator = FileManager.default.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        } else {
            enumerator = FileManager.default.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
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

        // Sort by date (newest first)
        files.sort { $0.date > $1.date }
        let filesToProcess = Array(files.prefix(maxFiles))

        if filesToProcess.isEmpty {
            return .success("No audio files found in: \(directory)")
        }

        // Transcribe each file
        let transcriber = SpeechTranscriptionTool()
        var results: [String] = []
        var successCount = 0
        var totalDuration: TimeInterval = 0

        for (url, _) in filesToProcess {
            let transcribeInput = ToolInput(parameters: [
                "path": AnyCodable(url.path),
                "language": AnyCodable(language),
                "include_timing": AnyCodable(false)
            ])

            let output = try await transcriber.execute(transcribeInput, context: context)

            if !output.isError {
                successCount += 1
                results.append("=== \(url.lastPathComponent) ===")
                results.append(output.content)
                results.append("")
            } else {
                results.append("=== \(url.lastPathComponent) ===")
                results.append("Error: \(output.content)")
                results.append("")
            }
        }

        var summary = "Transcribed \(successCount)/\(filesToProcess.count) audio files\n\n"
        summary += results.joined(separator: "\n")

        return .success(summary)
    }

    public func describeAction(_ input: ToolInput) -> String {
        if let dir = input.get("directory", as: String.self) {
            return "Transcribe audio files in: \(dir)"
        }
        return "Transcribe audio files"
    }
}

// MARK: - Voice Memo Search Tool

/// Search and transcribe Voice Memos
public struct VoiceMemoTool: Tool {
    public let name = "transcribe_voice_memos"
    public let description = """
        Find and transcribe recent Voice Memos.
        Searches your Voice Memos library and transcribes matching recordings.
        Useful for extracting information from voice notes.
        """

    public var inputSchema: ToolSchema {
        ToolSchema(
            properties: [
                "count": .init(
                    type: "integer",
                    description: "Number of recent memos to transcribe (default: 5)"
                ),
                "search": .init(
                    type: "string",
                    description: "Optional search term to filter memos by name"
                ),
                "language": .init(
                    type: "string",
                    description: "Language code (default: en-US)"
                )
            ],
            required: []
        )
    }

    public init() {}

    public func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        let count = input.get("count", as: Int.self) ?? 5
        let search = input.get("search", as: String.self)
        let language = input.get("language", as: String.self) ?? "en-US"

        // Voice Memos are stored in iCloud or local container
        let possiblePaths = [
            // iCloud Voice Memos
            (NSHomeDirectory() as NSString).appendingPathComponent("Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings"),
            // Local Voice Memos (older location)
            (NSHomeDirectory() as NSString).appendingPathComponent("Library/Application Support/com.apple.voicememos/Recordings")
        ]

        var recordingsPath: String?
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                recordingsPath = path
                break
            }
        }

        guard let path = recordingsPath else {
            return .error("Voice Memos folder not found. Voice Memos may not be set up or accessible.")
        }

        // Find m4a files
        let directoryURL = URL(fileURLWithPath: path)
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .nameKey],
            options: [.skipsHiddenFiles]
        ) else {
            return .error("Cannot access Voice Memos folder")
        }

        var memos: [(url: URL, date: Date, name: String)] = []

        while let url = enumerator.nextObject() as? URL {
            let ext = url.pathExtension.lowercased()
            if ext == "m4a" {
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let name = url.deletingPathExtension().lastPathComponent

                // Apply search filter if provided
                if let searchTerm = search {
                    if !name.localizedCaseInsensitiveContains(searchTerm) {
                        continue
                    }
                }

                memos.append((url, date, name))
            }
        }

        // Sort by date (newest first)
        memos.sort { $0.date > $1.date }
        let memosToProcess = Array(memos.prefix(count))

        if memosToProcess.isEmpty {
            if let searchTerm = search {
                return .success("No Voice Memos found matching: \"\(searchTerm)\"")
            }
            return .success("No Voice Memos found")
        }

        // Transcribe each memo
        let transcriber = SpeechTranscriptionTool()
        var results: [String] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        for (url, date, name) in memosToProcess {
            let transcribeInput = ToolInput(parameters: [
                "path": AnyCodable(url.path),
                "language": AnyCodable(language)
            ])

            results.append("=== \(name) ===")
            results.append("Recorded: \(dateFormatter.string(from: date))")
            results.append("")

            let output = try await transcriber.execute(transcribeInput, context: context)
            results.append(output.content)
            results.append("")
        }

        return .success("Found \(memosToProcess.count) Voice Memos:\n\n\(results.joined(separator: "\n"))")
    }

    public func describeAction(_ input: ToolInput) -> String {
        let count = input.get("count", as: Int.self) ?? 5
        if let search = input.get("search", as: String.self) {
            return "Transcribe Voice Memos matching: \"\(search)\""
        }
        return "Transcribe \(count) recent Voice Memos"
    }
}

// MARK: - Audio Info Tool

/// Get information about audio files without transcribing
public struct AudioInfoTool: Tool {
    public let name = "audio_info"
    public let description = """
        Get metadata and information about an audio file.
        Returns duration, format, sample rate, channels, and other details.
        Useful for understanding audio files before transcription.
        """

    public var inputSchema: ToolSchema {
        ToolSchema(
            properties: [
                "path": .init(
                    type: "string",
                    description: "Path to the audio file"
                )
            ],
            required: ["path"]
        )
    }

    public init() {}

    public func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        #if canImport(AVFoundation)
        let path = try input.require("path", as: String.self)
        let url = URL(fileURLWithPath: path)

        guard FileManager.default.fileExists(atPath: path) else {
            return .error("File not found: \(path)")
        }

        do {
            let info = try await getAudioInfo(url: url)
            return .success(info)
        } catch {
            return .error("Failed to read audio info: \(error.localizedDescription)")
        }
        #else
        return .error("AVFoundation not available on this platform")
        #endif
    }

    public func describeAction(_ input: ToolInput) -> String {
        if let path = input.get("path", as: String.self) {
            let name = (path as NSString).lastPathComponent
            return "Get audio info: \(name)"
        }
        return "Get audio info"
    }

    #if canImport(AVFoundation)
    private func getAudioInfo(url: URL) async throws -> String {
        let asset = AVURLAsset(url: url)

        // Load properties
        let duration = try await asset.load(.duration)

        var output = "=== Audio Info ===\n"
        output += "File: \(url.lastPathComponent)\n"
        output += "Path: \(url.path)\n\n"

        // Duration
        let seconds = CMTimeGetSeconds(duration)
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        output += "Duration: \(minutes)m \(secs)s (\(String(format: "%.2f", seconds)) seconds)\n"

        // File size
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            let mbSize = Double(size) / (1024 * 1024)
            output += "File Size: \(String(format: "%.2f", mbSize)) MB\n"
        }

        // Get audio tracks using older synchronous API wrapped in async
        let tracks = asset.tracks(withMediaType: .audio)

        for track in tracks {
            output += "\n--- Audio Track ---\n"

            // Format description
            let formatDescriptions = track.formatDescriptions as? [CMAudioFormatDescription] ?? []
            if let formatDesc = formatDescriptions.first {
                let basicDesc = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
                if let desc = basicDesc?.pointee {
                    output += "Sample Rate: \(Int(desc.mSampleRate)) Hz\n"
                    output += "Channels: \(desc.mChannelsPerFrame)\n"
                    output += "Bits per Channel: \(desc.mBitsPerChannel)\n"

                    // Format ID
                    let formatID = desc.mFormatID
                    let formatName = formatIDToString(formatID)
                    output += "Format: \(formatName)\n"
                }
            }

            // Estimated data rate
            let estimatedRate = track.estimatedDataRate
            if estimatedRate > 0 {
                output += "Bitrate: \(Int(estimatedRate / 1000)) kbps\n"
            }
        }

        // Check if transcription is supported
        output += "\n--- Transcription Support ---\n"
        let supportedExtensions = ["wav", "mp3", "m4a", "caf", "aiff", "aif"]
        let ext = url.pathExtension.lowercased()
        if supportedExtensions.contains(ext) {
            output += "✓ Format supported for transcription\n"
        } else {
            output += "✗ Format may not be supported for transcription\n"
        }

        return output
    }

    private func formatIDToString(_ formatID: AudioFormatID) -> String {
        switch formatID {
        case kAudioFormatLinearPCM: return "Linear PCM (WAV)"
        case kAudioFormatMPEG4AAC: return "AAC"
        case kAudioFormatMPEGLayer3: return "MP3"
        case kAudioFormatAppleLossless: return "Apple Lossless"
        case kAudioFormatFLAC: return "FLAC"
        case kAudioFormatOpus: return "Opus"
        default:
            // Convert format ID to 4-char string
            var id = formatID.bigEndian
            let chars = withUnsafeBytes(of: &id) { Data($0) }
            if let str = String(data: chars, encoding: .ascii) {
                return str
            }
            return "Unknown (\(formatID))"
        }
    }
    #endif
}

// MARK: - Errors

public enum SpeechError: Error, LocalizedError {
    case notAuthorized
    case recognizerNotAvailable
    case languageNotSupported(String)
    case transcriptionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Speech recognition not authorized"
        case .recognizerNotAvailable:
            return "Speech recognizer not available"
        case .languageNotSupported(let lang):
            return "Language not supported: \(lang)"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        }
    }
}
