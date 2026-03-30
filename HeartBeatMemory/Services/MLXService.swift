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
    /// Access this property to monitor model download status.
    @MainActor
    private(set) var modelDownloadProgress: Progress?

    /// Downloaded model names (tracked locally)
    @MainActor
    private(set) var downloadedModels: Set<String> = []

    /// UserDefaults key for persisting downloaded models
    private let downloadedModelsKey = "MLXDownloadedModels"

    /// Initialize and load persisted downloaded models
    init() {
        // Load persisted downloaded models from UserDefaults
        if let persisted = UserDefaults.standard.stringArray(forKey: downloadedModelsKey) {
            downloadedModels = Set(persisted)
        }
    }

    /// Save downloaded models to UserDefaults
    private func persistDownloadedModels() {
        UserDefaults.standard.set(Array(downloadedModels), forKey: downloadedModelsKey)
    }

    /// Loads a model from the hub or retrieves it from cache.
    /// - Parameter model: The model configuration to load
    /// - Returns: A ModelContainer instance containing the loaded model
    /// - Throws: Errors that might occur during model loading
    private func load(model: LMModel) async throws -> ModelContainer {
        // Set GPU memory limit to prevent out of memory issues
        Memory.cacheLimit = 20 * 1024 * 1024

        // Return cached model if available to avoid reloading
        if let container = modelCache.object(forKey: model.name as NSString) {
            return container
        } else {
            // Select appropriate factory based on model type
            let factory: ModelFactory =
                switch model.type {
                case .llm:
                    LLMModelFactory.shared
                case .vlm:
                    VLMModelFactory.shared
                }

            // Load model and track download progress
            let container = try await factory.loadContainer(
                hub: .default, configuration: model.configuration
            ) { progress in
                Task { @MainActor in
                    self.modelDownloadProgress = progress
                }
            }

            // Cache the loaded model for future use
            modelCache.setObject(container, forKey: model.name as NSString)

            // Mark as downloaded
            downloadedModels.insert(model.name)
            persistDownloadedModels()

            return container
        }
    }

    /// Manually download a model without loading it into memory
    /// - Parameter model: The model to download
    func downloadModel(_ model: LMModel) async throws {
        // Select appropriate factory based on model type
        let factory: ModelFactory =
            switch model.type {
            case .llm:
                LLMModelFactory.shared
            case .vlm:
                VLMModelFactory.shared
            }

        // Trigger download by loading the container
        // The container will be cached and can be retrieved later
        modelDownloadProgress = nil

        let container = try await factory.loadContainer(
            hub: .default, configuration: model.configuration
        ) { progress in
            Task { @MainActor in
                self.modelDownloadProgress = progress
            }
        }

        // Cache the loaded model
        modelCache.setObject(container, forKey: model.name as NSString)
        downloadedModels.insert(model.name)
        persistDownloadedModels()
        modelDownloadProgress = nil
    }

    /// Check if a model is already downloaded (in cache)
    /// - Parameter modelName: Name of the model to check
    /// - Returns: True if the model is cached
    func isModelDownloaded(_ modelName: String) -> Bool {
        // Check both cache and persisted downloaded models
        let inCache = modelCache.object(forKey: modelName as NSString) != nil
        let inPersisted = downloadedModels.contains(modelName)
        
        // Also check actual file existence in huggingface cache
        if inPersisted {
            let modelPath = getModelCachePath(for: modelName)
            if FileManager.default.fileExists(atPath: modelPath) {
                return true
            }
        }
        
        return inCache
    }
    
    /// Get the local cache path for a model
    private func getModelCachePath(for modelName: String) -> String {
        // Standard MLX/huggingface cache location
        let basePath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let huggingfaceCache = basePath.appendingPathComponent("huggingface/hub")
        
        // Model identifiers are based on the configuration
        // For Qwen2-VL-2B-Instruct-4bit, the folder contains model weights
        let modelIdentifier = getModelIdentifier(for: modelName)
        
        return huggingfaceCache.appendingPathComponent("models--mlx-community--\(modelIdentifier)/snapshots/main").path
    }
    
    /// Get model identifier from model name
    private func getModelIdentifier(for modelName: String) -> String {
        // Map model name to huggingface identifier
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
    
    /// Check if model files exist locally, if not download
    /// - Parameter model: The model to check/load
    /// - Returns: ModelContainer
    private func loadOrDownloadModel(_ model: LMModel) async throws -> ModelContainer {
        let modelPath = getModelCachePath(for: model.name)
        
        // Check if model files exist on disk
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: modelPath) {
            // Files exist, load from local cache
            return try await loadFromLocal(model: model)
        } else {
            // Files don't exist, need to download
            return try await downloadAndLoad(model: model)
        }
    }
    
    /// Load model from local cache
    private func loadFromLocal(model: LMModel) async throws -> ModelContainer {
        let factory: ModelFactory =
            switch model.type {
            case .llm:
                LLMModelFactory.shared
            case .vlm:
                VLMModelFactory.shared
            }
        
        // Use default hub which should find cached files
        let container = try await factory.loadContainer(
            hub: .default, configuration: model.configuration
        ) { progress in
            Task { @MainActor in
                self.modelDownloadProgress = progress
            }
        }
        
        return container
    }
    
    /// Download and load model from huggingface
    private func downloadAndLoad(model: LMModel) async throws -> ModelContainer {
        let factory: ModelFactory =
            switch model.type {
            case .llm:
                LLMModelFactory.shared
            case .vlm:
                VLMModelFactory.shared
            }
        
        modelDownloadProgress = nil
        
        let container = try await factory.loadContainer(
            hub: .default, configuration: model.configuration
        ) { progress in
            Task { @MainActor in
                self.modelDownloadProgress = progress
            }
        }
        
        modelDownloadProgress = nil
        return container
    }

    /// Remove a model from cache
    /// - Parameter modelName: Name of the model to remove
    func removeModel(_ modelName: String) {
        modelCache.removeObject(forKey: modelName as NSString)
        downloadedModels.remove(modelName)
        persistDownloadedModels()
    }

    /// Get list of downloaded models with their info
    /// - Returns: Array of downloaded LMModel objects
    func getDownloadedModels() -> [LMModel] {
        return MLXService.availableModels.filter { downloadedModels.contains($0.name) }
    }

    /// Clear all cached models
    func clearAllModels() {
        modelCache.removeAllObjects()
        downloadedModels.removeAll()
        persistDownloadedModels()
    }

    /// Generates text based on the provided messages using the specified model.
    /// - Parameters:
    ///   - messages: Array of chat messages including user, assistant, and system messages
    ///   - model: The language model to use for generation
    /// - Returns: An AsyncStream of generated text tokens
    /// - Throws: Errors that might occur during generation
    func generate(messages: [Message], model: LMModel) async throws -> AsyncStream<Generation> {
        // Load or retrieve model from cache
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
