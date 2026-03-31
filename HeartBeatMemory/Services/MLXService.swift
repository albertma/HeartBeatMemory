//
//  MLXService.swift
//  HeartBeatMemory
//
//  Created by albertma on 2026/3/29.
//

import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXVLM
import Hub

/// A service class that manages machine learning models for text and vision-language tasks.
/// This class handles model loading, caching, and text generation using various LLM and VLM models.
@Observable
class MLXService {
    /// List of available models that can be used for generation.
    /// Includes both language models (LLM) and vision-language models (VLM).
    static let availableModels: [LMModel] = [
        LMModel(name: "qwen3:1.7b", configuration: LLMRegistry.qwen3_1_7b_4bit, type: .llm),
        LMModel(name: "qwen2.5VL:3b", configuration: VLMRegistry.qwen2_5VL3BInstruct4Bit, type: .vlm),
        LMModel(name: "qwen2VL:2b", configuration: VLMRegistry.qwen2VL2BInstruct4Bit, type: .vlm),
        LMModel(name: "smolVLM", configuration: VLMRegistry.smolvlminstruct4bit, type: .vlm),
    ]

    /// Cache to store loaded model containers to avoid reloading.
    private let modelCache = NSCache<NSString, ModelContainer>()
    
    /// Tracks the current model download progress.
    @MainActor
    private(set) var modelDownloadProgress: Progress?

    /// Downloaded model names (tracked locally for persistence check)
    @MainActor
    private(set) var downloadedModels: Set<String> = []

    /// UserDefaults key for persisting downloaded models
    private let downloadedModelsKey = "MLXDownloadedModels"
    
    /// Base directory for model cache (persistent between app runs)
    private var modelCacheDirectory: URL {
        // Use app support directory which persists between app runs
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let cacheDir = appSupport.appendingPathComponent("MLXModels", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        return cacheDir
    }

    /// Initialize and load persisted downloaded models
    init() {
        // Load persisted downloaded models from UserDefaults
        if let persisted = UserDefaults.standard.stringArray(forKey: downloadedModelsKey) {
            downloadedModels = Set(persisted)
        }
        
        NSLog("MLXService init, cache directory: \(modelCacheDirectory.path)")
        
        // Check which models are actually cached
        checkCachedModels()
    }

    /// Save downloaded models to UserDefaults
    private func persistDownloadedModels() {
        UserDefaults.standard.set(Array(downloadedModels), forKey: downloadedModelsKey)
    }
    
    /// Check which models are actually cached on disk
    private func checkCachedModels() {
        let fileManager = FileManager.default
        
        for model in MLXService.availableModels {
            let modelPath = getModelCachePath(for: model.name)
            if fileManager.fileExists(atPath: modelPath) {
                NSLog("Model found in cache: \(model.name)")
            }
        }
    }
    
    /// Get the model cache path for a specific model
    private func getModelCachePath(for modelName: String) -> String {
        let modelIdentifier = getModelIdentifier(for: modelName)
        return modelCacheDirectory
            .appendingPathComponent("models--mlx-community--\(modelIdentifier)/snapshots/main")
            .path
    }
    
    /// Get model identifier from model name
    private func getModelIdentifier(for modelName: String) -> String {
        switch modelName {
        case "qwen2.5VL:3b":
            return "Qwen2.5-VL-3B-Instruct-4bit"
        case "qwen2VL:2b":
            return "Qwen2-VL-2B-Instruct-4bit"
        case "qwen3:1.7b":
            return "Qwen3-1.7B-4bit"
        case "smolVLM":
            return "smolVLM-Instruct"
        default:
            return modelName.replacingOccurrences(of: ":", with: "-")
        }
    }

    /// Loads a model from the hub or retrieves it from cache.
    /// - Parameter model: The model configuration to load
    /// - Returns: A ModelContainer instance containing the loaded model
    /// - Throws: Errors that might occur during model loading
    private func load(model: LMModel) async throws -> ModelContainer {
        NSLog("Load model: \(model.name)")
        Memory.cacheLimit = 20 * 1024 * 1024

        // Return cached model if available (memory cache)
        if let container = modelCache.object(forKey: model.name as NSString) {
            NSLog("Got model from memory cache")
            return container
        }
        
        // Check if model files exist in disk cache
        let modelCachePath = getModelCachePath(for: model.name)
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: modelCachePath) {
            NSLog("Model exists in disk cache: \(modelCachePath)")
        } else {
            NSLog("Model not in disk cache, will download")
        }
        
        // Select appropriate factory based on model type
        let factory: ModelFactory =
            switch model.type {
            case .llm:
                LLMModelFactory.shared
            case .vlm:
                VLMModelFactory.shared
            }

        // Load model - will use cached files if available, otherwise download
        NSLog("Calling loadContainer for model: \(model.name)")
        let container = try await factory.loadContainer(
            hub: HubApiExtension.default, configuration: model.configuration
        ) { progress in
            NSLog("Download/Load progress: \(Int(progress.fractionCompleted * 100))%")
            Task { @MainActor in
                self.modelDownloadProgress = progress
            }
        }

        // Cache in memory
        modelCache.setObject(container, forKey: model.name as NSString)
        
        // Mark as downloaded
        downloadedModels.insert(model.name)
        persistDownloadedModels()
        
        NSLog("Model loaded successfully: \(model.name)")
        return container
    }

