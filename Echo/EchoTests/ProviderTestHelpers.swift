//
//  ProviderTestHelpers.swift
//  EchoTests
//
//  Shared test utilities. MockURLProtocol reads a handler key set via
//  URLProtocol.setProperty inside HTTPClient.requestInterceptor. Each test
//  gets an isolated handler; parallel suites never share state.
//

import Foundation
@testable import EchoCore

// File-scope lock and handler registry
private let mockLock = NSLock()
private var mockHandlers: [String: (URLRequest) throws -> MockURLProtocol.Result] = [:]
private let handlerPropertyKey = "EchoMockHandlerKey"

// MARK: - MockURLProtocol

final class MockURLProtocol: URLProtocol {
    struct Result {
        let statusCode: Int
        let data: Data
        let delay: TimeInterval
        let error: URLError?

        init(statusCode: Int, data: Data = Data()) {
            self.statusCode = statusCode
            self.data = data
            self.delay = 0
            self.error = nil
        }

        static func delayed(statusCode: Int, data: Data, delay: TimeInterval) -> Result {
            Result(statusCode: statusCode, data: data, delay: delay, error: nil)
        }

        static func failure(_ error: URLError) -> Result {
            Result(statusCode: 0, data: Data(), delay: 0, error: error)
        }

        private init(statusCode: Int, data: Data, delay: TimeInterval, error: URLError?) {
            self.statusCode = statusCode
            self.data = data
            self.delay = delay
            self.error = error
        }
    }

    // MARK: Legacy static API (HTTPClientTests, @Suite(.serialized))

    static func install(_ handler: @escaping (URLRequest) throws -> Result) {
        mockLock.lock()
        mockHandlers["__legacy__"] = handler
        mockLock.unlock()
    }

    static func uninstall() {
        mockLock.lock()
        mockHandlers.removeValue(forKey: "__legacy__")
        mockLock.unlock()
    }

    // MARK: URLProtocol

    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let key = (URLProtocol.property(forKey: handlerPropertyKey, in: request) as? String)
                  ?? "__legacy__"
        mockLock.lock()
        let handler = mockHandlers[key]
        mockLock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotLoadFromNetwork))
            return
        }

        // Reconstruct a usable URLRequest that includes the body data.
        // URLSession transfers httpBody to a stream, so we need to read it back.
        var usableRequest = request
        if usableRequest.httpBody == nil, let stream = usableRequest.httpBodyStream {
            var bodyData = Data()
            stream.open()
            let bufferSize = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            while stream.hasBytesAvailable {
                let count = stream.read(buffer, maxLength: bufferSize)
                if count > 0 { bodyData.append(buffer, count: count) }
            }
            buffer.deallocate()
            stream.close()
            usableRequest.httpBody = bodyData
        }

        do {
            let result = try handler(usableRequest)
            let work = { [weak self] in
                guard let self, !self.stopped else { return }
                if let error = result.error {
                    self.client?.urlProtocol(self, didFailWithError: error)
                    return
                }
                let response = HTTPURLResponse(
                    url: self.request.url!,
                    statusCode: result.statusCode,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: result.data)
                self.client?.urlProtocolDidFinishLoading(self)
            }
            if result.delay > 0 {
                DispatchQueue.global().asyncAfter(deadline: .now() + result.delay, execute: work)
            } else {
                work()
            }
        } catch let error as URLError {
            client?.urlProtocol(self, didFailWithError: error)
        } catch {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
        }
    }

    override func stopLoading() { stopped = true }
}

// MARK: - HTTPClient isolated factory

extension HTTPClient {
    /// Creates an HTTPClient with an isolated MockURLProtocol handler.
    /// Uses HTTPClient.requestInterceptor to stamp each request with the
    /// unique handler key before URLSession submission.
    static func makeTestClient(
        handler: @escaping (URLRequest) throws -> MockURLProtocol.Result
    ) -> HTTPClient {
        let key = UUID().uuidString
        mockLock.lock()
        mockHandlers[key] = handler
        mockLock.unlock()

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = HTTPClient(session: URLSession(configuration: config))
        client.requestInterceptor = { request in
            let mutable = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
            URLProtocol.setProperty(key, forKey: handlerPropertyKey, in: mutable)
            request = mutable as URLRequest
        }
        return client
    }
}

// MARK: - Audio fixture

func makeAudioFixture(named name: String = "fixture.m4a") throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + "-" + name)
    try Data([0xAA, 0xBB, 0xCC, 0xDD]).write(to: url)
    return url
}
