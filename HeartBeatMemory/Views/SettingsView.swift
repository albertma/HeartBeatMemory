import SwiftUI
import MLXLMCommon

// 全局 MLXService 实例,确保 UI 能响应状态变化
@Observable
class SharedMLXService {
    static let shared = SharedMLXService()

    let mlxService = MLXService()
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("openAIKey") private var openAIKey: String = ""
    @AppStorage("autoGenerate") private var autoGenerate: Bool = true
    @AppStorage("generateTime") private var generateTime: Date = Date()

    // MLX Model settings
    @AppStorage("EnableLocalLLM") private var enableLocalLLM: Bool = false
    @AppStorage("MLXModelName") private var selectedModelName: String = ""

    // 使用 @Bindable 让 UI 响应 MLXService 状态变化
    @Bindable private var sharedService = SharedMLXService.shared

    private var mlxService: MLXService { sharedService.mlxService }

    @State private var showingKeyInput: Bool = false
    @State private var showingModelInfo: Bool = false
    @State private var showingDownloadedModels: Bool = false
    @State private var modelToDelete: String?

    var body: some View {
        NavigationStack {
            List {
                // MLX Model Section
                Section("本地AI模型") {
                    Toggle("启用本地模型", isOn: $enableLocalLLM)

                    if enableLocalLLM {
                        // Model Selection
                        Picker("选择模型", selection: $selectedModelName) {
                            ForEach(MLXService.availableModels) { model in
                                HStack {
                                    Text(model.displayName)
                                    if mlxService.isModelDownloaded(model) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.caption)
                                    }
                                }
                                .tag(model.name)
                            }
                        }
                        .onAppear {
                            if selectedModelName.isEmpty {
                                selectedModelName = MLXService.availableModels.first?.name ?? ""
                            }
                        }

                        // Download Progress
                        if let progress = mlxService.modelDownloadProgress, !progress.isFinished {
                            ModelDownloadProgressView(progress: progress)
                        }

                        // Downloaded Models List
                        let downloadedModels = mlxService.getDownloadedModels()
                        if !downloadedModels.isEmpty {
                            NavigationLink {
                                DownloadedModelsView(
                                    selectedModelName: $selectedModelName
                                )
                            } label: {
                                HStack {
                                    Label("已下载模型", systemImage: "square.stack.3d.up")
                                    Spacer()
                                    Text("\(downloadedModels.count)个")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        // Download Model Button (for models not yet downloaded)
                        ForEach(MLXService.availableModels.filter { !mlxService.isModelDownloaded($0.name) }) { model in
                            Button {
                                Task {
                                    try? await mlxService.downloadModel(model)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.down.circle")
                                        .foregroundColor(.blue)
                                    Text("下载 \(model.name)")
                                    Spacer()
                                    if mlxService.modelDownloadProgress != nil {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    }
                                }
                            }
                        }
                    }
                }

                // OpenAI Section (shown when local model is disabled)
                Section("云端AI设置") {
                    HStack {
                        Label("API Key", systemImage: "key")
                        Spacer()
                        Button("设置") {
                            showingKeyInput = true
                        }
                    }

                    Text("使用OpenAI GPT模型生成回忆")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("生成设置") {
                    Toggle("自动生成每日回忆", isOn: $autoGenerate)

                    if autoGenerate {
                        DatePicker("生成时间", selection: $generateTime, displayedComponents: .hourAndMinute)
                    }
                }

                Section("数据权限") {
                    NavigationLink("管理访问权限") {
                        PermissionsView()
                    }
                }

                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    Link("隐私政策", destination: URL(string: "https://example.com/privacy")!)
                    Link("使用条款", destination: URL(string: "https://example.com/terms")!)
                }

                Section {
                    Button(role: .destructive) {
                        // 清除数据
                    } label: {
                        Label("清除所有数据", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("设置")
            .sheet(isPresented: $showingKeyInput) {
                APIKeyInputView(key: $openAIKey)
            }
            .sheet(isPresented: $showingModelInfo) {
                ModelInfoView(
                    modelName: selectedModelName,
                    modelType: selectedModelType
                )
            }
        }
    }

    private var selectedModelType: LMModel.ModelType {
        MLXService.availableModels.first { $0.name == selectedModelName }?.type ?? .llm
    }
}

// MARK: - Model Download Progress View

struct ModelDownloadProgressView: View {
    let progress: Progress

    @State private var isShowingDetail: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(.blue)
                Text("下载中...")
                    .font(.subheadline)
                Spacer()
                Text("\(Int(progress.fractionCompleted * 100))%")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            ProgressView(value: progress.fractionCompleted)
                .progressViewStyle(.linear)

            Button {
                isShowingDetail = true
            } label: {
                Text("查看详情")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 8)
        .popover(isPresented: $isShowingDetail, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Text("模型下载中")
                    .font(.headline)

                ProgressView(value: progress.fractionCompleted) {
                    HStack {
                        Text(progress.localizedAdditionalDescription)
                            .bold()
                        Spacer()
                        Text(progress.localizedDescription)
                    }
                }

                Text("首次使用需要下载模型文件,请保持网络连接")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(minWidth: 280)
        }
    }
}

// MARK: - Model Info View

struct ModelInfoView: View {
    let modelName: String
    let modelType: LMModel.ModelType

    // 使用 @Bindable 让 UI 响应状态变化
    @Bindable private var sharedService = SharedMLXService.shared
    private var mlxService: MLXService { sharedService.mlxService }

    @State private var isDownloading: Bool = false
    @State private var downloadError: String?
    @State private var isDownloaded: Bool = false

    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("模型信息") {
                    InfoRow(label: "名称", value: modelName)
                    InfoRow(label: "类型", value: modelType == .llm ? "语言模型" : "视觉语言模型")
                    InfoRow(label: "特点", value: modelDescription)
                    InfoRow(label: "状态", value: isDownloaded ? "已下载" : "未下载")
                }

                Section("存储位置") {
                    Text("App Documents/MLXModels/")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)

                    // Show model size if downloaded
                    if isDownloaded, let size = mlxService.getModelSize(modelName) {
                        InfoRow(label: "大小", value: formatBytes(size))
                    }
                }

                // Download Button Section
                Section {
                    if isDownloaded {
                        Button {
                            // Model already downloaded
                        } label: {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("已下载")
                            }
                        }
                        .disabled(true)
                    } else if isDownloading {
                        Button {
                            // Download in progress
                        } label: {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("下载中...")
                            }
                        }
                        .disabled(true)

                        // Show download progress if available
                        if let progress = mlxService.modelDownloadProgress {
                            VStack(alignment: .leading, spacing: 8) {
                                ProgressView(value: progress.fractionCompleted)
                                    .progressViewStyle(.linear)

                                HStack {
                                    Text(progress.localizedAdditionalDescription)
                                        .font(.caption)
                                    Spacer()
                                    Text("\(Int(progress.fractionCompleted * 100))%")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    } else {
                        Button {
                            Task {
                                await downloadCurrentModel()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.down.circle")
                                    .foregroundColor(.blue)
                                Text("下载模型")
                            }
                        }
                    }

                    if let error = downloadError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Section {
                    Text("首次使用需要下载模型文件,请保持网络连接。下载完成后模型将缓存本地。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("模型详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                checkDownloadStatus()
            }
        }
    }

    private var modelDescription: String {
        switch modelType {
        case .llm:
            return "纯文本生成,适合日常对话和内容创作"
        case .vlm:
            return "支持图像理解,可以分析照片内容"
        }
    }

    private func checkDownloadStatus() {
        isDownloaded = mlxService.isModelDownloaded(modelName)
    }

    private func downloadCurrentModel() async {
        guard let model = MLXService.availableModels.first(where: { $0.name == modelName }) else {
            downloadError = "未找到模型配置"
            return
        }

        isDownloading = true
        downloadError = nil

        do {
            try await mlxService.downloadModel(model)
            isDownloaded = true
            isDownloading = false
        } catch {
            downloadError = "下载失败: \(error.localizedDescription)"
            isDownloading = false
        }
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
    }
}

// MARK: - Helper Functions

private func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}

// MARK: - API Key Input View

struct APIKeyInputView: View {
    @Binding var key: String
    @Environment(\.dismiss) var dismiss
    @State private var inputKey: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("输入API Key", text: $inputKey)
                    Text("请从OpenAI官网获取API Key")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        key = inputKey
                        UserDefaults.standard.set(inputKey, forKey: "OpenAIAPIKey")
                        dismiss()
                    }
                }
            }
            .onAppear { inputKey = key }
        }
    }
}

