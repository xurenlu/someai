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
        let local_dir: String?
        let actual_size_bytes: Int?
        let file_types: [String]?
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

    struct DownloadResponse: Codable {
        let status: String
        let model_id: String
        let local_dir: String?
    }

    struct ErrorResponse: Codable {
        let error: ErrorDetail?
    }

    struct ErrorDetail: Codable {
        let code: String?
        let message: String?
        let model_id: String?
    }

    /// If error is MODEL_NOT_LOADED, returns the model_id for preload. Otherwise nil.
    static func modelIdForPreload(from error: Error) -> String? {
        guard let ns = error as NSError?,
              ns.domain == "EngineClient",
              let code = ns.userInfo["error_code"] as? String,
              code == modelNotLoadedCode else { return nil }
        return ns.userInfo["model_id"] as? String
    }

    /// Download model via engine. Uses 1 hour timeout for large models.
    static func downloadModel(modelId: String) async throws -> DownloadResponse {
        let url = baseURL.appendingPathComponent("models").appendingPathComponent("download")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["model_id": modelId])
        req.timeoutInterval = 3600

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw NSError(domain: "EngineClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        if http.statusCode >= 200, http.statusCode < 300 {
            return try JSONDecoder().decode(DownloadResponse.self, from: data)
        }
        if let errBody = try? JSONDecoder().decode(ErrorResponse.self, from: data),
           let msg = errBody.error?.message {
            throw NSError(domain: "EngineClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        throw NSError(domain: "EngineClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Download failed"])
    }

    /// Progress update from streaming download.
    struct DownloadProgress: Sendable {
        let downloaded: Int64
        let total: Int64
        let done: Bool
        let error: String?
        let localDir: String?
    }

    /// Stream model download with progress via SSE. Supports resume on retry.
    static func downloadModelStreaming(modelId: String) -> AsyncThrowingStream<DownloadProgress, Error> {
        var components = URLComponents(url: baseURL.appendingPathComponent("models").appendingPathComponent("download").appendingPathComponent("stream"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "model_id", value: modelId)]
        guard let url = components.url else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: NSError(domain: "EngineClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
            }
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3600

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                    guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        continuation.finish(throwing: NSError(domain: "EngineClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Download failed"]))
                        return
                    }
                    var buffer = ""
                    var finished = false
                    for try await byte in bytes {
                        if finished { break }
                        buffer.append(Character(Unicode.Scalar(byte)))
                        if buffer.hasSuffix("\n\n") {
                            for line in buffer.components(separatedBy: "\n") {
                                guard line.hasPrefix("data: ") else { continue }
                                let jsonStr = String(line.dropFirst(6))
                                guard let data = jsonStr.data(using: .utf8),
                                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                                let downloaded = (obj["downloaded"] as? NSNumber)?.int64Value ?? 0
                                let total = (obj["total"] as? NSNumber)?.int64Value ?? 0
                                let done = (obj["done"] as? Bool) ?? false
                                let error = obj["error"] as? String
                                let localDir = obj["local_dir"] as? String
                                continuation.yield(DownloadProgress(downloaded: downloaded, total: total, done: done, error: error, localDir: localDir))
                                if done {
                                    finished = true
                                    break
                                }
                            }
                            buffer = ""
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    struct AddModelRequest: Encodable {
        let hf_repo: String
        let name: String?
        let type: String
        let size_bytes: Int
    }

    struct AddModelResponse: Codable {
        let status: String
        let model_id: String
    }

    /// Add custom model from HuggingFace. Model appears in list and can be downloaded.
    static func addModel(hfRepo: String, name: String? = nil, type: String = "llm", sizeBytes: Int = 0) async throws -> AddModelResponse {
        let url = baseURL.appendingPathComponent("models")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(AddModelRequest(
            hf_repo: hfRepo,
            name: name?.isEmpty == true ? nil : name,
            type: type,
            size_bytes: sizeBytes
        ))

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw NSError(domain: "EngineClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        if http.statusCode >= 200, http.statusCode < 300 {
            return try JSONDecoder().decode(AddModelResponse.self, from: data)
        }
        if let errBody = try? JSONDecoder().decode(ErrorResponse.self, from: data),
           let msg = errBody.error?.message {
            throw NSError(domain: "EngineClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        throw NSError(domain: "EngineClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Add model failed"])
    }

    /// Delete local model files. Allows re-download.
    static func deleteModel(modelId: String) async throws {
        let url = baseURL.appendingPathComponent("models").appendingPathComponent(modelId)
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw NSError(domain: "EngineClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        if http.statusCode >= 200, http.statusCode < 300 {
            return
        }
        if let errBody = try? JSONDecoder().decode(ErrorResponse.self, from: data),
           let msg = errBody.error?.message {
            throw NSError(domain: "EngineClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        throw NSError(domain: "EngineClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Delete failed"])
    }

    // MARK: - Generation APIs (unified, with retry for network errors)

    static let generateMaxRetries = 2
    static let generateRetryDelay: UInt64 = 1_000_000_000  // 1s

    /// Returns true if error is retriable (network/connection).
    private static func isRetriable(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
                return true
            default:
                return urlError.code.rawValue == -1024
            }
        }
        return false
    }

    struct LLMGenerateRequest: Encodable {
        let prompt: String
        let temperature: Double
        let max_tokens: Int
        let model_id: String?
    }

    struct LLMGenerateResponse: Decodable {
        let text: String
    }

    /// Error code when model was unloaded and needs preload
    static let modelNotLoadedCode = "MODEL_NOT_LOADED"

    /// Coordinates preload so concurrent requests for same model trigger only one load.
    private static let preloadCoordinator = ModelPreloadCoordinator()

    private actor ModelPreloadCoordinator {
        private var inProgress: [String: Task<Void, Error>] = [:]

        func preload(modelId: String) async throws {
            if let existing = inProgress[modelId] {
                try await existing.value
                return
            }
            let task = Task {
                try await EngineClient.preloadModel(modelId: modelId)
            }
            inProgress[modelId] = task
            defer { inProgress.removeValue(forKey: modelId) }
            try await task.value
        }
    }

    static func preloadModel(modelId: String) async throws {
        let url = baseURL.appendingPathComponent("models").appendingPathComponent(modelId).appendingPathComponent("load")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 300  // 5 min for large models

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw NSError(domain: "EngineClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        if (200..<300).contains(http.statusCode) { return }
        if let errBody = try? JSONDecoder().decode(ErrorResponse.self, from: data),
           let msg = errBody.error?.message {
            throw NSError(domain: "EngineClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        throw NSError(domain: "EngineClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Preload failed"])
    }

    static func generateChat(prompt: String, temperature: Double = 0.7, maxTokens: Int = 512, modelId: String? = nil) async throws -> String {
        let url = baseURL.appendingPathComponent("llm").appendingPathComponent("generate")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(LLMGenerateRequest(prompt: prompt, temperature: temperature, max_tokens: maxTokens, model_id: modelId))

        var lastError: Error?
        var hasPreloadRetried = false
        for attempt in 1...(generateMaxRetries + 1) {
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse else {
                    throw NSError(domain: "EngineClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                }
                if (200..<300).contains(http.statusCode) {
                    let decoded = try JSONDecoder().decode(LLMGenerateResponse.self, from: data)
                    return decoded.text
                }
                if let errBody = try? JSONDecoder().decode(ErrorResponse.self, from: data),
                   let detail = errBody.error {
                    var info: [String: Any] = [NSLocalizedDescriptionKey: detail.message ?? "LLM error"]
                    if detail.code == modelNotLoadedCode {
                        info["error_code"] = modelNotLoadedCode
                        if let mid = detail.model_id { info["model_id"] = mid }
                    }
                    throw NSError(domain: "EngineClient", code: http.statusCode, userInfo: info)
                }
                throw NSError(domain: "EngineClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "LLM error"])
            } catch {
                lastError = error
                if let mid = EngineClient.modelIdForPreload(from: error), !hasPreloadRetried {
                    hasPreloadRetried = true
                    try await preloadCoordinator.preload(modelId: mid)
                    continue
                }
                if isRetriable(error), attempt <= generateMaxRetries {
                    try? await Task.sleep(nanoseconds: generateRetryDelay)
                } else {
                    throw NSError(domain: "EngineClient", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: userFriendlyError(from: error)
                    ])
                }
            }
        }
        throw NSError(domain: "EngineClient", code: -1, userInfo: [
            NSLocalizedDescriptionKey: userFriendlyError(from: lastError!)
        ])
    }

    struct TTSGenerateRequest: Encodable {
        let text: String
        let language: String
        let speaker: String
        let model_id: String?
    }

    static func generateTTS(text: String, language: String = "zh", speaker: String = "default", modelId: String? = nil) async throws -> Data {
        let url = baseURL.appendingPathComponent("tts").appendingPathComponent("generate")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(TTSGenerateRequest(text: text, language: language, speaker: speaker, model_id: modelId))

        var lastError: Error?
        var hasPreloadRetried = false
        for attempt in 1...(generateMaxRetries + 1) {
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse else {
                    throw NSError(domain: "EngineClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                }
                if (200..<300).contains(http.statusCode) {
                    return data
                }
                if let errBody = try? JSONDecoder().decode(ErrorResponse.self, from: data),
                   let detail = errBody.error {
                    var info: [String: Any] = [NSLocalizedDescriptionKey: detail.message ?? "TTS error"]
                    if detail.code == modelNotLoadedCode {
                        info["error_code"] = modelNotLoadedCode
                        if let mid = detail.model_id { info["model_id"] = mid }
                    }
                    throw NSError(domain: "EngineClient", code: http.statusCode, userInfo: info)
                }
                throw NSError(domain: "EngineClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "TTS error"])
            } catch {
                lastError = error
                if let mid = EngineClient.modelIdForPreload(from: error), !hasPreloadRetried {
                    hasPreloadRetried = true
                    try await preloadCoordinator.preload(modelId: mid)
                    continue
                }
                if isRetriable(error), attempt <= generateMaxRetries {
                    try? await Task.sleep(nanoseconds: generateRetryDelay)
                } else {
                    throw NSError(domain: "EngineClient", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: userFriendlyError(from: error)
                    ])
                }
            }
        }
        throw NSError(domain: "EngineClient", code: -1, userInfo: [
            NSLocalizedDescriptionKey: userFriendlyError(from: lastError!)
        ])
    }

    struct ImageGenerateRequest: Encodable {
        let prompt: String
        let width: Int
        let height: Int
    }

    static func generateImage(prompt: String, width: Int = 512, height: Int = 512) async throws -> Data {
        let url = baseURL.appendingPathComponent("image").appendingPathComponent("generate")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(ImageGenerateRequest(prompt: prompt, width: width, height: height))

        var lastError: Error?
        for attempt in 1...(generateMaxRetries + 1) {
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse else {
                    throw NSError(domain: "EngineClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                }
                if (200..<300).contains(http.statusCode) {
                    return data
                }
                let errMsg = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error?.message ?? "Image error"
                throw NSError(domain: "EngineClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: errMsg])
            } catch {
                lastError = error
                if isRetriable(error), attempt <= generateMaxRetries {
                    try? await Task.sleep(nanoseconds: generateRetryDelay)
                } else {
                    throw NSError(domain: "EngineClient", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: userFriendlyError(from: error)
                    ])
                }
            }
        }
        throw NSError(domain: "EngineClient", code: -1, userInfo: [
            NSLocalizedDescriptionKey: userFriendlyError(from: lastError!)
        ])
    }

    struct STTResponse: Decodable {
        let text: String
    }

    static func recognizeOCR(imageData: Data, format: String = "text") async throws -> String {
        let url: URL
        if format == "json" {
            var comp = URLComponents(url: baseURL.appendingPathComponent("ocr").appendingPathComponent("recognize"), resolvingAgainstBaseURL: false)!
            comp.queryItems = [URLQueryItem(name: "format", value: "json")]
            url = comp.url!
        } else {
            url = baseURL.appendingPathComponent("ocr").appendingPathComponent("recognize")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let boundary = UUID().uuidString
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"image.png\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        var lastError: Error?
        for attempt in 1...(generateMaxRetries + 1) {
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse else {
                    throw NSError(domain: "EngineClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                }
                if (200..<300).contains(http.statusCode) {
                    if format == "json" {
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let text = json["text"] as? String {
                            return text
                        }
                    }
                    return String(data: data, encoding: .utf8) ?? ""
                }
                let errMsg = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error?.message ?? "OCR error"
                throw NSError(domain: "EngineClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: errMsg])
            } catch {
                lastError = error
                if isRetriable(error), attempt <= generateMaxRetries {
                    try? await Task.sleep(nanoseconds: generateRetryDelay)
                } else {
                    throw NSError(domain: "EngineClient", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: userFriendlyError(from: error)
                    ])
                }
            }
        }
        throw NSError(domain: "EngineClient", code: -1, userInfo: [
            NSLocalizedDescriptionKey: userFriendlyError(from: lastError!)
        ])
    }

    static func transcribe(audioData: Data) async throws -> String {
        let url = baseURL.appendingPathComponent("stt").appendingPathComponent("transcribe")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let boundary = UUID().uuidString
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        var lastError: Error?
        for attempt in 1...(generateMaxRetries + 1) {
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse else {
                    throw NSError(domain: "EngineClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                }
                if (200..<300).contains(http.statusCode) {
                    return try JSONDecoder().decode(STTResponse.self, from: data).text
                }
                let errMsg = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error?.message ?? "STT error"
                throw NSError(domain: "EngineClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: errMsg])
            } catch {
                lastError = error
                if isRetriable(error), attempt <= generateMaxRetries {
                    try? await Task.sleep(nanoseconds: generateRetryDelay)
                } else {
                    throw NSError(domain: "EngineClient", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: userFriendlyError(from: error)
                    ])
                }
            }
        }
        throw NSError(domain: "EngineClient", code: -1, userInfo: [
            NSLocalizedDescriptionKey: userFriendlyError(from: lastError!)
        ])
    }
}
