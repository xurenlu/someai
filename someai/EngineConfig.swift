//
//  EngineConfig.swift
//  someai
//
//  引擎端口等配置，支持 UserDefaults 持久化。
//

import Foundation

/// 引擎配置（端口等），与 EngineManager、EngineClient 共享。
final class EngineConfig {
    static let shared = EngineConfig()

    private let portKey = "engine_port"

    /// 有效端口范围
    private let minPort = 1024
    private let maxPort = 65535
    private let defaultPort = 18080

    var enginePort: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: portKey)
            if v >= minPort && v <= maxPort { return v }
            return defaultPort
        }
        set {
            let clamped = min(max(newValue, minPort), maxPort)
            UserDefaults.standard.set(clamped, forKey: portKey)
        }
    }

    var baseURL: URL {
        URL(string: "http://127.0.0.1:\(enginePort)")!
    }

    private init() {}
}

// MARK: - 端口占用检查

/// 检查端口占用情况，返回占用进程信息（用于诊断连接失败）。
struct PortChecker {
    /// 检查指定端口，返回占用该端口的进程描述；若未被占用则返回 nil。
    static func processesUsing(port: Int) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-i", ":\(port)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            return parseLsofOutput(output)
        } catch {
            return []
        }
    }

    /// 解析 lsof 输出，提取 COMMAND 与 PID。
    private static func parseLsofOutput(_ output: String) -> [String] {
        var result: [String] = []
        let lines = output.split(separator: "\n")
        for line in lines.dropFirst() {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2,
                  let pid = Int(parts[1]) else { continue }
            let command = String(parts[0])
            result.append("\(command) (PID \(pid))")
        }
        return result
    }
}
