import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXVLM
import Hub
import UIKit

// MARK: - 下载状态详情(用于实时 UI 更新)

struct DownloadStatusDetail: Equatable {
    let modelName: String
    let currentFile: String
    let downloadedBytes: Int64
    let totalBytes: Int64
    let filesDone: Int
    let filesTotal: Int

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(downloadedBytes) / Double(totalBytes)
    }

    var progressPercent: Int {
        Int(progress * 100)
    }

    var formattedDownloaded: String {
        formatBytes(downloadedBytes)
    }

    var formattedTotal: String {
        formatBytes(totalBytes)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1024 / 1024
        if mb > 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        return String(format: "%.0f MB", mb)
    }
}

// MARK: - LMModel 扩展:所有模型必须使用 mlx-community 下的公开 repo

extension ModelConfiguration {
    static let qwen2VL_2b     = ModelConfiguration(id: "mlx-community/Qwen2-VL-2B-Instruct-4bit")
   // static let gemma3_4b    = ModelConfiguration(id: "mlx-community/gemma-3-4b-it-qat-4bit")
}

// MARK: - MLXService

/// 管理 MLX 模型的加载、缓存与文本生成
@Observable
class MLXService {

    // MARK: - 可用模型列表
    // ✅ 全部使用 mlx-community repo,保证 hf-mirror.com 可公开访问(无需登录)
    static let availableModels: [LMModel] = [
        LMModel(name: "qwen2VL:2b",   configuration: .qwen2VL_2b,   type: .vlm),
//        LMModel(name: "gemma3-4b",   configuration: .gemma3_4b,   type: .vlm),
    ]

    // MARK: - App 状态检查(防止后台 GPU 调用)
    private var isAppInForeground: Bool {
        UIApplication.shared.applicationState == .active
    }

    // MARK: - 状态属性

    /// 当前模型下载进度,绑定到 UI
    @MainActor
    private(set) var modelDownloadProgress: Progress?

    /// 下载状态详情(文件名、文件进度等),用于实时更新 UI
    @MainActor
    var downloadStatus: DownloadStatusDetail?

    /// 是否正在加载/下载模型
    @MainActor
    private(set) var isLoadingModel: Bool = false

    // MARK: - 私有属性

    /// 内存缓存:同一会话内避免重复加载,最多缓存 1 个模型防止 OOM
    private let modelCache = NSCache<NSString, ModelContainer>()

    /// 下载用 HubApi → Caches(Hub 库在此路径行为正常,能正确下载)
    private let downloadHubApi: HubApi = HubApiExtension.default

    /// 加载用 HubApi → Documents(持久化存储,重装 App 后仍可用)
    private let persistentHubApi: HubApi = HubApiExtension.persistent

    // MARK: - 初始化

    init() {
        modelCache.countLimit = 1
        let cacheDir = downloadHubApi.localRepoLocation(Hub.Repo(id: "mlx-community/test"))
        let docsDir  = persistentHubApi.localRepoLocation(Hub.Repo(id: "mlx-community/test"))
        NSLog("📂 下载目录 (Caches):    \(cacheDir.deletingLastPathComponent().deletingLastPathComponent().path)")
        NSLog("📂 持久化目录 (Documents): \(docsDir.deletingLastPathComponent().deletingLastPathComponent().path)")

        // 启动时检查是否有未完成的下载,自动继续
        Task {
            await checkAndResumeInterruptedDownloads()
        }
    }

