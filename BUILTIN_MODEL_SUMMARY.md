# 内置模型配置总结

## 已完成的工作

### 1. MLXService.swift 修改
- **新增错误类型**：
  - `bundleModelNotFound`
  - `bundledModelLoadFailed(String)`
  
- **新增 Bundle 模型检测方法**：
  ```swift
  var hasBundledModel: Bool  // 检查是否有内置模型
  func isBundledModel(_ modelName: String) -> Bool  // 检查指定模型是否是内置模型
  var bundledModelInfo: (name: String, displayName: String, type: LMModel.ModelType)?  // 获取内置模型信息
  ```
  
- **新增 Bundle 加载方法**：
  ```swift
  private func loadBundledModel(_ model: LMModel) async throws -> ModelContainer
  ```
  
- **修改加载优先级**：
  ```swift
  // 新的加载顺序：
  // 1. Bundle 预置模型 (qwen2VL:2b)
  // 2. 内存缓存
  // 3. Documents 持久化存储
  // 4. Caches 临时存储
  // 5. 网络下载
  ```

### 2. SettingsView.swift 修改
- **添加内置模型检测**：
  ```swift
  private var hasBundledModel: Bool
  private var bundledModelInfo: (name: String, displayName: String, type: LMModel.ModelType)?
  ```
  
- **修改 UI 显示**：
  - 添加内置模型提示横幅
  - 在模型选择器中优先显示内置模型
  - 显示当前模型状态（已内置/已下载/未下载）
  - 使用不同的图标区分内置模型和下载模型

### 3. ModelDownloadView.swift 修改
- **添加内置模型信息显示**：
  - 在单独的 "内置模型" 区域显示
  - 显示 "开箱即用，无需下载" 提示
  - 使用不同的图标（checkmark.seal.fill）

### 4. 创建测试文件
- `test_bundle_path.swift` - 验证 bundle 路径和文件存在性
- `BUNDLE_MODEL_SETUP.md` - Xcode 项目配置指南

## 使用流程

### 1. 首次启动
1. 用户打开 Settings → 本地AI模型
2. 看到 "内置模型已预装" 提示
3. 启用本地模型开关
4. 自动选择内置模型 "Qwen2-VL-2B (内置)"
5. 状态显示 "已内置"

### 2. 模型管理
1. 点击 "管理模型"
2. 在 ModelDownloadView 中看到：
   - **内置模型**区域：显示预装模型信息
   - **可下载模型**区域：显示其他可下载模型

### 3. 离线使用
1. 关闭网络连接
2. 内置模型仍然可用
3. AI 功能正常工作

## Xcode 项目配置

### 步骤 1: 添加 LLM 文件夹到项目
1. 打开 `HeartBeatMemory.xcodeproj`
2. 右键点击 `HeartBeatMemory` 文件夹
3. 选择 **Add Files to "HeartBeatMemory"...**
4. 选择 `LLM` 文件夹
5. 确保勾选：
   - [x] **Copy items if needed**
   - [x] **Create folder references**
   - **Add to targets**: `HeartBeatMemory`

### 步骤 2: 验证 Bundle 资源
运行 `test_bundle_path.swift` 验证：
```bash
cd /Users/albertma/sourcecode/workspace/swift/HeartBeatMemory
swift test_bundle_path.swift
```

### 步骤 3: 编译测试
1. 编译项目
2. 运行应用
3. 测试 Settings 中的内置模型显示
4. 测试 AI 功能

## 关键代码片段

### Bundle 路径查找
```swift
Bundle.main.url(
    forResource: "Qwen2-VL-2B-Instruct-4bit",
    withExtension: nil,
    subdirectory: "LLM"
)
```

### 内置模型加载
```swift
private func loadBundledModel(_ model: LMModel) async throws -> ModelContainer {
    guard let bundleURL = Bundle.main.url(
        forResource: "Qwen2-VL-2B-Instruct-4bit",
        withExtension: nil,
        subdirectory: "LLM"
    ) else {
        throw MLXError.bundleModelNotFound
    }
    
    let localConfig = ModelConfiguration(directory: bundleURL)
    // ... 加载逻辑
}
```

### Settings 显示
```swift
if hasBundledModel, let info = bundledModelInfo {
    HStack {
        Image(systemName: "checkmark.seal.fill")
            .foregroundColor(.green)
        VStack(alignment: .leading, spacing: 2) {
            Text("内置模型已预装")
                .font(.subheadline)
            Text("无需下载，开箱即用")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        Spacer()
        Text(info.displayName)
            .font(.caption)
            .foregroundColor(.green)
    }
    .padding(.vertical, 4)
}
```

## 故障排除

### 问题 1: Bundle 中找不到模型
- 检查 LLM 文件夹是否添加到 Copy Bundle Resources
- 检查文件夹引用类型（应为蓝色文件夹图标）
- 运行 `test_bundle_path.swift` 验证

### 问题 2: 内置模型不显示
- 检查 `hasBundledModel` 返回值
- 验证 bundle 路径查找逻辑
- 检查模型文件夹结构

### 问题 3: 加载失败
- 检查 ModelConfiguration 初始化
- 验证文件权限
- 查看控制台日志

## 优势

1. **离线可用**：无需网络即可使用 AI 功能
2. **快速启动**：无需下载等待
3. **用户体验**：开箱即用，降低使用门槛
4. **可靠性**：避免网络下载失败问题
5. **一致性**：所有用户使用相同版本的模型