//
//  HTTPClientTests.swift
//  EchoTests
//
//  MockURLProtocol and HTTPClient.makeTestClient are defined in ProviderTestHelpers.swift.
//

import Foundation
import Testing
@testable import EchoCore

@Suite(.serialized)
struct HTTPClientTests {
    private let endpoint = URL(string: "https://example.test/resource")!

    @Test("HTTPClient returns successful response data")
    func success() async throws {
        let client = HTTPClient.makeTestClient { request in
            #expect(request.httpMethod == "GET")
            return MockURLProtocol.Result(statusCode: 200, data: Data("ok".utf8))
        }
        let response = try await client.execute(HTTPRequest(url: endpoint))
        #expect(response.statusCode == 200)
        #expect(String(data: response.data, encoding: .utf8) == "ok")
    }

    @Test("HTTPClient maps HTTP error responses")
    func httpError() async {
        let client = HTTPClient.makeTestClient { _ in
            MockURLProtocol.Result(statusCode: 401, data: Data("unauthorized".utf8))
        }
        do {
            _ = try await client.execute(HTTPRequest(url: endpoint))
            Issue.record("Expected unauthorized error")
        } catch let error as NetworkError {
            #expect(error == .unauthorized)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("HTTPClient maps URLSession timeout errors")
    func timeout() async {
        let client = HTTPClient.makeTestClient { _ in
            throw URLError(.timedOut)
        }
        do {
            _ = try await client.execute(HTTPRequest(url: endpoint))
            Issue.record("Expected timeout error")
        } catch let error as NetworkError {
            #expect(error == .timeout)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("HTTPClient cancellation maps to cancelled")
    func cancellation() async {
        let client = HTTPClient.makeTestClient { _ in
            .delayed(statusCode: 200, data: Data("late".utf8), delay: 5)
        }
        let task = Task {
            try await client.execute(HTTPRequest(url: endpoint))
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Expected cancellation error")
        } catch let error as NetworkError {
            #expect(error == .cancelled)
        } catch is CancellationError {
            Issue.record("HTTPClient leaked CancellationError instead of NetworkError.cancelled")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("HTTPClient decodes successful JSON responses")
    func decoding() async throws {
        struct Payload: Decodable, Equatable {
            let message: String
        }
        let client = HTTPClient.makeTestClient { _ in
            MockURLProtocol.Result(
                statusCode: 200,
                data: Data(#"{"message":"hello"}"#.utf8)
            )
        }
        let result: Payload = try await client.send(
            HTTPRequest(url: endpoint),
            decode: Payload.self
        )
        #expect(result == Payload(message: "hello"))
    }

    @Test("HTTPClient maps JSON decoding failures")
    func decodingFailure() async {
        let client = HTTPClient.makeTestClient { _ in
            MockURLProtocol.Result(statusCode: 200, data: Data("not-json".utf8))
        }
        struct Payload: Decodable { let message: String }
        do {
            let _: Payload = try await client.send(
                HTTPRequest(url: endpoint),
                decode: Payload.self
            )
            Issue.record("Expected decoding failure")
        } catch let error as NetworkError {
            guard case .decodingFailed = error else {
                Issue.record("Unexpected NetworkError: \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