    /// 检查并继续中断的下载
    private func checkAndResumeInterruptedDownloads() async {
        for model in Self.availableModels {
            let repoId = model.configuration.name
            guard let metadata = DownloadMetadataManager.shared.loadMetadata(for: repoId) else {
                continue
            }

            // 有 pending 文件,说明下载未完成
            if !metadata.pendingFiles.isEmpty {
                NSLog("📥 发现中断的下载: \(model.name), 待下载 \(metadata.pendingFiles.count) 个文件")

                // 检查是否有文件真实存在
                let hasRealFiles = metadata.completedFiles.contains { filename in
                    let dest = downloadHubApi.localRepoLocation(repo(for: model.configuration))
                        .appendingPathComponent(filename)
                    return FileManager.default.fileExists(atPath: dest.path)
                }

                if hasRealFiles || metadata.completedFiles.count > 0 {
                    // 自动继续下载
                    do {
                        try await downloadModel(model)
                        NSLog("✅ 自动继续下载完成: \(model.name)")
                    } catch {
                        NSLog("⚠️ 自动继续下载失败: \(model.name) - \(error.localizedDescription)")
                    }
                } else {
                    // 没有真实文件,删除元数据重新下载
                    NSLog("⚠️ 元数据存在但无真实文件,重新创建: \(model.name)")
                    DownloadMetadataManager.shared.deleteMetadata(for: repoId)
                }
            }
        }
    }

    // MARK: - 工具方法:从 ModelConfiguration 构造 Hub.Repo

    /// ModelConfiguration.name 格式为 "org/repo",直接用它构造 Hub.Repo
    private func repo(for configuration: ModelConfiguration) -> Hub.Repo {
        Hub.Repo(id: configuration.name)
    }

    // MARK: - 模型存在性检查
    /// 检查模型是否已下载(使用元数据判断)
    func isModelDownloaded(_ model: LMModel) -> Bool {
        if modelCache.object(forKey: model.name as NSString) != nil { return true }

        // 1. 使用元数据判断
        let repoId = model.configuration.name
        if let metadata = DownloadMetadataManager.shared.loadMetadata(for: repoId) {
            if !metadata.completedFiles.isEmpty && metadata.pendingFiles.isEmpty {
                return true
            }
        }

        // 2. 兼容:检查目录
        for hubApi in [persistentHubApi, downloadHubApi] {
            let dir = hubApi.localRepoLocation(repo(for: model.configuration))
            if let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path), !files.isEmpty {
                return true
            }
        }

