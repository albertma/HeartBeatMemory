import SwiftUI
import MLXLMCommon

/// 单独的模型下载页面
struct ModelDownloadView: View {
    @Bindable private var sharedService = SharedMLXService.shared
    private var mlxService: MLXService { sharedService.mlxService }
    
    @State private var selectedModelName: String = ""
    @State private var showDeleteAlert = false
    @State private var modelToDelete: String?
    @State private var selectedRepo: String?
    @State private var showFiles = false
    @State private var downloadedModels: [LMModel] = []
    
    // 用于触发 View 刷新的计数器
    @State private var refreshTrigger: Int = 0
    
    var body: some View {
        List {
            // 下载进度 - 使用 downloadStatus 进行实时更新
            if let status = mlxService.downloadStatus {
                Section("正在下载") {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: status.progress)
                            .progressViewStyle(.linear)
                        
                        HStack {
                            Text(status.currentFile)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text("\(status.filesDone)/\(status.filesTotal) 文件")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("\(status.formattedDownloaded) / \(status.formattedTotal)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(status.progressPercent)%")
                                .font(.caption)
                                .bold()
                        }
                    }
                }
            } else if let progress = mlxService.modelDownloadProgress, !progress.isFinished {
                Section("正在下载") {
                    ProgressView(progress)
                        .progressViewStyle(.linear)
                }
            }
            
            // 内置模型信息
            if mlxService.hasBundledModel {
                Section("内置模型") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Qwen2-VL-2B (内置)")
                                .font(.headline)
                            Text("开箱即用，无需下载")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("约 1.2 GB")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                            .font(.title2)
                    }
                    .padding(.vertical, 4)
                }
            }
            
            // 可下载模型列表 - 实时更新下载状态
            Section("可下载模型") {
                ForEach(MLXService.availableModels.filter { $0.name != "qwen2VL:2b" }) { model in
                    ModelItemRow(
                        model: model,
                        downloadStatus: getDownloadStatus(for: model),
                        isDownloaded: mlxService.isModelDownloaded(model),
                        onDownload: { download(model) },
                        onDelete: { 
                            modelToDelete = model.name
                            showDeleteAlert = true 
                        }
                    )
                }
            }
            
            // 已下载
            if !downloadedModels.isEmpty {
                Section("已下载 (\(downloadedModels.count))") {
                    ForEach(downloadedModels) { model in
                        DownloadedModelRow(model: model)
                    }
                }
            }
        }
        .navigationTitle("模型管理")
        .onAppear {
            downloadedModels = mlxService.getDownloadedModels()
            if selectedModelName.isEmpty {
                selectedModelName = downloadedModels.first?.name ?? ""
            }
        }
        .onChange(of: mlxService.downloadStatus) { _, newStatus in
            // 当 downloadStatus 变化时，强制刷新 View
            NSLog("Update downloaded status")
            refreshTrigger += 1
            downloadedModels = mlxService.getDownloadedModels()
        }
        .id(refreshTrigger) // 强制刷新
        .alert("删除模型", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let name = modelToDelete {
                    try? mlxService.removeModel(name)
                    downloadedModels = mlxService.getDownloadedModels()
                }
            }
        } message: {
            Text("确定要删除这个模型吗？")
        }
    }
    
    /// 获取模型的下载状态（用于实时显示下载进度）
    /// 优先级：
    /// 1. 直接检查文件是否真实存在（最可靠）
    /// 2. downloadStatus 仅在下载进行中时使用
    /// 3. calculateProgress 计算实际进度
    private func getDownloadStatus(for model: LMModel) -> ModelDownloadState {
        let repoId = model.configuration.name
        
        // 1. 优先：直接检查文件是否真实存在
        if mlxService.isModelDownloaded(model) {
            return .completed
        }
        
        // 2. 检查目录中是否有任何文件（备用判断）
        if checkFilesExist(repoId: repoId) {
            return .completed
        }
        
        // 3. 如果当前有活动下载状态且匹配这个模型
        if let status = mlxService.downloadStatus, status.modelName == repoId {
            if status.filesDone == status.filesTotal && status.filesTotal > 0 {
                return .completed
            }
            return .downloading(
                filesDone: status.filesDone,
                filesTotal: status.filesTotal,
                progress: status.progress
            )
        }
        
        // 4. 使用 MLXService 计算实际下载状态
        if let progressInfo = mlxService.calculateDownloadProgress(repoId: repoId) {
            if progressInfo.filesDone == progressInfo.filesTotal && progressInfo.filesTotal > 0 {
                return .completed
            } else if progressInfo.filesDone > 0 {
                return .downloading(
                    filesDone: progressInfo.filesDone,
                    filesTotal: progressInfo.filesTotal,
                    progress: progressInfo.progress
                )
            }
        }
        
        return .notStarted
    }
    
    /// 直接检查模型文件是否存在
    private func checkFilesExist(repoId: String) -> Bool {
        let fm = FileManager.default
        let docsDir = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("huggingface/models/\(repoId)")
        let cacheDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("huggingface/models/\(repoId)")
        
        // 检查 Documents 目录
        if let contents = try? fm.contentsOfDirectory(atPath: docsDir.path),
           !contents.filter({ !$0.hasPrefix(".") }).isEmpty {
            return true
        }
        
        // 检查 Caches 目录
        if let contents = try? fm.contentsOfDirectory(atPath: cacheDir.path),
           !contents.filter({ !$0.hasPrefix(".") }).isEmpty {
            return true
        }
        
        return false
    }
    
    private func download(_ model: LMModel) {
        Task {
            try? await mlxService.downloadModel(model)
        }
    }
    
    private func formatSize(_ bytes: Int64?) -> String {
        guard let bytes = bytes else { return "" }
        let mb = Double(bytes) / 1024 / 1024
        if mb > 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        return String(format: "%.0f MB", mb)
    }
}

