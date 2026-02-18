//
//  SettingsView.swift
//  someai
//
//  设置页 - 版本、麦克风权限状态与申请
//

import SwiftUI
import AVFoundation

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
    @State private var micObserver = MicPermissionObserver()
    @State private var enginePortText: String = "\(EngineConfig.shared.enginePort)"

    var body: some View {
        List {
            Section {
                HStack {
                    Text("settings.version")
                    Spacer()
                    Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0-rc9")")
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
                }
            } header: {
                Text("settings.engine")
            } footer: {
                Text("settings.engine_port_footer")
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

    private func openSystemPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
