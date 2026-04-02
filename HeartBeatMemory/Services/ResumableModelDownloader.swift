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
// 使用前台 URLSession (default configuration) + HTTP Range 请求实现断点续传。
// 不用 background session，避免跨沙盒临时文件移动失败的问题。
// 下载流程：
//   1. GET /api/models/{repo}  →  获取文件列表
//   2. 逐文件串行下载（网络不稳定时串行比并发更可靠）
//   3. 每个文件先写到 .tmp 临时文件，完成后原子 rename 到目标路径
//   4. 网络中断时保留 .tmp 文件，下次通过 Range 头续传

actor ResumableModelDownloader {

    // MARK: - 配置

    private let repoId: String          // "mlx-community/Qwen2-VL-2B-Instruct-4bit"
    private let mirrorBase: String      // "https://hf-mirror.com"
    private let destinationDir: URL     // 文件最终存放目录

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 120   // 单次请求超时
        config.timeoutIntervalForResource = 7 * 24 * 3600  // 整体资源超时 7 天
        config.waitsForConnectivity       = true
        config.allowsExpensiveNetworkAccess    = true
        config.allowsConstrainedNetworkAccess  = true
        return URLSession(configuration: config)
    }()

    // MARK: - Init

    init(repoId: String,
         mirrorBase: String = "https://hf-mirror.com",
         destinationDir: URL) {
        self.repoId       = repoId
        self.mirrorBase   = mirrorBase
        self.destinationDir = destinationDir
    }

    // MARK: - 公开接口

    /// 下载整个模型，逐文件串行，支持每个文件断点续传。
    /// - Returns: destinationDir（所有文件都在此目录下）
    func download(progressHandler: @escaping DownloadProgressHandler) async throws -> URL {

        // 1. 确保目录存在
        try FileManager.default.createDirectory(
            at: destinationDir,
            withIntermediateDirectories: true
        )

        // 2. 获取文件列表
        let allFiles = try await fetchFileList()
        NSLog("📋 共 \(allFiles.count) 个文件需要检查")

        // 3. 过滤掉已完整下载的文件
        let pending = allFiles.filter { filename in
            let dest = destinationDir.appendingPathComponent(filename)
            return !FileManager.default.fileExists(atPath: dest.path)
        }

        if pending.isEmpty {
            NSLog("✅ 所有文件已存在，无需下载")
            progressHandler(1, 1, allFiles.count, allFiles.count)
            return destinationDir
        }

        NSLog("⬇️ 需要下载 \(pending.count)/\(allFiles.count) 个文件")

        // 4. 统计总大小（先设一个估算值，实际大小下载时更新）
        var totalDownloaded: Int64 = allFiles
            .filter { !pending.contains($0) }
            .compactMap { fileSizeAt(destinationDir.appendingPathComponent($0)) }
            .reduce(0, +)
        var totalSize: Int64 = totalDownloaded
        var filesDone = allFiles.count - pending.count

        // 5. 逐文件串行下载（最多重试 5 次）
        for filename in pending {
            NSLog("⬇️ 开始: \(filename)")

            var lastError: Error?
            for attempt in 1...5 {
                do {
                    let bytes = try await downloadFile(
                        filename: filename,
                        onProgress: { received, fileTotal in
                            totalDownloaded += received
                            if fileTotal > 0 { totalSize = max(totalSize, totalDownloaded + fileTotal) }
                            progressHandler(totalDownloaded, totalSize, filesDone, allFiles.count)
                        }
                    )
                    totalDownloaded += bytes
                    filesDone += 1
                    progressHandler(totalDownloaded, totalSize, filesDone, allFiles.count)
                    NSLog("✅ 完成: \(filename) (\(bytes) bytes)")
                    lastError = nil
                    break
                } catch {
                    lastError = error
                    NSLog("⚠️ 第\(attempt)/5次失败 \(filename): \(error.localizedDescription)")
                    if attempt < 5 {
                        let wait = UInt64(min(3 * attempt, 15)) * 1_000_000_000
                        try? await Task.sleep(nanoseconds: wait)
                    }
                }
            }

            if let err = lastError {
                NSLog("❌ 文件下载最终失败: \(filename)")
                throw err
            }
        }

        return destinationDir
    }

    // MARK: - 单文件下载（HTTP Range 断点续传）

    /// 下载单个文件，若存在 .tmp 则续传
    /// - Returns: 本次下载的新增字节数
    private func downloadFile(
        filename: String,
        onProgress: @escaping (Int64, Int64) -> Void
    ) async throws -> Int64 {

        let dest    = destinationDir.appendingPathComponent(filename)
        let tmpDest = destinationDir.appendingPathComponent(filename + ".tmp")

        // 确保父目录存在（filename 可能含子路径）
        try FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // 已有临时文件 → 续传
        let resumeOffset: Int64 = fileSizeAt(tmpDest) ?? 0

        // 构建请求
        let urlString = "\(mirrorBase)/\(repoId)/resolve/main/\(filename)"
        guard let url = URL(string: urlString) else {
            throw DownloaderError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        if resumeOffset > 0 {
            request.setValue("bytes=\(resumeOffset)-", forHTTPHeaderField: "Range")
            NSLog("🔄 续传 \(filename) 从 \(resumeOffset) bytes")
        }

        // 发起请求
        let (asyncBytes, response) = try await Self.session.bytes(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw DownloaderError.invalidResponse
        }

        // 200 = 全新下载，206 = 续传，其他都是错误
        guard http.statusCode == 200 || http.statusCode == 206 else {
            throw DownloaderError.httpError(http.statusCode)
        }

        // 服务端返回的文件总大小
        let contentLength = http.value(forHTTPHeaderField: "Content-Length")
            .flatMap { Int64($0) } ?? -1

        // 打开临时文件追加写入
        if !FileManager.default.fileExists(atPath: tmpDest.path) {
            FileManager.default.createFile(atPath: tmpDest.path, contents: nil)
        }

        let fileHandle = try FileHandle(forWritingTo: tmpDest)
        defer { try? fileHandle.close() }

        // 续传时跳到文件末尾
        if resumeOffset > 0 {
            try fileHandle.seekToEnd()
        }

        // 流式写入
        var newBytes: Int64 = 0
        var buffer = Data(capacity: 256 * 1024)  // 256KB buffer

        for try await byte in asyncBytes {
            buffer.append(byte)
            if buffer.count >= 256 * 1024 {
                fileHandle.write(buffer)
                newBytes += Int64(buffer.count)
                onProgress(Int64(buffer.count), contentLength)
                buffer.removeAll(keepingCapacity: true)
            }
        }

        // 写入剩余数据
        if !buffer.isEmpty {
            fileHandle.write(buffer)
            newBytes += Int64(buffer.count)
            onProgress(Int64(buffer.count), contentLength)
        }

        try fileHandle.close()

        // 原子重命名 tmp → 最终文件
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

    // MARK: - 获取文件列表

    private func fetchFileList() async throws -> [String] {
        let apiURL = URL(string: "\(mirrorBase)/api/models/\(repoId)")!
        let (data, response) = try await Self.session.data(from: apiURL)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw DownloaderError.httpError((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let siblings = json["siblings"] as? [[String: Any]] else {
            throw DownloaderError.parseError("无法解析文件列表 JSON")
        }

        return siblings.compactMap { $0["rfilename"] as? String }
    }

    // MARK: - 错误类型

    enum DownloaderError: LocalizedError {
        case invalidURL(String)
        case invalidResponse
        case httpError(Int)
        case parseError(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL(let u):   return "无效 URL: \(u)"
            case .invalidResponse:     return "无效的服务器响应"
            case .httpError(let c):    return "HTTP 错误: \(c)"
            case .parseError(let m):   return "解析错误: \(m)"
            }
        }
    }
}
