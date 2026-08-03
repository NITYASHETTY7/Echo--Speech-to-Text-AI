//
//  GeminiProviderTests.swift
//  EchoTests
//

import Foundation
import Testing
@testable import EchoCore

@Suite(.serialized)
struct GeminiProviderTests {
    private let config = ProviderRegistry.configuration(for: .gemini)

    @Test("Sets x-goog-api-key header with bare key")
    func apiKeyHeader() async throws {
        var captured: URLRequest?
        let audio = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audio) }
        let client = HTTPClient.makeTestClient { req in
            captured = req
            return .init(statusCode: 200, data: successResponse("Hi"))
        }
        defer { MockURLProtocol.uninstall() }

        let provider = GeminiProvider(config: config, apiKey: "goog-key", httpClient: client)
        _ = try await provider.transcribe(audioFile: audio, model: "gemini-2.0-flash", language: nil)

        #expect(captured?.value(forHTTPHeaderField: "x-goog-api-key") == "goog-key")
    }

    @Test("URL contains model name in path")
    func urlContainsModel() async throws {
        var captured: URLRequest?
        let audio = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audio) }
        let client = HTTPClient.makeTestClient { req in
            captured = req
            return .init(statusCode: 200, data: successResponse(""))
        }
        defer { MockURLProtocol.uninstall() }

        let provider = GeminiProvider(config: config, apiKey: "k", httpClient: client)
        _ = try await provider.transcribe(audioFile: audio, model: "gemini-2.0-flash", language: nil)

        #expect(captured?.url?.absoluteString.contains("gemini-2.0-flash:generateContent") == true)
    }

    @Test("Request body contains base64 inline_data")
    func base64AudioInBody() async throws {
        var capturedBody: Data?
        let audio = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audio) }
        let audioData = try Data(contentsOf: audio)
        let expectedBase64 = audioData.base64EncodedString()
        let client = HTTPClient.makeTestClient { req in
            capturedBody = req.httpBody
            return .init(statusCode: 200, data: successResponse(""))
        }
        defer { MockURLProtocol.uninstall() }

        let provider = GeminiProvider(config: config, apiKey: "k", httpClient: client)
        _ = try await provider.transcribe(audioFile: audio, model: "gemini-2.0-flash", language: nil)

        guard let body = capturedBody,
              let parsed = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let contents = parsed["contents"] as? [[String: Any]],
              let parts = contents.first?["parts"] as? [[String: Any]],
              let inlineData = parts.last?["inline_data"] as? [String: Any]
        else {
            Issue.record("Could not parse request body")
            return
        }
        #expect(inlineData["data"] as? String == expectedBase64)
        #expect(inlineData["mime_type"] as? String == "audio/mp4")
    }

    @Test("Language phrase included in prompt when language set")
    func promptWithLanguage() async throws {
        var capturedBody: Data?
        let audio = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audio) }
        let client = HTTPClient.makeTestClient { req in
            capturedBody = req.httpBody
            return .init(statusCode: 200, data: successResponse(""))
        }
        defer { MockURLProtocol.uninstall() }

        let provider = GeminiProvider(config: config, apiKey: "k", httpClient: client)
        _ = try await provider.transcribe(audioFile: audio, model: "gemini-2.0-flash", language: "de")

        guard let body = capturedBody,
              let parsed = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let contents = parsed["contents"] as? [[String: Any]],
              let parts = contents.first?["parts"] as? [[String: Any]],
              let promptText = parts.first?["text"] as? String
        else {
            Issue.record("Could not parse request body")
            return
        }
        #expect(promptText.contains("in de"))
    }

    @Test("Parses transcript from candidates path")
    func responseParsingSuccess() async throws {
        let audio = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audio) }
        let client = HTTPClient.makeTestClient { _ in .init(statusCode: 200, data: successResponse("Gemini transcript.")) }
        defer { MockURLProtocol.uninstall() }

        let provider = GeminiProvider(config: config, apiKey: "k", httpClient: client)
        let result = try await provider.transcribe(audioFile: audio, model: "gemini-2.0-flash", language: nil)

        #expect(result.text == "Gemini transcript.")
    }

    @Test("Malformed response returns empty transcript")
    func malformedResponse() async throws {
        let audio = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audio) }
        let client = HTTPClient.makeTestClient { _ in .init(statusCode: 200, data: Data("bad".utf8)) }
        defer { MockURLProtocol.uninstall() }

        let provider = GeminiProvider(config: config, apiKey: "k", httpClient: client)
        let result = try await provider.transcribe(audioFile: audio, model: "gemini-2.0-flash", language: nil)

        #expect(result.text.isEmpty)
    }

    @Test("HTTP 403 throws forbidden NetworkError")
    func forbiddenError() async throws {
        let audio = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audio) }
        let client = HTTPClient.makeTestClient { _ in .init(statusCode: 403, data: Data()) }
        defer { MockURLProtocol.uninstall() }

        let provider = GeminiProvider(config: config, apiKey: "k", httpClient: client)
        do {
            _ = try await provider.transcribe(audioFile: audio, model: "gemini-2.0-flash", language: nil)
            Issue.record("Expected forbidden error")
        } catch let error as NetworkError {
            #expect(error == .forbidden)
        }
    }

    // MARK: - Helpers

    private func successResponse(_ text: String) -> Data {
        let escaped = text.replacingOccurrences(of: "\"", with: "\\\"")
        return Data("""
        {"candidates":[{"content":{"parts":[{"text":"\(escaped)"}]}}]}
        """.utf8)
    }
}
