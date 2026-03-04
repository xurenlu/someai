//
//  ContentView.swift
//  someai
//
//  MacAIStudio 主界面 - 重新设计的侧边栏布局
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum SidebarItem: String, CaseIterable, Identifiable {
    case chat
    case voiceAssistant
    case imageGen
    case textToSpeech
    case speechToText
    case ocr
    case history
    case modelManager
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat: return "sidebar.chat"
        case .voiceAssistant: return "sidebar.voice_assistant"
        case .imageGen: return "sidebar.image_gen"
        case .textToSpeech: return "sidebar.text_to_speech"
        case .speechToText: return "sidebar.speech_to_text"
        case .ocr: return "sidebar.ocr"
        case .history: return "sidebar.history"
        case .modelManager: return "sidebar.model_manager"
        case .settings: return "sidebar.settings"
        }
    }

    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        case .voiceAssistant: return "wave.form"
        case .imageGen: return "photo.badge.plus"
        case .textToSpeech: return "speaker.wave.2"
        case .speechToText: return "mic"
        case .ocr: return "doc.text.viewfinder"
        case .history: return "clock.arrow.circlepath"
        case .modelManager: return "cpu"
        case .settings: return "gearshape"
        }
    }

    var section: SidebarSection {
        switch self {
        case .chat, .voiceAssistant, .imageGen, .textToSpeech, .speechToText, .ocr:
            return .features
        case .history, .modelManager, .settings:
            return .system
        }
    }
}

enum SidebarSection: String, CaseIterable, Identifiable {
    case features
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .features: return "sidebar.section.features"
        case .system: return "sidebar.section.system"
        }
    }
}

