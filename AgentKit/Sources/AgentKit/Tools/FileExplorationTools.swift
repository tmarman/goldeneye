import Foundation

// MARK: - File Exploration Tools

/// Tools for exploring the user's file system to understand their work and interests.
/// These are read-only, safe tools designed for the Concierge to use during profile building.

// MARK: - List Directory Tool

/// Lists contents of a directory with useful metadata
public struct ListDirectoryTool: Tool {
    public let name = "list_directory"
    public let description = """
        List the contents of a directory. Returns file and folder names with basic metadata \
        like size and modification date. Use this to explore the user's file structure and \
        understand how they organize their work.
        """

    public let inputSchema = ToolSchema(
        properties: [
            "path": .init(
                type: "string",
                description: "The directory path to list (can use ~ for home directory)"
            ),
            "include_hidden": .init(
                type: "boolean",
                description: "Whether to include hidden files (default: false)"
            )
        ],
        required: ["path"]
    )

    public init() {}

    public func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        let pathString: String = try input.require("path")
        let includeHidden = input.get("include_hidden", as: Bool.self) ?? false

        // Expand ~ to home directory
        let expandedPath = (pathString as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        let fileManager = FileManager.default

        // Check if path exists and is a directory
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .error("Directory not found: \(pathString)")
        }
        guard isDirectory.boolValue else {
            return .error("Path is not a directory: \(pathString)")
        }

        // Check read access
        guard fileManager.isReadableFile(atPath: url.path) else {
            return .error("Cannot read directory (permission denied): \(pathString)")
        }

        // List contents
        do {
            var contents = try fileManager.contentsOfDirectory(atPath: url.path)

            // Filter hidden files if needed
            if !includeHidden {
                contents = contents.filter { !$0.hasPrefix(".") }
            }

            // Sort: directories first, then by name
            contents.sort { a, b in
                let aPath = url.appendingPathComponent(a)
                let bPath = url.appendingPathComponent(b)
                var aIsDir: ObjCBool = false
                var bIsDir: ObjCBool = false
                fileManager.fileExists(atPath: aPath.path, isDirectory: &aIsDir)
                fileManager.fileExists(atPath: bPath.path, isDirectory: &bIsDir)

                if aIsDir.boolValue != bIsDir.boolValue {
                    return aIsDir.boolValue
                }
                return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
            }

            // Build output with metadata
            var output = "Contents of \(pathString):\n\n"

            for item in contents.prefix(50) {  // Limit to 50 items
                let itemPath = url.appendingPathComponent(item)
                var itemIsDir: ObjCBool = false
                fileManager.fileExists(atPath: itemPath.path, isDirectory: &itemIsDir)

                if itemIsDir.boolValue {
                    output += "📁 \(item)/\n"
                } else {
                    // Get file size
                    let attrs = try? fileManager.attributesOfItem(atPath: itemPath.path)
                    let size = (attrs?[.size] as? Int64) ?? 0
                    let sizeStr = formatFileSize(size)
                    output += "📄 \(item) (\(sizeStr))\n"
                }
            }

            if contents.count > 50 {
                output += "\n... and \(contents.count - 50) more items"
            }

            return .success(output)

        } catch {
            return .error("Failed to list directory: \(error.localizedDescription)")
        }
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        if bytes < 1024 * 1024 * 1024 { return "\(bytes / 1024 / 1024) MB" }
        return "\(bytes / 1024 / 1024 / 1024) GB"
    }
}

// MARK: - Analyze Folder Tool

/// Analyzes a folder structure to understand its purpose
public struct AnalyzeFolderTool: Tool {
    public let name = "analyze_folder"
    public let description = """
        Analyze a folder to understand what it contains and what it might tell us about the user. \
        Returns statistics about file types, subfolder structure, and notable patterns. \
        Use this to quickly understand the purpose of a directory.
        """

    public let inputSchema = ToolSchema(
        properties: [
            "path": .init(
                type: "string",
                description: "The folder path to analyze (can use ~ for home directory)"
            ),
            "depth": .init(
                type: "integer",
                description: "How deep to scan subfolders (default: 2, max: 5)"
            )
        ],
        required: ["path"]
    )

    public init() {}

    public func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        let pathString: String = try input.require("path")
        let depth = min(input.get("depth", as: Int.self) ?? 2, 5)

        let expandedPath = (pathString as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: url.path) else {
            return .error("Folder not found: \(pathString)")
        }

        // Collect statistics
        var fileTypes: [String: Int] = [:]
        var totalFiles = 0
        var totalFolders = 0
        var totalSize: Int64 = 0
        var recentFiles: [(name: String, date: Date)] = []
        var notableFolders: [String] = []