// MARK: - Permissions View

struct PermissionsView: View {
    var body: some View {
        List {
            PermissionRow(icon: "calendar", title: "日历", description: "读取日历事件")
            PermissionRow(icon: "bell", title: "提醒", description: "读取提醒事项")
            PermissionRow(icon: "photo", title: "照片", description: "读取照片")
            PermissionRow(icon: "location", title: "位置", description: "访问位置历史")
            PermissionRow(icon: "note", title: "备忘录", description: "读取备忘录")
        }
        .navigationTitle("数据权限")
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 32)
                .foregroundColor(.blue)

            VStack(alignment: .leading) {
                Text(title)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        }
    }
}

// MARK: - Downloaded Models View

struct DownloadedModelsView: View {
    @Binding var selectedModelName: String
    
    // 使用 @Bindable 让 UI 响应状态变化
    @Bindable private var sharedService = SharedMLXService.shared
    private var mlxService: MLXService { sharedService.mlxService }
    
    @State private var showingDeleteAlert: Bool = false
    @State private var modelToDelete: String?
    @State private var showingDeleteAllAlert: Bool = false
    
    // 动态获取已下载模型列表
    private var downloadedModels: [LMModel] {
        mlxService.getDownloadedModels()
    }

    var body: some View {
        List {
            Section {
                ForEach(downloadedModels) { model in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.name)
                                .font(.headline)
                            Text(model.isVisionModel ? "视觉语言模型" : "语言模型")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if model.name == selectedModelName {
                            Text("使用中")
                                .font(.caption)
                                .foregroundColor(.blue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                        }

                        Button(role: .destructive) {
                            modelToDelete = model.name
                            showingDeleteAlert = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("已下载模型 (\(downloadedModels.count)个)")
            } footer: {
                Text("删除模型将清除本地缓存文件,释放存储空间。")
            }

            Section {
                Button(role: .destructive) {
                    showingDeleteAllAlert = true
                } label: {
                    HStack {
                        Image(systemName: "trash.slash")
                        Text("删除所有模型")
                    }
                }
            }
        }
        .navigationTitle("已下载模型")
        .alert("删除模型", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                if let name = modelToDelete {
                    mlxService.removeModel(name)
                    if selectedModelName == name {
                        // Reset to first available model
                        if let first = MLXService.availableModels.first {
                            selectedModelName = first.name
                        }
                    }
                }
            }
        } message: {
            Text("确定要删除模型 \"\(modelToDelete ?? "")\" 吗?删除后将无法使用该模型,需要重新下载。")
        }
        .alert("删除所有模型", isPresented: $showingDeleteAllAlert) {
            Button("取消", role: .cancel) { }
            Button("删除全部", role: .destructive) {
                mlxService.clearAllModels()
                if let first = MLXService.availableModels.first {
                    selectedModelName = first.name
                }
            }
        } message: {
            Text("确定要删除所有已下载的模型吗?这将释放所有模型占用的存储空间。")
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
