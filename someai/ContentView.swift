//
//  ContentView.swift
//  someai
//
//  MacAIStudio 主界面 - Sidebar 布局
//

import SwiftUI
import AppKit

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
    @State private var portOccupants: [String] = []
    @State private var downloadingId: String? = nil
    @State private var deletingId: String? = nil
    @State private var modelToDelete: EngineClient.ModelSummary? = nil

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
                    Text("\(String(localized: "model_manager.health")): \(healthStatus)")
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
                            Label(String(localized: "model_manager.copy_diagnostics"), systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isLoading)
                    }
                }
            } header: {
                Text(String(localized: "model_manager.status_header"))
            }

            Section {
                ForEach(models, id: \.id) { model in
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
                                        HStack(spacing: 4) {
                                            ProgressView()
                                                .scaleEffect(0.7)
                                            if let sz = model.size_bytes, sz > 0 {
                                                Text(String(format: String(localized: "model_manager.downloading_size"), formatBytes(sz)))
                                                    .font(.caption)
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
            } header: {
                Text(String(localized: "model_manager.models_header"))
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
        lastError = nil
        do {
            _ = try await EngineClient.downloadModel(modelId: modelId)
            await refreshAsync()
        } catch {
            await MainActor.run {
                lastError = error.localizedDescription
            }
        }
        await MainActor.run {
            downloadingId = nil
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

#Preview {
    ContentView()
        .environment(EngineManager.shared)
}
