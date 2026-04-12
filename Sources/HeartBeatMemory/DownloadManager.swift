// MARK: - 下载任务模型
struct DownloadTask: Identifiable {
    let id: String
    let url: URL
    let fileName: String
    var status: DownloadStatus
    var progress: Double
    var tempPath: String?
}

enum DownloadStatus: String {
    case pending, downloading, paused, stopped, completed, failed
}

// MARK: - 下载管理器
class DownloadManager: ObservableObject {
    static let shared = DownloadManager()
    
    @Published var downloadingTasks: [DownloadTask] = []
    @Published var completedFiles: [DownloadedFile] = []
    
    private let fileManager = FileManager.default
    private var activeDownloads: [String: URLSessionDownloadTask] = []
    
    private var downloadsDir: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Downloads")
    }
    
    private var tempDir: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Temp")
    }
    
    init() {
        try? fileManager.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        cleanupIncompleteDownloads()  // 清理.tmp未完成文件
        loadCompletedFilesList()
    }
    
    // MARK: 1. 清理.tmp未完成的文件，删除后可以重新下载
    private func cleanupIncompleteDownloads() {
        do {
            let tempFiles = try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            for file in tempFiles where file.pathExtension == "tmp" {
                try fileManager.removeItem(at: file)
                print("已删除未完成的临时文件: \(file.lastPathComponent)")
            }
        } catch {
            print("清理失败: \(error)")
        }
    }
    
    // MARK: 开始下载
    func startDownload(from url: URL, fileName: String? = nil) -> String? {
        let name = fileName ?? url.lastPathComponent
        
        // 检查是否已在下载
        if downloadingTasks.contains(where: { $0.fileName == name && $0.status == .downloading }) {
            print("文件正在下载: \(name)")
            return nil
        }
        
        // 检查是否已存在
        if completedFiles.contains(where: { $0.fileName == name }) {
            print("文件已存在: \(name)")
            return nil
        }
        
        let taskId = UUID().uuidString
        let task = DownloadTask(id: taskId, url: url, fileName: name, status: .downloading, progress: 0)
        
        downloadingTasks.append(task)
        performDownload(task)
        
        return taskId
    }
    
    private func performDownload(_ task: DownloadTask) {
        let session = URLSession.shared
        let downloadTask = session.downloadTask(with: task.url) { [weak self] tempUrl, response, error in
            guard let self = self, let tempUrl = tempUrl else {
                self?.updateTaskStatus(task.id, status: .failed)
                return
            }
            
            let destURL = self.downloadsDir.appendingPathComponent(task.fileName)
            
            do {
                if self.fileManager.fileExists(atPath: destURL.path) {
                    try self.fileManager.removeItem(at: destURL)
                }
                try self.fileManager.moveItem(at: tempUrl, to: destURL)
                
                DispatchQueue.main.async {
                    self.updateTaskStatus(task.id, status: .completed)
                    self.completedFiles.append(DownloadedFile(
                        fileName: task.fileName,
                        filePath: destURL.path,
                        fileSize: (try? self.fileManager.attributesOfItem(atPath: destURL.path)[.size] as? Int64) ?? 0
                    ))
                    self.saveCompletedFilesList()
                }
            } catch {
                self.updateTaskStatus(task.id, status: .failed)
            }
        }
        
        activeDownloads[task.id] = downloadTask
        downloadTask.resume()
    }
    
    private func updateTaskStatus(_ id: String, status: DownloadStatus) {
        if let index = downloadingTasks.firstIndex(where: { $0.id == id }) {
            downloadingTasks[index].status = status
        }
    }
    
    // MARK: 2. 暂停下载
    func pauseDownload(taskId: String) {
        guard let task = activeDownloads[taskId] else { return }
        task.cancel { _ in }
        updateTaskStatus(taskId, status: .paused)
        print("已暂停: \(taskId)")
    }
    
    // MARK: 2. 停止下载 - 删除所有已下载的部分文件
    func stopDownload(taskId: String) {
        if let task = activeDownloads[taskId] {
            task.cancel()
            activeDownloads.removeValue(forKey: taskId)
        }
        
        // 删除临时文件
        if let task = downloadingTasks.first(where: { $0.id == taskId }), let tempPath = task.tempPath {
            try? fileManager.removeItem(atPath: tempPath)
        }
        
        downloadingTasks.removeAll { $0.id == taskId }
        print("已停止并删除: \(taskId)")
    }
    
    // MARK: 3. 删除已下载的指定文件
    func deleteFile(fileName: String) {
        if let index = completedFiles.firstIndex(where: { $0.fileName == fileName }) {
            let file = completedFiles[index]
            try? fileManager.removeItem(atPath: file.filePath)
            completedFiles.remove(at: index)
            saveCompletedFilesList()
            print("已删除: \(fileName)")
        }
    }
    
    // MARK: 重新下载
    func redownload(fileName: String) -> String? {
        guard let file = completedFiles.first(where: { $0.fileName == fileName }) else { return nil }
        return startDownload(from: URL(string: file.filePath) ?? URL(fileURLWithPath: file.filePath), fileName: fileName)
    }
    
    // MARK: 持久化
    private func saveCompletedFilesList() {
        let url = downloadsDir.appendingPathComponent("files.json")
        if let data = try? JSONEncoder().encode(completedFiles) {
            try? data.write(to: url)
        }
    }
    
    private func loadCompletedFilesList() {
        let url = downloadsDir.appendingPathComponent("files.json")
        guard let data = try? Data(contentsOf: url),
              let files = try? JSONDecoder().decode([DownloadedFile].self, from: data) else { return }
        
        // 验证文件是否存在
        completedFiles = files.filter { fileManager.fileExists(atPath: $0.filePath) }
        saveCompletedFilesList()
    }
    
    // MARK: 列表
    func listDownloading() -> [DownloadTask] {
        downloadingTasks.filter { $0.status == .downloading || $0.status == .paused }
    }
    
    func listCompleted() -> [DownloadedFile] {
        completedFiles
    }
}

// MARK: - 已下载文件
struct DownloadedFile: Codable, Identifiable {
    var id: String { fileName }
    let fileName: String
    let filePath: String
    let fileSize: Int64
    
    var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}