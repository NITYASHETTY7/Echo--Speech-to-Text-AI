//
//  DeepgramProviderTests.swift
//  EchoTests
//

import Foundation
import Testing
@testable import EchoCore

@Suite(.serialized)
struct DeepgramProviderTests {
    private let config = ProviderRegistry.configuration(for: .deepgram)

    @Test("Uses Token auth header")
    func tokenAuth() async throws {
        var captured: URLRequest?
        let audio = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audio) }
        let client = HTTPClient.makeTestClient { req in
            captured = req
            return .init(statusCode: 200, data: responseJSON("Hello."))
        }
        defer { MockURLProtocol.uninstall() }

        let provider = DeepgramProvider(config: config, apiKey: "dg-key", httpClient: client)
        _ = try await provider.transcribe(audioFile: audio, model: "nova-3", language: nil)

        #expect(captured?.value(forHTTPHeaderField: "Authorization") == "Token dg-key")
    }

    @Test("URL contains model and smart_format query params")
    func urlQueryParams() async throws {
        var captured: URLRequest?
        let audio = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audio) }
        let client = HTTPClient.makeTestClient { req in
            captured = req
            return .init(statusCode: 200, data: responseJSON(""))
        }
        defer { MockURLProtocol.uninstall() }

        let provider = DeepgramProvider(config: config, apiKey: "k", httpClient: client)
        _ = try await provider.transcribe(audioFile: audio, model: "nova-3", language: nil)

        let urlStr = captured?.url?.absoluteString ?? ""
        #expect(urlStr.contains("model=nova-3"))
        #expect(urlStr.contains("smart_format=true"))
        #expect(!urlStr.contains("language="))
    }

    @Test("Language query param is added when set")
    func languageQueryParam() async throws {
        var captured: URLRequest?
        let audio = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audio) }
        let client = HTTPClient.makeTestClient { req in
            captured = req
            return .init(statusCode: 200, data: responseJSON(""))
        }
        defer { MockURLProtocol.uninstall() }

        let provider = DeepgramProvider(config: config, apiKey: "k", httpClient: client)
        _ = try await provider.transcribe(audioFile: audio, model: "nova-3", language: "es")

        let urlStr = captured?.url?.absoluteString ?? ""
        #expect(urlStr.contains("language=es"))
    }

    @Test("Sends raw audio bytes with audio/mp4 Content-Type")
    func rawBytesBody() async throws {
        var captured: URLRequest?
        let audio = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audio) }
        let expected = try Data(contentsOf: audio)
        let client = HTTPClient.makeTestClient { req in
            captured = req
            return .init(statusCode: 200, data: responseJSON(""))
        }
        defer { MockURLProtocol.uninstall() }

        let provider = DeepgramProvider(config: config, apiKey: "k", httpClient: client)
        _ = try await provider.transcribe(audioFile: audio, model: "nova-3", language: nil)

        #expect(captured?.value(forHTTPHeaderField: "Content-Type") == "audio/mp4")
        #expect(captured?.httpBody == expected)
    }

    @Test("Parses nested transcript JSON correctly")
    func responseParsingSuccess() async throws {
        let audio = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audio) }
        let client = HTTPClient.makeTestClient { _ in .init(statusCode: 200, data: responseJSON("Deepgram result.")) }
        defer { MockURLProtocol.uninstall() }

        let provider = DeepgramProvider(config: config, apiKey: "k", httpClient: client)
        let result = try await provider.transcribe(audioFile: audio, model: "nova-3", language: nil)

        #expect(result.text == "Deepgram result.")
    }

    @Test("Malformed response returns empty transcript")
    func malformedResponse() async throws {
        let audio = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audio) }
        let client = HTTPClient.makeTestClient { _ in .init(statusCode: 200, data: Data("bad".utf8)) }
        defer { MockURLProtocol.uninstall() }

        let provider = DeepgramProvider(config: config, apiKey: "k", httpClient: client)
        let result = try await provider.transcribe(audioFile: audio, model: "nova-3", language: nil)

        #expect(result.text.isEmpty)
    }

    @Test("HTTP 401 throws unauthorized NetworkError")
    func unauthorizedError() async throws {
        let audio = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audio) }
        let client = HTTPClient.makeTestClient { _ in .init(statusCode: 401, data: Data()) }
        defer { MockURLProtocol.uninstall() }

        let provider = DeepgramProvider(config: config, apiKey: "k", httpClient: client)
        do {
            _ = try await provider.transcribe(audioFile: audio, model: "nova-3", language: nil)
            Issue.record("Expected error")
        } catch let error as NetworkError {
            #expect(error == .unauthorized)
        }
    }

    // MARK: - Helpers

    private func responseJSON(_ transcript: String) -> Data {
        let escaped = transcript.replacingOccurrences(of: "\"", with: "\\\"")
        return Data("""
        {"results":{"channels":[{"alternatives":[{"transcript":"\(escaped)"}]}]}}
        """.utf8)
    }
}
