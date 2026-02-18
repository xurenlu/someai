//
//  ContentView.swift
//  someai
//
//  MacAIStudio 主界面 - Sidebar 布局
//

import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case chat
    case tts
    case voiceChat
    case image
    case modelManager
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat: return "sidebar.chat"
        case .tts: return "sidebar.tts"
        case .voiceChat: return "sidebar.voice_chat"
        case .image: return "sidebar.image"
        case .modelManager: return "sidebar.model_manager"
        case .settings: return "sidebar.settings"
        }
    }

    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        case .tts: return "speaker.wave.2"
        case .voiceChat: return "mic.fill"
        case .image: return "photo"
        case .modelManager: return "cpu"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    @Environment(EngineManager.self) var engineManager
    @State private var selectedItem: SidebarItem? = .modelManager
    @State private var healthStatus: String = "—"
    @State private var models: [EngineClient.ModelSummary] = []
    @State private var isLoading = false
    @State private var lastError: String?

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedItem) {
                ForEach(SidebarItem.allCases) { item in
                    NavigationLink(value: item) {
                        Label(String(localized: String.LocalizationValue(item.title)), systemImage: item.icon)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            Group {
                switch selectedItem {
                case .chat:
                    ChatView()
                case .tts:
                    TTSView()
                case .voiceChat:
                    VoiceChatView()
                case .image:
                    ImageView()
                case .modelManager:
                    ModelManagerView(
                        healthStatus: $healthStatus,
                        models: $models,
                        isLoading: $isLoading,
                        lastError: $lastError,
                        engineManager: engineManager
                    )
                case .settings:
                    SettingsView()
                case .none:
                    Text("Select an item")
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
            engineManager.startEngine()
            // Engine needs ~2s to start; fetchHealth/fetchModels have built-in retry (3 attempts, 1.5s apart)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                refreshEngineStatus()
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
            do {
                let health = try await EngineClient.fetchHealth()
                healthStatus = "\(health.status) (\(health.models_loaded.joined(separator: ", ") == "" ? "—" : health.models_loaded.joined(separator: ", ")))"
                let modelsResp = try await EngineClient.fetchModels()
                models = modelsResp.models
            } catch {
                lastError = error.localizedDescription
                healthStatus = "Error"
                models = []
            }
            isLoading = false
        }
    }
}

// MARK: - Placeholder Views (M2+ will implement)

struct ChatPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "chat.placeholder.title",
            systemImage: "bubble.left.and.bubble.right",
            description: Text("chat.placeholder.desc")
        )
    }
}

struct TTSPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "tts.placeholder.title",
            systemImage: "speaker.wave.2",
            description: Text("tts.placeholder.desc")
        )
    }
}

struct VoiceChatPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "voice_chat.placeholder.title",
            systemImage: "mic.fill",
            description: Text("voice_chat.placeholder.desc")
        )
    }
}

struct ImagePlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "image.placeholder.title",
            systemImage: "photo",
            description: Text("image.placeholder.desc")
        )
    }
}

// MARK: - Model Manager View

struct ModelManagerView: View {
    @Binding var healthStatus: String
    @Binding var models: [EngineClient.ModelSummary]
    @Binding var isLoading: Bool
    @Binding var lastError: String?
    var engineManager: EngineManager

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
                if isLoading {
                    ProgressView()
                } else {
                    Text("\(String(localized: "model_manager.health")): \(healthStatus)")
                        .font(.subheadline)
                }
                if let err = lastError {
                    Text("\(String(localized: "model_manager.error_label")): \(err)")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button {
                        Task { await refreshAsync() }
                    } label: {
                        Label(String(localized: "model_manager.retry"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading)
                }
            } header: {
                Text(String(localized: "model_manager.status_header"))
            }

            Section {
                ForEach(models, id: \.id) { model in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.name)
                            .font(.headline)
                        HStack {
                            Text(model.type)
                                .font(.caption)
                                .padding(2)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(4)
                            Text(model.status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text(String(localized: "model_manager.models_header"))
            }
        }
        .navigationTitle(String(localized: "sidebar.model_manager"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await refreshAsync() }
                } label: {
                    Label(String(localized: "model_manager.retry"), systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .refreshable {
            await refreshAsync()
        }
    }

    private func refreshAsync() async {
        isLoading = true
        lastError = nil
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

#Preview {
    ContentView()
        .environment(EngineManager.shared)
}
