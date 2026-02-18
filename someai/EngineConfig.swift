//
//  EngineConfig.swift
//  someai
//
//  引擎端口等配置，支持 UserDefaults 持久化。
//

import Foundation
import Darwin

/// 引擎配置（端口等），与 EngineManager、EngineClient 共享。
final class EngineConfig {
    static let shared = EngineConfig()

    private let portKey = "engine_port"
    private let useChinaMirrorKey = "engine_use_china_mirror"
    private let memoryLimitMBKey = "engine_memory_limit_mb"
    private let modelIdleTimeoutMinutesKey = "engine_model_idle_timeout_minutes"
    private let outputDirectoryKey = "output_directory"

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

    /// Python 引擎进程内存上限（MB），0 表示不限制
    var memoryLimitMB: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: memoryLimitMBKey)
            return v >= 0 ? v : 0
        }
        set {
            UserDefaults.standard.set(max(0, newValue), forKey: memoryLimitMBKey)
        }
    }

    /// 模型空闲超时（分钟），超时后自动卸载以释放内存。默认 15 分钟，修改后需重启引擎
    var modelIdleTimeoutMinutes: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: modelIdleTimeoutMinutesKey)
            return v >= 1 ? v : 15
        }
        set {
            UserDefaults.standard.set(max(1, min(1440, newValue)), forKey: modelIdleTimeoutMinutesKey)
        }
    }

    /// 使用中国 PyPI 镜像（清华源）加速 uv sync 依赖下载
    var useChinaMirror: Bool {
        get { UserDefaults.standard.bool(forKey: useChinaMirrorKey) }
        set { UserDefaults.standard.set(newValue, forKey: useChinaMirrorKey) }
    }

    /// 生成文件输出目录（TTS 音频、图片等），默认 ~/Downloads/someai
    var outputDirectory: URL {
        get {
            if let path = UserDefaults.standard.string(forKey: outputDirectoryKey), !path.isEmpty {
                return URL(fileURLWithPath: path)
            }
            return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
                .appendingPathComponent("someai", isDirectory: true)
        }
        set {
            UserDefaults.standard.set(newValue.path, forKey: outputDirectoryKey)
        }
    }

    /// 中国镜像 URL（清华源）
    static let chinaMirrorURL = "https://pypi.tuna.tsinghua.edu.cn/simple"

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

    /// 获取占用指定端口的进程 PID 列表。
    static func pidsUsing(port: Int) -> [Int] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-t", "-i", ":\(port)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            return output.split(separator: "\n").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        } catch {
            return []
        }
    }

    /// 获取进程的完整命令行。
    private static func commandLine(pid: Int) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", "\(pid)", "-o", "args="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    /// 从 PID 文件读取我们记录的引擎 PID（启动时写入）。
    static func readPidFromFile(projectRoot: URL) -> Int? {
        let pidFile = projectRoot.appendingPathComponent(".engine.pid")
        guard let data = try? Data(contentsOf: pidFile),
              let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int(s) else { return nil }
        return pid
    }

    /// 删除 PID 文件。
    static func removePidFile(projectRoot: URL) {
        let pidFile = projectRoot.appendingPathComponent(".engine.pid")
        try? FileManager.default.removeItem(at: pidFile)
    }

    /// 判断进程是否为我们的引擎：PID 文件匹配 或 命令行含 uvicorn + engine.server。
    static func isEngineProcess(pid: Int, projectRoot: URL?) -> Bool {
        if let root = projectRoot, let ourPid = readPidFromFile(projectRoot: root), pid == ourPid {
            return true
        }
        guard let cmd = commandLine(pid: pid) else { return false }
        return cmd.contains("uvicorn") && cmd.contains("engine.server")
    }

    /// 终止占用端口的旧引擎进程，返回终止的数量。projectRoot 用于读取 PID 文件。
    static func killEngineProcessesOn(port: Int, projectRoot: URL?) -> Int {
        let pids = pidsUsing(port: port)
        let ourPid = projectRoot.flatMap { readPidFromFile(projectRoot: $0) }
        var killed = 0
        for pid in pids {
            if isEngineProcess(pid: pid, projectRoot: projectRoot) {
                if kill(pid_t(pid), SIGTERM) == 0 {
                    killed += 1
                }
                if pid == ourPid, let root = projectRoot {
                    removePidFile(projectRoot: root)
                }
            }
        }
        return killed
    }
}
