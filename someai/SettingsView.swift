//
//  SettingsView.swift
//  someai
//
//  设置页 - 版本、麦克风权限状态与申请
//

import SwiftUI
import AVFoundation
import AppKit

enum MicPermissionStatus {
    case granted
    case denied
    case undetermined
}

@Observable
final class MicPermissionObserver {
    var status: MicPermissionStatus = .undetermined

    func refresh() {
        #if os(macOS)
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: status = .granted
        case .denied, .restricted: status = .denied
        case .notDetermined: status = .undetermined
        @unknown default: status = .undetermined
        }
        #else
        switch AVAudioApplication.shared.recordPermission {
        case .granted: status = .granted
        case .denied: status = .denied
        case .undetermined: status = .undetermined
        @unknown default: status = .undetermined
        }
        #endif
    }

    func request() {
        #if os(macOS)
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        #else
        AVAudioApplication.requestRecordPermission { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        #endif
    }
}

struct SettingsView: View {
    @Environment(EngineManager.self) var engineManager
    @AppStorage("engine_use_china_mirror") private var useChinaMirror = false
    @State private var micObserver = MicPermissionObserver()
    @State private var enginePortText: String = "\(EngineConfig.shared.enginePort)"
    @State private var memoryLimitText: String = ""
    @State private var modelIdleTimeoutText: String = "15"
    @State private var llmTimeoutText: String = "300"
    @State private var imageTimeoutText: String = "180"
    @State private var modelLoadTimeoutText: String = "300"
    @State private var modelDownloadTimeoutText: String = "3600"
    @State private var outputDirPath: String = ""
    @State private var isSyncing = false
    @State private var syncMessage: String?
    @State private var syncFailed = false

