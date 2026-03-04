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
    @Environment(ViewStateStore.self) var viewStateStore
    @State private var models: [EngineClient.ModelSummary] = []
    @State private var currentConversationId: String?
    @State private var regeneratingMessageId: String? = nil // 正在重新生成的消息ID

    private var inputText: Binding<String> {
        Binding(
            get: { viewStateStore.chatInputText },
            set: { viewStateStore.chatInputText = $0 }
        )
    }

    private var isGenerating: Binding<Bool> {
        Binding(
            get: { viewStateStore.chatIsGenerating },
            set: { viewStateStore.chatIsGenerating = $0 }
        )
    }

    private var selectedModelId: Binding<String> {
        Binding(
            get: { viewStateStore.chatSelectedModelId },
            set: { viewStateStore.chatSelectedModelId = $0 }
        )
    }

    private var messageCount: Int { viewStateStore.chatMessages.count }
    private var showNewChatButton: Bool { messageCount >= 5 }

    private var llmModels: [EngineClient.ModelSummary] {
        let filtered = models.filter { $0.type == "llm" }
        guard !filtered.isEmpty else {
            return [EngineClient.ModelSummary(id: "qwen2.5-1.5b-instruct", name: "Qwen2.5-1.5B", type: "llm", capabilities: [], status: "", size_bytes: nil, quantization: nil, version: nil, updated_at: nil, local_dir: nil, actual_size_bytes: nil, file_types: nil)]
        }

        // 将当前选中的模型移到列表最前面
        let currentModelId = selectedModelId.wrappedValue
        if !currentModelId.isEmpty,
           let currentIndex = filtered.firstIndex(where: { $0.id == currentModelId }) {
            var sorted = filtered
            let currentModel = sorted.remove(at: currentIndex)
            sorted.insert(currentModel, at: 0)
            return sorted
        }

        return filtered
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
                ForEach(viewStateStore.chatMessages) { msg in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: msg.role == "user" ? "person.circle" : "cpu")
                                .foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(msg.text)
                                    .textSelection(.enabled)

                                // 显示时间信息
                                if msg.role == "assistant" && !msg.text.isEmpty {
                                    HStack(spacing: 8) {
                                        if let loadTime = msg.loadTimeMs {
                                            HStack(spacing: 4) {
                                                Image(systemName: "arrow.down.circle")
                                                    .font(.caption2)
                                                Text("加载: \(formatTime(loadTime))")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }

                                        if let responseTime = msg.responseTimeMs {
                                            HStack(spacing: 4) {
                                                Image(systemName: "bolt.circle")
                                                    .font(.caption2)
                                                Text("响应: \(formatTime(responseTime))")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }

                                // 刷新按钮（仅对已完成响应的AI消息显示）
                                if msg.role == "assistant" && msg.canRegenerate && !msg.text.isEmpty && msg.text != String(localized: "chat.model_loading") && msg.text != String(localized: "chat.model_loaded") {
                                    HStack(spacing: 4) {
                                        Button {
                                            regenerateResponse(msg)
                                        } label: {
                                            HStack(spacing: 2) {
                                                Image(systemName: regeneratingMessageId == msg.id ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                                                    .font(.caption)
                                                Text("重新生成")
                                                    .font(.caption)
                                            }
                                        }
                                        .buttonStyle(.borderless)
                                        .disabled(regeneratingMessageId != nil || isGenerating.wrappedValue)
                                        .opacity(regeneratingMessageId == msg.id ? 0.5 : 1)

                                        if regeneratingMessageId == msg.id {
                                            ProgressView()
                                                .scaleEffect(0.5)
                                        }
                                    }
                                }
                            }

                            Spacer(minLength: 0)
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 8))
                }
            }
            .listStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: viewStateStore.chatMessages.count) { _, _ in
                if let last = viewStateStore.chatMessages.indices.last {
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

    // 格式化时间显示
    private func formatTime(_ ms: Int) -> String {
        if ms < 1000 {
            return "\(ms)ms"
        } else if ms < 60000 {
            return String(format: "%.1fs", Double(ms) / 1000.0)
        } else {
            let minutes = ms / 60000
            let seconds = (ms % 60000) / 1000
            return "\(minutes)m\(seconds)s"
        }
    }

    // 重新生成响应
    private func regenerateResponse(_ message: ViewStateStore.ChatMessage) {
        guard let index = viewStateStore.chatMessages.firstIndex(where: { $0.id == message.id }),
              index > 0 else { return }

        // 获取用户消息
        let userMessage = viewStateStore.chatMessages[index - 1]
        guard userMessage.role == "user" else { return }

        regeneratingMessageId = message.id
        viewStateStore.chatIsGenerating = true

        // 创建历史记录
        let cid = currentConversationId ?? UUID().uuidString
        if currentConversationId == nil {
            currentConversationId = cid
        }
        let payload = GenerationPayload(chat: .init(prompt: userMessage.text, temperature: 0.7, maxTokens: 512, modelId: selectedModelId.wrappedValue))
        let record = GenerationRecord(kind: .chat, status: .running, payload: payload, conversationId: cid)
        historyStore.append(record)

        let start = Date()
        let loadingKey = String(localized: "chat.model_loading")

        Task {
            do {
                // 检查模型是否已加载
                let loadedResp = try await EngineClient.fetchLoadedModels()
                let isLoaded = loadedResp.loaded_models.contains { $0.id == selectedModelId.wrappedValue }

                var loadTimeMs: Int? = nil

                if !isLoaded {
                    let loadStart = Date()
                    // 显示正在加载
                    await MainActor.run {
                        var msgs = viewStateStore.chatMessages
                        if index < msgs.count {
                            msgs[index].text = loadingKey
                            msgs[index].loadTimeMs = nil
                            msgs[index].responseTimeMs = nil
                            viewStateStore.chatMessages = msgs
                        }
                    }
                    // 触发加载
                    try await EngineClient.preloadModel(modelId: selectedModelId.wrappedValue)
                    loadTimeMs = Int(Date().timeIntervalSince(loadStart) * 1000)
                }

                // 生成新响应
                let genStart = Date()
                let result = try await EngineClient.generateChat(prompt: userMessage.text, temperature: 0.7, maxTokens: 512, modelId: selectedModelId.wrappedValue)
                let responseTimeMs = Int(Date().timeIntervalSince(genStart) * 1000)

                await MainActor.run {
                    var msgs = viewStateStore.chatMessages
                    if index < msgs.count {
                        msgs[index].text = result
                        msgs[index].loadTimeMs = loadTimeMs
                        msgs[index].responseTimeMs = responseTimeMs
                        msgs[index].canRegenerate = true
                        viewStateStore.chatMessages = msgs
                    }
                    historyStore.update(id: record.id, status: .success, resultRef: .init(text: result), durationMs: responseTimeMs)
                    viewStateStore.chatIsGenerating = false
                    regeneratingMessageId = nil
                }
            } catch {
                await MainActor.run {
                    var msgs = viewStateStore.chatMessages
                    if index < msgs.count {
                        msgs[index].text = "Error: \(error.localizedDescription)"
                        viewStateStore.chatMessages = msgs
                    }
                    historyStore.update(id: record.id, status: .failed, errorMessage: error.localizedDescription)
                    viewStateStore.chatIsGenerating = false
                    regeneratingMessageId = nil
                }
            }
        }
    }

    private func startNewChat() {
        currentConversationId = nil
        viewStateStore.chatMessages = []
    }

    private func inputBar(containerHeight: CGFloat) -> some View {
        let maxInputHeight = max(120, containerHeight * 0.5)
        let maxLineCount = max(6, Int(maxInputHeight / 24))

        return VStack(spacing: 8) {
            // 模型选择器（放在上方）
            HStack {
                Picker("chat.model", selection: selectedModelId) {
                    ForEach(llmModels, id: \.id) { m in
                        Text(m.name).tag(m.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 输入框和发送按钮
            HStack(alignment: .bottom, spacing: 8) {
                TextField("chat.input_placeholder", text: inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...maxLineCount)
                    .frame(minHeight: 40, maxHeight: maxInputHeight, alignment: .topLeading)
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
                .disabled(inputText.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating.wrappedValue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func fetchModels() {
        Task {
            do {
                let resp = try await EngineClient.fetchModels()
                await MainActor.run {
                    models = resp.models
                    if selectedModelId.wrappedValue.isEmpty, let first = resp.models.first(where: { $0.type == "llm" }) {
                        viewStateStore.chatSelectedModelId = first.id
                    }
                }
            } catch {
                print("[ChatView] fetchModels error: \(error)")
            }
        }
    }

    private func sendMessage() {
        let text = inputText.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        viewStateStore.chatInputText = ""

        // 添加用户消息
        let userMsg = ViewStateStore.ChatMessage(role: "user", text: text)
        viewStateStore.chatMessages.append(userMsg)

        // 添加一个占位的助手消息
        let assistantMsgId = UUID().uuidString
        let placeholderMsg = ViewStateStore.ChatMessage(id: assistantMsgId, role: "assistant", text: "", canRegenerate: true)
        viewStateStore.chatMessages.append(placeholderMsg)

        viewStateStore.chatIsGenerating = true

        let cid = currentConversationId ?? UUID().uuidString
        if currentConversationId == nil {
            currentConversationId = cid
        }
        let payload = GenerationPayload(chat: .init(prompt: text, temperature: 0.7, maxTokens: 512, modelId: selectedModelId.wrappedValue))
        let record = GenerationRecord(kind: .chat, status: .running, payload: payload, conversationId: cid)
        historyStore.append(record)

        let loadingKey = String(localized: "chat.model_loading")
        let loadedKey = String(localized: "chat.model_loaded")

        Task {
            do {
                // 1. 检查模型是否已加载
                let loadedResp = try await EngineClient.fetchLoadedModels()
                let isLoaded = loadedResp.loaded_models.contains { $0.id == selectedModelId.wrappedValue }

                var loadTimeMs: Int? = nil

                if !isLoaded {
                    let loadStart = Date()
                    // 2. 显示正在加载
                    await MainActor.run {
                        if let index = viewStateStore.chatMessages.firstIndex(where: { $0.id == assistantMsgId }) {
                            viewStateStore.chatMessages[index].text = loadingKey
                        }
                    }
                    // 3. 触发加载
                    try await EngineClient.preloadModel(modelId: selectedModelId.wrappedValue)
                    loadTimeMs = Int(Date().timeIntervalSince(loadStart) * 1000)

                    // 4. 更新为加载完成
                    await MainActor.run {
                        if let index = viewStateStore.chatMessages.firstIndex(where: { $0.id == assistantMsgId }) {
                            viewStateStore.chatMessages[index].text = loadedKey
                            viewStateStore.chatMessages[index].loadTimeMs = loadTimeMs
                        }
                    }
                }

                // 5. 自动发送聊天内容（无论是否刚加载）
                let genStart = Date()
                let result = try await EngineClient.generateChat(prompt: text, temperature: 0.7, maxTokens: 512, modelId: selectedModelId.wrappedValue)
                let responseTimeMs = Int(Date().timeIntervalSince(genStart) * 1000)

                await MainActor.run {
                    if let index = viewStateStore.chatMessages.firstIndex(where: { $0.id == assistantMsgId }) {
                        viewStateStore.chatMessages[index].text = result
                        viewStateStore.chatMessages[index].responseTimeMs = responseTimeMs
                        viewStateStore.chatMessages[index].canRegenerate = true
                        // 如果没有加载时间，说明模型已加载，不显示加载信息
                        if loadTimeMs == nil {
                            viewStateStore.chatMessages[index].loadTimeMs = nil
                        }
                    }
                    historyStore.update(id: record.id, status: .success, resultRef: .init(text: result), durationMs: responseTimeMs)
                    viewStateStore.chatIsGenerating = false
                }
            } catch {
                await MainActor.run {
                    if let index = viewStateStore.chatMessages.firstIndex(where: { $0.id == assistantMsgId }) {
                        viewStateStore.chatMessages[index].text = "Error: \(error.localizedDescription)"
                    }
                    historyStore.update(id: record.id, status: .failed, errorMessage: error.localizedDescription)
                    viewStateStore.chatIsGenerating = false
                }
            }
        }
    }
}
