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
    
    var body: some View {
        List {
            // 下载进度
            if let progress = mlxService.modelDownloadProgress, !progress.isFinished {
                Section("正在下载") {
                    ProgressView(progress)
                        .progressViewStyle(.linear)
                }
            }
            
            // 模型列表
            Section("可用模型") {
                ForEach(MLXService.availableModels) { model in
                    ModelItemRow(
                        model: model,
                        isDownloaded: isDownloaded(model),
                        diskSize: mlxService.modelDiskSize(model),
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
                        DisclosureGroup {
                            FileListView(modelName: model.configuration.name)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(model.displayName)
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
        .alert("删除模型", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let name = modelToDelete {
                    try? mlxService.removeModel(name)
                }
            }
        } message: {
            Text("确定要删除这个模型吗？")
        }
    }
    
    private func isDownloaded(_ model: LMModel) -> Bool {
        mlxService.isModelDownloaded(model)
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

// MARK: - 文件列表视图

struct FileListView: View {
    let modelName: String
    @State private var files: [(String, Int64)] = []
    @State private var isLoading = true
    
    var body: some View {
        if isLoading {
            ProgressView()
                .onAppear { loadFiles() }
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
    let isDownloaded: Bool
    let diskSize: Int64?
    let onDownload: (() -> Void)?
    let onDelete: (() -> Void)?
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(model.displayName).font(.headline)
                if let size = diskSize {
                    Text(formatSize(size)).font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            if isDownloaded {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                if onDelete != nil {
                    Button { onDelete?() } label: {
                        Image(systemName: "trash").foregroundColor(.red)
                    }.buttonStyle(.plain)
                }
            } else if let onDownload = onDownload {
                Button("下载") { onDownload() }.buttonStyle(.bordered)
            }
        }
    }
    
    private func formatSize(_ bytes: Int64?) -> String {
        guard let b = bytes else { return "未知" }
        let mb = Double(b) / 1024 / 1024
        return mb > 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb)
    }
}

#Preview {
    ModelDownloadView()
}