// MARK: - 模型下载状态枚举

enum ModelDownloadState {
    case notStarted          // 未开始
    case downloading(filesDone: Int, filesTotal: Int, progress: Double)  // 下载中
    case completed          // 已完成
}

// MARK: - 文件列表视图

struct FileListView: View {
    let modelName: String
    @State private var files: [(String, Int64)] = []
    @State private var isLoading = true
    @State private var downloadStatus: DownloadStatusDetail?
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if files.isEmpty {
                Text("无文件").foregroundColor(.secondary)
            } else {
                ForEach(files, id: \.0) { file, size in
                    HStack {
                        Image(systemName: iconFor(file))
                            .foregroundColor(.secondary)
                        Text(file)
                            .font(.caption)
                        Spacer()
                        Text(formatSize(size))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .onAppear {
            loadFiles()
            downloadStatus = SharedMLXService.shared.mlxService.downloadStatus
        }
        .onChange(of: SharedMLXService.shared.mlxService.downloadStatus) { _, newStatus in
            downloadStatus = newStatus
            loadFiles()
        }
    }
    
    private func loadFiles() {
        let repoId = modelName
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("huggingface/models/\(repoId)")
        let cache = fm.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("huggingface/models/\(repoId)")
        
        var allFiles: [(String, Int64)] = []
        
        for dir in [docs, cache] {
            NSLog("current dir: \(dir.absoluteString)")
            if let contents = try? fm.contentsOfDirectory(atPath: dir.path) {
                for f in contents where !f.hasPrefix(".") {
                    let path = dir.appendingPathComponent(f)
                    if let attrs = try? fm.attributesOfItem(atPath: path.path),
                       let size = attrs[.size] as? Int64 {
                        allFiles.append((f, size))
                    }
                }
            }
        }
        
        files = allFiles.sorted { $0.0 < $1.0 }
        isLoading = false
    }
    
    private func iconFor(_ file: String) -> String {
        if file.hasSuffix(".safetensors"){
            return "cpu"
        } else if file.hasSuffix(".json") {
            return "doc.text"
        }
        return "doc"
    }
    
    private func formatSize(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1024 / 1024
        if mb > 1024 { return String(format: "%.1f GB", mb / 1024) }
        if mb > 1 { return String(format: "%.0f MB", mb) }
        return String(format: "%.0f KB", mb * 1024)
    }
}

// MARK: - Row Views

struct ModelItemRow: View {
    let model: LMModel
    let downloadStatus: ModelDownloadState  // 新增：下载状态
    let isDownloaded: Bool
    let onDownload: (() -> Void)?
    let onDelete: (() -> Void)?
    
    @Bindable private var sharedService = SharedMLXService.shared
    private var mlxService: MLXService { sharedService.mlxService }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(model.displayName).font(.headline)
                
                // 动态获取磁盘大小
                if let size = mlxService.modelDiskSize(model) {
                    Text(formatSize(size)).font(.caption).foregroundColor(.secondary)
                }
                
                // 显示下载进度
                if case .downloading(let done, let total, let progress) = downloadStatus {
                    HStack(spacing: 4) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .frame(width: 80)
                        Text("\(done)/\(total)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 2)
                }
            }
            Spacer()
            
            // 根据状态显示不同的 UI
            switch downloadStatus {
            case .notStarted:
                if let onDownload = onDownload {
                    Button("下载") { onDownload() }.buttonStyle(.bordered)
                }
                
            case .downloading:
                Button("下载中") {}
                    .buttonStyle(.bordered)
                    .disabled(true)
                    .tint(.gray)
                
            case .completed:
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                if onDelete != nil {
                    Button { onDelete?() } label: {
                        Image(systemName: "trash").foregroundColor(.red)
                    }.buttonStyle(.plain)
                }
            }
        }
    }
    
    private func formatSize(_ bytes: Int64?) -> String {
        guard let b = bytes else { return "未知" }
        let mb = Double(b) / 1024 / 1024
        return mb > 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb)
    }
}

// MARK: - 已下载模型行（带动态大小更新）

struct DownloadedModelRow: View {
    let model: LMModel
    
    @Bindable private var sharedService = SharedMLXService.shared
    private var mlxService: MLXService { sharedService.mlxService }
    
    var body: some View {
        DisclosureGroup {
            FileListView(modelName: model.configuration.name)
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(model.displayName).font(.headline)
                    // 动态获取磁盘大小
                    if let size = mlxService.modelDiskSize(model) {
                        Text(formatSize(size))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
    }
    
    private func formatSize(_ bytes: Int64?) -> String {
        guard let b = bytes else { return "" }
        let mb = Double(b) / 1024 / 1024
        
        if mb > 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }else if (mb > 1.0){
            return String(format: "%.0f MB", mb)
        }else {
            let kb = Double(b) / 1024
            if kb > 1.0{
                return String(format: "%.f KB", kb)
            }else{
                return String(format: "%d Bytes", b)
            }
        }
        
      
    }
}

#Preview {
    ModelDownloadView()
}
