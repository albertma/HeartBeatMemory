//
//  ChatView.swift
//  HeartBeatMemory
//
//  Created by albertma on 2026/3/31.
//

import SwiftUI
import UIKit
import MLXLMCommon
import UniformTypeIdentifiers
import PhotosUI

/// 聊天界面 - 整合对话、输入框和工具栏
struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedItem: PhotosPickerItem?
    
    init() {
        let mlxService = MLXService()
        self._viewModel = State(initialValue: ChatViewModel(mlxService: mlxService))
    }
    
    var body: some View {
        NavigationStack {
            contentView
        }
    }
    
    // MARK: - 主内容视图
    private var contentView: some View {
        VStack(spacing: 0) {
            conversationList
            Divider()
            inputArea
        }
        .navigationTitle("AI 聊天")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                modelSelectorMenu
            }
            
            ToolbarItem(placement: .topBarLeading) {
                clearButton
            }
        }
        .onChange(of: selectedItem) { _, newValue in
            handleSelectedItem(newValue)
        }
        .onChange(of: selectedPhotoItem) { _, newValue in
            selectedItem = newValue
        }
        .alert("错误", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("确定") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
    
    // MARK: - 对话列表
    private var conversationList: some View {
        ConversationView(
            messages: viewModel.messages,
            dismissKeyboard: {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - 输入区域
    private var inputArea: some View {
        VStack(spacing: 8) {
            mediaPreview
            inputBar
        }
        .background(.bar)
    }
    
    // MARK: - 媒体预览
    @ViewBuilder
    private var mediaPreview: some View {
        if viewModel.selectedModel.type == .vlm {
            if !viewModel.mediaSelection.images.isEmpty || !viewModel.mediaSelection.videos.isEmpty {
                MediaPreviewsView(mediaSelection: viewModel.mediaSelection)
            }
        }
    }
    
    // MARK: - 输入栏
    private var inputBar: some View {
        HStack(spacing: 12) {
            photoPickerButton
            textInput
            sendButton
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    
    // MARK: - 照片选择按钮
    @ViewBuilder
    private var photoPickerButton: some View {
        if viewModel.selectedModel.type == .vlm {
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Image(systemName: "photo.badge.plus")
                    .font(.title3)
            }
        }
    }
    
    // MARK: - 文本输入
    private var textInput: some View {
        TextField("输入消息...", text: $viewModel.prompt, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(1...5)
    }
    
    // MARK: - 发送按钮
    private var sendButton: some View {
        Button {
            if viewModel.isGenerating {
                viewModel.generateTask?.cancel()
            } else {
                Task {
                    await viewModel.generate()
                }
            }
        } label: {
            Image(systemName: viewModel.isGenerating ? "stop.circle.fill" : "paperplane.fill")
                .font(.title2)
                .foregroundStyle(viewModel.isGenerating ? .red : .blue)
        }
        .disabled(!isSendEnabled)
    }
    
    // MARK: - 清空按钮
    private var clearButton: some View {
        Button("清空") {
            viewModel.clear(.chat)
        }
        .disabled(viewModel.messages.count <= 1)
    }
    
    // MARK: - 模型选择菜单
    private var modelSelectorMenu: some View {
        Menu {
            ForEach(MLXService.availableModels, id: \.name) { model in
                modelMenuButton(model: model)
            }
        } label: {
            HStack(spacing: 4) {
                Text(viewModel.selectedModel.name)
                    .font(.caption)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
        }
    }
    
    // MARK: - 模型菜单按钮
    private func modelMenuButton(model: LMModel) -> some View {
        Button {
            if model.type == .llm {
                viewModel.mediaSelection.images = []
                viewModel.mediaSelection.videos = []
            }
            viewModel.selectedModel = model
        } label: {
            ModelMenuRow(model: model, selectedName: viewModel.selectedModel.name)
        }
    }
    
    // MARK: - 处理选中的照片
    private func handleSelectedItem(_ item: PhotosPickerItem?) {
        guard let item = item else { return }
        
        Task {
            do {
                if let data = try await item.loadTransferable(type: Data.self) {
                    let vm = viewModel
                    let url = try vm.saveToTempFile(data: data, identifier: UUID().uuidString)
                    vm.addMedia(.success([url]))
                }
            } catch {
                viewModel.addMedia(.failure(error))
            }
        }
        selectedItem = nil
    }
    
    // MARK: - 判断是否可以发送
    private var isSendEnabled: Bool {
        if viewModel.isGenerating {
            return true
        }
        if viewModel.selectedModel.type == .vlm {
            return !viewModel.prompt.isEmpty || !viewModel.mediaSelection.isEmpty
        } else {
            return !viewModel.prompt.isEmpty
        }
    }
}

// MARK: - 辅助视图

private struct ModelMenuRow: View {
    let model: LMModel
    let selectedName: String
    
    var body: some View {
        HStack {
            Text(model.name)
            Text(model.type == .vlm ? "(视觉)" : "(文本)")
                .font(.caption2)
                .foregroundColor(.secondary)
            if selectedName == model.name {
                Image(systemName: "checkmark")
            }
        }
    }
}

#Preview {
    ChatView()
}