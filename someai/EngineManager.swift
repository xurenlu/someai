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
    private(set) var process: Process?

    private let port = 8001
    private let baseURL: URL

    var engineURL: URL {
        baseURL.appendingPathComponent("health")
    }

    init() {
        baseURL = URL(string: "http://127.0.0.1:\(port)")!
    }

    @MainActor
    func startEngine() {
        guard !isRunning else { return }

        let engineDir = Self.findEngineDirectory()
        guard let engine = engineDir else {
            print("[EngineManager] Cannot start: engine dir not found")
            return
        }

        let projectRoot = engine.deletingLastPathComponent()
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
                print("[EngineManager] stderr: \(str.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }

        do {
            try process.run()
            self.process = process
            isRunning = true
            print("[EngineManager] Started engine at \(baseURL), cwd=\(projectRoot.path)")
        } catch {
            print("[EngineManager] Failed to start: \(error)")
        }
    }

    @MainActor
    func stopEngine() {
        process?.terminate()
        process = nil
        isRunning = false
        print("[EngineManager] Stopped engine")
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
        // 1. Development: ENGINE_PATH env or current working directory (Xcode scheme)
        if let envPath = ProcessInfo.processInfo.environment["ENGINE_PATH"],
           FileManager.default.fileExists(atPath: envPath) {
            return URL(fileURLWithPath: envPath)
        }
        let cwd = FileManager.default.currentDirectoryPath
        let engineInCwd = (cwd as NSString).appendingPathComponent("engine")
        if FileManager.default.fileExists(atPath: engineInCwd) {
            return URL(fileURLWithPath: engineInCwd)
        }

        // 2. In app bundle Resources (packaged app)
        if let resourceURL = Bundle.main.resourceURL {
            let engineInBundle = resourceURL.appendingPathComponent("engine")
            if FileManager.default.fileExists(atPath: engineInBundle.path) {
                return engineInBundle
            }
        }

        return nil
    }
}
