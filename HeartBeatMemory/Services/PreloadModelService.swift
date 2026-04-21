//
//  PreloadModelService.swift
//  HeartBeatMemory
//
//  Created by albertma on 2026/4/13.
//

import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXVLM
import Hub
import UIKit

/// 专门处理模型预加载的服务
/// 职责: 管理模型预加载到内存缓存，如果选择的是内置模型，则从 Bundle 复制到 Cache 再加载
@Observable
class PreloadModelService {
    
    // MARK: - 单例模式
    static let shared = PreloadModelService()
    
    // MARK: - 私有属性
    
    /// 内存缓存:同一会话内避免重复加载,最多缓存 1 个模型防止 OOM
    private let modelCache = NSCache<NSString, ModelContainer>()
    
    /// MLXService 共享实例 - 用于实际的模型加载
    private let mlxService: MLXService
    
    /// Hub API 用于文件操作
    private let hubApi: HubApi = HubApiExtension.default
    
    // MARK: - 状态属性
    
    /// 预加载状态
    @MainActor
    private(set) var isPreloading: Bool = false
    
    /// 预加载进度 (0.0 - 1.0)
    @MainActor
    private(set) var preloadProgress: Double = 0.0
    
    /// 预加载状态描述
    @MainActor
    private(set) var preloadStatus: String = ""
    
    /// 预加载错误信息
    @MainActor
    private(set) var preloadError: String?
    
    // MARK: - 初始化
    
    private init() {
        self.mlxService = SharedMLXService.shared.mlxService
        modelCache.countLimit = 1
    }
    
    // MARK: - 公共方法
    
    /// 检查模型是否已加载到内存缓存
    func isModelLoaded(_ modelName: String) -> Bool {
        return modelCache.object(forKey: modelName as NSString) != nil
    }
    
    /// 获取已缓存的模型容器
    func getCachedModel(_ modelName: String) -> ModelContainer? {
        return modelCache.object(forKey: modelName as NSString)
    }
    
    /// 预加载模型到内存
    /// - Parameter modelName: 模型名称 (如 "qwen2VL:2b")
    /// - Returns: 成功时无返回值
    func preloadModel(_ modelName: String) async throws {
        // 1. 检查是否已在内存缓存中
        if isModelLoaded(modelName) {
            NSLog("⚡️ 模型已在内存缓存中: \(modelName)")
            return
        }
        
        await MainActor.run {
            self.isPreloading = true
            self.preloadProgress = 0.0
            self.preloadStatus = "开始预加载..."
            self.preloadError = nil
        }
        
        defer {
            Task { @MainActor in
                self.isPreloading = false
                self.preloadStatus = ""
            }
        }
        
        do {
            // 2. 获取模型容器
            let container: ModelContainer
            
            // 检查是否是内置模型
            if modelName == "qwen2VL:2b" && mlxService.hasBundledModel {
                await updateStatus("处理内置模型...", progress: 0.1)
                container = try await loadBundledModel()
            } else {
                await updateStatus("加载模型...", progress: 0.1)
                container = try await loadRegularModel(modelName)
            }
            
            // 3. 放入内存缓存
            await updateStatus("加载到内存缓存...", progress: 0.9)
            modelCache.setObject(container, forKey: modelName as NSString)
            
            await updateStatus("预加载完成", progress: 1.0)
            NSLog("✅ 预加载完成: \(modelName)")
            
        } catch {
            await MainActor.run {
                self.preloadError = "预加载失败: \(error.localizedDescription)"
            }
            NSLog("❌ 预加载失败: \(error)")
            throw error
        }
    }
    
    /// 清除模型缓存
    func clearCache() {
        modelCache.removeAllObjects()
        NSLog("🧹 已清除模型缓存")
    }
    
    // MARK: - 私有方法
    
    /// 更新预加载状态
    @MainActor
    private func updateStatus(_ status: String, progress: Double) async {
        self.preloadStatus = status
        self.preloadProgress = progress
    }
    
    /// 加载内置模型 (Qwen2-VL-2B)
    /// 流程: Bundle → Cache → 加载
    private func loadBundledModel() async throws -> ModelContainer {
        NSLog("📦 处理内置模型...")
        
        // 1. 获取 Bundle 中的模型路径
        guard let bundleURL = mlxService.getBundledModelURL() else {
            throw PreloadError.bundleModelNotFound
        }
        
        await updateStatus("验证模型文件...", progress: 0.2)
        
        // 2. 检查模型文件是否存在
        let configFile = bundleURL.appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: configFile.path) else {
            throw PreloadError.bundleModelNotFound
        }
        
