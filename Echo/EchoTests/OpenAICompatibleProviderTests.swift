//
//  OpenAICompatibleProviderTests.swift
//  EchoTests
//

import Foundation
import Testing
@testable import EchoCore

@Suite(.serialized)
struct OpenAICompatibleProviderTests {
    private let groqConfig = ProviderRegistry.configuration(for: .groq)
    private let openAIConfig = ProviderRegistry.configuration(for: .openAI)
    private let azureConfig = ProviderRegistry.configuration(for: .azure)

    // MARK: - Request generation

    @Test("Sets correct auth header with Bearer prefix (Groq / OpenAI)")
    func bearerAuth() async throws {
        var capturedRequest: URLRequest?
        let audio = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audio) }
        let client = HTTPClient.makeTestClient { req in
            capturedRequest = req
            return .init(statusCode: 200, data: successJSON("hello"))
        }
        defer { MockURLProtocol.uninstall() }

        let provider = OpenAICompatibleProvider(config: groqConfig, apiKey: "sk-test", httpClient: client)
        _ = try await provider.transcribe(audioFile: audio, model: "whisper-large-v3-turbo", language: nil)

        let authHeader = capturedRequest?.value(forHTTPHeaderField: "Authorization")
        #expect(authHeader == "Bearer sk-test")
    }

    @Test("Azure provider uses api-key header with no prefix")
    func azureAuth() async throws {
        var capturedRequest: URLRequest?
        let audio = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audio) }

        // Azure requires a user-supplied base URL; patch one in.
        let azure = azureConfig.withBaseURL("https://my.openai.azure.com/openai/deployments/my-deploy/")
        let client = HTTPClient.makeTestClient { req in
            capturedRequest = req
            return .init(statusCode: 200, data: successJSON("hello"))
        }
        defer { MockURLProtocol.uninstall() }

        let provider = OpenAICompatibleProvider(config: azure, apiKey: "azure-key", httpClient: client)
        _ = try await provider.transcribe(audioFile: audio, model: "custom-model", language: nil)

        let authHeader = capturedRequest?.value(forHTTPHeaderField: "api-key")
        #expect(authHeader == "azure-key")
    }

    @Test("Multipart body contains required OpenAI fields")
    func multipartFields() async throws {
        var capturedBody: Data?
        let audio = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audio) }
        let client = HTTPClient.makeTestClient { req in
            capturedBody = req.httpBody
            return .init(statusCode: 200, data: successJSON(""))
        }
        defer { MockURLProtocol.uninstall() }

        let provider = OpenAICompatibleProvider(config: openAIConfig, apiKey: "k", httpClient: client)
        _ = try await provider.transcribe(audioFile: audio, model: "whisper-1", language: nil)

        let body = String(decoding: capturedBody ?? Data(), as: UTF8.self)
        #expect(body.contains("name=\"file\""))
        #expect(body.contains("name=\"model\""))
        #expect(body.contains("name=\"response_format\""))
        #expect(body.contains("verbose_json"))
        #expect(body.contains("name=\"temperature\""))
        #expect(body.contains("name=\"prompt\""))
        #expect(body.contains("Echo."))
    }

    @Test("Language field is included when language is set")
    func languageIncluded() async throws {
        var capturedBody: Data?
        let audio = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audio) }
        let client = HTTPClient.makeTestClient { req in
            capturedBody = req.httpBody
            return .init(statusCode: 200, data: successJSON(""))
        }
        defer { MockURLProtocol.uninstall() }

        let provider = OpenAICompatibleProvider(config: groqConfig, apiKey: "k", httpClient: client)
        _ = try await provider.transcribe(audioFile: audio, model: "whisper-large-v3-turbo", language: "fr")

        let body = String(decoding: capturedBody ?? Data(), as: UTF8.self)
        #expect(body.contains("name=\"language\""))
        #expect(body.contains("\r\nfr\r\n"))
    }

    @Test("Language field is omitted when language is nil or auto")
    func languageOmitted() async throws {
        var capturedBodyNil: Data?
        var capturedBodyAuto: Data?
        let audio1 = try makeAudioFixture()
        let audio2 = try makeAudioFixture()
        defer {
            try? FileManager.default.removeItem(at: audio1)
            try? FileManager.default.removeItem(at: audio2)
        }

        let client1 = HTTPClient.makeTestClient { req in
            capturedBodyNil = req.httpBody
            return .init(statusCode: 200, data: successJSON(""))
        }
        let provider1 = OpenAICompatibleProvider(config: groqConfig, apiKey: "k", httpClient: client1)
        _ = try await provider1.transcribe(audioFile: audio1, model: "whisper-large-v3-turbo", language: nil)
        MockURLProtocol.uninstall()

        let client2 = HTTPClient.makeTestClient { req in
            capturedBodyAuto = req.httpBody
            return .init(statusCode: 200, data: successJSON(""))
        }
        let provider2 = OpenAICompatibleProvider(config: groqConfig, apiKey: "k", httpClient: client2)
        _ = try await provider2.transcribe(audioFile: audio2, model: "whisper-large-v3-turbo", language: "auto")
        MockURLProtocol.uninstall()

        let body1 = String(decoding: capturedBodyNil ?? Data(), as: UTF8.self)
        let body2 = String(decoding: capturedBodyAuto ?? Data(), as: UTF8.self)
        #expect(!body1.contains("name=\"language\""))
        #expect(!body2.contains("name=\"language\""))
    }

    // MARK: - Response parsing

    @Test("Returns transcript text on success")
    func returnsTranscript() async throws {
        let audio = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audio) }
        let client = HTTPClient.makeTestClient { _ in
            .init(statusCode: 200, data: successJSON("Hello world"))
        }
        defer { MockURLProtocol.uninstall() }

        let provider = OpenAICompatibleProvider(config: groqConfig, apiKey: "k", httpClient: client)
        let result = try await provider.transcribe(audioFile: audio, model: "whisper-large-v3-turbo", language: nil)

        #expect(result.text == "Hello world")
    }

    @Test("Hallucination filter discards high no_speech_prob segments")
    func hallucinationFilter() async throws {
        let audio = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audio) }
        let responseData = Data("""
        {"text":"Thank you.","segments":[{"no_speech_prob":0.95}]}
        """.utf8)
        let client = HTTPClient.makeTestClient { _ in .init(statusCode: 200, data: responseData) }
        defer { MockURLProtocol.uninstall() }

        let provider = OpenAICompatibleProvider(config: groqConfig, apiKey: "k", httpClient: client)
        let result = try await provider.transcribe(audioFile: audio, model: "whisper-large-v3-turbo", language: nil)

        #expect(result.text.isEmpty)
    }

    @Test("Known hallucination phrase list discards transcripts")
    func knownPhrases() async throws {
        let audio = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audio) }
        let client = HTTPClient.makeTestClient { _ in
            .init(statusCode: 200, data: successJSON("thank you."))
        }
        defer { MockURLProtocol.uninstall() }

        let provider = OpenAICompatibleProvider(config: groqConfig, apiKey: "k", httpClient: client)
        let result = try await provider.transcribe(audioFile: audio, model: "whisper-large-v3-turbo", language: nil)

        #expect(result.text.isEmpty)
    }

    @Test("Malformed JSON response returns empty transcript")
    func malformedJSON() async throws {
        let audio = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audio) }
        let client = HTTPClient.makeTestClient { _ in
            .init(statusCode: 200, data: Data("not-json".utf8))
        }
        defer { MockURLProtocol.uninstall() }

        let provider = OpenAICompatibleProvider(config: groqConfig, apiKey: "k", httpClient: client)
        let result = try await provider.transcribe(audioFile: audio, model: "whisper-large-v3-turbo", language: nil)

        #expect(result.text.isEmpty)
    }

    // MARK: - Error mapping

    @Test("HTTP 401 surfaces as unauthorized NetworkError")
    func unauthorizedError() async throws {
        let audio = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audio) }
        let client = HTTPClient.makeTestClient { _ in .init(statusCode: 401, data: Data()) }
        defer { MockURLProtocol.uninstall() }

        let provider = OpenAICompatibleProvider(config: groqConfig, apiKey: "k", httpClient: client)
        do {
            _ = try await provider.transcribe(audioFile: audio, model: "whisper-large-v3-turbo", language: nil)
            Issue.record("Expected unauthorized error")
        } catch let error as NetworkError {
            #expect(error == .unauthorized)
        }
    }

    @Test("HTTP 429 surfaces as tooManyRequests NetworkError")
    func rateLimitError() async throws {
        let audio = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audio) }
        let client = HTTPClient.makeTestClient { _ in .init(statusCode: 429, data: Data()) }
        defer { MockURLProtocol.uninstall() }

        let provider = OpenAICompatibleProvider(config: groqConfig, apiKey: "k", httpClient: client)
        do {
            _ = try await provider.transcribe(audioFile: audio, model: "whisper-large-v3-turbo", language: nil)
            Issue.record("Expected tooManyRequests error")
        } catch let error as NetworkError {
            #expect(error == .tooManyRequests)
        }
    }

    @Test("Missing audio file throws invalidConfiguration")
    func missingAudioFile() async throws {
        let missing = URL(fileURLWithPath: "/tmp/does-not-exist.m4a")
        let client = HTTPClient.makeTestClient { _ in .init(statusCode: 200, data: Data()) }
        defer { MockURLProtocol.uninstall() }

        let provider = OpenAICompatibleProvider(config: groqConfig, apiKey: "k", httpClient: client)
        do {
            _ = try await provider.transcribe(audioFile: missing, model: "whisper-large-v3-turbo", language: nil)
            Issue.record("Expected invalidConfiguration error")
        } catch let error as ProviderError {
            guard case .invalidConfiguration = error else {
                Issue.record("Unexpected ProviderError: \(error)")
                return
            }
        }
    }

    // MARK: - Cancellation

    @Test("Cancellation propagates as NetworkError.cancelled")
    func cancellation() async {
        let audio = try? makeAudioFixture()
        defer { if let a = audio { try? FileManager.default.removeItem(at: a) } }
        guard let audio else { Issue.record("Failed to create audio fixture"); return }

        MockURLProtocol.install { _ in .delayed(statusCode: 200, data: Data(), delay: 10) }
        defer { MockURLProtocol.uninstall() }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let client = HTTPClient(session: URLSession(configuration: configuration))
        let provider = OpenAICompatibleProvider(config: groqConfig, apiKey: "k", httpClient: client)

        let task = Task {
            try await provider.transcribe(audioFile: audio, model: "whisper-large-v3-turbo", language: nil)
        }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancelled error")
        } catch let error as NetworkError {
            #expect(error == .cancelled)
        } catch is CancellationError {
            Issue.record("Leaked CancellationError instead of NetworkError.cancelled")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - Helpers

    private func successJSON(_ text: String) -> Data {
        let escaped = text.replacingOccurrences(of: "\"", with: "\\\"")
        return Data(#"{"text":"\#(escaped)"}"#.utf8)
    }
}

// MARK: - ProviderConfig test extension (internal test helper)

extension ProviderConfig {
    func withBaseURL(_ url: String) -> ProviderConfig {
        ProviderConfig(
            id: id,
            displayName: displayName,
            defaultBaseURL: url,
            supportedModels: supportedModels,
            defaultModel: defaultModel,
            authHeaderName: authHeaderName,
            authHeaderValueFormat: authHeaderValueFormat,
            capabilities: capabilities
        )
    }
}
