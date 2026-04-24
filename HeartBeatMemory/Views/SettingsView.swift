import SwiftUI
import MLXLMCommon
import CoreData

// 全局 MLXService 实例,确保 UI 能响应状态变化
@Observable
class SharedMLXService {
    static let shared = SharedMLXService()

    let mlxService = MLXService()
}

// 全局 PreloadModelService 实例
@Observable
class SharedPreloadModelService {
    static let shared = SharedPreloadModelService()
    
    let preloadService = PreloadModelService.shared
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("openAIKey") private var openAIKey: String = ""
    @AppStorage("autoGenerate") private var autoGenerate: Bool = true
    @AppStorage("generateTime") private var generateTime: Date = Date()
    @AppStorage("llmTemperature") private var llmTemperature: Double = 0.6
    @AppStorage("diaryPrompt") private var diaryPrompt: String = "根据背景关键词，写一篇日记，第一人称，视觉优先，描写光影、氛围、动作，100字内，并给出标题。"

    // MLX Model settings
    @AppStorage("EnableLocalLLM") private var enableLocalLLM: Bool = true
    @AppStorage("MLXModelName") private var selectedModelName: String = ""

    // 使用 @Bindable 让 UI 响应 MLXService 状态变化
    @Bindable private var sharedService = SharedMLXService.shared
    
    // 使用 @Bindable 让 UI 响应 PreloadModelService 状态变化
    @Bindable private var sharedPreloadService = SharedPreloadModelService.shared

    private var mlxService: MLXService { sharedService.mlxService }
    private var preloadService: PreloadModelService { sharedPreloadService.preloadService }

    @State private var showingKeyInput: Bool = false
    @State private var showingModelInfo: Bool = false
    @State private var showingDownloadedModels: Bool = false
    @State private var modelToDelete: String?

    // 检测是否有内置模型
    private var hasBundledModel: Bool {
        mlxService.hasBundledModel
    }
    
    // 获取内置模型信息
    private var bundledModelInfo: (name: String, displayName: String, type: LMModel.ModelType)? {
        // 优先从 MLXService 获取
        if let info = mlxService.bundledModelInfo {
            return info
        }
        
        // 备选：直接返回内置模型信息（即使 bundle 暂时找不到也显示）
        // 这允许用户在 Xcode 项目配置完成后使用内置模型
        return (
            name: "qwen2VL:2b",
            displayName: "Qwen2-VL-2B (内置)",
            type: .vlm
        )
    }
    
    // 预加载状态
    @State private var isPreloading: Bool = false
    @State private var preloadError: String?

    var body: some View {
        NavigationStack {
            List {
                // MLX Model Section
                Section("本地AI模型") {
                    // 内置模型提示
                    if hasBundledModel {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                            Text("内置模型已预装")
                                .font(.subheadline)
                            Spacer()
                            Text("Qwen2-VL-2B")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        .padding(.vertical, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("内置模型未配置")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            Text("请将 LLM 文件夹添加到 Xcode ")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }

                    Toggle("启用本地模型", isOn: $enableLocalLLM)

                    if enableLocalLLM {
                        // 模型选择
                        Picker("选择模型", selection: $selectedModelName) {
                            HStack {
                                Text("Qwen2-VL-2B (内置)")
                                if hasBundledModel {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                } else {
                                    Image(systemName: "questionmark.circle")
                                        .foregroundColor(.orange)
                                }
                            }
                            .tag("qwen2VL:2b")
                            
                            ForEach(MLXService.availableModels.filter { $0.name != "qwen2VL:2b" }) { model in
                                HStack {
                                    Text(model.displayName)
                                    if mlxService.isModelDownloaded(model) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    }
                                }
                                .tag(model.name)
                            }
                        }
                        .onAppear {
                            if selectedModelName.isEmpty {
                                selectedModelName = "qwen2VL:2b"
                            }
                        }

                        // 预加载按钮
                        HStack {
                            if preloadService.isPreloading {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("预加载中...")
                                    .font(.caption)
                            } else if preloadService.isModelLoaded(selectedModelName) {
                                Label("已预加载", systemImage: "bolt.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else {
                                Button {
                                    Task { await preloadSelectedModel() }
                                } label: {
                                    Label("预加载模型", systemImage: "bolt.fill")
                                        .font(.caption)
                                }
                                .disabled(preloadService.isPreloading)
                            }
                            Spacer()
                        }

                        // 模型管理
                        NavigationLink {
                            ModelDownloadView()
                        } label: {
                            Label("管理模型", systemImage: "square.stack.3d.down")
                        }
                    }
                }// LLM Temperature 设置
                Section("生成设置") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Temperature")
                            Spacer()
                            Text(String(format: "%.1f", llmTemperature))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $llmTemperature, in: 0...1, step: 0.1)
                        Text("值越大越有创意，值越小越保守 (0.0-1.0)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("日记 Prompt")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        TextEditor(text: $diaryPrompt)
                            .frame(minHeight: 80)
                            .font(.system(.caption))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                        Text("生成日记时的 prompt 模板，{context} 会替换为背景关键词")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }// End of Temperature

// OpenAI Section (shown when local model is disabled)
//                Section("云端AI设置") {
//                    HStack {
//                        Label("API Key", systemImage: "key")
//                        Spacer()
//                        Button("设置") {
//                            showingKeyInput = true
//                        }
//                    }
//
//                    Text("使用OpenAI GPT模型生成回忆")
//                        .font(.caption)
//                        .foregroundColor(.secondary)
//                }

//                Section("生成设置") {
//                    Toggle("自动生成每日回忆", isOn: $autoGenerate)
//
//                    if autoGenerate {
//                        DatePicker("生成时间", selection: $generateTime, displayedComponents: .hourAndMinute)
//                    }
//                }

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
//            .sheet(isPresented: $showingModelInfo) {
//                ModelInfoView(
//                    modelName: selectedModelName,
//                    modelType: selectedModelType
//                )
//            }
        }
    }

    private var selectedModelType: LMModel.ModelType {
        MLXService.availableModels.first { $0.name == selectedModelName }?.type ?? .llm
    }
    
    // MARK: - 预加载方法
    
    private func preloadSelectedModel() async {
        guard !selectedModelName.isEmpty else { return }
        
        do {
            try await preloadService.preloadModel(selectedModelName)
            preloadError = nil
        } catch {
            preloadError = "预加载失败: \(error.localizedDescription)"
            NSLog("❌ 预加载失败: \(error)")
        }
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