        await updateStatus("准备模型配置...", progress: 0.4)
        
        // 3. 复制到 Cache (如果尚未复制)
        let cacheDir = hubApi.localRepoLocation(Hub.Repo(id: "mlx-community/Qwen2-VL-2B-Instruct-4bit"))
        let cachedModelDir = cacheDir
        
        if !FileManager.default.fileExists(atPath: cachedModelDir.path) {
            await updateStatus("复制模型到缓存...", progress: 0.5)
            try await copyModelToCache(from: bundleURL, to: cachedModelDir)
        }
        
        await updateStatus("加载模型...", progress: 0.7)
        
        // 4. 使用 directory config 加载模型
        let localConfig = ModelConfiguration(directory: cachedModelDir)
        
        let factory: ModelFactory = VLMModelFactory.shared
        
        let container = try await factory.loadContainer(
            hub: hubApi,
            configuration: localConfig
        ) { _ in }
        
        NSLog("✅ Bundle 模型加载成功")
        return container
    }
    
    /// 加载常规模型 (已下载的模型)
    private func loadRegularModel(_ modelName: String) async throws -> ModelContainer {
        NSLog("📦 加载常规模型: \(modelName)")
        
        guard let model = MLXService.availableModels.first(where: { $0.name == modelName }) else {
            throw PreloadError.modelNotFound
        }
        
        // 使用 MLXService 加载模型
        return try await mlxService.load(model: model)
    }
    
    /// 将模型从 Bundle 复制到 Cache 目录
    private func copyModelToCache(from sourceURL: URL, to destURL: URL) async throws {
        let fileManager = FileManager.default
        
        // 创建目标目录
        let destDir = destURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: destDir.path) {
            try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)
        }
        
        // 获取源文件列表
        let sourceFiles = try fileManager.contentsOfDirectory(atPath: sourceURL.path)
        
        // 获取模型目录下的所有文件
        let modelFiles = sourceFiles.filter { file in
            !file.hasPrefix(".")
        }
        
        let totalFiles = modelFiles.count
        var copiedFiles = 0
        
        for file in modelFiles {
            let sourcePath = sourceURL.appendingPathComponent(file)
            let destPath = destURL.appendingPathComponent(file)
            
            // 如果目标文件不存在，复制
            if !fileManager.fileExists(atPath: destPath.path) {
                try fileManager.copyItem(at: sourcePath, to: destPath)
            }
            
            copiedFiles += 1
            let progress = 0.5 + Double(copiedFiles) / Double(totalFiles) * 0.3
            await updateStatus("复制文件 \(copiedFiles)/\(totalFiles)...", progress: progress)
        }
        
        NSLog("📦 模型已复制到 Cache: \(destURL.path)")
    }
}

// MARK: - 错误类型

enum PreloadError: Error, LocalizedError {
    case modelNotFound
    case bundleModelNotFound
    case modelNotDownloaded
    case copyFailed(String)
    case loadFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "模型未找到"
        case .bundleModelNotFound:
            return "内置模型未找到，请检查 Xcode 项目配置"
        case .modelNotDownloaded:
            return "模型未下载，请先下载模型"
        case .copyFailed(let reason):
            return "模型复制失败: \(reason)"
        case .loadFailed(let reason):
            return "模型加载失败: \(reason)"
        }
    }
}

// MARK: - 架构说明

/*
 架构设计:
 
 1. MLXService - 核心模型服务
    - 负责与 MLX 库对接
    - 处理模型下载、加载、管理
    - 提供 Bundle 模型检测功能
 
 2. PreloadModelService - 预加载服务
    - 依赖 MLXService
    - 负责模型预加载到内存缓存
    - 处理内置模型的 Bundle → Cache 复制流程
    - 管理预加载状态和进度
 
 工作流程:
 
 当用户选择预加载内置模型 (qwen2VL:2b):
 1. 检查内存缓存 → 如果存在，直接返回
 2. 检查 Bundle 模型是否存在
 3. 复制 Bundle 模型到 Cache 目录
 4. 从 Cache 目录加载模型到内存
 5. 存入内存缓存
 
 当用户选择预加载已下载模型:
 1. 检查内存缓存 → 如果存在，直接返回
 2. 调用 MLXService 加载模型
 3. 存入内存缓存
 */