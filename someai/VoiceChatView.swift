//
//  VoiceChatView.swift
//  someai
//
//  语音聊天 - 录音 -> STT -> LLM -> TTS -> 播放
//

import SwiftUI
import AVFoundation

struct VoiceChatView: View {
    @Environment(EngineManager.self) var engineManager
    @State private var isRecording = false
    @State private var isProcessing = false
    @State private var transcript = ""
    @State private var responseText = ""
    @State private var lastError: String?
    @State private var conversationLog: [(user: String, assistant: String)] = []
    @State private var audioEngine: AVAudioEngine?
    @State private var outputFile: AVAudioFile?
    @State private var recordingURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !conversationLog.isEmpty {
                List {
                    ForEach(Array(conversationLog.enumerated()), id: \.offset) { _, pair in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(pair.user)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(pair.assistant)
                                .font(.body)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if isProcessing {
                HStack {
                    ProgressView()
                    Text("voice_chat.processing")
                }
            }

            if let err = lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button {
                    toggleRecording()
                } label: {
                    Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(isRecording ? .red : .blue)
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)

                Text(isRecording ? "voice_chat.stop" : "voice_chat.record")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .padding()
        .navigationTitle(String(localized: "sidebar.voice_chat"))
        .onAppear { requestMicPermission() }
    }

    private func requestMicPermission() {
        #if os(iOS)
        AVAudioApplication.requestRecordPermission { _ in }
        #endif
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice_\(UUID().uuidString).wav")
        recordingURL = url
        do {
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let bus = 0
            let format = input.inputFormat(forBus: bus)
            let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            input.installTap(onBus: bus, bufferSize: 512, format: format) { buffer, _ in
                try? file.write(from: buffer)
            }
            try engine.start()
            audioEngine = engine
            outputFile = file
            isRecording = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func stopRecording() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        outputFile = nil
        isRecording = false
        guard let url = recordingURL else { return }
        processVoiceInput(url: url)
    }

    private func processVoiceInput(url: URL) {
        isProcessing = true
        lastError = nil
        Task {
            do {
                let text = try await transcribe(url: url)
                await MainActor.run { transcript = text }
                let llmText = try await generateLLM(prompt: text)
                await MainActor.run { responseText = llmText }
                let audioData = try await generateTTS(text: llmText)
                await MainActor.run {
                    conversationLog.append((user: text, assistant: llmText))
                    playAudio(data: audioData)
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    lastError = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }

    private func transcribe(url: URL) async throws -> String {
        let data = try Data(contentsOf: url)
        let endpoint = EngineClient.baseURL.appendingPathComponent("stt").appendingPathComponent("transcribe")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        let boundary = UUID().uuidString
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        let (respData, _) = try await URLSession.shared.data(for: req)
        let decoded = try JSONDecoder().decode(STTResponse.self, from: respData)
        return decoded.text
    }

    private func generateLLM(prompt: String) async throws -> String {
        let url = EngineClient.baseURL.appendingPathComponent("llm").appendingPathComponent("generate")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(LLMGenerateRequest(prompt: prompt, temperature: 0.7, max_tokens: 512))
        let (data, _) = try await URLSession.shared.data(for: req)
        let resp = try JSONDecoder().decode(LLMGenerateResponse.self, from: data)
        return resp.text
    }

    private func generateTTS(text: String) async throws -> Data {
        let url = EngineClient.baseURL.appendingPathComponent("tts").appendingPathComponent("generate")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(TTSGenerateRequest(text: text, language: "zh", speaker: "default"))
        let (data, _) = try await URLSession.shared.data(for: req)
        return data
    }

    private func playAudio(data: Data) {
        do {
            let player = try AVAudioPlayer(data: data)
            player.play()
        } catch {
            lastError = error.localizedDescription
        }
    }
}

struct STTResponse: Codable {
    let text: String
}