        // Skip these heavy directories
        let skipDirs = Set(["node_modules", ".build", "build", "DerivedData", ".git", "Pods", "vendor", "__pycache__"])

        func scan(at url: URL, currentDepth: Int) {
            guard currentDepth <= depth else { return }
            guard fileManager.isReadableFile(atPath: url.path) else { return }

            guard let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { return }

            var filesAtThisLevel = 0
            let maxFilesPerLevel = 500

            while let itemURL = enumerator.nextObject() as? URL, filesAtThisLevel < maxFilesPerLevel {
                let name = itemURL.lastPathComponent

                // Skip heavy directories
                if skipDirs.contains(name) {
                    enumerator.skipDescendants()
                    continue
                }

                // Check if we're too deep
                let relativePath = itemURL.path.replacingOccurrences(of: url.path, with: "")
                let itemDepth = relativePath.components(separatedBy: "/").count - 1
                if itemDepth > depth {
                    enumerator.skipDescendants()
                    continue
                }

                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: itemURL.path, isDirectory: &isDirectory) {
                    if isDirectory.boolValue {
                        totalFolders += 1
                        // Track notable folder names
                        if currentDepth == 0 && !name.hasPrefix(".") {
                            notableFolders.append(name)
                        }
                    } else {
                        totalFiles += 1
                        filesAtThisLevel += 1

                        let ext = itemURL.pathExtension.lowercased()
                        if !ext.isEmpty {
                            fileTypes[ext, default: 0] += 1
                        }

                        // Get file metadata
                        if let attrs = try? fileManager.attributesOfItem(atPath: itemURL.path) {
                            if let size = attrs[.size] as? Int64 {
                                totalSize += size
                            }
                            if let modDate = attrs[.modificationDate] as? Date {
                                if recentFiles.count < 10 {
                                    recentFiles.append((name: name, date: modDate))
                                }
                            }
                        }
                    }
                }
            }
        }

        scan(at: url, currentDepth: 0)

        // Sort recent files by date
        recentFiles.sort { $0.date > $1.date }

        // Build analysis output
        var output = "## Analysis of \(pathString)\n\n"

        // Overview
        output += "### Overview\n"
        output += "- **Total files:** \(totalFiles)\n"
        output += "- **Total folders:** \(totalFolders)\n"
        output += "- **Total size:** \(formatSize(totalSize))\n\n"

        // File types
        if !fileTypes.isEmpty {
            output += "### File Types\n"
            let sortedTypes = fileTypes.sorted { $0.value > $1.value }
            for (ext, count) in sortedTypes.prefix(10) {
                output += "- **.\(ext):** \(count) files\n"
            }
            output += "\n"
        }

        // Notable subfolders
        if !notableFolders.isEmpty {
            output += "### Notable Subfolders\n"
            for folder in notableFolders.prefix(15) {
                output += "- 📁 \(folder)\n"
            }
            output += "\n"
        }

        // Inferences
        output += "### Possible Inferences\n"
        output += inferPurpose(fileTypes: fileTypes, folders: notableFolders)

        return .success(output)
    }

    private func formatSize(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        if bytes < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(bytes) / 1024 / 1024) }
        return String(format: "%.1f GB", Double(bytes) / 1024 / 1024 / 1024)
    }

    private func inferPurpose(fileTypes: [String: Int], folders: [String]) -> String {
        var inferences: [String] = []

        // Code project detection
        let codeExts = ["swift", "ts", "tsx", "js", "jsx", "py", "rs", "go", "java", "c", "cpp", "rb"]
        let codeCount = codeExts.reduce(0) { $0 + (fileTypes[$1] ?? 0) }
        if codeCount > 20 {
            inferences.append("- This appears to be a **code project** or development folder")
        }

        // Document folder
        let docExts = ["pdf", "doc", "docx", "txt", "md", "pages"]
        let docCount = docExts.reduce(0) { $0 + (fileTypes[$1] ?? 0) }
        if docCount > 10 {
            inferences.append("- Contains significant **documents** - may be work or research related")
        }

        // Photo collection
        let photoExts = ["jpg", "jpeg", "png", "heic", "heif", "gif"]
        let photoCount = photoExts.reduce(0) { $0 + (fileTypes[$1] ?? 0) }
        if photoCount > 50 {
            inferences.append("- Large **photo collection** - photography may be an interest")
        }

        // Travel indicators
        let travelFolders = folders.filter { name in
            let lower = name.lowercased()
            return lower.contains("travel") || lower.contains("trip") || lower.contains("vacation")
        }
        if !travelFolders.isEmpty {
            inferences.append("- Found travel-related folders: \(travelFolders.joined(separator: ", "))")
        }

        // Work indicators
        let workFolders = folders.filter { name in
            let lower = name.lowercased()
            return lower.contains("work") || lower.contains("projects") || lower.contains("clients")
        }
        if !workFolders.isEmpty {
            inferences.append("- Found work-related folders: \(workFolders.joined(separator: ", "))")
        }

        if inferences.isEmpty {
            inferences.append("- No strong patterns detected yet - may need to explore subfolders")
        }

        return inferences.joined(separator: "\n")
    }
}

