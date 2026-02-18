//
//  EngineClient.swift
//  someai
//
//  HTTP client for MacAIStudio engine API.
//

import Foundation

struct EngineClient {
    static let baseURL = URL(string: "http://127.0.0.1:8001")!

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

    static func fetchHealth() async throws -> HealthResponse {
        let url = baseURL.appendingPathComponent("health")
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(HealthResponse.self, from: data)
    }

    static func fetchModels() async throws -> ModelsResponse {
        let url = baseURL.appendingPathComponent("models")
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(ModelsResponse.self, from: data)
    }

    static func fetchLoadedModels() async throws -> LoadedModelsResponse {
        let url = baseURL.appendingPathComponent("models").appendingPathComponent("loaded")
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(LoadedModelsResponse.self, from: data)
    }
}