    var body: some View {
        List {
            Section {
                HStack {
                    Text("settings.version")
                    Spacer()
                    Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.0")")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("settings.general")
            }

            Section {
                HStack {
                    Text("settings.engine_port")
                    Spacer()
                    TextField("settings.engine_port_placeholder", text: $enginePortText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                        .onSubmit { applyEnginePort() }
                }
                .onAppear {
                    enginePortText = "\(EngineConfig.shared.enginePort)"
                    memoryLimitText = EngineConfig.shared.memoryLimitMB > 0 ? "\(EngineConfig.shared.memoryLimitMB)" : ""
                    modelIdleTimeoutText = "\(EngineConfig.shared.modelIdleTimeoutMinutes)"
                    llmTimeoutText = "\(Int(EngineConfig.shared.llmGenerateTimeoutSeconds))"
                    imageTimeoutText = "\(Int(EngineConfig.shared.imageGenerateTimeoutSeconds))"
                    modelLoadTimeoutText = "\(Int(EngineConfig.shared.modelLoadTimeoutSeconds))"
                    modelDownloadTimeoutText = "\(Int(EngineConfig.shared.modelDownloadTimeoutSeconds))"
                    outputDirPath = EngineConfig.shared.outputDirectory.path
                }
                HStack {
                    Text("settings.memory_limit_mb")
                    Spacer()
                    TextField(String(localized: "settings.memory_limit_placeholder"), text: $memoryLimitText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                        .onSubmit { applyMemoryLimit() }
                }
                HStack {
                    Text("settings.model_idle_timeout")
                    Spacer()
                    TextField(String(localized: "settings.model_idle_timeout_placeholder"), text: $modelIdleTimeoutText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                        .onSubmit { applyModelIdleTimeout() }
                }
                Toggle("settings.use_china_mirror", isOn: $useChinaMirror)

                // Timeout Settings
                HStack {
                    Text("settings.llm_timeout")
                    Spacer()
                    TextField("settings.llm_timeout_placeholder", text: $llmTimeoutText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                        .onSubmit { applyLLMTimeout() }
                    Text("settings.seconds")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                HStack {
                    Text("settings.image_timeout")
                    Spacer()
                    TextField("settings.image_timeout_placeholder", text: $imageTimeoutText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                        .onSubmit { applyImageTimeout() }
                    Text("settings.seconds")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                HStack {
                    Text("settings.model_load_timeout")
                    Spacer()
                    TextField("settings.model_load_timeout_placeholder", text: $modelLoadTimeoutText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                        .onSubmit { applyModelLoadTimeout() }
                    Text("settings.seconds")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                HStack {
                    Text("settings.model_download_timeout")
                    Spacer()
                    TextField("settings.model_download_timeout_placeholder", text: $modelDownloadTimeoutText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                        .onSubmit { applyModelDownloadTimeout() }
                    Text("settings.seconds")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                if isSyncing {
                    HStack {
                        ProgressView()
                        Text("settings.syncing_deps")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button("settings.sync_deps") {
                        Task {
                            isSyncing = true
                            syncMessage = nil
                            syncFailed = false
                            let ok = await engineManager.syncDependencies()
                            syncFailed = !ok
                            syncMessage = ok ? String(localized: "settings.sync_deps_success") : String(localized: "settings.sync_deps_failed")
                            isSyncing = false
                        }
                    }
                    .disabled(isSyncing)
                }
                if let msg = syncMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(syncFailed ? .red : .secondary)
                }
            } header: {
                Text("settings.engine")
            } footer: {
                Text("settings.engine_footer")
            }

            Section {
                HStack {
                    Text("settings.output_directory")
                    Spacer()
                    TextField(String(localized: "settings.output_directory_placeholder"), text: $outputDirPath)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 200)
                        .onSubmit { applyOutputDirectory() }
                    Button {
                        pickOutputDirectory()
                    } label: {
                        Label(String(localized: "settings.browse"), systemImage: "folder")
                    }
                }
            } header: {
                Text("settings.output")
            } footer: {
                Text("settings.output_footer")
            }

            Section {
                HStack {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(micStatusColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("settings.mic_permission")
                            .font(.headline)
                        Text(micStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if micObserver.status == .undetermined {
                        Button("settings.request_mic") {
                            micObserver.request()
                        }
                    } else if micObserver.status == .denied {
                        Button("settings.open_system_prefs") {
                            openSystemPreferences()
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("settings.permissions")
            } footer: {
                Text("settings.mic_footer")
            }

            Section {
                NavigationLink {
                    LLMsTxtView()
                } label: {
                    Label("settings.view_llms_txt", systemImage: "doc.text")
                }
            } header: {
                Text("settings.api_docs")
            } footer: {
                Text("settings.llms_txt_footer")
            }
        }
        .navigationTitle(String(localized: "sidebar.settings"))
        .onAppear {
            micObserver.refresh()
        }
    }

    private var micStatusColor: Color {
        switch micObserver.status {
        case .granted: return .green
        case .denied: return .red
        case .undetermined: return .orange
        }
    }

    private var micStatusText: String {
        switch micObserver.status {
        case .granted: return String(localized: "settings.mic_granted")
        case .denied: return String(localized: "settings.mic_denied")
        case .undetermined: return String(localized: "settings.mic_undetermined")
        }
    }

    private func applyEnginePort() {
        if let v = Int(enginePortText), v >= 1024, v <= 65535 {
            let oldPort = EngineConfig.shared.enginePort
            EngineConfig.shared.enginePort = v
            if oldPort != v {
                EngineManager.shared.stopEngine()
            }
        } else {
            enginePortText = "\(EngineConfig.shared.enginePort)"
        }
    }

    private func applyOutputDirectory() {
        let trimmed = outputDirPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let path = (trimmed as NSString).expandingTildeInPath
        EngineConfig.shared.outputDirectory = URL(fileURLWithPath: path)
        outputDirPath = EngineConfig.shared.outputDirectory.path
    }

    private func pickOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = EngineConfig.shared.outputDirectory
        panel.begin { response in
            if response == .OK, let url = panel.url {
                EngineConfig.shared.outputDirectory = url
                outputDirPath = url.path
            }
        }
    }

    private func applyMemoryLimit() {
        let trimmed = memoryLimitText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            EngineConfig.shared.memoryLimitMB = 0
            memoryLimitText = ""
            EngineManager.shared.stopEngine()
            return
        }
        if let v = Int(trimmed), v > 0 {
            EngineConfig.shared.memoryLimitMB = v
            memoryLimitText = "\(v)"
            EngineManager.shared.stopEngine()
        } else {
            memoryLimitText = EngineConfig.shared.memoryLimitMB > 0 ? "\(EngineConfig.shared.memoryLimitMB)" : ""
        }
    }

    private func applyModelIdleTimeout() {
        let trimmed = modelIdleTimeoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let v = Int(trimmed), v >= 1, v <= 1440 {
            EngineConfig.shared.modelIdleTimeoutMinutes = v
            modelIdleTimeoutText = "\(v)"
            EngineManager.shared.stopEngine()
        } else {
            modelIdleTimeoutText = "\(EngineConfig.shared.modelIdleTimeoutMinutes)"
        }
    }

    private func applyLLMTimeout() {
        let trimmed = llmTimeoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let v = Int(trimmed), v >= 10, v <= 3600 {
            EngineConfig.shared.llmGenerateTimeoutSeconds = TimeInterval(v)
            llmTimeoutText = "\(v)"
        } else {
            llmTimeoutText = "\(Int(EngineConfig.shared.llmGenerateTimeoutSeconds))"
        }
    }

    private func applyImageTimeout() {
        let trimmed = imageTimeoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let v = Int(trimmed), v >= 10, v <= 3600 {
            EngineConfig.shared.imageGenerateTimeoutSeconds = TimeInterval(v)
            imageTimeoutText = "\(v)"
        } else {
            imageTimeoutText = "\(Int(EngineConfig.shared.imageGenerateTimeoutSeconds))"
        }
    }

    private func applyModelLoadTimeout() {
        let trimmed = modelLoadTimeoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let v = Int(trimmed), v >= 30, v <= 1800 {
            EngineConfig.shared.modelLoadTimeoutSeconds = TimeInterval(v)
            modelLoadTimeoutText = "\(v)"
        } else {
            modelLoadTimeoutText = "\(Int(EngineConfig.shared.modelLoadTimeoutSeconds))"
        }
    }

    private func applyModelDownloadTimeout() {
        let trimmed = modelDownloadTimeoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let v = Int(trimmed), v >= 60, v <= 10800 {
            EngineConfig.shared.modelDownloadTimeoutSeconds = TimeInterval(v)
            modelDownloadTimeoutText = "\(v)"
        } else {
            modelDownloadTimeoutText = "\(Int(EngineConfig.shared.modelDownloadTimeoutSeconds))"
        }
    }

    private func openSystemPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - LLMs.txt Viewer

struct LLMsTxtView: View {
    @State private var content: String?
    @State private var errorMessage: String?
    @State private var isLoading = true

    private var llmsTxtURL: URL {
        EngineConfig.shared.baseURL.appendingPathComponent("llms.txt")
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let content {
                ScrollView {
                    Text(content)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("settings.llms_txt_error")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("settings.llms_txt_open_browser") {
                        openURL(llmsTxtURL)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
        .navigationTitle("llms.txt")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await fetchContent()
        }
    }

    private func openURL(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }

    private func fetchContent() async {
        isLoading = true
        errorMessage = nil
        content = nil
        do {
            let (data, _) = try await URLSession.shared.data(from: llmsTxtURL)
            if let text = String(data: data, encoding: .utf8) {
                content = text
            } else {
                errorMessage = "Invalid encoding"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