struct ContentView: View {
    @Environment(EngineManager.self) var engineManager
    @State private var selectedItem: SidebarItem? = .chat
    @State private var healthStatus: String = "—"
    @State private var models: [EngineClient.ModelSummary] = []
    @State private var isLoading = false
    @State private var lastError: String?

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedItem) {
                ForEach(SidebarSection.allCases) { section in
                    Section {
                        ForEach(SidebarItem.allCases.filter { $0.section == section }) { item in
                            NavigationLink(value: item) {
                                Label(String(localized: String.LocalizationValue(item.title)), systemImage: item.icon)
                            }
                        }
                    } header: {
                        Text(String(localized: String.LocalizationValue(section.title)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 120, ideal: 160)
        } detail: {
            Group {
                switch selectedItem {
                case .chat:
                    ChatView()
                case .voiceAssistant:
                    VoiceAssistantView()
                case .imageGen:
                    ImageView()
                case .textToSpeech:
                    TTSView()
                case .speechToText:
                    STTView()
                case .ocr:
                    OCRView()
                case .history:
                    HistoryHubView()
                case .modelManager:
                    ModelManagerView(
                        healthStatus: $healthStatus,
                        models: $models,
                        isLoading: $isLoading,
                        lastError: $lastError,
                        engineManager: engineManager,
                        selectedSidebarItem: $selectedItem
                    )
                case .settings:
                    SettingsView()
                case .none:
                    Text("history.select_item")
                }
            }
            .onAppear {
                if selectedItem == .modelManager {
                    refreshEngineStatus()
                }
            }
            .onChange(of: selectedItem) { _, newValue in
                if newValue == .modelManager {
                    refreshEngineStatus()
                }
            }
        }
        .onAppear {
            Task {
                let ready = await engineManager.ensureEngineReady()
                if ready {
                    refreshEngineStatus()
                } else {
                    lastError = engineManager.lastStartupError
                    healthStatus = "Error"
                    models = []
                }
            }
        }
        .onDisappear {
            engineManager.stopEngine()
        }
    }

    private func refreshEngineStatus() {
        isLoading = true
        lastError = nil
        Task {
            if !engineManager.isRunning {
                let ready = await engineManager.ensureEngineReady()
                guard ready else {
                    await MainActor.run {
                        lastError = engineManager.lastStartupError
                        healthStatus = "Error"
                        models = []
                        isLoading = false
                    }
                    return
                }
            }
            do {
                let health = try await EngineClient.fetchHealth()
                await MainActor.run {
                    healthStatus = "\(health.status) (\(health.models_loaded.joined(separator: ", ") == "" ? "—" : health.models_loaded.joined(separator: ", ")))"
                }
                let modelsResp = try await EngineClient.fetchModels()
                await MainActor.run {
                    models = modelsResp.models
                }
            } catch {
                await MainActor.run {
                    lastError = error.localizedDescription
                    healthStatus = "Error"
                    models = []
                }
            }
            await MainActor.run {
                isLoading = false
            }
        }
    }
}

// MARK: - New Feature Views

/// 语音助手 - 完整的 STT → LLM → TTS 交互流程
struct VoiceAssistantView: View {
    @Environment(GenerationHistoryStore.self) private var historyStore
    @Environment(ViewStateStore.self) private var viewStateStore

    @State private var isRecording = false
    @State private var availableModels: [EngineClient.ModelSummary] = []

    private var transcript: Binding<String> {
        Binding(
            get: { viewStateStore.voiceTranscript },
            set: { viewStateStore.voiceTranscript = $0 }
        )
    }

    private var responseText: Binding<String> {
        Binding(
            get: { viewStateStore.voiceResponseText },
            set: { viewStateStore.voiceResponseText = $0 }
        )
    }

    private var audioURL: Binding<URL?> {
        Binding(
            get: { viewStateStore.voiceAudioURL },
            set: { viewStateStore.voiceAudioURL = $0 }
        )
    }

    private var isProcessing: Binding<Bool> {
        Binding(
            get: { viewStateStore.voiceIsProcessing },
            set: { viewStateStore.voiceIsProcessing = $0 }
        )
    }

    private var selectedModelId: Binding<String?> {
        Binding(
            get: { viewStateStore.voiceSelectedLLMModel.isEmpty ? nil : viewStateStore.voiceSelectedLLMModel },
            set: { viewStateStore.voiceSelectedLLMModel = $0 ?? "" }
        )
    }

    private var selectedTTSModel: Binding<String?> {
        Binding(
            get: { viewStateStore.voiceSelectedTTSModel.isEmpty ? nil : viewStateStore.voiceSelectedTTSModel },
            set: { viewStateStore.voiceSelectedTTSModel = $0 ?? "" }
        )
    }

    private var selectedSTTModel: Binding<String?> {
        Binding(
            get: { viewStateStore.voiceSelectedSTTModel.isEmpty ? nil : viewStateStore.voiceSelectedSTTModel },
            set: { viewStateStore.voiceSelectedSTTModel = $0 ?? "" }
        )
    }

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Text("voice_assistant.title")
                    .font(.title)
                    .bold()
                Text("voice_assistant.description")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 20)

            // Model Selection
            HStack(spacing: 16) {
                Picker("voice_assistant.stt_model", selection: selectedSTTModel) {
                    Text("voice_assistant.auto").tag(nil as String?)
                    ForEach(availableModels.filter { $0.type == "stt" }, id: \.id) { model in
                        Text(model.name).tag(model.id as String?)
                    }
                }
                .pickerStyle(.menu)

                Picker("voice_assistant.tts_model", selection: selectedTTSModel) {
                    Text("voice_assistant.auto").tag(nil as String?)
                    ForEach(availableModels.filter { $0.type == "tts" }, id: \.id) { model in
                        Text(model.name).tag(model.id as String?)
                    }
                }
                .pickerStyle(.menu)

                Picker("voice_assistant.llm_model", selection: selectedModelId) {
                    Text("voice_assistant.auto").tag(nil as String?)
                    ForEach(availableModels.filter { $0.type == "llm" }, id: \.id) { model in
                        Text(model.name).tag(model.id as String?)
                    }
                }
                .pickerStyle(.menu)
            }
            .padding(.horizontal)
            .onAppear {
                loadModels()
            }

            Divider()

            // Transcript Display
            VStack(alignment: .leading, spacing: 12) {
                Text("voice_assistant.you_said")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                ScrollView {
                    Text(transcript.wrappedValue.isEmpty ? "voice_assistant.tap_to_speak" : transcript.wrappedValue)
                        .font(.body)
                        .foregroundStyle(transcript.wrappedValue.isEmpty ? .tertiary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 100)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
            }
            .padding(.horizontal)

            // Response Display
            VStack(alignment: .leading, spacing: 12) {
                Text("voice_assistant.response")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                ScrollView {
                    Text(responseText.wrappedValue.isEmpty ? "voice_assistant.response_placeholder" : responseText.wrappedValue)
                        .font(.body)
                        .foregroundStyle(responseText.wrappedValue.isEmpty ? .tertiary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 150)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)

                if let audioURL = audioURL.wrappedValue {
                    AudioPlayerView(audioURL: audioURL)
                }
            }
            .padding(.horizontal)

            Spacer()

            // Control Buttons
            HStack(spacing: 20) {
                Button {
                    Task {
                        await startVoiceInteraction()
                    }
                } label: {
                    Label("voice_assistant.start", systemImage: "mic.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isProcessing.wrappedValue)

                if audioURL.wrappedValue != nil || !responseText.wrappedValue.isEmpty {
                    Button {
                        saveToHistory()
                    } label: {
                        Label("voice_assistant.save", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.bottom, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(String(localized: "sidebar.voice_assistant"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func loadModels() {
        Task {
            do {
                let resp = try await EngineClient.fetchModels()
                await MainActor.run {
                    availableModels = resp.models.filter { $0.status == "installed" }
                }
            } catch {
                print("Failed to load models: \(error)")
            }
        }
    }

    private func startVoiceInteraction() async {
        isProcessing.wrappedValue = true
        defer { isProcessing.wrappedValue = false }

        // 1. Record audio
        guard let recordingURL = await recordAudio() else { return }

        // 2. STT
        let audioData = try? Data(contentsOf: recordingURL)
        guard let audioData, let transcribed = try? await EngineClient.transcribe(audioData: audioData) else { return }
        viewStateStore.voiceTranscript = transcribed

        // 3. LLM
        let llmResponse = try? await EngineClient.generateChat(
            prompt: transcribed,
            temperature: 0.7,
            maxTokens: 512,
            modelId: selectedModelId.wrappedValue
        )
        guard let response = llmResponse else { return }
        viewStateStore.voiceResponseText = response

        // 4. TTS
        if let ttsAudio = try? await EngineClient.generateTTS(
            text: response,
            language: "zh",
            speaker: "default",
            modelId: selectedTTSModel.wrappedValue
        ) {
            let fileName = "voice_\(Int(Date().timeIntervalSince1970)).mp3"
            let outputURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(fileName)
            try? ttsAudio.write(to: outputURL)
            viewStateStore.voiceAudioURL = outputURL
        }
    }

    private func recordAudio() async -> URL? {
        // Simplified recording - in real implementation would show recording UI
        try? await Task.sleep(nanoseconds: 100_000_000) // Simulate recording
        return nil
    }

    private func saveToHistory() {
        let payload = GenerationPayload(
            voiceChat: .init(
                userText: viewStateStore.voiceTranscript,
                assistantText: viewStateStore.voiceResponseText,
                llmPrompt: viewStateStore.voiceTranscript,
                llmTemperature: 0.7,
                llmMaxTokens: 512,
                ttsText: viewStateStore.voiceResponseText,
                ttsLanguage: "zh",
                ttsSpeaker: "default"
            )
        )
        let record = GenerationRecord(
            kind: .voiceChat,
            status: .success,
            payload: payload
        )
        historyStore.append(record)
        viewStateStore.voiceTranscript = ""
        viewStateStore.voiceResponseText = ""
        viewStateStore.voiceAudioURL = nil
    }
}

/// 语音识别视图
struct STTView: View {
    @Environment(ViewStateStore.self) private var viewStateStore

    @State private var availableModels: [EngineClient.ModelSummary] = []

    private var selectedAudioURL: Binding<URL?> {
        Binding(
            get: { viewStateStore.sttSelectedAudioURL },
            set: { viewStateStore.sttSelectedAudioURL = $0 }
        )
    }

    private var transcriptText: Binding<String> {
        Binding(
            get: { viewStateStore.sttTranscriptText },
            set: { viewStateStore.sttTranscriptText = $0 }
        )
    }

    private var isProcessing: Binding<Bool> {
        Binding(
            get: { viewStateStore.sttIsProcessing },
            set: { viewStateStore.sttIsProcessing = $0 }
        )
    }

    private var selectedModelId: Binding<String?> {
        Binding(
            get: { viewStateStore.sttSelectedModelId.isEmpty ? nil : viewStateStore.sttSelectedModelId },
            set: { viewStateStore.sttSelectedModelId = $0 ?? "" }
        )
    }

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Text("stt.title")
                    .font(.title)
                    .bold()
                Text("stt.description")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 20)

            // Model Selection
            HStack {
                Picker("stt.model", selection: selectedModelId) {
                    Text("stt.auto_select").tag(nil as String?)
                    ForEach(availableModels.filter { $0.type == "stt" }, id: \.id) { model in
                        Text(model.name).tag(model.id as String?)
                    }
                }
                .pickerStyle(.menu)
            }
            .padding(.horizontal)
            .onAppear {
                loadModels()
            }

            Divider()

            // File Selection
            VStack(alignment: .leading, spacing: 12) {
                Text("stt.select_audio")
                    .font(.headline)

                if let url = selectedAudioURL.wrappedValue {
                    HStack {
                        Text(url.lastPathComponent)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("stt.remove") {
                            viewStateStore.sttSelectedAudioURL = nil
                            viewStateStore.sttTranscriptText = ""
                        }
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                } else {
                    Button {
                        selectAudioFile()
                    } label: {
                        Label("stt.browse", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal)

            // Transcript Result
            VStack(alignment: .leading, spacing: 12) {
                Text("stt.transcript")
                    .font(.headline)

                TextEditor(text: transcriptText)
                    .font(.body)
                    .frame(minHeight: 200)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
                    .disabled(isProcessing.wrappedValue)

                HStack {
                    Spacer()
                    Button {
                        copyTranscript()
                    } label: {
                        Label("stt.copy", systemImage: "doc.on.doc")
                    }
                    .disabled(transcriptText.wrappedValue.isEmpty)
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal)

            Spacer()

            // Action Button
            Button {
                Task {
                    await transcribe()
                }
            } label: {
                Label("stt.transcribe", systemImage: "mic")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selectedAudioURL.wrappedValue == nil || isProcessing.wrappedValue)
            .padding(.bottom, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(String(localized: "sidebar.speech_to_text"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func loadModels() {
        Task {
            do {
                let resp = try await EngineClient.fetchModels()
                await MainActor.run {
                    availableModels = resp.models.filter { $0.status == "installed" }
                }
            } catch {
                print("Failed to load models: \(error)")
            }
        }
    }

    private func selectAudioFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .movie]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                viewStateStore.sttSelectedAudioURL = url
            }
        }
    }

    private func transcribe() async {
        guard let url = viewStateStore.sttSelectedAudioURL else { return }
        isProcessing.wrappedValue = true
        defer { isProcessing.wrappedValue = false }

        do {
            let data = try Data(contentsOf: url)
            let result = try await EngineClient.transcribe(audioData: data)
            await MainActor.run {
                viewStateStore.sttTranscriptText = result
            }
        } catch {
            await MainActor.run {
                viewStateStore.sttTranscriptText = error.localizedDescription
            }
        }
    }

    private func copyTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(viewStateStore.sttTranscriptText, forType: .string)
    }
}

/// 简单的音频播放器视图
struct AudioPlayerView: View {
    let audioURL: URL
    @State private var isPlaying = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)

            Slider(value: .constant(0.5))
                .disabled(true)

            Text("0:00 / 0:00")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func togglePlayback() {
        isPlaying.toggle()
        // In real implementation, would use AVAudioPlayer
    }
}

// MARK: - Model Manager View (keep existing)

struct ModelManagerView: View {
    @Binding var healthStatus: String
    @Binding var models: [EngineClient.ModelSummary]
    @Binding var isLoading: Bool
    @Binding var lastError: String?
    var engineManager: EngineManager
    @Binding var selectedSidebarItem: SidebarItem?
    @State private var portOccupants: [String] = []
    @State private var downloadingId: String? = nil
    @State private var downloadProgress: (downloaded: Int64, total: Int64)? = nil
    @State private var deletingId: String? = nil
    @State private var modelToDelete: EngineClient.ModelSummary? = nil
    @State private var showAddModelSheet = false
    @State private var addModelHfRepo = ""
    @State private var addModelName = ""
    @State private var addModelType = "llm"
    @State private var addModelAdding = false
    @State private var addModelError: String? = nil
    @State private var diagnosticsCopied = false

    var body: some View {
        List {
            Section {
                HStack {
                    Circle()
                        .fill(engineManager.isRunning ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(engineManager.isRunning ? String(localized: "model_manager.status.engine_running") : String(localized: "model_manager.status.engine_stopped"))
                        .font(.headline)
                }
                if engineManager.isPreparing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(String(localized: "model_manager.preparing"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if isLoading {
                    ProgressView()
                } else {
                    Text("\(String(localized: "model_manager.health")): \(engineManager.isRunning ? healthStatus : "—")")
                        .font(.subheadline)
                }
                if let err = lastError {
                    Text("\(String(localized: "model_manager.error_label")): \(err)")
                        .font(.caption)
                        .foregroundStyle(.red)
                    if !portOccupants.isEmpty {
                        Text(String(format: String(localized: "model_manager.port_occupied_by"), portOccupants.joined(separator: ", ")))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    HStack(spacing: 8) {
                        if !portOccupants.isEmpty {
                            Button {
                                Task { await killStaleEngineAndRetry() }
                            } label: {
                                Label(String(localized: "model_manager.kill_and_retry"), systemImage: "xmark.circle")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isLoading)
                        }
                        Button {
                            Task { await refreshAsync() }
                        } label: {
                            Label(String(localized: "model_manager.retry"), systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isLoading)
                        Button {
                            copyDiagnostics()
                        } label: {
                            if diagnosticsCopied {
                                Label(String(localized: "model_manager.copied"), systemImage: "checkmark.circle.fill")
                            } else {
                                Label(String(localized: "model_manager.copy_diagnostics"), systemImage: "doc.on.doc")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isLoading)
                        .animation(.easeInOut(duration: 0.2), value: diagnosticsCopied)
                        Button {
                            selectedSidebarItem = .settings
                        } label: {
                            Label(String(localized: "model_manager.open_settings"), systemImage: "gearshape")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } header: {
                Text(String(localized: "model_manager.status_header"))
            }

            ForEach(groupedModels, id: \.type) { group in
                Section {
                    ForEach(group.models, id: \.id) { model in
                        modelRow(model)
                    }
                } header: {
                    HStack(spacing: 8) {
                        Text(localizedModelType(group.type))
                        Text("(\(group.models.count))")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(String(localized: "sidebar.model_manager"))
        .onAppear {
            if !engineManager.isRunning {
                engineManager.startEngine()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    Button {
                        showAddModelSheet = true
                    } label: {
                        Label(String(localized: "model_manager.add_model"), systemImage: "plus.circle")
                    }
                    .help(String(localized: "model_manager.add_model_title"))
                    if let root = engineManager.projectRoot {
                        Button {
                            openInFinder(path: root.appendingPathComponent("models").path)
                        } label: {
                            Label(String(localized: "model_manager.open_models_root"), systemImage: "folder.badge.gearshape")
                        }
                        .help(String(localized: "model_manager.open_models_root_help"))
                    }
                    Button {
                        Task { await refreshAsync() }
                    } label: {
                        Label(String(localized: "model_manager.retry"), systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
        }
        .sheet(isPresented: $showAddModelSheet, onDismiss: {
            addModelHfRepo = ""
            addModelName = ""
            addModelType = "llm"
            addModelError = nil
            Task { await refreshAsync() }
        }) {
            AddModelSheet(
                hfRepo: $addModelHfRepo,
                name: $addModelName,
                type: $addModelType,
                isAdding: $addModelAdding,
                error: $addModelError,
                onAdd: { Task { await addModelSubmit() } }
            )
        }
        .refreshable {
            await refreshAsync()
        }
        .confirmationDialog(String(localized: "model_manager.delete_confirm_title"), isPresented: Binding(
            get: { modelToDelete != nil },
            set: { if !$0 { modelToDelete = nil } }
        )) {
            if let m = modelToDelete {
                Button(String(localized: "model_manager.delete"), role: .destructive) {
                    Task { await deleteModel(m.id) }
                }
                Button(String(localized: "model_manager.cancel"), role: .cancel) {
                    modelToDelete = nil
                }
            }
        } message: {
            if let m = modelToDelete {
                Text(String(format: String(localized: "model_manager.delete_confirm_message"), m.name))
            }
        }
    }

    private func localizedModelType(_ type: String) -> String {
        switch type.lowercased() {
        case "llm": return String(localized: "model_manager.type.llm")
        case "tts": return String(localized: "model_manager.type.tts")
        case "stt": return String(localized: "model_manager.type.stt")
        case "image": return String(localized: "model_manager.type.image")
        case "vision": return String(localized: "model_manager.type.vision")
        case "ocr": return String(localized: "model_manager.type.ocr")
        case "—", "": return String(localized: "model_manager.type.other")
        default: return type
        }
    }

    private var groupedModels: [(type: String, models: [EngineClient.ModelSummary])] {
        let grouped = Dictionary(grouping: models) { model in
            model.type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : model.type
        }
        return grouped.keys
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { key in
                let sortedModels = (grouped[key] ?? []).sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                return (type: key, models: sortedModels)
            }
    }

    @ViewBuilder
    private func modelRow(_ model: EngineClient.ModelSummary) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.name)
                    .font(.headline)
                HStack(spacing: 6) {
                    Text(model.type)
                        .font(.caption)
                        .padding(2)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                    Text(model.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let size = model.actual_size_bytes ?? model.size_bytes, size > 0 {
                        Text(formatBytes(size))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let types = model.file_types, !types.isEmpty {
                        Text(types.joined(separator: " "))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.vertical, 4)
            Spacer()
            HStack(spacing: 6) {
                if model.status == "installed", let dir = model.local_dir {
                    Button {
                        openInFinder(path: dir)
                    } label: {
                        Label(String(localized: "model_manager.open_in_finder"), systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    Button(role: .destructive) {
                        modelToDelete = model
                    } label: {
                        if deletingId == model.id {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Label(String(localized: "model_manager.delete"), systemImage: "trash")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(deletingId != nil)
                }
                if model.status == "not_downloaded" {
                    Button {
                        Task { await downloadModel(model.id) }
                    } label: {
                        if downloadingId == model.id {
                            HStack(spacing: 6) {
                                if let prog = downloadProgress, prog.total > 0 {
                                    ProgressView(value: Double(prog.downloaded), total: Double(prog.total))
                                        .frame(width: 80)
                                    Text("\(formatBytes(Int(prog.downloaded)))/\(formatBytes(Int(prog.total)))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    if let sz = model.size_bytes, sz > 0 {
                                        Text(String(format: String(localized: "model_manager.downloading_size"), formatBytes(sz)))
                                            .font(.caption)
                                    }
                                }
                            }
                        } else {
                            Label(String(localized: "model_manager.download"), systemImage: "arrow.down.circle")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(downloadingId != nil)
                }
            }
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        let gb = Double(bytes) / 1_073_741_824
        let mb = Double(bytes) / 1_048_576
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        return String(format: "%.0f KB", Double(bytes) / 1024)
    }

    private func openInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }

    private func copyDiagnostics() {
        let text = engineManager.buildDiagnostics()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        diagnosticsCopied = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            diagnosticsCopied = false
        }
    }

    private func deleteModel(_ modelId: String) async {
        modelToDelete = nil
        deletingId = modelId
        lastError = nil
        do {
            try await EngineClient.deleteModel(modelId: modelId)
            await refreshAsync()
        } catch {
            await MainActor.run {
                lastError = error.localizedDescription
            }
        }
        await MainActor.run {
            deletingId = nil
        }
    }

    private func killStaleEngineAndRetry() async {
        let port = EngineConfig.shared.enginePort
        let projectRoot = engineManager.projectRoot
        let killed = PortChecker.killEngineProcessesOn(port: port, projectRoot: projectRoot)
        if killed > 0 {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        await refreshAsync()
    }

    private func downloadModel(_ modelId: String) async {
        downloadingId = modelId
        downloadProgress = nil
        lastError = nil
        var completedError: String? = nil
        do {
            for try await prog in EngineClient.downloadModelStreaming(modelId: modelId) {
                if prog.done {
                    completedError = prog.error
                    break
                }
                if prog.total > 0 || prog.downloaded > 0 {
                    await MainActor.run {
                        downloadProgress = (prog.downloaded, max(prog.total, prog.downloaded))
                    }
                }
            }
            await MainActor.run {
                if let err = completedError {
                    lastError = err
                }
            }
            if completedError == nil {
                await refreshAsync()
            }
        } catch {
            await MainActor.run {
                lastError = error.localizedDescription
            }
        }
        await MainActor.run {
            downloadingId = nil
            downloadProgress = nil
        }
    }

    private func addModelSubmit() async {
        let repo = addModelHfRepo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repo.isEmpty, repo.contains("/") else {
            await MainActor.run {
                addModelError = String(localized: "model_manager.add_model_invalid_repo")
            }
            return
        }
        addModelAdding = true
        addModelError = nil
        do {
            _ = try await EngineClient.addModel(
                hfRepo: repo,
                name: addModelName.isEmpty ? nil : addModelName,
                type: addModelType
            )
            await MainActor.run {
                showAddModelSheet = false
                addModelHfRepo = ""
                addModelName = ""
                addModelType = "llm"
            }
            await refreshAsync()
        } catch {
            await MainActor.run {
                addModelError = error.localizedDescription
            }
        }
        await MainActor.run {
            addModelAdding = false
        }
    }

    private func refreshAsync() async {
        isLoading = true
        lastError = nil
        if !engineManager.isRunning {
            let ready = await engineManager.ensureEngineReady()
            guard ready else {
                await MainActor.run {
                    lastError = engineManager.lastStartupError
                    healthStatus = "Error"
                    models = []
                    isLoading = false
                }
                return
            }
        }
        portOccupants = []
        do {
            let health = try await EngineClient.fetchHealth()
            await MainActor.run {
                healthStatus = "\(health.status) (\(health.models_loaded.isEmpty ? "—" : health.models_loaded.joined(separator: ", ")))"
            }
            let modelsResp = try await EngineClient.fetchModels()
            await MainActor.run {
                models = modelsResp.models
            }
        } catch {
            let occupants = PortChecker.processesUsing(port: EngineConfig.shared.enginePort)
            await MainActor.run {
                lastError = error.localizedDescription
                portOccupants = occupants
                healthStatus = "Error"
                models = []
            }
        }
        await MainActor.run {
            isLoading = false
        }
    }
}

// MARK: - Add Model Sheet

struct AddModelSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var hfRepo: String
    @Binding var name: String
    @Binding var type: String
    @Binding var isAdding: Bool
    @Binding var error: String?
    var onAdd: () -> Void

    private let modelTypes = ["llm", "tts", "stt", "image", "vision", "ocr"]

    var body: some View {
        VStack(spacing: 20) {
            Text(String(localized: "model_manager.add_model_title"))
                .font(.title2)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "model_manager.add_model_hf_repo"))
                    .font(.headline)
                TextField(String(localized: "model_manager.add_model_hf_repo_placeholder"), text: $hfRepo)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "model_manager.add_model_name"))
                    .font(.headline)
                TextField("", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "model_manager.add_model_type"))
                    .font(.headline)
                Picker("", selection: $type) {
                    ForEach(modelTypes, id: \.self) { t in
                        Text(t).tag(t)
                    }
                }
                .pickerStyle(.segmented)
            }

            if let err = error {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .padding(24)
        .frame(minWidth: 400, minHeight: 320)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "model_manager.cancel")) {
                    dismiss()
                }
                .disabled(isAdding)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "model_manager.add_model_add")) {
                    onAdd()
                }
                .disabled(isAdding || hfRepo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(EngineManager.shared)
}
