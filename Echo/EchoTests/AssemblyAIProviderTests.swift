//
//  AssemblyAIProviderTests.swift
//  EchoTests
//

import Foundation
import Testing
@testable import EchoCore

@Suite(.serialized)
struct AssemblyAIProviderTests {
    private let config = ProviderRegistry.configuration(for: .assemblyAI)

    @Test("Auth header uses bare key (no Bearer prefix)")
    func bareKeyAuth() async throws {
        var calls: [URLRequest] = []
        let audio = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audio) }

        let step = Counter()
        let client = HTTPClient.makeTestClient { req in
            calls.append(req)
            return Self.stepResponse(step: step.next(), result: "Hello.")
        }

        let provider = AssemblyAIProvider(config: config, apiKey: "assemblyKey", httpClient: client)
        _ = try await provider.transcribe(audioFile: audio, model: "default", language: nil)

        for req in calls {
            #expect(req.value(forHTTPHeaderField: "Authorization") == "assemblyKey")
        }
    }

    @Test("Upload step posts raw audio bytes")
    func uploadPostsRawBytes() async throws {
        let audio = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audio) }
        let expected = try Data(contentsOf: audio)

        var uploadRequest: URLRequest?
        let step = Counter()
        let client = HTTPClient.makeTestClient { req in
            let n = step.next()
            if n == 0 { uploadRequest = req }
            return Self.stepResponse(step: n, result: "Done.")
        }

        let provider = AssemblyAIProvider(config: config, apiKey: "k", httpClient: client)
        _ = try await provider.transcribe(audioFile: audio, model: "default", language: nil)

        #expect(uploadRequest?.httpBody == expected)
        #expect(uploadRequest?.value(forHTTPHeaderField: "Content-Type") == "audio/mp4")
    }

    @Test("Returns transcript when status is completed")
    func completedStatus() async throws {
        let audio = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audio) }

        let step = Counter()
        let client = HTTPClient.makeTestClient { req in
            Self.stepResponse(step: step.next(), result: "AssemblyAI result.")
        }

        let provider = AssemblyAIProvider(config: config, apiKey: "k", httpClient: client)
        let result = try await provider.transcribe(audioFile: audio, model: "default", language: nil)

        #expect(result.text == "AssemblyAI result.")
    }

    @Test("Throws transportError when status is error")
    func errorStatus() async throws {
        let audio = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audio) }

        let step = Counter()
        let client = HTTPClient.makeTestClient { _ in
            let n = step.next()
            switch n {
            case 0:
                return .init(statusCode: 200, data: Data(#"{"upload_url":"https://cdn.test/a"}"#.utf8))
            case 1:
                return .init(statusCode: 200, data: Data(#"{"id":"j1","status":"queued"}"#.utf8))
            default:
                return .init(statusCode: 200,
                             data: Data(#"{"status":"error","error":"Something went wrong"}"#.utf8))
            }
        }

        let provider = AssemblyAIProvider(config: config, apiKey: "k", httpClient: client)
        do {
            _ = try await provider.transcribe(audioFile: audio, model: "default", language: nil)
            Issue.record("Expected error")
        } catch let error as NetworkError {
            guard case .transportError = error else {
                Issue.record("Unexpected NetworkError: \(error)")
                return
            }
        }
    }

    @Test("HTTP 401 throws unauthorized")
    func unauthorizedOnUpload() async throws {
        let audio = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audio) }
        let client = HTTPClient.makeTestClient { _ in .init(statusCode: 401, data: Data()) }

        let provider = AssemblyAIProvider(config: config, apiKey: "k", httpClient: client)
        do {
            _ = try await provider.transcribe(audioFile: audio, model: "default", language: nil)
            Issue.record("Expected unauthorized error")
        } catch let error as NetworkError {
            #expect(error == .unauthorized)
        }
    }

    @Test("Missing audio file throws invalidConfiguration")
    func missingAudioFile() async throws {
        let client = HTTPClient.makeTestClient { _ in .init(statusCode: 200, data: Data()) }

        let provider = AssemblyAIProvider(config: config, apiKey: "k", httpClient: client)
        do {
            _ = try await provider.transcribe(
                audioFile: URL(fileURLWithPath: "/tmp/missing.m4a"),
                model: "default",
                language: nil
            )
            Issue.record("Expected invalidConfiguration error")
        } catch let error as ProviderError {
            guard case .invalidConfiguration = error else {
                Issue.record("Unexpected ProviderError: \(error)")
                return
            }
        }
    }

    // MARK: - Helpers

    private static func stepResponse(step n: Int, result: String) -> MockURLProtocol.Result {
        switch n {
        case 0:
            return .init(statusCode: 200, data: Data(#"{"upload_url":"https://cdn.test/audio"}"#.utf8))
        case 1:
            return .init(statusCode: 200, data: Data(#"{"id":"job1","status":"queued"}"#.utf8))
        default:
            let escaped = result.replacingOccurrences(of: "\"", with: "\\\"")
            return .init(statusCode: 200,
                         data: Data(#"{"status":"completed","text":"\#(escaped)"}"#.utf8))
        }
    }
}

// MARK: - Thread-safe step counter

private final class Counter {
    private var value = 0
    private let lock = NSLock()
    func next() -> Int {
        lock.lock()
        defer { value += 1; lock.unlock() }
        return value
    }
}
