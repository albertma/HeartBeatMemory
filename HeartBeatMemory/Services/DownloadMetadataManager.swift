import Foundation

// MARK: - 下载状态

enum DownloadStatus: String, Codable {
    case pending
    case downloading
    case completed
    case failed
}

// MARK: - 单个文件下载记录

struct FileDownloadRecord: Codable, Identifiable {
    let id: String
    var status: DownloadStatus
    var size: Int64
    var downloadedSize: Int64
    var errorMessage: String?
    var lastUpdated: Date
    
    init(filename: String, size: Int64 = 0) {
        self.id = filename
        self.status = .pending
        self.size = size
        self.downloadedSize = 0
        self.errorMessage = nil
        self.lastUpdated = Date()
    }
}

// MARK: - 模型下载元数据

struct ModelDownloadMetadata: Codable {
    let repoId: String
    let modelName: String
    var files: [String: FileDownloadRecord]
    var totalSize: Int64
    var downloadedSize: Int64
    let createdAt: Date
    var lastUpdated: Date
    
    init(repoId: String, modelName: String) {
        self.repoId = repoId
        self.modelName = modelName
        self.files = [:]
        self.totalSize = 0
        self.downloadedSize = 0
        self.createdAt = Date()
        self.lastUpdated = Date()
    }
    
    mutating func addFile(_ filename: String, size: Int64) {
        files[filename] = FileDownloadRecord(filename: filename, size: size)
        totalSize += size
    }
    
    mutating func updateFileStatus(_ filename: String, status: DownloadStatus, downloadedSize: Int64? = nil, error: String? = nil) {
        guard var record = files[filename] else { return }
        record.status = status
        if let downloadedSize = downloadedSize {
            record.downloadedSize = downloadedSize
        }
        if let error = error {
            record.errorMessage = error
        }
        record.lastUpdated = Date()
        files[filename] = record
        // 更新总下载大小
        self.downloadedSize = files.values.filter { $0.status == .completed }.reduce(0) { $0 + $1.size }
        lastUpdated = Date()
    }
    
    var pendingFiles: [String] {
        files.values.filter { $0.status == .pending || $0.status == .failed }.map { $0.id }
    }
    
    var completedFiles: [String] {
        files.values.filter { $0.status == .completed }.map { $0.id }
    }
    
    var progress: Double {
        guard totalSize > 0 else { return 0 }
        return Double(downloadedSize) / Double(totalSize)
    }
}

// MARK: - 元数据管理器

class DownloadMetadataManager {
    static let shared = DownloadMetadataManager()
    
    private let fileManager = FileManager.default
    private let metadataDir: URL
    private var metadataCache: [String: ModelDownloadMetadata] = [:]
    
    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        metadataDir = appSupport.appendingPathComponent("DownloadMetadata", isDirectory: true)
        try? fileManager.createDirectory(at: metadataDir, withIntermediateDirectories: true)
    }
    
    private func metadataPath(for repoId: String) -> URL {
        let safeRepoId = repoId.replacingOccurrences(of: "/", with: "_")
        return metadataDir.appendingPathComponent(safeRepoId + ".json")
    }
    
    func loadMetadata(for repoId: String) -> ModelDownloadMetadata? {
        if let cached = metadataCache[repoId] {
            return cached
        }
        let path = metadataPath(for: repoId)
        guard fileManager.fileExists(atPath: path.path) else { return nil }
        
        do {
            let data = try Data(contentsOf: path)
            let metadata = try JSONDecoder().decode(ModelDownloadMetadata.self, from: data)
            metadataCache[repoId] = metadata
            return metadata
        } catch {
            print("⚠️ 加载元数据失败: \(error)")
            return nil
        }
    }
    
    func saveMetadata(_ metadata: ModelDownloadMetadata) {
        do {
            let data = try JSONEncoder().encode(metadata)
            let path = metadataPath(for: metadata.repoId)
            try data.write(to: path, options: .atomic)
            metadataCache[metadata.repoId] = metadata
        } catch {
            print("⚠️ 保存元数据失败: \(error)")
        }
    }
    
    func createMetadata(repoId: String, modelName: String, files: [String], fileSizes: [String: Int64]) -> ModelDownloadMetadata {
        var metadata = ModelDownloadMetadata(repoId: repoId, modelName: modelName)
        for filename in files {
            metadata.addFile(filename, size: fileSizes[filename] ?? 0)
        }
        saveMetadata(metadata)
        return metadata
    }
    
    func updateFileStatus(repoId: String, filename: String, status: DownloadStatus, downloadedSize: Int64? = nil, error: String? = nil) {
        guard let metadata = metadataCache[repoId] ?? loadMetadata(for: repoId) else { return }
        var updated = metadata
        updated.updateFileStatus(filename, status: status, downloadedSize: downloadedSize, error: error)
        saveMetadata(updated)
    }
    
    func deleteMetadata(for repoId: String) {
        try? fileManager.removeItem(at: metadataPath(for: repoId))
        metadataCache.removeValue(forKey: repoId)
    }
}
