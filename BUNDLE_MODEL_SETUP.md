# Xcode 项目配置指南：添加预置模型到 Bundle

## 步骤 1: 检查 LLM 文件夹结构

确保 LLM 文件夹包含完整的模型文件：
```
LLM/
└── Qwen2-VL-2B-Instruct-4bit/
    ├── config.json
    ├── model.safetensors
    ├── model.safetensors.index.json
    ├── preprocessor_config.json
    ├── tokenizer.json
    └── tokenizer_config.json
```

## 步骤 2: 将 LLM 文件夹添加到 Xcode 项目

### 方法 A: 使用 Xcode GUI
1. 打开 `HeartBeatMemory.xcodeproj`
2. 在项目导航器中，右键点击 `HeartBeatMemory` 文件夹
3. 选择 **Add Files to "HeartBeatMemory"...**
4. 选择 `LLM` 文件夹
5. 确保勾选：
   - [x] **Copy items if needed**
   - [x] **Create folder references**
   - **Add to targets**: `HeartBeatMemory`

### 方法 B: 使用命令行（可选）
```bash
# 1. 确保在项目根目录
cd /Users/albertma/sourcecode/workspace/swift/HeartBeatMemory

# 2. 使用 xcodebuild 添加资源（需要手动编辑 .pbxproj）
# 或者直接使用 Xcode GUI 更简单
```

## 步骤 3: 验证 Bundle 资源

在代码中验证模型文件是否在 bundle 中：

```swift
// 测试代码
if let bundleURL = Bundle.main.url(
    forResource: "Qwen2-VL-2B-Instruct-4bit",
    withExtension: nil,
    subdirectory: "LLM"
) {
    print("✅ Bundle 模型路径: \(bundleURL.path)")
    
    let configFile = bundleURL.appendingPathComponent("config.json")
    if FileManager.default.fileExists(atPath: configFile.path) {
        print("✅ config.json 存在")
    } else {
        print("❌ config.json 不存在")
    }
} else {
    print("❌ Bundle 中找不到模型")
}
```

## 步骤 4: 修改 MLXService 的加载逻辑

我已经修改了 `MLXService.swift`，添加了以下功能：

1. **新增错误类型**：
   - `bundleModelNotFound`
   - `bundledModelLoadFailed(String)`

2. **新增方法**：
   - `loadBundledModel(_:)` - 从 bundle 加载预置模型

3. **修改加载优先级**：
   - 优先尝试从 bundle 加载 `qwen2VL:2b` 模型
   - 如果失败，回退到现有下载逻辑

## 关键代码改动

### 1. Bundle 加载方法
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

### 2. 修改后的加载优先级
```swift
private func load(model: LMModel) async throws -> ModelContainer {
    // 1. 内存缓存命中
    // 2. 优先尝试从 Bundle 加载 (预置模型)
    if model.name == "qwen2VL:2b" {
        do {
            let container = try await loadBundledModel(model)
            // ... 缓存并返回
        } catch {
            NSLog("⚠️ Bundle 加载失败,尝试下载: \(error)")
        }
    }
    // 3. 原有下载逻辑...
}
```

## 测试步骤

1. **编译运行**：确保项目编译通过
2. **Bundle 验证**：运行测试代码验证模型文件在 bundle 中
3. **功能测试**：测试 AI 功能是否正常工作
4. **离线测试**：关闭网络，验证应用能否离线使用预置模型

## 注意事项

1. **Bundle 大小**：模型文件约 1.2GB，会增加应用安装包大小
2. **内存使用**：加载大模型时注意内存管理
3. **版本管理**：更新模型时需要重新打包应用
4. **代码签名**：确保模型文件被正确签名

## 故障排除

### 问题 1: Bundle 中找不到模型
- 检查 LLM 文件夹是否添加到 Copy Bundle Resources
- 检查文件夹引用类型（应为蓝色文件夹图标，不是黄色）
- 检查文件路径大小写

### 问题 2: config.json 不存在
- 验证模型文件夹结构
- 检查文件是否被正确复制

### 问题 3: 加载失败
- 检查 ModelConfiguration 初始化
- 验证 HubApi 配置
- 查看控制台日志