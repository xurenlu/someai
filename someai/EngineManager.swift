//
//  EngineManager.swift
//  someai
//
//  Manages Python engine process lifecycle.
//

import Foundation
import Observation

@Observable
final class EngineManager {
    static let shared = EngineManager()

    private(set) var isRunning = false
    private(set) var isStarting = false
    private(set) var isPreparing = false
    private(set) var process: Process?
    private(set) var lastStartupError: String?
    private(set) var lastStderrLine: String?

    private var port: Int { EngineConfig.shared.enginePort }
    var baseURL: URL { EngineConfig.shared.baseURL }
    private let startupTimeoutSeconds: TimeInterval = 15
    private let readinessPollNanos: UInt64 = 400_000_000
    private var prepareTask: Task<Bool, Never>?

    var engineURL: URL {
        baseURL.appendingPathComponent("health")
    }

    /// 项目根目录，用于 PID 文件等。nil 表示引擎目录未找到。
    var projectRoot: URL? {
        Self.findEngineDirectory()?.deletingLastPathComponent()
    }

    init() {}

    @MainActor
    func startEngine() {
        guard !isRunning else {
            lastStartupError = nil
            return
        }

        lastStartupError = nil
        lastStderrLine = nil
        isStarting = true

        let engineDir = Self.findEngineDirectory()
        guard let engine = engineDir else {
            lastStartupError = String(localized: "model_manager.error.engine_dir_not_found")
            isStarting = false
            print("[EngineManager] Cannot start: engine dir not found")
            return
        }
        let projectRoot = engine.deletingLastPathComponent()

        var occupied = PortChecker.processesUsing(port: port)
        if let first = occupied.first {
            let killed = PortChecker.killEngineProcessesOn(port: port, projectRoot: projectRoot)
            if killed > 0 {
                print("[EngineManager] Killed \(killed) stale engine process(es) on port \(port)")
                Thread.sleep(forTimeInterval: 0.5)
                occupied = PortChecker.processesUsing(port: port)
                if occupied.isEmpty {
                    // 端口已释放，继续启动
                } else {
                    lastStartupError = String(
                        format: String(localized: "model_manager.error.port_in_use_by_process"),
                        port,
                        occupied.joined(separator: ", ")
                    )
                    isStarting = false
                    return
                }
            } else {
                lastStartupError = String(
                    format: String(localized: "model_manager.error.port_in_use_by_process"),
                    port,
                    first
                )
                isStarting = false
                print("[EngineManager] Cannot start: port \(port) is in use by \(first) (not our engine)")
                return
            }
        }

        let process = Process()
        process.currentDirectoryURL = projectRoot

        // Prefer: 1) uv run, 2) .venv/bin/python (from uv sync)
        if let uvPath = Self.findUvPath() {
            process.executableURL = URL(fileURLWithPath: uvPath)
            process.arguments = ["run", "python", "-m", "uvicorn", "engine.server:app", "--host", "127.0.0.1", "--port", "\(port)"]
        } else if let pythonPath = Self.findPythonPath(projectRoot: projectRoot) {
            process.executableURL = URL(fileURLWithPath: pythonPath)
            process.arguments = ["-m", "uvicorn", "engine.server:app", "--host", "127.0.0.1", "--port", "\(port)"]
        } else {
            lastStartupError = String(localized: "model_manager.error.python_not_found")
            isStarting = false
            print("[EngineManager] Cannot start: neither uv nor python found")
            return
        }
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Capture stderr for debugging (read async to avoid blocking)
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let str = String(data: data, encoding: .utf8), !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                print("[EngineManager] stderr: \(trimmed)")
                Task { @MainActor [weak self] in
                    self?.lastStderrLine = trimmed
                }
            }
        }

        process.terminationHandler = { [weak self] p in
            if let cwd = p.currentDirectoryURL {
                PortChecker.removePidFile(projectRoot: cwd)
            }
            Task { @MainActor in
                guard let self else { return }
                if self.process?.processIdentifier == p.processIdentifier {
                    self.process = nil
                    self.isRunning = false
                    self.isStarting = false
                    if p.terminationStatus != 0, self.lastStartupError == nil {
                        if let stderr = self.lastStderrLine, !stderr.isEmpty {
                            self.lastStartupError = String(
                                format: String(localized: "model_manager.error.engine_start_failed_with_stderr"),
                                stderr
                            )
                        } else {
                            self.lastStartupError = String(
                                format: String(localized: "model_manager.error.engine_exited"),
                                p.terminationStatus
                            )
                        }
                    }
                    print("[EngineManager] Engine process exited (status: \(p.terminationStatus))")
                }
            }
        }

        do {
            try process.run()
            self.process = process
            isRunning = true
            isStarting = false
            Self.writePidFile(pid: process.processIdentifier, projectRoot: projectRoot)
            print("[EngineManager] Started engine at \(baseURL), cwd=\(projectRoot.path)")
        } catch {
            isStarting = false
            lastStartupError = String(
                format: String(localized: "model_manager.error.engine_start_failed_with_stderr"),
                error.localizedDescription
            )
            print("[EngineManager] Failed to start: \(error)")
        }
    }

    @MainActor
    func ensureEngineReady() async -> Bool {
        if !isRunning {
            let envReady: Bool
            if let existing = prepareTask {
                envReady = await existing.value
            } else {
                let task = Task { await prepareEnvironmentIfNeeded() }
                prepareTask = task
                envReady = await task.value
                prepareTask = nil
            }
            guard envReady else {
                return false
            }
            startEngine()
        }
        guard isRunning else {
            return false
        }
        return await waitForHealthReady(timeoutSeconds: startupTimeoutSeconds)
    }

    @MainActor
    func stopEngine() {
        if let p = process, let cwd = p.currentDirectoryURL {
            PortChecker.removePidFile(projectRoot: cwd)
        }
        process?.terminate()
        process = nil
        isRunning = false
        isStarting = false
        lastStderrLine = nil
        print("[EngineManager] Stopped engine")
    }

    @MainActor
    private func waitForHealthReady(timeoutSeconds: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if await checkHealthOnce() {
                lastStartupError = nil
                return true
            }
            if process == nil || !isRunning {
                if lastStartupError == nil {
                    if let stderr = lastStderrLine, !stderr.isEmpty {
                        lastStartupError = String(
                            format: String(localized: "model_manager.error.engine_start_failed_with_stderr"),
                            stderr
                        )
                    } else {
                        lastStartupError = String(
                            format: String(localized: "model_manager.error.engine_not_ready"),
                            port
                        )
                    }
                }
                return false
            }
            try? await Task.sleep(nanoseconds: readinessPollNanos)
        }

        if let first = PortChecker.processesUsing(port: port).first {
            lastStartupError = String(
                format: String(localized: "model_manager.error.port_in_use_by_process"),
                port,
                first
            )
        } else if let stderr = lastStderrLine, !stderr.isEmpty {
            lastStartupError = String(
                format: String(localized: "model_manager.error.engine_start_failed_with_stderr"),
                stderr
            )
        } else {
            lastStartupError = String(
                format: String(localized: "model_manager.error.engine_not_ready"),
                port
            )
        }
        return false
    }

    private func checkHealthOnce() async -> Bool {
        var request = URLRequest(url: engineURL)
        request.timeoutInterval = 1.2
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    @MainActor
    private func prepareEnvironmentIfNeeded() async -> Bool {
        guard let engine = Self.findEngineDirectory() else { return true }
        let projectRoot = engine.deletingLastPathComponent()
        let venvPython = projectRoot
            .appendingPathComponent(".venv")
            .appendingPathComponent("bin")
            .appendingPathComponent("python3")
        if FileManager.default.isExecutableFile(atPath: venvPython.path) {
            return true
        }
        guard let uvPath = Self.findUvPath() else {
            return true
        }

        let pyprojectURL = projectRoot.appendingPathComponent("pyproject.toml")
        guard FileManager.default.fileExists(atPath: pyprojectURL.path) else {
            lastStartupError = String(localized: "model_manager.error.pyproject_not_found")
            print("[EngineManager] Cannot run uv sync: pyproject.toml not found in \(projectRoot.path)")
            return false
        }

        isPreparing = true
        print("[EngineManager] .venv missing, running uv sync...")
        let result = await Self.runProcess(
            executablePath: uvPath,
            arguments: ["sync"],
            workingDirectory: projectRoot
        )
        isPreparing = false
        if !result.success {
            let detail = result.stderr ?? "uv sync failed"
            lastStartupError = String(
                format: String(localized: "model_manager.error.uv_sync_failed"),
                detail
            )
            print("[EngineManager] uv sync failed: \(detail)")
            return false
        }
        return true
    }

    /// 生成诊断信息文本，便于用户反馈问题。
    @MainActor
    func buildDiagnostics() -> String {
        var lines: [String] = []
        lines.append("--- Engine Diagnostics ---")
        lines.append("App Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
        lines.append("Port: \(port)")
        lines.append("Engine Running: \(isRunning)")
        lines.append("Engine Starting: \(isStarting)")
        lines.append("Engine Preparing: \(isPreparing)")
        if let err = lastStartupError {
            lines.append("Last Error: \(err)")
        }
        if let stderr = lastStderrLine, !stderr.isEmpty {
            lines.append("Last stderr: \(stderr)")
        }
        let uvPath = Self.findUvPath() ?? "not found"
        lines.append("uv path: \(uvPath)")
        if let resourceURL = Bundle.main.resourceURL {
            let projectDirURL = resourceURL.appendingPathComponent("project_dir.txt")
            if let data = try? Data(contentsOf: projectDirURL),
               let content = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !content.isEmpty {
                lines.append("project_dir.txt: \(content)")
            } else {
                lines.append("project_dir.txt: not found or empty")
            }
        }
        if let engine = Self.findEngineDirectory() {
            let projectRoot = engine.deletingLastPathComponent()
            let pythonPath = Self.findPythonPath(projectRoot: projectRoot) ?? "not found"
            lines.append("Python path: \(pythonPath)")
            lines.append("Project root: \(projectRoot.path)")
        } else {
            lines.append("Engine dir: not found")
        }
        let occupied = PortChecker.processesUsing(port: port)
        if !occupied.isEmpty {
            lines.append("Port occupants: \(occupied.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }

    private static func writePidFile(pid: Int32, projectRoot: URL) {
        let pidFile = projectRoot.appendingPathComponent(".engine.pid")
        let content = "\(pid)"
        try? content.write(to: pidFile, atomically: true, encoding: .utf8)
    }

    private static func runProcess(
        executablePath: String,
        arguments: [String],
        workingDirectory: URL
    ) async -> (success: Bool, stderr: String?) {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectory
            let stderrPipe = Pipe()
            process.standardOutput = FileHandle.nullDevice
            process.standardError = stderrPipe
            do {
                try process.run()
                process.waitUntilExit()
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let err = String(data: errData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return (process.terminationStatus == 0, err)
            } catch {
                return (false, error.localizedDescription)
            }
        }.value
    }

    private static func findUvPath() -> String? {
        let candidates = ["/opt/homebrew/bin/uv", "/usr/local/bin/uv", "\(NSHomeDirectory())/.local/bin/uv"]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    private static func findPythonPath(projectRoot: URL) -> String? {
        let venvPython = projectRoot.appendingPathComponent(".venv").appendingPathComponent("bin").appendingPathComponent("python3")
        if FileManager.default.isExecutableFile(atPath: venvPython.path) {
            return venvPython.path
        }
        let candidates = ["/opt/homebrew/bin/python3", "/usr/bin/python3", "/usr/local/bin/python3"]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    private static func findEngineDirectory() -> URL? {
        // 1. ENGINE_PATH env (for custom override)
        if let envPath = ProcessInfo.processInfo.environment["ENGINE_PATH"],
           FileManager.default.fileExists(atPath: envPath) {
            return URL(fileURLWithPath: envPath)
        }

        // 2. project_dir.txt (written at build time when running from Xcode)
        //    优先使用项目目录，这样能复用用户手动 uv sync 创建的 .venv
        if let resourceURL = Bundle.main.resourceURL {
            let projectDirURL = resourceURL.appendingPathComponent("project_dir.txt")
            if let data = try? Data(contentsOf: projectDirURL),
               let projectRoot = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !projectRoot.isEmpty {
                let engineInProject = (projectRoot as NSString).appendingPathComponent("engine")
                if FileManager.default.fileExists(atPath: engineInProject) {
                    return URL(fileURLWithPath: engineInProject)
                }
            }
        }

        // 3. Current working directory (e.g. Xcode scheme with custom working dir)
        let cwd = FileManager.default.currentDirectoryPath
        let engineInCwd = (cwd as NSString).appendingPathComponent("engine")
        if FileManager.default.fileExists(atPath: engineInCwd) {
            return URL(fileURLWithPath: engineInCwd)
        }

        // 4. In app bundle Resources (packaged app, no project_dir.txt)
        if let resourceURL = Bundle.main.resourceURL {
            let engineInBundle = resourceURL.appendingPathComponent("engine")
            if FileManager.default.fileExists(atPath: engineInBundle.path) {
                return engineInBundle
            }
        }

        return nil
    }
}