// MARK: - Read File Names Tool

/// Reads file and folder names from a path to understand context
public struct ReadFileNamesTool: Tool {
    public let name = "read_file_names"
    public let description = """
        Read just the names of files and folders in a directory. This is useful for quickly \
        understanding the themes or topics covered without needing full file details. \
        Great for analyzing what a collection of files might reveal about interests.
        """

    public let inputSchema = ToolSchema(
        properties: [
            "path": .init(
                type: "string",
                description: "The directory path (can use ~ for home directory)"
            ),
            "pattern": .init(
                type: "string",
                description: "Optional: filter by extension (e.g., 'pdf', 'jpg')"
            )
        ],
        required: ["path"]
    )

    public init() {}

    public func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        let pathString: String = try input.require("path")
        let pattern = input.get("pattern", as: String.self)

        let expandedPath = (pathString as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: url.path) else {
            return .error("Path not found: \(pathString)")
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return .error("Cannot read directory: \(pathString)")
        }

        var names: [String] = []
        let maxItems = 100

        while let itemURL = enumerator.nextObject() as? URL, names.count < maxItems {
            // Skip directories in output (we want file names)
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: itemURL.path, isDirectory: &isDir), isDir.boolValue {
                // Only go one level deep
                let depth = itemURL.path.replacingOccurrences(of: url.path, with: "").components(separatedBy: "/").count
                if depth > 2 {
                    enumerator.skipDescendants()
                }
                continue
            }

            let name = itemURL.deletingPathExtension().lastPathComponent
            let ext = itemURL.pathExtension.lowercased()

            // Apply pattern filter if specified
            if let pattern = pattern, !ext.isEmpty {
                if ext != pattern.lowercased() {
                    continue
                }
            }

            // Skip very short or generic names
            if name.count > 2 && !name.hasPrefix("IMG_") && !name.hasPrefix("DSC_") {
                names.append(name)
            }
        }

        if names.isEmpty {
            return .success("No matching files found in \(pathString)")
        }

        var output = "File names in \(pathString)"
        if let pattern = pattern {
            output += " (.\(pattern) files)"
        }
        output += ":\n\n"

        for name in names {
            output += "- \(name)\n"
        }

        if names.count == maxItems {
            output += "\n... (showing first \(maxItems) results)"
        }

        return .success(output)
    }
}

// MARK: - Save Profile Learning Tool

/// Allows the agent to record learnings about the user
public struct SaveProfileLearningTool: Tool {
    public let name = "save_profile_learning"
    public let description = """
        Save a learning about the user to their profile. Use this when you've discovered \
        something meaningful about the user's work, interests, or patterns based on their files.
        """

    public let inputSchema = ToolSchema(
        properties: [
            "category": .init(
                type: "string",
                description: "Category: work, interest, pattern, or general",
                enumValues: ["work", "interest", "pattern", "general"]
            ),
            "title": .init(
                type: "string",
                description: "Short title for this learning (e.g., 'Swift Developer', 'Travel Enthusiast')"
            ),
            "description": .init(
                type: "string",
                description: "Longer description explaining what you learned and why it matters"
            ),
            "evidence": .init(
                type: "string",
                description: "The file paths or observations that support this learning"
            ),
            "confidence": .init(
                type: "number",
                description: "Confidence level from 0.0 to 1.0"
            )
        ],
        required: ["category", "title", "description", "confidence"]
    )

    private let onLearning: @Sendable (String, String, String, String?, Double) async -> Void

    public init(onLearning: @escaping @Sendable (String, String, String, String?, Double) async -> Void) {
        self.onLearning = onLearning
    }

    public func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        let category: String = try input.require("category")
        let title: String = try input.require("title")
        let description: String = try input.require("description")
        let evidence = input.get("evidence", as: String.self)
        let confidence: Double = try input.require("confidence")

        // Validate category
        guard ["work", "interest", "pattern", "general"].contains(category) else {
            return .error("Invalid category: \(category). Must be work, interest, pattern, or general.")
        }

        // Validate confidence
        guard confidence >= 0.0 && confidence <= 1.0 else {
            return .error("Confidence must be between 0.0 and 1.0")
        }

        // Save the learning
        await onLearning(category, title, description, evidence, confidence)

        return .success("Saved learning: **\(title)** (\(category)) with \(Int(confidence * 100))% confidence")
    }
}
