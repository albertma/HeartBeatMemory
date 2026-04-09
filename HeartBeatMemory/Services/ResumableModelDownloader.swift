import Foundation

// MARK: - 进度回调

typealias DownloadProgressHandler = @Sendable (
    _ downloaded: Int64,
    _ total: Int64,
    _ filesDone: Int,
    _ filesTotal: Int
) -> Void

// MARK: - ResumableModelDownloader
//
// 使用元数据文件记录下载状态，支持断点续传。
// 下载流程：
//   1. GET /api/models/{repo}  →  获取文件列表
//   2. 读取/创建元数据文件
//   3. 逐文件下载，更新元数据
//   4. 退出后再次启动可继续

actor ResumableModelDownloader {

    // MARK: - 配置

    private let repoId: String
    private let mirrorBase: String
    private let destinationDir: URL
    private let requiredExtensions: [String]?
    private let metadataManager: DownloadMetadataManager
    
    // iOS 必需扩展名
    static let iOSRequiredExtensions = [
        "config.json",
        "generation_config.json",
        "model.safetensors",
        "model.safetensors.index.json",
        "processor_config.json",
        "tokenizer_config.json",
        "tokenizer.json"
    ]
    
    // iOS 忽略的文件
    static let iOSIgnorePatterns = [
        ".gitattributes",
        ".md",
        "_web.task",
        "torchscript/",
        "rust_model.bin"
    ]

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 600
        config.timeoutIntervalForResource = 7 * 24 * 3600
        config.waitsForConnectivity = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        return URLSession(configuration: config)
    }()

    // MARK: - Init

    init(repoId: String,
         mirrorBase: String = "https://hf-mirror.com",
         destinationDir: URL,
         requiredExtensions: [String]? = nil,
         metadataManager: DownloadMetadataManager = .shared) {
        self.repoId = repoId
        self.mirrorBase = mirrorBase
        self.destinationDir = destinationDir
        self.requiredExtensions = requiredExtensions
        self.metadataManager = metadataManager
    }
    
    static func iOSDownloader(
        repoId: String,
        mirrorBase: String = "https://hf-mirror.com",
        destinationDir: URL
    ) -> ResumableModelDownloader {
        ResumableModelDownloader(
            repoId: repoId,
            mirrorBase: mirrorBase,
            destinationDir: destinationDir,
            requiredExtensions: iOSRequiredExtensions
        )
    }

    // MARK: - 下载主流程

    func download(
        modelName: String,
        progressHandler: @escaping DownloadProgressHandler
    ) async throws -> URL {

        // 1. 确保目录存在
        try FileManager.default.createDirectory(
            at: destinationDir,
            withIntermediateDirectories: true
        )

        // 2. 获取文件列表和大小
        let (allFiles, fileSizes) = try await fetchFileListWithSizes()
        NSLog("📋 API 返回 \(allFiles.count) 个文件")
        
        // 3. 加载或创建元数据
        var metadata = loadOrCreateMetadata(
            allFiles: allFiles,
            fileSizes: fileSizes,
            modelName: modelName
        )
        
        // 4. 过滤需要下载的文件
        let pending = filterPendingFiles(allFiles: allFiles, metadata: metadata)
        
        if pending.isEmpty {
            NSLog("✅ 所有文件已存在，无需下载")
            progressHandler(1, 1, metadata.files.count, metadata.files.count)
            return destinationDir
        }

        NSLog("⬇️ 需要下载 \(pending.count)/\(allFiles.count) 个文件")

        // 5. 统计已下载大小
        var totalDownloaded: Int64 = metadata.downloadedSize
        var totalSize: Int64 = metadata.totalSize
        let filesDone = metadata.files.count - pending.count

        // 6. 逐文件下载
        for filename in pending {
            NSLog("⬇️ 开始: \(filename)")
            
            // 更新状态为下载中
            await MainActor.run {
                metadataManager.updateFileStatus(repoId: repoId, filename: filename, status: .downloading)
            }
            
            var lastError: Error?
            for attempt in 1...10 {
                do {
                    let bytes = try await downloadFile(filename: filename)
                    totalDownloaded += bytes
                    
                    // 更新为完成
                    await MainActor.run {
                        metadataManager.updateFileStatus(repoId: repoId, filename: filename, status: .completed, downloadedSize: bytes)
                    }
                    
                    NSLog("✅ 完成: \(filename) (\(bytes / 1024 / 1024) MB)")
                    lastError = nil
                    break
                } catch {
                    lastError = error
                    NSLog("⚠️ 第\(attempt)/10次失败: \(filename) - \(error.localizedDescription)")
                    if attempt < 10 {
                        let wait = UInt64(min(3 * attempt, 15)) * 1_000_000_000
                        try? await Task.sleep(nanoseconds: wait)
                    }
                }
            }
            
            if let err = lastError {
                await MainActor.run {
                    metadataManager.updateFileStatus(repoId: repoId, filename: filename, status: .failed, error: err.localizedDescription)
                }
                throw err
            }
            
            progressHandler(totalDownloaded, totalSize, filesDone, metadata.files.count)
        }

        return destinationDir
    }
    
    // MARK: - 加载/创建元数据
    
    private func loadOrCreateMetadata(
        allFiles: [String],
        fileSizes: [String: Int64],
        modelName: String
    ) -> ModelDownloadMetadata {
        // 尝试加载
        if let existing = metadataManager.loadMetadata(for: repoId) {
            // 检查文件列表是否有变化
            if Set(existing.files.keys) == Set(allFiles) {
                NSLog("📋 加载已有元数据: \(existing.completedFiles.count)/\(existing.files.count) 已完成")
                return existing
            } else {
                // 文件列表变化，重新创建
                NSLog("🔄 文件列表变化，重新创建元数据")
            }
        }
        
        // 创建新元数据
        let metadata = metadataManager.createMetadata(
            repoId: repoId,
            modelName: modelName,
            files: allFiles,
            fileSizes: fileSizes
        )
        
        return metadata
    }
    
    // MARK: - 过滤待下载文件
    
    private func filterPendingFiles(allFiles: [String], metadata: ModelDownloadMetadata) -> [String] {
        // 需要 iOS 过滤
        if let extensions = requiredExtensions, !extensions.isEmpty {
            let filtered = allFiles.filter { filename in
                let matches = extensions.contains { ext in
                    filename.hasSuffix(ext) || filename.contains(ext)
                }
                let ignored = Self.iOSIgnorePatterns.contains { filename.contains($0) }
                return matches && !ignored
            }
            
            // 只返回未完成的文件
            return filtered.filter { filename in
                guard let record = metadata.files[filename] else { return true }
                return record.status != .completed
            }
        }
        
        // 返回未完成文件
        return metadata.pendingFiles
    }

    // MARK: - 单文件下载
    
    private func downloadFile(filename: String) async throws -> Int64 {
        let dest = destinationDir.appendingPathComponent(filename)
        let tmpDest = destinationDir.appendingPathComponent(filename + ".tmp")
        
        try FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        
        // 断点续传：获取已下载大小
        let resumeOffset: Int64 = fileSizeAt(tmpDest) ?? 0
        
        let urlString = "\(mirrorBase)/\(repoId)/resolve/main/\(filename)"
        guard let url = URL(string: urlString) else {
            throw DownloaderError.invalidURL(urlString)
        }
        
        var request = URLRequest(url: url)
        if resumeOffset > 0 {
            request.setValue("bytes=\(resumeOffset)-", forHTTPHeaderField: "Range")
            NSLog("🔄 续传 \(filename) 从 \(resumeOffset) bytes")
        }
        
        let (asyncBytes, response) = try await Self.session.bytes(for: request)
        
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200 || http.statusCode == 206 else {
            throw DownloaderError.httpError((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        
        if !FileManager.default.fileExists(atPath: tmpDest.path) {
            FileManager.default.createFile(atPath: tmpDest.path, contents: nil)
        }
        
        let fileHandle = try FileHandle(forWritingTo: tmpDest)
        defer { try? fileHandle.close() }
        
        if resumeOffset > 0 {
            try fileHandle.seekToEnd()
        }
        
        var newBytes: Int64 = 0
        var buffer = Data(capacity: 256 * 1024)
        
        for try await byte in asyncBytes {
            buffer.append(byte)
            if buffer.count >= 256 * 1024 {
                fileHandle.write(buffer)
                newBytes += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        
        if !buffer.isEmpty {
            fileHandle.write(buffer)
            newBytes += Int64(buffer.count)
        }
        
        try fileHandle.close()
        
        // 移动到目标位置
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: tmpDest, to: dest)
        
        return newBytes
    }

    // MARK: - 工具
    
    private func fileSizeAt(_ url: URL) -> Int64? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? Int64) ?? (attrs?[.size] as? Int).map { Int64($0) }
    }

    // MARK: - 获取文件列表（含大小）
    
    private func fetchFileListWithSizes() async throws -> ([String], [String: Int64]) {
        let apiURL = URL(string: "\(mirrorBase)/api/models/\(repoId)")!
        let (data, response) = try await Self.session.data(from: apiURL)
        
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw DownloaderError.httpError(statusCode)
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let siblings = json["siblings"] as? [[String: Any]] else {
            throw DownloaderError.parseError
        }
        
        var files: [String] = []
        var fileSizes: [String: Int64] = [:]
        
        for item in siblings {
            guard let filename = item["rfilename"] as? String else { continue }
            let size = item["size"] as? Int64 ?? 0
            files.append(filename)
            fileSizes[filename] = size
        }
        
        return (files, fileSizes)
    }

    // MARK: - 错误
    
    enum DownloaderError: LocalizedError {
        case invalidURL(String)
        case invalidResponse
        case httpError(Int)
        case parseError
        
        var errorDescription: String? {
            switch self {
            case .invalidURL(let u): return "无效 URL: \(u)"
            case .invalidResponse: return "无效响应"
            case .httpError(let c): return "HTTP \(c)"
            case .parseError: return "解析错误"
            }
        }
    }
}
