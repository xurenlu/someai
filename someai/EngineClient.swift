//
//  EngineClient.swift
//  someai
//
//  HTTP client for MacAIStudio engine API.
//

import Foundation

/// User-friendly error descriptions for engine connection failures.
enum EngineConnectionError: LocalizedError {
    case connectionRefused
    case timeout
    case notConnected
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .connectionRefused:
            return String(localized: "model_manager.error.connection_refused")
        case .timeout:
            return String(localized: "model_manager.error.timeout")
        case .notConnected:
            return String(localized: "model_manager.error.not_connected")
        case .serverError(let msg):
            return msg
        }
    }
}

struct EngineClient {
    static var baseURL: URL { EngineConfig.shared.baseURL }

    /// Max retries for fetch operations.
    static let maxRetries = 3
    /// Delay between retries (seconds).
    static let retryDelay: UInt64 = 1_500_000_000  // 1.5s in nanoseconds

    struct HealthResponse: Codable {
        let status: String
        let models_loaded: [String]
    }

    struct ModelSummary: Codable {
        let id: String
        let name: String
        let type: String
        let capabilities: [String]
        let status: String
        let size_bytes: Int?
        let quantization: String?
        let version: String?
        let updated_at: String?
    }

    struct ModelsResponse: Codable {
        let models: [ModelSummary]
    }

    struct LoadedModelInfo: Codable {
        let id: String
        let type: String
        let device: String?
        let memory_mb: Int?
        let load_ms: Int?
        let loaded_at: String?
    }

    struct LoadedModelsResponse: Codable {
        let loaded_models: [LoadedModelInfo]
        let engine: EngineInfo?
    }

    struct EngineInfo: Codable {
        let queue_size: Int?
        let uptime_sec: Int?
    }

    /// Converts URLSession/network errors into user-friendly messages.
    private static func userFriendlyError(from error: Error) -> String {
        if let urlError = error as? URLError {
            // -1024 = connectionRefused, -1004 = cannotConnectToHost
            let code = urlError.code.rawValue
            if code == -1024 || urlError.code == .cannotConnectToHost {
                let port = EngineConfig.shared.enginePort
                let occupied = PortChecker.processesUsing(port: port)
                if let first = occupied.first {
                    print("[EngineClient] Connection refused to \(baseURL) - port \(port) is occupied by \(first)")
                    return String(
                        format: String(localized: "model_manager.error.port_in_use_by_process"),
                        port,
                        first
                    )
                }
                print("[EngineClient] Connection refused to \(baseURL) - engine not ready")
                return String(format: String(localized: "model_manager.error.engine_not_ready"), port)
            }
            if urlError.code == .timedOut {
                print("[EngineClient] Request timed out to \(baseURL)")
                return EngineConnectionError.timeout.errorDescription ?? error.localizedDescription
            }
            if urlError.code == .notConnectedToInternet {
                return EngineConnectionError.notConnected.errorDescription ?? error.localizedDescription
            }
            print("[EngineClient] Network error: \(code) \(error.localizedDescription)")
        }
        return error.localizedDescription
    }

    static func fetchHealth() async throws -> HealthResponse {
        let url = baseURL.appendingPathComponent("health")
        var lastError: Error?
        for attempt in 1...maxRetries {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                return try JSONDecoder().decode(HealthResponse.self, from: data)
            } catch {
                lastError = error
                print("[EngineClient] fetchHealth attempt \(attempt)/\(maxRetries) failed: \(error.localizedDescription)")
                if attempt < maxRetries {
                    try? await Task.sleep(nanoseconds: retryDelay)
                }
            }
        }
        throw NSError(domain: "EngineClient", code: -1, userInfo: [
            NSLocalizedDescriptionKey: userFriendlyError(from: lastError!)
        ])
    }

    static func fetchModels() async throws -> ModelsResponse {
        let url = baseURL.appendingPathComponent("models")
        var lastError: Error?
        for attempt in 1...maxRetries {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                return try JSONDecoder().decode(ModelsResponse.self, from: data)
            } catch {
                lastError = error
                print("[EngineClient] fetchModels attempt \(attempt)/\(maxRetries) failed: \(error.localizedDescription)")
                if attempt < maxRetries {
                    try? await Task.sleep(nanoseconds: retryDelay)
                }
            }
        }
        throw NSError(domain: "EngineClient", code: -1, userInfo: [
            NSLocalizedDescriptionKey: userFriendlyError(from: lastError!)
        ])
    }

    static func fetchLoadedModels() async throws -> LoadedModelsResponse {
        let url = baseURL.appendingPathComponent("models").appendingPathComponent("loaded")
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(LoadedModelsResponse.self, from: data)
    }
}
