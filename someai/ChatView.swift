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
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
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

        return HStack(spacing: 8) {
            Picker("chat.model", selection: $selectedModelId) {
                ForEach(llmModels, id: \.id) { m in
                    Text(m.name).tag(m.id)
                }
            }
            .pickerStyle(.menu)
            .frame(minWidth: 120, maxWidth: 160)

            TextField("chat.input_placeholder", text: $inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...maxLineCount)
                .frame(minHeight: 44, maxHeight: maxInputHeight, alignment: .topLeading)
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
        .padding(.horizontal, 12)
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
        Task {
            do {
                let result = try await EngineClient.generateChat(prompt: text, temperature: 0.7, maxTokens: 512, modelId: selectedModelId)
                let durationMs = Int(Date().timeIntervalSince(start) * 1000)
                await MainActor.run {
                    messages.append((role: "assistant", text: result))
                    historyStore.update(id: record.id, status: .success, resultRef: .init(text: result), durationMs: durationMs)
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    messages.append((role: "assistant", text: "Error: \(error.localizedDescription)"))
                    historyStore.update(id: record.id, status: .failed, errorMessage: error.localizedDescription)
                    isGenerating = false
                }
            }
        }
    }
}