        return false
    }


    /// 检查模型文件是否完整下载(必须有 config.json,否则视为未完成)
    /// 只检查目录存在是不够的--目录可能是上次下载失败的残留

    /// 检查模型是否已下载(接受模型名称字符串,供 View 直接调用)
    func isModelDownloaded(_ modelName: String) -> Bool {
        guard let model = Self.availableModels.first(where: { $0.name == modelName }) else {
            return false
        }
        return isModelDownloaded(model)
    }

    /// 获取已下载模型占用磁盘空间(字节)
    /// 只计算已完成的文件，不包括 .tmp 文件
    func modelDiskSize(_ model: LMModel) -> Int64? {
        
        // 检查两个目录：Documents 和 Caches
        let docsDir = persistentHubApi.localRepoLocation(repo(for: model.configuration))
        let cacheDir = downloadHubApi.localRepoLocation(repo(for: model.configuration))
        
        var total: Int64 = 0
        
        // 遍历目录并累加文件大小
        for dir in [docsDir, cacheDir] {
            guard FileManager.default.fileExists(atPath: dir.path) else { continue }
            
            let sizeKey = URLResourceKey.fileSizeKey
            guard let enumerator = FileManager.default.enumerator(
                at: dir, includingPropertiesForKeys: [sizeKey], options: .skipsHiddenFiles
            ) else { continue }
            
            for case let url as URL in enumerator {
                // 排除 .tmp 文件（未完成的下载）
                if url.pathExtension == "tmp" {
                    continue
                }
                if let size = try? url.resourceValues(forKeys: [sizeKey]).fileSize {
                    total += Int64(size)
                }
            }
        }
        
        return total > 0 ? total : nil
    }
    
    /// 计算下载进度（供 View 使用）
    func calculateDownloadProgress(repoId: String) -> (filesDone: Int, filesTotal: Int, progress: Double)? {
        guard let metadata = DownloadMetadataManager.shared.loadMetadata(for: repoId) else {
            return nil
        }
        
        let files = Array(metadata.files.values)
        let filesTotal = files.count
        guard filesTotal > 0 else { return nil }
        
        // 检查 Caches 和 Documents 目录
        let cacheDir = downloadHubApi.localRepoLocation(Hub.Repo(id: repoId))
        let docsDir = persistentHubApi.localRepoLocation(Hub.Repo(id: repoId))
        
        var filesDone = 0
        var actualDownloadedBytes: Int64 = 0
        var actualTotalBytes: Int64 = 0
        
        for record in files {
            actualTotalBytes += record.size
            
            let cacheFile = cacheDir.appendingPathComponent(record.id)
            let cacheTmpFile = cacheDir.appendingPathComponent(record.id + ".tmp")
            let docsFile = docsDir.appendingPathComponent(record.id)
            let docsTmpFile = docsDir.appendingPathComponent(record.id + ".tmp")
            
            var foundSize: Int64? = nil
            
            // 检查已完成文件
            if FileManager.default.fileExists(atPath: cacheFile.path) {
                if let attrs = try? FileManager.default.attributesOfItem(atPath: cacheFile.path),
                   let size = attrs[.size] as? Int64 {
                    foundSize = size
                }
            } else if FileManager.default.fileExists(atPath: docsFile.path) {
                if let attrs = try? FileManager.default.attributesOfItem(atPath: docsFile.path),
                   let size = attrs[.size] as? Int64 {
                    foundSize = size
                }
            }
            
            // 检查 .tmp 文件
            if foundSize == nil {
                if FileManager.default.fileExists(atPath: cacheTmpFile.path) {
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: cacheTmpFile.path),
                       let size = attrs[.size] as? Int64 {
                        foundSize = size
                    }
                } else if FileManager.default.fileExists(atPath: docsTmpFile.path) {
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: docsTmpFile.path),
                       let size = attrs[.size] as? Int64 {
                        foundSize = size
                    }
                }
            }
            
            if let size = foundSize {
                actualDownloadedBytes += size
                if size >= record.size { // 文件已完整下载
                    filesDone += 1
                }
            }
        }
        
        // 检查额外的 .tmp 文件
        for dir in [cacheDir, docsDir] {
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
                for filename in contents where filename.hasSuffix(".tmp") {
                    let filePath = dir.appendingPathComponent(filename)
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: filePath.path),
                       let size = attrs[.size] as? Int64 {
                        actualDownloadedBytes += size
                    }
                }
            }
        }
        
        let progress = actualTotalBytes > 0 ? Double(actualDownloadedBytes) / Double(actualTotalBytes) : 0
        
        return (filesDone, filesTotal, progress)
    }
    
    /// 获取需要下载的文件列表（从远程获取，过滤出需要下载的文件）
    /// - Parameter repoId: 模型 repoId
    /// - Returns: 需要下载的文件列表 [(filename, size)]
    func getPendingDownloadFiles(repoId: String) async throws -> [(filename: String, size: Int64)] {
        // 1. 从远程获取文件列表
        let apiURL = URL(string: "https://huggingface.co/api/models/\(repoId)")!
        let (data, response) = try await URLSession.shared.data(from: apiURL)
        
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw MLXError.networkError
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let siblings = json["siblings"] as? [[String: Any]] else {
            throw MLXError.parseError
        }
        
        // 2. 构建远程文件列表
        var remoteFiles: [(filename: String, size: Int64)] = []
        for item in siblings {
            guard let filename = item["rfilename"] as? String else { continue }
            let size = item["size"] as? Int64 ?? 0
            remoteFiles.append((filename, size))
        }
        
        // 3. 检查已存在的文件
        let cacheDir = downloadHubApi.localRepoLocation(Hub.Repo(id: repoId))
        let docsDir = persistentHubApi.localRepoLocation(Hub.Repo(id: repoId))
        
        // 4. 过滤出需要下载的文件（不存在的或未完成的）
        var pendingFiles: [(filename: String, size: Int64)] = []
        for file in remoteFiles {
            let cacheFile = cacheDir.appendingPathComponent(file.filename)
            let docsFile = docsDir.appendingPathComponent(file.filename)
            
            // 检查文件是否已存在
            let existsAtCache = FileManager.default.fileExists(atPath: cacheFile.path)
            let existsAtDocs = FileManager.default.fileExists(atPath: docsFile.path)
            let exists = existsAtCache || existsAtDocs
            
            if !exists {
                pendingFiles.append(file)
            }
        }
        
        return pendingFiles
    }

    /// 删除本地已下载的模型文件
    func deleteModel(_ model: LMModel) throws {
        modelCache.removeObject(forKey: model.name as NSString)

        // 1. 删除两个目录的文件
        for dir in [
            persistentHubApi.localRepoLocation(repo(for: model.configuration)),
            downloadHubApi.localRepoLocation(repo(for: model.configuration))
        ] {
            if FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.removeItem(at: dir)
            }
        }

        // 2. 删除元数据(否则 isModelDownloaded 会误判为已下载)
        let repoId = model.configuration.name
        DownloadMetadataManager.shared.deleteMetadata(for: repoId)

        NSLog("🗑️ 已删除模型: \(model.name)")
    }

    // MARK: - SettingsView 兼容接口

    /// 获取已下载的模型列表
    func getDownloadedModels() -> [LMModel] {
        Self.availableModels.filter { isModelDownloaded($0) }
    }

    /// 获取模型磁盘占用(按模型名查找)
    func getModelSize(_ modelName: String) -> Int64? {
        guard let model = Self.availableModels.first(where: { $0.name == modelName }) else {
            return nil
        }
        return modelDiskSize(model)
    }

    /// 删除模型(按模型名,供 SettingsView 使用)
    func removeModel(_ modelName: String) {
        guard let model = Self.availableModels.first(where: { $0.name == modelName }) else {
            NSLog("removeModel: 找不到模型 \(modelName)")
            return
        }
        try? deleteModel(model)
    }


    // MARK: - 诊断

    /// 批量检测所有模型在当前镜像下是否可访问(用于启动时诊断)
    func checkAllModelsAccessibility() async -> [String: Bool] {
        var results: [String: Bool] = [:]
        await withTaskGroup(of: (String, Bool).self) { group in
            for model in Self.availableModels {
                group.addTask {
                    let repoId = model.configuration.name
                    let urlString = "https://hf-mirror.com/api/models/\(repoId)"
                    guard let url = URL(string: urlString) else { return (model.name, false) }
                    do {
                        let (_, response) = try await URLSession.shared.data(from: url)
                        let ok = (response as? HTTPURLResponse)?.statusCode == 200
                        return (model.name, ok)
                    } catch {
                        return (model.name, false)
                    }
                }
            }
            for await (name, accessible) in group {
                results[name] = accessible
                NSLog(accessible ? "✅ 可访问: \(name)" : "❌ 不可访问: \(name)")
            }
        }
        return results
    }

    // MARK: - 模型加载(核心)

    // MARK: - 目录查找

    /// 返回模型的本地目录:优先 Documents(持久化),其次 Caches(刚下载)
    private func localModelDirectory(for model: LMModel) -> URL {
        let docsDir   = persistentHubApi.localRepoLocation(repo(for: model.configuration))
        let cachesDir = downloadHubApi.localRepoLocation(repo(for: model.configuration))

        let configInDocs   = docsDir.appendingPathComponent("config.json").path
        let configInCaches = cachesDir.appendingPathComponent("config.json").path

        if FileManager.default.fileExists(atPath: configInDocs) {
            NSLog("📂 使用 Documents 目录: \(docsDir.path)")
            return docsDir
        }
        NSLog("📂 使用 Caches 目录: \(cachesDir.path)")
        return cachesDir
    }

    // MARK: - 加载模型(核心)

    /// 加载优先级:内存缓存 → Documents → Caches → 下载到 Caches 再迁移到 Documents
    private func load(model: LMModel) async throws -> ModelContainer {
        NSLog("load(\(model.name)) 开始")

        // 1. 内存缓存命中
        if let cached = modelCache.object(forKey: model.name as NSString) {
            NSLog("⚡️ 内存缓存命中: \(model.name)")
            return cached
        }

        Memory.cacheLimit = 20 * 1024 * 1024

        await MainActor.run {
            self.isLoadingModel = true
            self.modelDownloadProgress = nil
        }
        defer { Task { @MainActor in self.isLoadingModel = false } }

        // 2. 文件不存在时先下载到 Caches
        if !isModelDownloaded(model) {
            NSLog("📥 文件未完整,启动下载: \(model.name)")
            try await runResumableDownload(model: model)
            // 下载完成后迁移到 Documents(持久化)
            migrateModelToDocuments(model)
        }

        // 3. 找到本地目录(Documents 优先,其次 Caches)
        let localDir = localModelDirectory(for: model)
        NSLog("📦 从本地目录加载: \(localDir.path)")

        // 4. 用本地路径构造 ModelConfiguration,Hub 库看到 directory 形式的 id
        //    会直接读本地文件,不请求 revision API,完全离线
        let localConfig = ModelConfiguration(directory: localDir)

        let factory: ModelFactory = switch model.type {
            case .llm: LLMModelFactory.shared
            case .vlm: VLMModelFactory.shared
        }

        let container: ModelContainer
        do {
            container = try await factory.loadContainer(
                hub: downloadHubApi,          // hub 仍需传入,但 directory config 不会触发网络请求
                configuration: localConfig
            ) { _ in }
        } catch {
            NSLog("❌ loadContainer 失败: \(error)")
            NSLog("❌ 详情: \((error as NSError).domain) code=\((error as NSError).code)")
            throw error
        }

        modelCache.setObject(container, forKey: model.name as NSString)
        NSLog("✅ 模型加载完成: \(model.name)")
        return container
    }

    /// 下载完成后将模型从 Caches 迁移到 Documents(防止系统在磁盘不足时清除)
    private func migrateModelToDocuments(_ model: LMModel) {
        let src = downloadHubApi.localRepoLocation(repo(for: model.configuration))
        let dst = persistentHubApi.localRepoLocation(repo(for: model.configuration))

        guard FileManager.default.fileExists(atPath: src.path),
              !FileManager.default.fileExists(atPath: dst.path) else {
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: dst.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: src, to: dst)
            NSLog("📦 模型已迁移到 Documents: \(model.name)")
        } catch {
            NSLog("⚠️ 迁移失败(Caches 版本仍可用): \(error)")
        }
    }

    /// 启动 ResumableModelDownloader,下载到 Caches 目录(iOS 过滤 + 元数据)
    private func runResumableDownload(model: LMModel) async throws {
        let destDir = downloadHubApi.localRepoLocation(repo(for: model.configuration))

        let downloader = ResumableModelDownloader.iOSDownloader(
            repoId: model.configuration.name,
            mirrorBase: "https://hf-mirror.com",
            destinationDir: destDir
        )

        let progress = Progress(totalUnitCount: 100)
        await MainActor.run {
            self.modelDownloadProgress = progress
            self.downloadStatus = DownloadStatusDetail(
                modelName: model.name,
                currentFile: "准备下载...",
                downloadedBytes: 0,
                totalBytes: 0,
                filesDone: 0,
                filesTotal: 0
            )
        }

        // 启动独立的进度监控 Task
        let progressTask = Task { @MainActor in
            await self.monitorDownloadProgress(repoId: model.configuration.name, progress: progress)
        }

        _ = try await downloader.download(modelName: model.name) { downloaded, total, filesDone, filesTotal in
            // 下载回调仅更新 Progress 对象,UI 观察通过 monitor task 更新
            Task { @MainActor in
                if total > 0 {
                    progress.totalUnitCount = total
                    progress.completedUnitCount = downloaded
                }
            }
        }

        // 取消监控 Task
        progressTask.cancel()

        await MainActor.run {
            self.modelDownloadProgress = nil
            self.downloadStatus = nil
        }
    }

    /// 独立的 Task 监控下载进度，定期从元数据管理器读取最新状态
    @MainActor
    private func monitorDownloadProgress(repoId: String, progress: Progress) async {
        while !Task.isCancelled {
            // 等待 0.5 秒后检查
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            guard let metadata = DownloadMetadataManager.shared.loadMetadata(for: repoId) else {
                continue
            }

            // 计算当前下载状态 - 实时检查文件系统中的文件
            let files = Array(metadata.files.values)
            let downloadingFile = files.first(where: { $0.status == .downloading })
            let filesDone = files.filter { $0.status == .completed }.count
            let filesTotal = files.count
            
            // 从文件系统检查实际下载的文件大小
            var actualDownloadedBytes: Int64 = 0
            var actualTotalBytes: Int64 = 0
            
            // 检查 Caches 目录
            let cacheDir = downloadHubApi.localRepoLocation(Hub.Repo(id: repoId))
            // 检查 Documents 目录
            let docsDir = persistentHubApi.localRepoLocation(Hub.Repo(id: repoId))
            
            // 1. 遍历元数据中的文件
            for (_, record) in metadata.files {
                actualTotalBytes += record.size
                
                // 检查文件是否真实存在于 Caches 或 Documents（也检查 .tmp 文件）
                let cacheFile = cacheDir.appendingPathComponent(record.id)
                let cacheTmpFile = cacheDir.appendingPathComponent(record.id + ".tmp")
                let docsFile = docsDir.appendingPathComponent(record.id)
                let docsTmpFile = docsDir.appendingPathComponent(record.id + ".tmp")
                
                // 优先检查已完成文件
                var foundSize: Int64? = nil
                
                if FileManager.default.fileExists(atPath: cacheFile.path) {
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: cacheFile.path),
                       let size = attrs[.size] as? Int64 {
                        foundSize = size
                    }
                } else if FileManager.default.fileExists(atPath: docsFile.path) {
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: docsFile.path),
                       let size = attrs[.size] as? Int64 {
                        foundSize = size
                    }
                }
                
                // 如果没有找到完成文件，检查 .tmp 文件（正在下载中）
                if foundSize == nil {
                    if FileManager.default.fileExists(atPath: cacheTmpFile.path) {
                        if let attrs = try? FileManager.default.attributesOfItem(atPath: cacheTmpFile.path),
                           let size = attrs[.size] as? Int64 {
                            foundSize = size
                        }
                    } else if FileManager.default.fileExists(atPath: docsTmpFile.path) {
                        if let attrs = try? FileManager.default.attributesOfItem(atPath: docsTmpFile.path),
                           let size = attrs[.size] as? Int64 {
                            foundSize = size
                        }
                    }
                }
                
                if let size = foundSize {
                    actualDownloadedBytes += size
                }
            }
            
            // 2. 额外检查目录中可能存在的 .tmp 文件（不在元数据中的）
            let tmpFiles = [cacheDir, docsDir].flatMap { dir -> [(String, Int64)] in
                guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
                    return []
                }
                return contents
                    .filter { $0.hasSuffix(".tmp") }
                    .compactMap { filename -> (String, Int64)? in
                        let filePath = dir.appendingPathComponent(filename)
                        if let attrs = try? FileManager.default.attributesOfItem(atPath: filePath.path),
                           let size = attrs[.size] as? Int64 {
                            // 排除已经在元数据中计算过的文件
                            let originalName = String(filename.dropLast(4)) // 去掉 .tmp
                            if metadata.files[originalName] == nil {
                                return (filename, size)
                            }
                        }
                        return nil
                    }
            }
            for (_, size) in tmpFiles {
                actualDownloadedBytes += size
            }

            // 更新 downloadStatus 触发 UI 刷新
            NSLog("DownloadStatus: actualTotalBytes: \(actualTotalBytes), filesDone: \(filesDone), filesTotal: \(filesTotal)")
            self.downloadStatus = DownloadStatusDetail(
                modelName: repoId,
                currentFile: downloadingFile?.id ?? (metadata.pendingFiles.isEmpty ? "完成" : "等待中"),
                downloadedBytes: actualDownloadedBytes,
                totalBytes: actualTotalBytes,
                filesDone: filesDone,
                filesTotal: filesTotal
            )

            // 同时更新 Progress 对象（确保一致性）
            if actualTotalBytes > 0 {
                progress.totalUnitCount = actualTotalBytes
                progress.completedUnitCount = actualDownloadedBytes
            }

            // 如果所有文件完成，退出监控
            if metadata.pendingFiles.isEmpty && filesDone > 0 {
                break
            }
        }
    }

    // MARK: - 手动预下载

    /// 预下载模型到磁盘,不占用 GPU 内存(适合在设置页面提前下载)
    func downloadModel(_ model: LMModel) async throws {
        NSLog("📥 手动预下载: \(model.name)")

        await MainActor.run {
            self.isLoadingModel = true
            self.modelDownloadProgress = nil
            self.downloadStatus = DownloadStatusDetail(
                modelName: model.name,
                currentFile: "准备下载...",
                downloadedBytes: 0,
                totalBytes: 0,
                filesDone: 0,
                filesTotal: 0
            )
        }
        defer {
            Task { @MainActor in
                self.isLoadingModel = false
                self.modelDownloadProgress = nil
                self.downloadStatus = nil
            }
        }

        try await runResumableDownload(model: model)
        migrateModelToDocuments(model)
        NSLog("✅ 预下载完成,已迁移到 Documents: \(model.name)")
    }

    // MARK: - 文本生成

    /// 生成文本流
    /// - Parameters:
    ///   - messages: 对话消息列表(含图片/视频 URL)
    ///   - model: 使用的模型
    /// - Returns: 异步 Token 生成流
    func generate(messages: [Message], model: LMModel) async throws -> AsyncStream<Generation> {

        // 检查是否在后台
        if !isAppInForeground {
            NSLog("⚠️ 应用在后台,等待回到前台...")
            // 等待回到前台(最多等 30 秒)
            for _ in 0..<30 {
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 秒
                if isAppInForeground {
                    NSLog("✅ 应用已回到前台,开始生成")
                    break
                }
            }

            if !isAppInForeground {
                throw MLXError.appInBackground
            }
        }

        NSLog("generate() 使用模型: \(model.name)")
        let modelContainer = try await load(model: model)

        let chat = messages.map { message -> Chat.Message in
            let role: Chat.Message.Role = switch message.role {
                case .assistant: .assistant
                case .user:      .user
                case .system:    .system
            }
            NSLog("message role=\(role), images=\(message.images.count), videos=\(message.videos.count)")
            let images: [UserInput.Image] = message.images.map { .url($0) }
            let videos: [UserInput.Video] = message.videos.map { .url($0) }
            return Chat.Message(role: role, content: message.content, images: images, videos: videos)
        }

        // Create a local copy of the processing configuration
        let processing = UserInput.Processing(resize: .init(width: 1024, height: 1024))

        return try await modelContainer.perform { (context: ModelContext) in
            // Create the UserInput inside the closure to avoid capturing non-Sendable types
            let userInput = UserInput(
                chat: chat,
                processing: processing
            )
            let lmInput = try await context.processor.prepare(input: userInput)
            let parameters = GenerateParameters(maxTokens:128, temperature: 0.2, topP: 0.4, repetitionPenalty: 1.05)
            return try MLXLMCommon.generate(input: lmInput, parameters: parameters, context: context)
        }
    }
}

// MARK: - MLX 错误类型

enum MLXError: Error {
    case appInBackground
    case modelNotLoaded
    case generationFailed(String)
    case networkError
    case parseError
}
