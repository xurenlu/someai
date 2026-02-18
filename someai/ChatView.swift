//
//  ChatView.swift
//  someai
//
//  LLM Chat UI - 对话窗口、输入框、模型选择、Streaming 输出
//

import SwiftUI

struct ChatView: View {
    @Environment(EngineManager.self) var engineManager
    @State private var inputText = ""
    @State private var messages: [(role: String, text: String)] = []
    @State private var isGenerating = false
    @State private var selectedModelId = "qwen2.5-1.5b-instruct"
    @State private var models: [EngineClient.ModelSummary] = []

    private var llmModels: [EngineClient.ModelSummary] {
        let filtered = models.filter { $0.type == "llm" }
        return filtered.isEmpty ? [EngineClient.ModelSummary(id: "qwen2.5-1.5b-instruct", name: "Qwen2.5-1.5B", type: "llm", capabilities: [], status: "", size_bytes: nil, quantization: nil, version: nil, updated_at: nil)] : filtered
    }

    var body: some View {
        VStack(spacing: 0) {
            messagesList
            Divider()
            inputBar
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
                }
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.indices.last {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            Picker("chat.model", selection: $selectedModelId) {
                ForEach(llmModels, id: \.id) { m in
                    Text(m.name).tag(m.id)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 120)

            TextField("chat.input_placeholder", text: $inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
        }
        .padding()
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

        Task {
            do {
                let url = EngineClient.baseURL.appendingPathComponent("llm").appendingPathComponent("generate")
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let body = LLMGenerateRequest(prompt: text, temperature: 0.7, max_tokens: 512)
                req.httpBody = try JSONEncoder().encode(body)
                let (data, _) = try await URLSession.shared.data(for: req)
                let resp = try JSONDecoder().decode(LLMGenerateResponse.self, from: data)
                await MainActor.run {
                    messages.append((role: "assistant", text: resp.text))
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    messages.append((role: "assistant", text: "Error: \(error.localizedDescription)"))
                    isGenerating = false
                }
            }
        }
    }
}

struct LLMGenerateRequest: Codable {
    let prompt: String
    let temperature: Double
    let max_tokens: Int
}

struct LLMGenerateResponse: Codable {
    let text: String
}