    /// Manually download a model without loading it into memory
    /// - Parameter model: The model to download
    func downloadModel(_ model: LMModel) async throws {
        NSLog("Manual download for model: \(model.name)")
        
        let factory: ModelFactory =
            switch model.type {
            case .llm:
                LLMModelFactory.shared
            case .vlm:
                VLMModelFactory.shared
            }

        modelDownloadProgress = nil

        // Download model
        _ = try await factory.loadContainer(
            hub: HubApiExtension.default, configuration: model.configuration
        ) { progress in
            Task { @MainActor in
                self.modelDownloadProgress = progress
            }
        }
        
        // Mark as downloaded
        downloadedModels.insert(model.name)
        persistDownloadedModels()
        modelDownloadProgress = nil
        
        NSLog("Model downloaded successfully: \(model.name)")
    }

    /// Check if a model is already downloaded (in disk cache)
    /// - Parameter modelName: Name of the model to check
    /// - Returns: True if the model is available in cache
    func isModelDownloaded(_ modelName: String) -> Bool {
        // Check memory cache first
        if modelCache.object(forKey: modelName as NSString) != nil {
            return true
        }
        
        // Check disk cache
        let modelCachePath = getModelCachePath(for: modelName)
        let exists = FileManager.default.fileExists(atPath: modelCachePath)
        NSLog("isModelDownloaded(\(modelName)): \(exists)")
        return exists
    }

    /// Remove a model from cache
    /// - Parameter modelName: Name of the model to remove
    func removeModel(_ modelName: String) {
        modelCache.removeObject(forKey: modelName as NSString)
        
        // Remove from disk - remove the entire model directory
        let modelCachePath = getModelCachePath(for: modelName)
        let modelDir = URL(fileURLWithPath: modelCachePath).deletingLastPathComponent()
        try? FileManager.default.removeItem(at: modelDir)
        
        downloadedModels.remove(modelName)
        persistDownloadedModels()
        
        NSLog("Model removed: \(modelName)")
    }

    /// Get list of downloaded models with their info
    /// - Returns: Array of downloaded LMModel objects
    func getDownloadedModels() -> [LMModel] {
        return MLXService.availableModels.filter { isModelDownloaded($0.name) }
    }

    /// Get size of a downloaded model
    /// - Parameter modelName: Name of the model
    /// - Returns: Size in bytes, or nil if not found
    func getModelSize(_ modelName: String) -> Int64? {
        let modelCachePath = getModelCachePath(for: modelName)
        let modelDir = URL(fileURLWithPath: modelCachePath).deletingLastPathComponent()
        
        guard FileManager.default.fileExists(atPath: modelDir.path) else {
            return nil
        }
        
        guard let enumerator = FileManager.default.enumerator(at: modelDir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return nil
        }
        
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let attributes = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let fileSize = attributes.fileSize {
                totalSize += Int64(fileSize)
            }
        }
        
        return totalSize
    }

    /// Clear all cached models
    func clearAllModels() {
        modelCache.removeAllObjects()
        
        // Clear disk cache
        try? FileManager.default.removeItem(at: modelCacheDirectory)
        try? FileManager.default.createDirectory(at: modelCacheDirectory, withIntermediateDirectories: true)
        
        downloadedModels.removeAll()
        persistDownloadedModels()
        
        NSLog("All models cleared")
    }

    /// Generates text based on the provided messages using the specified model.
    /// - Parameters:
    ///   - messages: Array of chat messages including user, assistant, and system messages
    ///   - model: The language model to use for generation
    /// - Returns: An AsyncStream of generated text tokens
    /// - Throws: Errors that might occur during generation
    func generate(messages: [Message], model: LMModel) async throws -> AsyncStream<Generation> {
        NSLog("Start to generate from model \(model.name)")
        let modelContainer = try await load(model: model)

        // Map app-specific Message type to Chat.Message for model input
        let chat = messages.map { message in
            let role: Chat.Message.Role =
                switch message.role {
                case .assistant:
                    .assistant
                case .user:
                    .user
                case .system:
                    .system
                }

            // Process any attached media for VLM models
            NSLog("image count: \(message.images.count), video count: \(message.videos.count)")
            let images: [UserInput.Image] = message.images.map { imageURL in .url(imageURL) }
            let videos: [UserInput.Video] = message.videos.map { videoURL in .url(videoURL) }

            return Chat.Message(
                role: role, content: message.content, images: images, videos: videos)
        }

        // Prepare input for model processing
        let userInput = UserInput(
            chat: chat, processing: .init(resize: .init(width: 1024, height: 1024)))

        // Generate response using the model
        return try await modelContainer.perform { (context: ModelContext) in
            let lmInput = try await context.processor.prepare(input: userInput)
            // Set temperature for response randomness (0.7 provides good balance)
            let parameters = GenerateParameters(temperature: 0.7)

            return try MLXLMCommon.generate(
                input: lmInput, parameters: parameters, context: context)
        }
    }
}