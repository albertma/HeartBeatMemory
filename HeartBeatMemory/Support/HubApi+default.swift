//
//  HubApiExtension.swift
//  HeartBeatMemory
//
//  Created by albertma on 2026/3/30.
//

import Foundation
import Hub

enum HubApiExtension {

    // MARK: - 镜像配置

    /// 必须在 App 启动最早期调用（早于任何 HubApi/MLXService 初始化）
    static func configureMirror() {
//        setenv("HF_ENDPOINT", "https://hf-mirror.com", 1)
//        print("🔀 HF_ENDPOINT 已设置为 hf-mirror.com")
    }

    // MARK: - 下载用（Caches）

    /// 下载时使用：指向 Library/Caches/huggingface
    /// Hub 库在 Caches 路径下行为正常，能正确完成下载
    /// ⚠️ iOS 磁盘不足时系统可能自动清除 Caches，所以下载完后要迁移到 Documents
    static let `default`: HubApi = makeHubApi(directory: .cachesDirectory)

    // MARK: - 持久化用（Documents）

    /// 加载时使用：指向 Documents/huggingface
    /// Documents 目录重装 App 后依然保留，不会被系统自动清除
    static let persistent: HubApi = makeHubApi(directory: .documentDirectory)

    // MARK: - 工厂方法

    private static func makeHubApi(directory: FileManager.SearchPathDirectory) -> HubApi {
        let fileManager = FileManager.default

        guard let baseDir = fileManager.urls(for: directory, in: .userDomainMask).first else {
            fatalError("❌ 无法获取目录: \(directory)")
        }

        let huggingfaceDir = baseDir.appendingPathComponent("huggingface", isDirectory: true)

        do {
            try fileManager.createDirectory(
                at: huggingfaceDir,
                withIntermediateDirectories: true,
                attributes: nil
            )
            let label = directory == .cachesDirectory ? "Caches" : "Documents"
            print("✅ HuggingFace [\(label)] 目录:", huggingfaceDir.path)
        } catch {
            print("❌ 创建目录失败:", error)
        }

        // Documents 目录排除 iCloud 备份（模型文件很大）
        if directory == .documentDirectory {
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutableDir = huggingfaceDir
            try? mutableDir.setResourceValues(resourceValues)
        }

        return HubApi(
            downloadBase: huggingfaceDir,
            endpoint: "https://hf-mirror.com"
        )
    }
}
