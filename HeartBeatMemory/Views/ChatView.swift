//
//  ChatView.swift
//  HeartBeatMemory
//
//  Created by albertma on 2026/3/31.
//

import SwiftUI
import MLXLMCommon
import UniformTypeIdentifiers

/// 聊天界面 - 整合对话、输入框和工具栏
struct ChatView: View {
    @State private var viewModel: ChatViewModel
    
    init() {
        let mlxService = MLXService()
        self._viewModel = State(initialValue: ChatViewModel(mlxService: mlxService))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 对话列表
                ConversationView(messages: viewModel.messages)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                Divider()
                
                // 输入区域
                VStack(spacing: 8) {
                    // 媒体预览
                    if !viewModel.mediaSelection.images.isEmpty || !viewModel.mediaSelection.videos.isEmpty {
                        MediaPreviewsView(mediaSelection: viewModel.mediaSelection)
                    }
                    
                    // 输入框和工具栏
                    HStack(spacing: 12) {
                        // 图片选择按钮
                        Button {
                            viewModel.mediaSelection.isShowing = true
                        } label: {
                            Image(systemName: "photo.badge.plus")
                                .font(.title3)
                        }
                        
                        // 文本输入
                        TextField("输入消息...", text: $viewModel.prompt, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...5)
                        
                        // 发送/停止按钮
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
                        .disabled(viewModel.prompt.isEmpty && viewModel.mediaSelection.isEmpty)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                .background(.bar)
            }
            .navigationTitle("AI 聊天")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(MLXService.availableModels.filter { $0.type == .llm }, id: \.name) { model in
                            Button {
                                viewModel.selectedModel = model
                            } label: {
                                HStack {
                                    Text(model.name)
                                    if viewModel.selectedModel.name == model.name {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
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
                
                ToolbarItem(placement: .topBarLeading) {
                    Button("清空") {
                        viewModel.clear(.chat)
                    }
                    .disabled(viewModel.messages.count <= 1)
                }
            }
            .fileImporter(
                isPresented: $viewModel.mediaSelection.isShowing,
                allowedContentTypes: [.image, .movie],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    viewModel.addMedia(.success(urls))
                case .failure(let error):
                    viewModel.addMedia(.failure(error))
                }
            }
            .alert("错误", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("确定") {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }
}

#Preview {
    ChatView()
}
