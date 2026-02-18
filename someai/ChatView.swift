//
//  ChatView.swift
//  someai
//
//  LLM Chat UI - 对话窗口、输入框、模型选择、Streaming 输出
//

import SwiftUI

struct ChatView: View {
    @Environment(EngineManager.self) var engineManager
    @Environment(GenerationHistoryStore.self) var historyStore
    @State private var inputText = ""
    @State private var messages: [(role: String, text: String)] = []
    @State private var isGenerating = false
    @State private var selectedModelId = "qwen2.5-1.5b-instruct"
    @State private var models: [EngineClient.ModelSummary] = []
    @State private var currentConversationId: String?

    private var messageCount: Int { messages.count }
    private var showNewChatButton: Bool { messageCount >= 5 }

    private var llmModels: [EngineClient.ModelSummary] {
        let filtered = models.filter { $0.type == "llm" }
        return filtered.isEmpty ? [EngineClient.ModelSummary(id: "qwen2.5-1.5b-instruct", name: "Qwen2.5-1.5B", type: "llm", capabilities: [], status: "", size_bytes: nil, quantization: nil, version: nil, updated_at: nil, local_dir: nil, actual_size_bytes: nil, file_types: nil)] : filtered
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                messagesList
                Divider()
                inputBar(containerHeight: proxy.size.height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle(String(localized: "sidebar.chat"))
        .onAppear { fetchModels() }
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(Array(messages.enumerated()), id: \.offset) { _, msg in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: msg.role == "user" ? "person.circle" : "cpu")
                            .foregroundStyle(.secondary)
                        Text(msg.text)
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 8))
                }
            }
            .listStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: messages.count) { _, _ in
                if let last = messages.indices.last {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if showNewChatButton {
                    Button {
                        startNewChat()
                    } label: {
                        Label(String(localized: "chat_hub.new_chat"), systemImage: "plus.bubble")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func startNewChat() {
        currentConversationId = nil
        messages = []
    }

    private func inputBar(containerHeight: CGFloat) -> some View {
        let maxInputHeight = max(120, containerHeight * 0.5)
        let maxLineCount = max(6, Int(maxInputHeight / 24))

        return HStack(alignment: .top, spacing: 8) {
            Picker("chat.model", selection: $selectedModelId) {
                ForEach(llmModels, id: \.id) { m in
                    Text(m.name).tag(m.id)
                }
            }
            .pickerStyle(.menu)
            .frame(minWidth: 120, maxWidth: 160)

            TextField("chat.input_placeholder", text: $inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...maxLineCount)
                .frame(minWidth: 240, minHeight: 72, maxHeight: maxInputHeight, alignment: .topLeading)
                .onKeyPress { press in
                    guard press.key == .return else { return .ignored }
                    if press.modifiers.contains(EventModifiers.shift) {
                        return .ignored  // Shift+Enter: 换行
                    }
                    sendMessage()
                    return .handled  // Enter: 发送
                }

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 0)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
    }

    private func fetchModels() {
        Task {
            do {
                let resp = try await EngineClient.fetchModels()
                await MainActor.run {
                    models = resp.models
                    if selectedModelId.isEmpty, let first = resp.models.first(where: { $0.type == "llm" }) {
                        selectedModelId = first.id
                    }
                }
            } catch {
                print("[ChatView] fetchModels error: \(error)")
            }
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        messages.append((role: "user", text: text))
        isGenerating = true

        let cid = currentConversationId ?? UUID().uuidString
        if currentConversationId == nil {
            currentConversationId = cid
        }
        let payload = GenerationPayload(chat: .init(prompt: text, temperature: 0.7, maxTokens: 512, modelId: selectedModelId))
        let record = GenerationRecord(kind: .chat, status: .running, payload: payload, conversationId: cid)
        historyStore.append(record)

        let start = Date()
        let loadingKey = String(localized: "chat.model_loading")
        let loadedKey = String(localized: "chat.model_loaded")

        Task {
            do {
                // 1. 检查模型是否已加载
                let loadedResp = try await EngineClient.fetchLoadedModels()
                let isLoaded = loadedResp.loaded_models.contains { $0.id == selectedModelId }

                if !isLoaded {
                    // 2. 显示正在加载
                    await MainActor.run {
                        messages.append((role: "assistant", text: loadingKey))
                    }
                    // 3. 触发加载
                    try await EngineClient.preloadModel(modelId: selectedModelId)
                    // 4. 更新为加载完成
                    await MainActor.run {
                        if let idx = messages.lastIndex(where: { $0.role == "assistant" && $0.text == loadingKey }) {
                            messages[idx] = (role: "assistant", text: loadedKey)
                        }
                    }
                }

                // 5. 自动发送聊天内容（无论是否刚加载）
                let result = try await EngineClient.generateChat(prompt: text, temperature: 0.7, maxTokens: 512, modelId: selectedModelId)
                let durationMs = Int(Date().timeIntervalSince(start) * 1000)
                await MainActor.run {
                    // 若有加载状态消息则替换为实际回复，否则追加
                    if let idx = messages.lastIndex(where: { $0.role == "assistant" && ($0.text == loadingKey || $0.text == loadedKey) }) {
                        messages[idx] = (role: "assistant", text: result)
                    } else {
                        messages.append((role: "assistant", text: result))
                    }
                    historyStore.update(id: record.id, status: .success, resultRef: .init(text: result), durationMs: durationMs)
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    messages.removeAll { $0.role == "assistant" && ($0.text == loadingKey || $0.text == loadedKey) }
                    messages.append((role: "assistant", text: "Error: \(error.localizedDescription)"))
                    historyStore.update(id: record.id, status: .failed, errorMessage: error.localizedDescription)
                    isGenerating = false
                }
            }
        }
    }
}
