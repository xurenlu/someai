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
                        engineManager: engineManager,
                        selectedSidebarItem: $selectedItem
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

    private let modelTypes = ["llm", "tts", "stt", "image", "vision"]

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
